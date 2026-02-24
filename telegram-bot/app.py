from flask import Flask, request, jsonify
import os
import json
import base64
import requests
import re
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Response

app = Flask(__name__)

BOT_TOKEN = os.getenv("BOT_TOKEN")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}" if BOT_TOKEN else ""
WORKSPACE_ID = os.getenv("WORKSPACE_ID")


def _init_firestore():
    if firebase_admin._apps:
        return firestore.client()

    sa_json = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    sa_b64 = os.getenv("FIREBASE_SERVICE_ACCOUNT_B64")

    if sa_json:
        cred = credentials.Certificate(json.loads(sa_json))
    elif sa_b64:
        decoded = base64.b64decode(sa_b64).decode("utf-8")
        cred = credentials.Certificate(json.loads(decoded))
    else:
        cred = credentials.Certificate("firebase-key.json")

    firebase_admin.initialize_app(cred)
    return firestore.client()


db = _init_firestore()


def _ws_collection(name: str):
    if WORKSPACE_ID and WORKSPACE_ID.strip():
        return db.collection("workspaces").document(WORKSPACE_ID.strip()).collection(name)
    return db.collection(name)


def send_message(chat_id, text, keyboard=None):
    payload = {
        "chat_id": chat_id,
        "text": text
    }

    if keyboard:
        payload["reply_markup"] = keyboard

    if not TELEGRAM_API:
        return

    try:
        resp = requests.post(f"{TELEGRAM_API}/sendMessage", json=payload, timeout=30)
        if resp.status_code < 200 or resp.status_code >= 300:
            print(f"Telegram sendMessage failed status={resp.status_code} body={resp.text}")
    except Exception as e:
        print(f"Telegram sendMessage exception: {e}")


def send_document(chat_id, file_path, caption=None):
    if not TELEGRAM_API:
        return False
    try:
        with open(file_path, "rb") as f:
            files = {"document": f}
            data = {"chat_id": str(chat_id)}
            if caption:
                data["caption"] = caption
            resp = requests.post(f"{TELEGRAM_API}/sendDocument", data=data, files=files, timeout=60)
            return resp.status_code >= 200 and resp.status_code < 300
    except Exception:
        return False


def save_user(chat_id, role, student_phone=None):
    user_ref = db.collection("users").document(str(chat_id))
    data = {"role": role}
    if student_phone:
        data["student_phone"] = student_phone
    user_ref.set(data, merge=True)


def get_user_by_phone(phone: str):
    docs = _ws_collection("students").where("phone", "==", phone).limit(1).get()
    if not docs:
        return None
    return docs[0].to_dict()


def get_student_by_phone(phone: str):
    return get_user_by_phone(phone)


def _normalize_phone_candidates(raw: str):
    text = (raw or '').strip()
    if not text:
        return []
    digits = ''.join(ch for ch in text if ch.isdigit())
    if not digits:
        return []

    country_code = ''.join(ch for ch in os.getenv('COUNTRY_CODE', '964') if ch.isdigit())
    candidates = []
    candidates.append(digits)

    if digits.startswith('0') and len(digits) > 1:
        without_zero = digits[1:]
        candidates.append(without_zero)
        if country_code and not without_zero.startswith(country_code):
            candidates.append(country_code + without_zero)

    if country_code and not digits.startswith(country_code):
        candidates.append(country_code + digits)

    seen = set()
    out = []
    for c in candidates:
        if c and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def _find_student_doc_for_student_phone(phone_raw: str):
    for cand in _normalize_phone_candidates(phone_raw):
        docs = _ws_collection('students').where('phone', '==', cand).limit(1).get()
        if docs:
            doc = docs[0]
            return doc.reference, (doc.to_dict() or {})
    return None, None


def _find_student_doc_for_parent_phone(phone_raw: str):
    parent_fields = ['parent_phone', 'parentPhone']
    for cand in _normalize_phone_candidates(phone_raw):
        for field in parent_fields:
            docs = _ws_collection('students').where(field, '==', cand).limit(1).get()
            if docs:
                doc = docs[0]
                return doc.reference, (doc.to_dict() or {})

    # Fallback: some data stores parent phone inside guardian encoded string:
    # primary_guardian = "name:...|phone:077...|..." (or camelCase)
    def _extract_phone_from_guardian(value: str):
        if not value:
            return None
        text = str(value)
        m = re.search(r"phone\s*[:=]\s*([+0-9]{7,})", text, flags=re.IGNORECASE)
        if not m:
            return None
        raw = m.group(1)
        digits = ''.join(ch for ch in raw if ch.isdigit())
        return digits or None

    wanted = set(_normalize_phone_candidates(phone_raw))

    guardian_fields = [
        'primary_guardian',
        'secondary_guardian',
        'primaryGuardian',
        'secondaryGuardian',
    ]

    def _scan_collection(col):
        for doc in col.stream():
            data = doc.to_dict() or {}
            for gfield in guardian_fields:
                g = data.get(gfield)
                p = _extract_phone_from_guardian(g)
                if not p:
                    continue
                for cand in _normalize_phone_candidates(p):
                    if cand in wanted:
                        return doc.reference, data, cand
        return None, None, None

    try:
        # 1) workspace-scoped (current behavior)
        ref, data, matched = _scan_collection(_ws_collection('students'))
        if ref is not None:
            # Write back parent_phone if missing to stabilize future lookups.
            try:
                existing = (data or {}).get('parent_phone')
                if (existing is None or str(existing).strip() == '') and matched:
                    ref.set({'parent_phone': matched}, merge=True)
            except Exception as e:
                print(f'parent phone writeback failed: {e}')
            return ref, data

        # 2) root-level fallback in case WORKSPACE_ID is misconfigured
        ref, data, matched = _scan_collection(db.collection('students'))
        if ref is not None:
            try:
                existing = (data or {}).get('parent_phone')
                if (existing is None or str(existing).strip() == '') and matched:
                    ref.set({'parent_phone': matched}, merge=True)
            except Exception as e:
                print(f'parent phone writeback failed: {e}')
            return ref, data
    except Exception as e:
        print(f'parent phone guardian fallback scan failed: {e}')

    return None, None


def _find_student_doc_by_phone(phone: str):
    docs = _ws_collection("students").where("phone", "==", phone).limit(1).get()
    if not docs:
        return None, None
    doc = docs[0]
    return doc.reference, (doc.to_dict() or {})


def _student_chat_field_for_role(role: str) -> str:
    r = (role or "").strip()
    if r == "طالب":
        return "telegram_student_chat_id"
    # ولي أمر
    return "telegram_parent_chat_id"


def send_message_text(chat_id, text):
    send_message(chat_id, text)


def send_group_text(chat_id, text):
    send_message(chat_id, text)


@app.route("/webhook", methods=["POST"])
def webhook():
    try:
        data = request.get_json(silent=True) or {}

        # Telegram may deliver different update types depending on chat type.
        # - groups/supergroups: message
        # - channels: channel_post
        # - when bot is added/removed: my_chat_member / chat_member
        message = data.get("message")
        if not isinstance(message, dict):
            message = data.get("channel_post")

        # membership updates
        member_update = data.get("my_chat_member") or data.get("chat_member")
        if not isinstance(message, dict) and not isinstance(member_update, dict):
            return "ok", 200

        chat = {}
        text = ""
        if isinstance(message, dict):
            chat = message.get("chat") or {}
            text = message.get("text", "")
        elif isinstance(member_update, dict):
            chat = member_update.get("chat") or {}

        chat_id = chat.get("id")
        if chat_id is None:
            return "ok", 200

        chat_type = (chat.get("type") or "").strip()
        if chat_type in ["group", "supergroup", "channel"]:
            title = chat.get("title") or chat.get("username") or "Unknown"
            _ws_collection("groups").document(str(chat_id)).set(
                {"chat_id": chat_id, "title": title, "type": chat_type},
                merge=True,
            )
            # For channels/groups we don't process linking flow.
            if chat_type != "private":
                return "ok", 200

        user_doc = db.collection("users").document(str(chat_id)).get()
        user_data = user_doc.to_dict() if user_doc.exists else None

        if text == "/start":
            keyboard = {
                "keyboard": [
                    [{"text": "طالب"}],
                    [{"text": "ولي أمر"}]
                ],
                "resize_keyboard": True,
                "one_time_keyboard": True
            }
            send_message(chat_id, "اختر نوع الحساب:", keyboard)
            return "ok", 200

        if text in ["طالب", "ولي أمر"]:
            save_user(chat_id, text)
            if text == "ولي أمر":
                send_message(
                    chat_id,
                    "هذه بوت استاذ باقر القره غولي لارسال التنبيهات و الدرجات\n"
                    "يرجى كتابة رقم ولي الامر المسجل لدينا\n"
                    "مثل 077XXXXXXXX",
                )
            else:
                send_message(
                    chat_id,
                    "هذه بوت استاذ باقر القره غولي لارسال التنبيهات و الدرجات\n"
                    "يرجى كتابة رقم الهاتف للطالب المسجل لدينا\n"
                    "مثل 077XXXXXXXX",
                )
            return "ok", 200

        if user_data:
            phone = (text or "").strip()
            role = (user_data.get("role", "") or "").strip()

            if role == "ولي أمر":
                student_ref, student_data = _find_student_doc_for_parent_phone(phone)
            else:
                student_ref, student_data = _find_student_doc_for_student_phone(phone)

            if student_ref is None:
                if role == "ولي أمر":
                    send_message(chat_id, "رقم ولي الامر غير موجود ❌")
                else:
                    send_message(chat_id, "رقم الطالب غير موجود ❌")
                return "ok", 200

            save_user(chat_id, role, phone)

            chat_field = _student_chat_field_for_role(role)
            existing_chat_id = student_data.get(chat_field)
            if existing_chat_id is not None and str(existing_chat_id) != str(chat_id):
                send_message(chat_id, "هذا الحساب مربوط مسبقًا بحساب تيليجرام آخر ❌")
                return "ok", 200

            student_ref.set({chat_field: chat_id}, merge=True)
            send_message(
                chat_id,
                "تم التسجيل ✅\n"
                "سيتم ارسال ملفات و تنبيهات وكل ما يخص الطالب هنا",
            )

        return "ok", 200
    except Exception as e:
        print(f"Webhook error: {e}")
        return "ok", 200


@app.route("/groups", methods=["GET"])
def get_groups():
    docs = _ws_collection("groups").get()
    groups = []
    for d in docs:
        data = d.to_dict() or {}
        groups.append({
            "chat_id": data.get("chat_id"),
            "title": data.get("title"),
        })
    return jsonify(groups)


@app.route("/send-user", methods=["POST"])
def send_user():
    data = request.json

    if TELEGRAM_API:
        requests.post(f"{TELEGRAM_API}/sendMessage", json=data)
    return {"status": "sent"}


@app.route("/send-group", methods=["POST"])
def send_group():
    data = request.json

    if TELEGRAM_API:
        requests.post(f"{TELEGRAM_API}/sendMessage", json=data)

    return {"status": "sent"}


@app.route("/send-document", methods=["POST"])
def send_document_endpoint():
    if not TELEGRAM_API:
        return jsonify({"status": "error", "message": "BOT_TOKEN not configured"}), 500

    chat_id = request.form.get("chat_id")
    caption = request.form.get("caption")
    uploaded = request.files.get("file")
    if not chat_id or uploaded is None:
        return jsonify({"status": "error", "message": "chat_id and file are required"}), 400

    # Save to a temp file then send
    tmp_dir = os.getenv("TMPDIR") or "/tmp"
    os.makedirs(tmp_dir, exist_ok=True)
    tmp_path = os.path.join(tmp_dir, uploaded.filename or "upload.bin")
    uploaded.save(tmp_path)

    ok = send_document(chat_id, tmp_path, caption=caption)
    try:
        os.remove(tmp_path)
    except Exception:
        pass

    if ok:
        return jsonify({"status": "sent"})
    return jsonify({"status": "error", "message": "failed to send document"}), 500


@app.route("/")
def home():
    return "Bot Running (Firestore v2)"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    app.run(host="0.0.0.0", port=port)
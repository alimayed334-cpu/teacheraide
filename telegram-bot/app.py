from flask import Flask, request, jsonify
import os
import json
import base64
import requests
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

        message = data.get("message")
        if not isinstance(message, dict):
            return "ok", 200

        chat = message.get("chat") or {}
        chat_id = chat.get("id")
        text = message.get("text", "")
        if chat_id is None:
            return "ok", 200

        if chat.get("type") in ["group", "supergroup"]:
            title = chat.get("title", "Unknown")
            _ws_collection("groups").document(str(chat_id)).set(
                {"chat_id": chat_id, "title": title},
                merge=True,
            )
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
            send_message(chat_id, "أدخل رقم الطالب:")
            return "ok", 200

        if user_data:
            phone = (text or "").strip()
            student_ref, student_data = _find_student_doc_by_phone(phone)
            if student_ref is None:
                send_message(chat_id, "رقم الطالب غير موجود ❌")
                return "ok", 200

            role = user_data.get("role", "")
            save_user(chat_id, role, phone)

            chat_field = _student_chat_field_for_role(role)
            existing_chat_id = student_data.get(chat_field)
            if existing_chat_id is not None and str(existing_chat_id) != str(chat_id):
                send_message(chat_id, "هذا الحساب مربوط مسبقًا بحساب تيليجرام آخر ❌")
                return "ok", 200

            student_ref.set({chat_field: chat_id}, merge=True)
            send_message(chat_id, "تم الربط ✅")

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
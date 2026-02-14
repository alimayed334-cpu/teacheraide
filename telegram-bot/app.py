from flask import Flask, request, jsonify
import os
import json
import base64
import requests
import firebase_admin
from firebase_admin import credentials, firestore

app = Flask(__name__)

BOT_TOKEN = os.getenv("BOT_TOKEN")
TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}" if BOT_TOKEN else ""


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


def send_message(chat_id, text, keyboard=None):
    payload = {
        "chat_id": chat_id,
        "text": text
    }

    if keyboard:
        payload["reply_markup"] = keyboard

    if not TELEGRAM_API:
        return

    requests.post(f"{TELEGRAM_API}/sendMessage", json=payload)


def save_user(chat_id, role, student_phone=None):
    user_ref = db.collection("users").document(str(chat_id))
    data = {"role": role}
    if student_phone:
        data["student_phone"] = student_phone
    user_ref.set(data, merge=True)


def get_student_by_phone(phone: str):
    docs = db.collection("students").where("phone", "==", phone).limit(1).get()
    if not docs:
        return None
    return docs[0].to_dict()


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
            db.collection("groups").document(str(chat_id)).set(
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
            student = get_student_by_phone(phone)
            if student:
                save_user(chat_id, user_data.get("role", ""), phone)
                send_message(chat_id, "تم الربط ✅")
            else:
                send_message(chat_id, "رقم الطالب غير موجود ❌")

        return "ok", 200
    except Exception as e:
        print(f"Webhook error: {e}")
        return "ok", 200


@app.route("/groups", methods=["GET"])
def get_groups():
    docs = db.collection("groups").get()
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


@app.route("/")
def home():
    return "Bot Running"


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 10000))
    app.run(host="0.0.0.0", port=port)
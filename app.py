from flask import Flask, request, jsonify
import psycopg2
import os
import requests

# ======================
# إعداد Flask
# ======================
app = Flask(name)

# ======================
# المتغيرات من Environment
# ======================
BOT_TOKEN = os.getenv("BOT_TOKEN")
DATABASE_URL = os.getenv("DATABASE_URL")

TELEGRAM_API = f"https://api.telegram.org/bot{BOT_TOKEN}"


# ======================
# دالة الاتصال بقاعدة البيانات
# ======================
def get_db():
    return psycopg2.connect(DATABASE_URL)


# ======================
# دالة إرسال الرسائل
# ======================
def send_message(chat_id, text, keyboard=None):
    payload = {
        "chat_id": chat_id,
        "text": text
    }

    if keyboard:
        payload["reply_markup"] = keyboard

    requests.post(f"{TELEGRAM_API}/sendMessage", json=payload)


# ======================
# Webhook لتلقي الرسائل من Telegram
# ======================
@app.route("/webhook", methods=["POST"])
def webhook():

    data = request.json

    if "message" not in data:
        return "ok"

    message = data["message"]
    chat = message["chat"]
    chat_id = chat["id"]
    text = message.get("text", "")

    conn = get_db()
    cur = conn.cursor()

    # إذا كانت الرسالة من جروب
    if chat["type"] in ["group", "supergroup"]:
        title = chat.get("title", "Unknown")

        cur.execute(
            """
            INSERT INTO groups (chat_id, title)
            VALUES (%s, %s)
            ON CONFLICT (chat_id)
            DO UPDATE SET title = EXCLUDED.title
            """,
            (chat_id, title),
        )

        conn.commit()
        cur.close()
        conn.close()
        return "ok"

    # تحقق من المستخدم
    cur.execute("SELECT role, student_id FROM users WHERE chat_id=%s", (chat_id,))
    user = cur.fetchone()

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

    elif text in ["طالب", "ولي أمر"]:

        cur.execute(
            """
            INSERT INTO users (chat_id, role)
            VALUES (%s, %s)
            ON CONFLICT (chat_id)
            DO UPDATE SET role = EXCLUDED.role
            """,
            (chat_id, text),
        )

        conn.commit()

        send_message(chat_id, "أدخل رقم الطالب:")

    elif user:

        phone = text.strip()

        cur.execute("SELECT id FROM students WHERE phone=%s", (phone,))
        student = cur.fetchone()

        if student:

            student_id = student[0]

            cur.execute(
                """
                UPDATE users
                SET student_id=%s
                WHERE chat_id=%s
                """,
                (student_id, chat_id),
            )

            conn.commit()

            send_message(chat_id, "تم التسجيل بنجاح ✅")

        else:
            send_message(chat_id, "رقم الطالب غير موجود ❌")

    cur.close()
    conn.close()

    return "ok"


# ======================
# جلب جميع الكروبات
# ======================
@app.route("/groups", methods=["GET"])
def get_groups():

    conn = get_db()
    cur = conn.cursor()

    cur.execute("SELECT chat_id, title FROM groups")
    groups = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify([
        {"chat_id": g[0], "title": g[1]}
        for g in groups
    ])


# ======================
# إرسال رسالة لمستخدم معين
# ======================
@app.route("/send-user", methods=["POST"])
def send_user():
    data = request.json

    requests.post(f"{TELEGRAM_API}/sendMessage", json=data)
    return {"status": "sent"}


# ======================
# إرسال رسالة للجروب
# ======================
@app.route("/send-group", methods=["POST"])
def send_group():
    data = request.json

    requests.post(f"{TELEGRAM_API}/sendMessage", json=data)

    return {"status": "sent"}

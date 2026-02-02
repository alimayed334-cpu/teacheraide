import os
import logging
import asyncio
import threading
import time
import atexit
import tempfile
import requests
from typing import Optional, Sequence

import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask, jsonify, request
from telegram import ReplyKeyboardMarkup, Update
from telegram.request import HTTPXRequest
from telegram.ext import (
    Application,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)


logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)


def _safe_filename_from_url(url: str) -> str:
    try:
        name = (url.split("?")[0].split("#")[0].rstrip("/").split("/")[-1] or "document")
        return name
    except Exception:
        return "document"


async def _send_document_with_fallback(*, bot, chat_id: int, file_url: str) -> None:
    """Try to send from temp.sh; if not PDF or download fails, try local file, else warn."""
    file_url = str(file_url).strip()
    if not file_url:
        return

    filename = _safe_filename_from_url(file_url)
    local_path = None

    # Attempt temp.sh download first
    try:
        with requests.get(file_url, stream=True, timeout=30, headers={"User-Agent": "teacher-aide-bot/1.0"}) as r:
            r.raise_for_status()
            with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{filename}") as tmp:
                tmp_path = tmp.name
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 256):
                    if chunk:
                        f.write(chunk)

        # Validate PDF header
        with open(tmp_path, "rb") as f_check:
            head = f_check.read(8)
        if not head.startswith(b"%PDF"):
            raise ValueError("downloaded_file_is_not_pdf")

        # Valid PDF: send it
        with open(tmp_path, "rb") as f:
            await bot.send_document(chat_id=int(chat_id), document=f, filename=filename)
        logger.info("Sent PDF from temp.sh: %s", filename)
        return
    except Exception as e:
        logger.warning("Temp.sh download/validate failed for %s: %s", file_url, e)
        # Clean up temp file if created
        try:
            if 'tmp_path' in locals():
                os.remove(tmp_path)
        except OSError:
            pass

    # Fallback: try local file if we can infer it (Flutter uses temp dir)
    try:
        import pathlib
        # Example: https://temp.sh/NCgZl/Documents___.pdf -> try local temp dir for Documents___.pdf
        guessed_name = filename if filename.lower().endswith('.pdf') else f"{filename}.pdf"
        # Try Windows temp first, then fallback
        for base_dir in [tempfile.gettempdir(), os.path.expanduser("~\\AppData\\Local\\Temp")]:
            candidate = pathlib.Path(base_dir) / guessed_name
            if candidate.is_file():
                with open(candidate, "rb") as f_check:
                    head = f_check.read(8)
                if head.startswith(b"%PDF"):
                    with open(candidate, "rb") as f:
                        await bot.send_document(chat_id=int(chat_id), document=f, filename=guessed_name)
                    logger.info("Sent local fallback PDF: %s", candidate)
                    return
    except Exception as fe:
        logger.debug("Local fallback failed: %s", fe)

    # If everything fails, send a warning message
    await bot.send_message(
        chat_id=int(chat_id),
        text="⚠️ فشل إرسال الملف، تم إرسال الرسالة فقط."
    )
    logger.warning("File sending failed for %s; sent warning message.", file_url)


async def _send_document_from_local_path(*, bot, chat_id: int, file_path: str) -> None:
    file_path = str(file_path).strip()
    if not file_path:
        return

    if not os.path.isfile(file_path):
        raise FileNotFoundError("local_file_not_found")

    try:
        with open(file_path, "rb") as f_check:
            head = f_check.read(8)
        if not head.startswith(b"%PDF"):
            raise ValueError("local_file_is_not_pdf")

        filename = os.path.basename(file_path) or "document.pdf"
        with open(file_path, "rb") as f:
            await bot.send_document(chat_id=int(chat_id), document=f, filename=filename)
        logger.info("Sent local PDF: %s", file_path)
    except Exception:
        logger.exception("Failed to send local PDF: %s", file_path)
        raise


async def _send_document_from_url(*, bot, chat_id: int, file_url: str) -> None:
    file_url = str(file_url).strip()
    if not file_url:
        return

    filename = _safe_filename_from_url(file_url)
    with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{filename}") as tmp:
        tmp_path = tmp.name

    try:
        with requests.get(file_url, stream=True, timeout=30, headers={"User-Agent": "teacher-aide-bot/1.0"}) as r:
            r.raise_for_status()
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=1024 * 256):
                    if chunk:
                        f.write(chunk)

        # Validate content: for PDFs we expect '%PDF' header.
        # temp.sh sometimes returns an HTML error page or text.
        with open(tmp_path, "rb") as f_check:
            head = f_check.read(8)
        if not head.startswith(b"%PDF"):
            raise ValueError("downloaded_file_is_not_pdf")

        with open(tmp_path, "rb") as f:
            await bot.send_document(chat_id=int(chat_id), document=f, filename=filename)
    finally:
        try:
            os.remove(tmp_path)
        except OSError:
            pass


def _pending_doc_sort_key(doc) -> float:
    try:
        data = doc.to_dict() or {}
        created_at = data.get("createdAt")
        if created_at is not None and hasattr(created_at, "timestamp"):
            return float(created_at.timestamp())
        if created_at is not None and isinstance(created_at, str):
            # best-effort; keep old string timestamps working
            return 0.0
    except Exception:
        pass

    try:
        # Firestore DocumentSnapshot has create_time
        ct = getattr(doc, "create_time", None)
        if ct is not None and hasattr(ct, "timestamp"):
            return float(ct.timestamp())
    except Exception:
        pass

    return 0.0


def _load_dotenv() -> None:
    dotenv_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if not os.path.exists(dotenv_path):
        return

    try:
        with open(dotenv_path, "r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip('"').strip("'")
                if not key:
                    continue
                os.environ[key] = value
    except OSError:
        return


def _get_env(name: str, default: Optional[str] = None) -> str:
    value = os.getenv(name, default)
    if value is None or value.strip() == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value.strip()


def _normalize_phone_candidates(raw: str) -> Sequence[str]:
    text = (raw or "").strip()
    if not text:
        return []

    digits = "".join(ch for ch in text if ch.isdigit())
    if not digits:
        return []

    country_code = "".join(ch for ch in os.getenv("COUNTRY_CODE", "964") if ch.isdigit())

    candidates = []

    # Keep raw digits (e.g., 077..., 9647..., 7...)
    candidates.append(digits)

    # 0XXXXXXXXX... -> XXXXXXXXX... (without leading 0)
    if digits.startswith("0") and len(digits) > 1:
        without_zero = digits[1:]
        candidates.append(without_zero)
        if country_code and not without_zero.startswith(country_code):
            candidates.append(country_code + without_zero)

    # XXXXXXXXX... -> COUNTRY_CODE + XXXXXXXXX... (when user types without 0 / without +country)
    if country_code and not digits.startswith(country_code):
        candidates.append(country_code + digits)

    # +9647... or 9647... should already become digits starting with 964
    # We keep it as-is above.

    seen = set()
    out = []
    for c in candidates:
        if c and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def _init_firestore() -> firestore.Client:
    sa_path = _get_env("FIREBASE_SERVICE_ACCOUNT", "serviceAccountKey.json")

    if not os.path.isabs(sa_path):
        base_dir = os.path.dirname(os.path.abspath(__file__))
        sa_path = os.path.join(base_dir, sa_path)

    if not firebase_admin._apps:
        cred = credentials.Certificate(sa_path)
        firebase_admin.initialize_app(cred)

    return firestore.client()


def _normalize_phone_digits(phone: str) -> str:
    digits = "".join(ch for ch in (phone or "") if ch.isdigit())
    country_code = "".join(ch for ch in os.getenv("COUNTRY_CODE", "964") if ch.isdigit())
    if digits.startswith("0") and len(digits) > 1:
        without_zero = digits[1:]
        if country_code and not without_zero.startswith(country_code):
            return country_code + without_zero
        return without_zero
    return digits


def _create_api_app(db: firestore.Client) -> Flask:
    app = Flask(__name__)

    @app.get("/health")
    def health() -> tuple:
        return jsonify({"ok": True}), 200

    @app.post("/upsert/student")
    def upsert_student() -> tuple:
        payload = request.get_json(silent=True) or {}
        student_id = str(payload.get("id") or "").strip()
        name = str(payload.get("name") or "").strip()
        phone_raw = (payload.get("phone") or "")
        phone = _normalize_phone_digits(str(phone_raw)) if str(phone_raw).strip() else None

        if not student_id or not name:
            return jsonify({"ok": False, "error": "missing_id_or_name"}), 400

        data = {
            "id": student_id,
            "name": name,
            "role": "student",
            "telegram_chat_id": None,
        }
        if phone:
            data["phone"] = phone

        db.collection(os.getenv("STUDENTS_COLLECTION", "students")).document(student_id).set(
            data, merge=True
        )
        return jsonify({"ok": True}), 200

    @app.post("/upsert/parent")
    def upsert_parent() -> tuple:
        payload = request.get_json(silent=True) or {}
        phone_raw = str(payload.get("phone") or "").strip()
        name_raw = str(payload.get("name") or "").strip() or None

        parent_id = _normalize_phone_digits(phone_raw)
        if not parent_id:
            return jsonify({"ok": False, "error": "missing_phone"}), 400

        data = {
            "id": parent_id,
            "phone": parent_id,
            "role": "parent",
            "telegram_chat_id": None,
        }
        if name_raw:
            data["name"] = name_raw

        db.collection(os.getenv("PARENTS_COLLECTION", "parents")).document(parent_id).set(
            data, merge=True
        )
        return jsonify({"ok": True, "id": parent_id}), 200

    @app.post("/delete/student")
    def delete_student() -> tuple:
        payload = request.get_json(silent=True) or {}
        student_id = str(payload.get("id") or "").strip()
        if not student_id:
            return jsonify({"ok": False, "error": "missing_id"}), 400
        db.collection(os.getenv("STUDENTS_COLLECTION", "students")).document(student_id).delete()
        return jsonify({"ok": True}), 200

    @app.get("/status")
    def status() -> tuple:
        student_id = str(request.args.get("studentId") or "").strip()
        parent_phone = str(request.args.get("parentPhone") or "").strip()
        result = {"student_linked": False, "parent_linked": False}

        if student_id:
            snap = db.collection(os.getenv("STUDENTS_COLLECTION", "students")).document(student_id).get()
            if snap.exists:
                chat_id = (snap.to_dict() or {}).get(os.getenv("CHAT_ID_FIELD", "telegram_chat_id"))
                result["student_linked"] = chat_id is not None

        if parent_phone:
            parent_id = _normalize_phone_digits(parent_phone)
            if parent_id:
                snap = db.collection(os.getenv("PARENTS_COLLECTION", "parents")).document(parent_id).get()
                if snap.exists:
                    chat_id = (snap.to_dict() or {}).get(os.getenv("CHAT_ID_FIELD", "telegram_chat_id"))
                    result["parent_linked"] = chat_id is not None

        return jsonify(result), 200

    @app.post("/enqueue")
    def enqueue() -> tuple:
        payload = request.get_json(silent=True) or {}
        recipient_type = str(payload.get("recipientType") or "").strip()
        recipient_id = str(payload.get("recipientId") or "").strip()
        message = str(payload.get("message") or "").strip()
        file_url = payload.get("fileUrl")
        file_path = payload.get("filePath")

        if not recipient_type or not recipient_id or not message:
            return jsonify({"ok": False, "error": "missing_fields"}), 400

        outbox = os.getenv("TELEGRAM_OUTBOX_COLLECTION", "telegram_outbox")
        db.collection(outbox).add(
            {
                "recipientType": recipient_type,
                "recipientId": recipient_id,
                "message": message,
                "fileUrl": file_url if (str(file_url).strip() if file_url is not None else "") else None,
                "filePath": file_path if (str(file_path).strip() if file_path is not None else "") else None,
                "status": "pending",
                "createdAt": firestore.SERVER_TIMESTAMP,
                "sentAt": None,
                "error": None,
            }
        )
        return jsonify({"ok": True}), 200

    return app


def _run_api_server(db: firestore.Client) -> None:
    host = os.getenv("BOT_API_HOST", "127.0.0.1")
    port = int(os.getenv("BOT_API_PORT", "5005"))
    app = _create_api_app(db)
    app.run(host=host, port=port, debug=False, use_reloader=False)


async def _link_chat_id_by_phone(
    *,
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
    phone_raw: str,
    chat_id: int,
    role: str,
) -> None:
    db: firestore.Client = context.application.bot_data["db"]

    students_collection = os.getenv("STUDENTS_COLLECTION", "students")
    parents_collection = os.getenv("PARENTS_COLLECTION", "parents")
    phone_field = os.getenv("PHONE_FIELD", "phone")
    chat_id_field = os.getenv("CHAT_ID_FIELD", "telegram_chat_id")

    collection = students_collection if role == "student" else parents_collection

    candidates = _normalize_phone_candidates(phone_raw)
    if not candidates:
        await update.message.reply_text("رقم الهاتف غير صالح ❌")
        return

    try:
        matches = []
        for candidate in candidates:
            docs = db.collection(collection).where(phone_field, "==", candidate).stream()
            for d in docs:
                matches.append(d)

        seen_ids = set()
        unique_matches = []
        for d in matches:
            if d.id not in seen_ids:
                seen_ids.add(d.id)
                unique_matches.append(d)

        if not unique_matches:
            await update.message.reply_text("الرقم غير مسجل لدينا ❌")
            return

        if len(unique_matches) == 1:
            db.collection(collection).document(unique_matches[0].id).update({chat_id_field: chat_id})
            await update.message.reply_text("تم الربط بنجاح 🎉")
            return

        context.user_data["pending_link_collection"] = collection
        context.user_data["pending_link_docs"] = [d.id for d in unique_matches]
        context.user_data["pending_link_chat_id"] = chat_id
        context.user_data["pending_link_field"] = chat_id_field

        lines = ["تم العثور على أكثر من اسم لهذا الرقم. اختر الرقم المناسب:"]
        for idx, d in enumerate(unique_matches, start=1):
            data = d.to_dict() or {}
            name = data.get("name") or d.id
            lines.append(f"{idx}) {name}")
        await update.message.reply_text("\n".join(lines))
    except Exception as e:
        await update.message.reply_text(
            "تعذر الاتصال بقاعدة البيانات حالياً. تأكد أن Firestore مفعّل وأن ملف Service Account يعود لنفس مشروع Firebase."
        )
        print(f"Firestore error: {e}")


async def _handle_pending_link_choice(update: Update, context: ContextTypes.DEFAULT_TYPE, text: str) -> bool:
    if update.message is None:
        return False
    docs = context.user_data.get("pending_link_docs")
    if not docs:
        return False

    try:
        choice = int(text.strip())
    except ValueError:
        await update.message.reply_text("اكتب رقم الخيار فقط (مثال: 1)")
        return True

    if choice < 1 or choice > len(docs):
        await update.message.reply_text("رقم غير صحيح. اختر رقم من القائمة.")
        return True

    collection = context.user_data.get("pending_link_collection")
    chat_id = context.user_data.get("pending_link_chat_id")
    field = context.user_data.get("pending_link_field")
    if not collection or not chat_id or not field:
        context.user_data.pop("pending_link_docs", None)
        return False

    doc_id = docs[choice - 1]
    db: firestore.Client = context.application.bot_data["db"]
    try:
        db.collection(collection).document(doc_id).update({field: chat_id})
        await update.message.reply_text("تم الربط بنجاح 🎉")
    except Exception as e:
        await update.message.reply_text("تعذر تحديث البيانات حالياً")
        print(f"Firestore link update error: {e}")

    context.user_data.pop("pending_link_collection", None)
    context.user_data.pop("pending_link_docs", None)
    context.user_data.pop("pending_link_chat_id", None)
    context.user_data.pop("pending_link_field", None)
    return True


async def _process_outbox(context: ContextTypes.DEFAULT_TYPE) -> None:
    db: firestore.Client = context.application.bot_data["db"]
    outbox_collection = os.getenv("TELEGRAM_OUTBOX_COLLECTION", "telegram_outbox")
    students_collection = os.getenv("STUDENTS_COLLECTION", "students")
    parents_collection = os.getenv("PARENTS_COLLECTION", "parents")
    chat_id_field = os.getenv("CHAT_ID_FIELD", "telegram_chat_id")

    try:
        pending_stream = (
            db.collection(outbox_collection)
            .where("status", "==", "pending")
            .limit(15)
            .stream()
        )

        pending = sorted(list(pending_stream), key=_pending_doc_sort_key)

        if pending:
            logger.info("Outbox: found %s pending message(s)", len(pending))
        else:
            logger.debug("Outbox: no pending messages")

        for doc in pending:
            data = doc.to_dict() or {}
            recipient_type = (data.get("recipientType") or "").strip()
            recipient_id = (data.get("recipientId") or "").strip()
            message = (data.get("message") or "").strip()
            file_url = data.get("fileUrl")
            file_path = data.get("filePath")

            logger.info(
                "Outbox: processing doc=%s recipientType=%s recipientId=%s hasFile=%s",
                getattr(doc, "id", ""),
                recipient_type,
                recipient_id,
                bool(file_path or file_url),
            )
            try:
                fp_preview = str(file_path)[:160] if file_path is not None else None
                fu_preview = str(file_url)[:160] if file_url is not None else None
                logger.info("Outbox: doc=%s filePath=%s fileUrl=%s", getattr(doc, "id", ""), fp_preview, fu_preview)
            except Exception:
                pass

            if not recipient_type or not recipient_id or not message:
                try:
                    doc.reference.update({"status": "failed", "error": "invalid_payload"})
                except Exception as update_error:
                    logger.exception("Outbox: failed to update invalid_payload for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
                continue

            chat_id = None
            if recipient_type == "student":
                snap = db.collection(students_collection).document(recipient_id).get()
                if snap.exists:
                    chat_id = (snap.to_dict() or {}).get(chat_id_field)
            elif recipient_type == "parent":
                snap = db.collection(parents_collection).document(recipient_id).get()
                if snap.exists:
                    chat_id = (snap.to_dict() or {}).get(chat_id_field)
            else:
                try:
                    doc.reference.update({"status": "failed", "error": "unknown_recipient_type"})
                except Exception as update_error:
                    logger.exception("Outbox: failed to update unknown_recipient_type for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
                continue

            if chat_id is None:
                try:
                    doc.reference.update({"status": "failed", "error": "not_linked"})
                except Exception as update_error:
                    logger.exception("Outbox: failed to update not_linked for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
                continue

            try:
                await context.bot.send_message(chat_id=int(chat_id), text=message)
                if file_path:
                    try:
                        await _send_document_from_local_path(bot=context.bot, chat_id=int(chat_id), file_path=str(file_path))
                    except Exception as file_error:
                        print(f"File sending error for local {file_path}: {file_error}")
                        doc.reference.update({
                            "status": "sent",
                            "sentAt": firestore.SERVER_TIMESTAMP,
                            "error": f"File error: {str(file_error)[:200]}"
                        })
                        continue
                elif file_url:
                    try:
                        await _send_document_with_fallback(bot=context.bot, chat_id=int(chat_id), file_url=str(file_url))
                    except Exception as file_error:
                        print(f"File sending error for {file_url}: {file_error}")
                        doc.reference.update({
                            "status": "sent",
                            "sentAt": firestore.SERVER_TIMESTAMP,
                            "error": f"File error: {str(file_error)[:200]}"
                        })
                        continue
                doc.reference.update({"status": "sent", "sentAt": firestore.SERVER_TIMESTAMP, "error": None})
            except Exception as e:
                print(f"Telegram sending error: {e}")
                doc.reference.update({"status": "failed", "error": str(e)[:500]})

    except Exception as e:
        print(f"Outbox processing error: {e}")


async def _process_outbox_with_bot(*, bot, db: firestore.Client) -> None:
    outbox_collection = os.getenv("TELEGRAM_OUTBOX_COLLECTION", "telegram_outbox")
    students_collection = os.getenv("STUDENTS_COLLECTION", "students")
    parents_collection = os.getenv("PARENTS_COLLECTION", "parents")
    chat_id_field = os.getenv("CHAT_ID_FIELD", "telegram_chat_id")

    try:
        pending_stream = (
            db.collection(outbox_collection)
            .where("status", "==", "pending")
            .limit(15)
            .stream()
        )

        pending = sorted(list(pending_stream), key=_pending_doc_sort_key)

        for doc in pending:
            data = doc.to_dict() or {}
            recipient_type = (data.get("recipientType") or "").strip()
            recipient_id = (data.get("recipientId") or "").strip()
            message = (data.get("message") or "").strip()
            file_url = data.get("fileUrl")
            file_path = data.get("filePath")

            if not recipient_type or not recipient_id or not message:
                doc.reference.update({"status": "failed", "error": "invalid_payload"})
                continue

            try:
                fp_preview = str(file_path)[:160] if file_path is not None else None
                fu_preview = str(file_url)[:160] if file_url is not None else None
                logger.info("Outbox2: doc=%s filePath=%s fileUrl=%s", getattr(doc, "id", ""), fp_preview, fu_preview)
            except Exception:
                pass

            chat_id = None
            if recipient_type == "student":
                snap = db.collection(students_collection).document(recipient_id).get()
                if snap.exists:
                    chat_id = (snap.to_dict() or {}).get(chat_id_field)
            elif recipient_type == "parent":
                snap = db.collection(parents_collection).document(recipient_id).get()
                if snap.exists:
                    chat_id = (snap.to_dict() or {}).get(chat_id_field)
            else:
                doc.reference.update({"status": "failed", "error": "unknown_recipient_type"})
                continue

            if chat_id is None:
                doc.reference.update({"status": "failed", "error": "not_linked"})
                continue
            try:
                await bot.send_message(chat_id=int(chat_id), text=message)
                if file_path:
                    try:
                        await _send_document_from_local_path(bot=bot, chat_id=int(chat_id), file_path=str(file_path))
                    except Exception as file_error:
                        print(f"File sending error for local {file_path}: {file_error}")
                        try:
                            doc.reference.update({
                                "status": "sent",
                                "sentAt": firestore.SERVER_TIMESTAMP,
                                "error": f"File error: {str(file_error)[:200]}"
                            })
                        except Exception as update_error:
                            logger.exception("Outbox: failed to update sent (file error) for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
                        continue
                elif file_url:
                    try:
                        await _send_document_with_fallback(bot=bot, chat_id=int(chat_id), file_url=str(file_url))
                    except Exception as file_error:
                        print(f"File sending error for {file_url}: {file_error}")
                        try:
                            doc.reference.update({
                                "status": "sent",
                                "sentAt": firestore.SERVER_TIMESTAMP,
                                "error": f"File error: {str(file_error)[:200]}"
                            })
                        except Exception as update_error:
                            logger.exception("Outbox: failed to update sent (file error) for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
                        continue
                try:
                    doc.reference.update({"status": "sent", "sentAt": firestore.SERVER_TIMESTAMP, "error": None})
                except Exception as update_error:
                    logger.exception("Outbox: failed to update sent for doc=%s", getattr(doc, "id", ""), exc_info=update_error)
            except Exception as e:
                print(f"Telegram sending error: {e}")
                try:
                    doc.reference.update({"status": "failed", "error": str(e)[:500]})
                except Exception as update_error:
                    logger.exception("Outbox: failed to update failed for doc=%s", getattr(doc, "id", ""), exc_info=update_error)

    except Exception as e:
        print(f"Outbox processing error: {e}")


def _start_outbox_loop(*, bot, db: firestore.Client) -> None:
    interval = int(os.getenv("OUTBOX_POLL_SECONDS", "5"))

    # Use a dedicated, long-lived event loop in this thread.
    # This prevents: RuntimeError('Event loop is closed') which can happen when
    # repeatedly creating/closing loops via asyncio.run().
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    while True:
        try:
            logger.debug("Outbox loop tick")
            loop.run_until_complete(_process_outbox_with_bot(bot=bot, db=db))
        except Exception as e:
            logger.exception("Outbox loop error", exc_info=e)
        time.sleep(max(1, interval))


async def _job_process_outbox(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Run outbox processing inside PTB's event loop (prevents 'Event loop is closed')."""
    try:
        db: firestore.Client = context.application.bot_data["db"]
        await _process_outbox_with_bot(bot=context.bot, db=db)
    except Exception as e:
        logger.exception("Outbox job error", exc_info=e)


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    keyboard = [["📚 طالب", "👪 ولي أمر"]]
    reply_markup = ReplyKeyboardMarkup(keyboard, one_time_keyboard=True, resize_keyboard=True)
    await update.message.reply_text("مرحباً! هل أنت طالب أم ولي أمر؟", reply_markup=reply_markup)


async def handle_role(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message is None:
        return

    text = (update.message.text or "").strip()

    if text == "📚 طالب":
        context.user_data["role"] = "student"
        context.user_data["awaiting_phone"] = True
        await update.message.reply_text("اكتب رقم هاتفك الآن (مثال: 07712345678)")
        return

    if text == "👪 ولي أمر":
        context.user_data["role"] = "parent"
        context.user_data["awaiting_phone"] = True
        await update.message.reply_text("اكتب رقم هاتفك الآن (مثال: 07712345678)")
        return

    await update.message.reply_text("اختر من الأزرار: 📚 طالب أو 👪 ولي أمر")


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if update.message is None:
        return

    text = (update.message.text or "").strip()
    if not text:
        return

    if await _handle_pending_link_choice(update, context, text):
        return

    # If we are awaiting manual phone, treat any text as a phone number
    if context.user_data.get("awaiting_phone") is True:
        role = context.user_data.get("role")
        if role not in ("student", "parent"):
            await update.message.reply_text("اضغط /start ثم اختر الدور أولاً")
            return
        context.user_data.pop("awaiting_phone", None)
        chat_id = update.message.chat_id
        await _link_chat_id_by_phone(update=update, context=context, phone_raw=text, chat_id=chat_id, role=role)
        return

    # Otherwise, treat it as role selection
    await handle_role(update, context)

def main() -> None:
    _load_dotenv()
    token = _get_env("BOT_TOKEN")
    db = _init_firestore()

    disable_polling = (os.getenv("DISABLE_POLLING", "").strip().lower() in {"1", "true", "yes"})

    token_prefix = "".join(ch for ch in token[:16] if ch.isalnum())
    lock_suffix = "_outbox" if disable_polling else ""
    lock_path = os.path.join(tempfile.gettempdir(), f"teacher_aide_telegram_bot_{token_prefix}{lock_suffix}.lock")
    lock_fd = None
    try:
        lock_fd = os.open(lock_path, os.O_CREAT | os.O_EXCL | os.O_RDWR)
        os.write(lock_fd, str(os.getpid()).encode("utf-8"))
    except FileExistsError:
        raise SystemExit(
            "Bot is already running. Close the other bot window/process first."
        )

    def _cleanup_lock() -> None:
        try:
            if lock_fd is not None:
                os.close(lock_fd)
        except OSError:
            pass
        try:
            os.remove(lock_path)
        except OSError:
            pass

    atexit.register(_cleanup_lock)

    api_thread = threading.Thread(target=_run_api_server, args=(db,), daemon=True)
    api_thread.start()

    logger.info("Bot starting (token_prefix=%s)", token[:10] + "...")

    tg_request = HTTPXRequest(
        connection_pool_size=int(os.getenv("TELEGRAM_HTTP_POOL_SIZE", "64")),
        pool_timeout=float(os.getenv("TELEGRAM_HTTP_POOL_TIMEOUT", "60")),
        connect_timeout=float(os.getenv("TELEGRAM_HTTP_CONNECT_TIMEOUT", "30")),
        read_timeout=float(os.getenv("TELEGRAM_HTTP_READ_TIMEOUT", "60")),
        write_timeout=float(os.getenv("TELEGRAM_HTTP_WRITE_TIMEOUT", "60")),
    )

    app = (
        Application.builder()
        .token(token)
        .request(tg_request)
        .build()
    )
    app.bot_data["db"] = db

    # Prefer JobQueue (same event loop) if available. Some installs do not include
    # the optional job-queue extra, in which case app.job_queue is None.
    interval = int(os.getenv("OUTBOX_POLL_SECONDS", "5"))
    if disable_polling:
        outbox_thread = threading.Thread(
            target=_start_outbox_loop,
            kwargs={"bot": app.bot, "db": db},
            daemon=True,
        )
        outbox_thread.start()
    else:
        if getattr(app, "job_queue", None) is not None:
            app.job_queue.run_repeating(_job_process_outbox, interval=interval, first=1)
        else:
            outbox_thread = threading.Thread(
                target=_start_outbox_loop,
                kwargs={"bot": app.bot, "db": db},
                daemon=True,
            )
            outbox_thread.start()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))

    async def _error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
        logger.exception("Unhandled error while processing update=%s", update, exc_info=context.error)

    app.add_error_handler(_error_handler)

    if disable_polling:
        logger.warning("DISABLE_POLLING=1: running outbox loop only (no Telegram polling/getUpdates).")
        while True:
            time.sleep(3600)

    # Network/DNS on Windows can fail intermittently. Keep retrying instead of exiting,
    # otherwise outbox messages remain stuck in 'pending'.
    while True:
        try:
            app.run_polling(allowed_updates=Update.ALL_TYPES, drop_pending_updates=True)
            break
        except Exception as e:
            logger.exception("Bot polling crashed; retrying in 10s", exc_info=e)
            time.sleep(10)


if __name__ == "__main__":
    main()

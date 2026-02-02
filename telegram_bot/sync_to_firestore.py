import json
import os
from typing import Any, Dict, List, Optional

import firebase_admin
from firebase_admin import credentials, firestore


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
                os.environ.setdefault(key, value)
    except OSError:
        return


def _get_env(name: str, default: Optional[str] = None) -> str:
    value = os.getenv(name, default)
    if value is None or value.strip() == "":
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value.strip()


def _init_firestore() -> firestore.Client:
    sa_path = _get_env("FIREBASE_SERVICE_ACCOUNT", "serviceAccountKey.json")

    if not os.path.isabs(sa_path):
        base_dir = os.path.dirname(os.path.abspath(__file__))
        sa_path = os.path.join(base_dir, sa_path)

    if not firebase_admin._apps:
        cred = credentials.Certificate(sa_path)
        firebase_admin.initialize_app(cred)

    return firestore.client()


def _safe_parent_doc_id(phone: str) -> str:
    # Firestore doc ids can contain many chars, but keep it stable and simple.
    digits = "".join(ch for ch in (phone or "") if ch.isdigit())
    return digits or phone


def _normalize_phone_for_lookup(phone: Optional[str]) -> Optional[str]:
    text = (phone or "").strip()
    if not text:
        return None
    digits = "".join(ch for ch in text if ch.isdigit())
    if not digits:
        return None

    country_code = "".join(ch for ch in os.getenv("COUNTRY_CODE", "964") if ch.isdigit())

    if digits.startswith("0") and len(digits) > 1:
        without_zero = digits[1:]
        if country_code and not without_zero.startswith(country_code):
            return country_code + without_zero
        return without_zero

    return digits


def _read_export(path: str) -> List[Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if isinstance(data, dict) and "students" in data and isinstance(data["students"], list):
        return data["students"]

    if isinstance(data, list):
        return data

    raise ValueError("Unsupported export format. Expected {'students':[...]} or a list.")


def sync(export_path: str) -> None:
    _load_dotenv()

    db = _init_firestore()

    students_collection = os.getenv("STUDENTS_COLLECTION", "students")
    parents_collection = os.getenv("PARENTS_COLLECTION", "parents")

    # We will write these fields in Firestore.
    student_phone_field = os.getenv("PHONE_FIELD", "phone")
    parent_phone_field = os.getenv("PHONE_FIELD", "phone")

    students = _read_export(export_path)

    batch = db.batch()
    ops = 0

    def commit_if_needed() -> None:
        nonlocal batch, ops
        if ops >= 450:
            batch.commit()
            batch = db.batch()
            ops = 0

    for s in students:
        student_id = str(s.get("id") or "").strip()
        if not student_id:
            continue

        phone_number = _normalize_phone_for_lookup(str(s.get("phoneNumber") or ""))
        parent_phone = _normalize_phone_for_lookup(str(s.get("parentPhone") or ""))

        student_doc = db.collection(students_collection).document(student_id)

        student_payload: Dict[str, Any] = {
            "id": student_id,
            "name": s.get("name"),
            "age": s.get("age"),
            "grade": s.get("grade"),
            "classId": s.get("classId"),
            "address": s.get("address"),
            "imageUrl": s.get("imageUrl"),
            "createdAt": s.get("createdAt"),
            "updatedAt": s.get("updatedAt"),
            "examIds": s.get("examIds"),
        }

        if phone_number:
            student_payload[student_phone_field] = phone_number

        # merge=True so we don't wipe telegram_chat_id if it already exists
        batch.set(student_doc, student_payload, merge=True)
        ops += 1
        commit_if_needed()

        if parent_phone:
            parent_doc_id = _safe_parent_doc_id(parent_phone)
            parent_doc = db.collection(parents_collection).document(parent_doc_id)

            parent_payload: Dict[str, Any] = {
                parent_phone_field: parent_phone,
                "studentIds": firestore.ArrayUnion([student_id]),
            }

            batch.set(parent_doc, parent_payload, merge=True)
            ops += 1
            commit_if_needed()

    if ops > 0:
        batch.commit()


def main() -> None:
    export_path = _get_env("EXPORT_JSON_PATH", "students_export.json")
    if not os.path.isabs(export_path):
        export_path = os.path.join(os.getcwd(), export_path)

    if not os.path.exists(export_path):
        raise FileNotFoundError(
            f"Export file not found: {export_path}\n"
            "Tip: export from the app (زر تصدير الطلاب) ثم انسخ الملف إلى telegram_bot/students_export.json"
        )

    sync(export_path)
    print("Sync completed.")


if __name__ == "__main__":
    main()

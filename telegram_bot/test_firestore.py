import firebase_admin
from firebase_admin import credentials, firestore

try:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)
    db = firestore.client()
    
    # Test connection
    docs = db.collection("students").stream()
    print("SUCCESS: Firestore connected successfully")
    print("Collections in 'students':")
    for doc in docs:
        print(f"  - {doc.id}: {doc.to_dict()}")
    
    if not list(db.collection("students").stream()):
        print("WARNING: Collection 'students' is empty or doesn't exist yet")
    
except Exception as e:
    print(f"ERROR: Error connecting to Firestore: {e}")
    print(f"   Type: {type(e).__name__}")

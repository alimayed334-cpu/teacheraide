import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class AuthApiService {
  static final fb.FirebaseAuth _auth = fb.FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<fb.UserCredential> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final u = cred.user;
    if (u != null && (displayName ?? '').trim().isNotEmpty) {
      await u.updateDisplayName(displayName!.trim());
    }

    return cred;
  }

  static Future<fb.UserCredential> login({
    required String email,
    required String password,
  }) async {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> logout() => _auth.signOut();

  static fb.User? currentUser() => _auth.currentUser;

  static DocumentReference<Map<String, dynamic>> userDoc(String uid) {
    return _db.collection('users').doc(uid);
  }

  static Future<Map<String, dynamic>?> getMyUserDoc() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final snap = await userDoc(uid).get();
    return snap.data();
  }

  static Future<String?> getMyRole() async {
    final data = await getMyUserDoc();
    return data?['role']?.toString();
  }

  static Future<String?> getMyWorkspaceId() async {
    final data = await getMyUserDoc();
    return data?['workspaceId']?.toString();
  }

  static Future<void> upsertMyProfile({
    required String email,
    required String name,
    String? role,
    String? workspaceId,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not authenticated');
    }

    await userDoc(uid).set(
      {
        'email': email.trim(),
        'name': name.trim(),
        if (role != null) 'role': role,
        if (workspaceId != null) 'workspaceId': workspaceId,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> setUserRole({
    required String uid,
    required String role,
    String? workspaceId,
  }) async {
    await userDoc(uid).set(
      {
        'role': role,
        if (workspaceId != null) 'workspaceId': workspaceId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<void> banUser({
    required String uid,
    required bool banned,
  }) async {
    await userDoc(uid).set(
      {
        'role': banned ? 'banned' : 'user',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> listUsers() async {
    final snap = await _db.collection('users').get();
    return snap.docs;
  }
}

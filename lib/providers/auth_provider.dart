import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/sync_service.dart';
import '../database/database_helper.dart';
import '../firebase_options.dart';

enum UserRole { admin, assistant, user, banned }

class User {
  final String name;
  final String email;

  User({required this.name, required this.email});
}

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = true;

  String? _userEmail;
  String? _userName;
  UserRole _userRole = UserRole.assistant;
  String? _workspaceId;

  bool _useLocalAuth = false;
  String? _localPassword;

  String? _lastBootstrapError;
  String? _lastAuthError;

  StreamSubscription<fb.User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;

  Future<void>? _ensureUserDocInFlight;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  UserRole get userRole => _userRole;
  String? get workspaceId => _workspaceId;
  String? get lastBootstrapError => _lastBootstrapError;
  String? get lastAuthError => _lastAuthError;
  User? get user => _userName != null ? User(name: _userName!, email: _userEmail ?? '') : null;

  static const String _kAuthIsAuthenticated = 'auth_is_authenticated';
  static const String _kAuthEmail = 'auth_email';
  static const String _kAuthName = 'auth_name';
  static const String _kAuthPassword = 'auth_password';

  AuthProvider() {
    _init();
  }

  Future<void> _updateSyncServiceState() async {
    try {
      final ws = _workspaceId;
      final approved = _userRole == UserRole.admin || _userRole == UserRole.assistant;
      final blocked = _userRole == UserRole.banned;

      if (!_useLocalAuth && approved && !blocked && (ws ?? '').isNotEmpty) {
        // One-time safe wipe (admin only) to remove local test data before first sync.
        if (_userRole == UserRole.admin) {
          final prefs = await SharedPreferences.getInstance();
          final key = 'local_wipe_done_${ws!}';
          final done = prefs.getBool(key) ?? false;
          if (!done) {
            await DatabaseHelper().wipeLocalAppDataPreservingSync();
            await prefs.setBool(key, true);
          }
        }

        await SyncService.instance.start(workspaceId: ws!);
        return;
      }

      await SyncService.instance.stop();
    } catch (_) {
      // Never block auth if sync fails.
    }
  }

  Future<bool> updateUserRole({
    required String userId,
    required UserRole role,
  }) async {
    if (_useLocalAuth) return false;
    if (_userRole != UserRole.admin) return false;

    final myUid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && userId == myUid) {
      return false;
    }

    try {
      final data = <String, dynamic>{
        'role': role.name,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // When promoting a user into the app, assign them to the same workspace.
      if ((role == UserRole.admin || role == UserRole.assistant) && (_workspaceId ?? '').isNotEmpty) {
        data['workspaceId'] = _workspaceId;
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        data,
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      debugPrint('خطأ في تحديث الدور: $e');
      return false;
    }
  }

  Future<bool> setUserBanned({
    required String userId,
    required bool banned,
  }) async {
    if (_useLocalAuth) return false;
    if (_userRole != UserRole.admin) return false;

    final myUid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && userId == myUid) {
      return false;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'role': banned ? UserRole.banned.name : UserRole.assistant.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      debugPrint('خطأ في تحديث الحظر: $e');
      return false;
    }
  }

  Future<bool> softDeleteUser({
    required String userId,
  }) async {
    if (_useLocalAuth) return false;
    if (_userRole != UserRole.admin) return false;

    final myUid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && userId == myUid) {
      return false;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).set(
        {
          'role': UserRole.banned.name,
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (e) {
      debugPrint('خطأ في حذف المستخدم: $e');
      return false;
    }
  }

  Future<bool> register(String name, String email, String password) async {
    if (_useLocalAuth) {
      // Local mode: treat as authenticate (first use creates account).
      return _authenticateLocal(name, email, password);
    }

    _isLoading = true;
    _lastAuthError = null;
    notifyListeners();

    try {
      final trimmedEmail = email.trim();
      final trimmedName = name.trim();

      debugPrint('authenticate: start email=$trimmedEmail');

      final credential = await fb.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );

      final u = credential.user;
      if (u == null) {
        debugPrint('authenticate: credential.user is null');
        _isLoading = false;
        notifyListeners();
        return false;
      }

      debugPrint('authenticate: success uid=${u.uid} email=${u.email}');

      if (trimmedName.isNotEmpty) {
        await u.updateDisplayName(trimmedName);
      }

      _userEmail = u.email;
      _userName = (u.displayName ?? '').trim().isEmpty ? (u.email ?? '') : u.displayName;

      await _ensureUserDoc(u.uid);

      _isAuthenticated = true;
      _lastAuthError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('خطأ في التسجيل: ${e.code} ${e.message}');
      _lastAuthError = '${e.code}: ${e.message ?? ''}'.trim();
    } catch (e) {
      debugPrint('خطأ في التسجيل: $e');
      _lastAuthError = e.toString();
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> changePassword(String oldPassword, String newPassword) async {
    if (!_isAuthenticated) return false;

    if (_useLocalAuth) {
      // Not supported in local fallback beyond the old behavior.
      // Keep it simple: verify old password matches and overwrite.
      _isLoading = true;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedPassword = prefs.getString(_kAuthPassword);
        if (storedPassword == null || storedPassword != oldPassword) {
          _isLoading = false;
          notifyListeners();
          return false;
        }
        _localPassword = newPassword;
        await _persistLocalAuthState();
        _isLoading = false;
        notifyListeners();
        return true;
      } catch (e) {
        debugPrint('خطأ في تغيير كلمة المرور: $e');
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }

    _isLoading = true;
    notifyListeners();

    try {
      final u = fb.FirebaseAuth.instance.currentUser;
      final email = u?.email;
      if (u == null || email == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final credential = fb.EmailAuthProvider.credential(
        email: email,
        password: oldPassword,
      );
      await u.reauthenticateWithCredential(credential);
      await u.updatePassword(newPassword);

      _isLoading = false;
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('خطأ في تغيير كلمة المرور: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('خطأ في تغيير كلمة المرور: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    if (_useLocalAuth) {
      return [];
    }

    // UI-level guard; real enforcement will be via Firestore Security Rules.
    if (_userRole != UserRole.admin) {
      return [];
    }

    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      return snap.docs.map((d) {
        final data = d.data();
        return {
          'id': d.id,
          'name': data['name'],
          'email': data['email'],
          'role': data['role'],
          'workspaceId': data['workspaceId'],
          'createdAt': data['createdAt'],
          'updatedAt': data['updatedAt'],
        };
      }).toList();
    } catch (e) {
      debugPrint('خطأ في تحميل المستخدمين: $e');
      return [];
    }
  }

  Future<void> _init() async {
    _isLoading = true;
    notifyListeners();

    // Some platforms/builds might reach here before Firebase is initialized.
    // Try initializing first; only fallback to local auth if initialization is truly unavailable.
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } on UnsupportedError {
        // Unsupported platform; allow local fallback.
      } catch (e) {
        debugPrint('Firebase init in AuthProvider failed: $e');
      }
    }

    final firebaseReady = Firebase.apps.isNotEmpty;
    debugPrint('AuthProvider init: firebaseReady=$firebaseReady apps=${Firebase.apps.length}');
    if (!firebaseReady) {
      _useLocalAuth = true;
      debugPrint('AuthProvider init: using local auth fallback');
      await _loadLocalAuthState();
      return;
    }

    _useLocalAuth = false;
    debugPrint('AuthProvider init: using Firebase auth');
    _listenToFirebaseAuth();
  }

  void _listenToFirebaseAuth() {
    _authSub?.cancel();
    _authSub = fb.FirebaseAuth.instance.authStateChanges().listen((fb.User? u) {
      debugPrint('authStateChanges: user=${u?.uid} email=${u?.email}');
      if (u == null) {
        _userDocSub?.cancel();
        _isAuthenticated = false;
        _userEmail = null;
        _userName = null;
        _userRole = UserRole.assistant;
        _workspaceId = null;
        _isLoading = false;
        _updateSyncServiceState();
        notifyListeners();
        return;
      }

      _isAuthenticated = true;
      _userEmail = u.email;
      _userName = (u.displayName ?? '').trim().isEmpty ? (u.email ?? '') : u.displayName;
      _isLoading = true;
      notifyListeners();

      _listenToUserDoc(u.uid);
    });
  }

  void _listenToUserDoc(String uid) {
    _userDocSub?.cancel();
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);

    _userDocSub = ref.snapshots().listen((snap) async {
      if (!snap.exists) {
        debugPrint('userDoc snapshots: missing user doc for uid=$uid, creating...');
        try {
          await _ensureUserDoc(uid);
        } catch (e) {
          _lastBootstrapError = e.toString();
          debugPrint('userDoc snapshots: failed creating user doc for uid=$uid: $e');
          _isLoading = false;
          notifyListeners();
        }
        return;
      }

      final data = snap.data() ?? <String, dynamic>{};
      final roleStr = (data['role']?.toString() ?? 'user').toLowerCase();
      _userRole = _parseRole(roleStr);
      _workspaceId = (data['workspaceId']?.toString().trim().isEmpty ?? true)
          ? null
          : data['workspaceId']?.toString();

      // If the user is approved but doesn't have workspaceId yet (common after reinstall),
      // attach the bootstrap workspace and let sync start.
      final approved = _userRole == UserRole.admin || _userRole == UserRole.assistant;
      if (!_useLocalAuth && approved && (_workspaceId ?? '').isEmpty) {
        try {
          // First try the existing bootstrap path.
          await _ensureUserDoc(uid);
        } catch (e) {
          _lastBootstrapError = e.toString();
          debugPrint('attach workspaceId via ensureUserDoc failed for uid=$uid: $e');
        }

        // Hard fallback: directly read system/bootstrap and set workspaceId.
        try {
          final bootstrap = await FirebaseFirestore.instance.collection('system').doc('bootstrap').get();
          final b = bootstrap.data() ?? <String, dynamic>{};
          final ws = b['workspaceId']?.toString();
          if ((ws ?? '').trim().isNotEmpty) {
            _workspaceId = ws;
            await FirebaseFirestore.instance.collection('users').doc(uid).set(
              {
                'workspaceId': ws,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        } catch (e) {
          _lastBootstrapError = e.toString();
          debugPrint('attach workspaceId hard fallback failed for uid=$uid: $e');
        }
      }

      _isLoading = false;
      await _updateSyncServiceState();
      notifyListeners();
    }, onError: (e) {
      debugPrint('userDoc snapshots error for uid=$uid: $e');
      _isLoading = false;
      notifyListeners();
    });
  }

  UserRole _parseRole(String role) {
    switch (role) {
      case 'admin':
        return UserRole.admin;
      case 'assistant':
      case 'user':
        return UserRole.assistant;
      case 'banned':
        return UserRole.banned;
      default:
        return UserRole.assistant;
    }
  }

  Future<void> _ensureUserDoc(String uid) async {
    // Prevent re-entrant/concurrent user bootstrap which can lead to role being
    // written as 'user' before the bootstrap transaction promotes to 'admin'.
    if (_ensureUserDocInFlight != null) {
      await _ensureUserDocInFlight;
      return;
    }

    final completer = Completer<void>();
    _ensureUserDocInFlight = completer.future;

    try {
      try {
        await _bootstrapWorkspaceIfNeeded(uid);
      } catch (e) {
        throw StateError('bootstrapWorkspaceIfNeeded failed: $e');
      }

      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final now = FieldValue.serverTimestamp();

      // IMPORTANT:
      // Don't overwrite an existing role/workspaceId. The first-user bootstrap sets role=admin
      // in the same call chain; writing role='user' here would downgrade the first admin.
      final existing = await (() async {
        try {
          return await ref.get();
        } catch (e) {
          throw StateError('users/$uid get failed: $e');
        }
      })();
      final existingData = existing.data() ?? <String, dynamic>{};
      final existingRole = existingData['role'];
      final existingWorkspaceId = existingData['workspaceId'];

      try {
        await ref.set(
          {
            'email': (_userEmail ?? '').trim(),
            'name': (_userName ?? '').trim(),
            if (existingRole == null) 'role': UserRole.assistant.name,
            if (existingWorkspaceId == null) 'workspaceId': _workspaceId,
            'createdAt': existing.exists ? (existingData['createdAt'] ?? now) : now,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        throw StateError('users/$uid set(merge:true) failed: $e');
      }

      // Safety: if this uid is the bootstrap owner, ensure the user has admin role
      // and the bootstrap workspace assigned. This fixes cases where a previous
      // write or rule prevented the role assignment.
      try {
        final bootstrap = await (() async {
          try {
            return await FirebaseFirestore.instance.collection('system').doc('bootstrap').get();
          } catch (e) {
            throw StateError('system/bootstrap get failed: $e');
          }
        })();
        final b = bootstrap.data() ?? <String, dynamic>{};
        final ownerUid = b['ownerUid']?.toString();
        final ws = b['workspaceId']?.toString();
        if (ownerUid == uid && (ws ?? '').trim().isNotEmpty) {
          try {
            await ref.set(
              {
                'role': UserRole.admin.name,
                'workspaceId': ws,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (e) {
            throw StateError('users/$uid promote-to-admin set failed: $e');
          }
        }
      } catch (e) {
        debugPrint('Bootstrap owner promote check failed: $e');
      }
    } catch (e) {
      // Surface Firestore failures (rules/network/etc.) to the UI.
      _lastBootstrapError = e.toString();
      debugPrint('ensureUserDoc failed for uid=$uid: $e');
      notifyListeners();
      rethrow;
    } finally {
      completer.complete();
      _ensureUserDocInFlight = null;
    }
  }

  Future<void> _bootstrapWorkspaceIfNeeded(String uid) async {
    // Bootstrap is a one-time operation per Firebase project:
    // - Create system/bootstrap
    // - Create workspaces/{workspaceId}
    // - Make the first user admin and assign workspaceId
    final db = FirebaseFirestore.instance;
    final bootstrapRef = db.collection('system').doc('bootstrap');

    try {
      _lastBootstrapError = null;
      final snap = await (() async {
        try {
          return await bootstrapRef.get();
        } catch (e) {
          throw StateError('system/bootstrap get failed: $e');
        }
      })();
      if (snap.exists) {
        final data = snap.data() ?? <String, dynamic>{};
        final ws = (data['workspaceId']?.toString().trim().isEmpty ?? true)
            ? null
            : data['workspaceId']?.toString();
        final ownerUid = data['ownerUid']?.toString();
        _workspaceId = ws;

        // If this signed-in user is the bootstrap owner, ensure they are admin and linked to the workspace.
        if (ownerUid == uid && (ws ?? '').isNotEmpty) {
          try {
            await db.collection('users').doc(uid).set(
              {
                'role': UserRole.admin.name,
                'workspaceId': ws,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          } catch (e) {
            throw StateError('users/$uid owner recovery set failed: $e');
          }
        }
        return;
      }

      final requestedWorkspaceId = const Uuid().v4();
      final now = FieldValue.serverTimestamp();

      final workspaceRef = db.collection('workspaces').doc(requestedWorkspaceId);
      final userRef = db.collection('users').doc(uid);

      String? resolvedWorkspaceId;
      bool createdBootstrap = false;

      await db.runTransaction((tx) async {
        final b = await tx.get(bootstrapRef);
        if (b.exists) {
          final data = b.data() ?? <String, dynamic>{};
          final ws = (data['workspaceId']?.toString().trim().isEmpty ?? true)
              ? null
              : data['workspaceId']?.toString();
          resolvedWorkspaceId = ws;
          return;
        }

        createdBootstrap = true;
        resolvedWorkspaceId = requestedWorkspaceId;

        tx.set(bootstrapRef, {
          'workspaceId': requestedWorkspaceId,
          'ownerUid': uid,
          'createdAt': now,
        });

        tx.set(workspaceRef, {
          'workspaceId': requestedWorkspaceId,
          'ownerUid': uid,
          'createdAt': now,
          'updatedAt': now,
        });

        // Ensure the first user becomes admin and is linked to the workspace.
        tx.set(
          userRef,
          {
            'role': UserRole.admin.name,
            'workspaceId': requestedWorkspaceId,
            'updatedAt': now,
          },
          SetOptions(merge: true),
        );
      });

      _workspaceId = resolvedWorkspaceId;

      if (!createdBootstrap || (resolvedWorkspaceId ?? '').isEmpty) {
        return;
      }

      // Extra safety: ensure the owner user doc is admin after transaction completion.
      await db.collection('users').doc(uid).set(
        {
          'role': UserRole.admin.name,
          'workspaceId': resolvedWorkspaceId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      _lastBootstrapError = e.toString();
      debugPrint('Bootstrap workspace error: $e');
      notifyListeners();
    }
  }

  Future<bool> authenticate(String name, String email, String password) async {
    if (_useLocalAuth) {
      return _authenticateLocal(name, email, password);
    }

    _isLoading = true;
    _lastAuthError = null;
    notifyListeners();

    try {
      final trimmedEmail = email.trim();
      final trimmedName = name.trim();

      fb.UserCredential credential;
      try {
        credential = await fb.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: trimmedEmail,
          password: password,
        );
      } on fb.FirebaseAuthException catch (e) {
        debugPrint('authenticate: signIn failed code=${e.code} message=${e.message}');
        // Some FirebaseAuth SDK versions return `invalid-credential` (or
        // `invalid-login-credentials`) instead of `user-not-found` when the
        // email doesn't exist yet. Treat these as "create account" cases.
        final createCodes = <String>{
          'user-not-found',
          'invalid-credential',
          'invalid-login-credentials',
        };

        if (createCodes.contains(e.code)) {
          credential = await fb.FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: trimmedEmail,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final u = credential.user;
      if (u == null) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if ((u.displayName ?? '').trim().isEmpty && trimmedName.isNotEmpty) {
        await u.updateDisplayName(trimmedName);
      }

      _userEmail = u.email;
      _userName = (u.displayName ?? '').trim().isEmpty ? (u.email ?? '') : u.displayName;

      await _ensureUserDoc(u.uid);

      _isAuthenticated = true;
      _lastAuthError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } on fb.FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException: ${e.code} ${e.message}');
      _lastAuthError = '${e.code}: ${e.message ?? ''}'.trim();
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('خطأ في المصادقة: $e');
      _lastAuthError = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_useLocalAuth) {
        _isAuthenticated = false;
        await _persistLocalAuthState();
      } else {
        await fb.FirebaseAuth.instance.signOut();
      }
    } catch (e) {
      debugPrint('خطأ في تسجيل الخروج: $e');
    }

    await _updateSyncServiceState();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadLocalAuthState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isAuthenticated = prefs.getBool(_kAuthIsAuthenticated) ?? false;
      _userEmail = prefs.getString(_kAuthEmail);
      _userName = prefs.getString(_kAuthName);
      _localPassword = prefs.getString(_kAuthPassword);
      _userRole = UserRole.admin;
    } catch (e) {
      debugPrint('خطأ في تحميل حالة المصادقة المحلية: $e');
      _isAuthenticated = false;
      _userEmail = null;
      _userName = null;
      _localPassword = null;
      _userRole = UserRole.admin;
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _persistLocalAuthState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAuthIsAuthenticated, _isAuthenticated);
    if ((_userEmail ?? '').trim().isEmpty) {
      await prefs.remove(_kAuthEmail);
    } else {
      await prefs.setString(_kAuthEmail, _userEmail!.trim());
    }
    if ((_userName ?? '').trim().isEmpty) {
      await prefs.remove(_kAuthName);
    } else {
      await prefs.setString(_kAuthName, _userName!.trim());
    }
    if ((_localPassword ?? '').isEmpty) {
      await prefs.remove(_kAuthPassword);
    } else {
      await prefs.setString(_kAuthPassword, _localPassword!);
    }
  }

  Future<bool> _authenticateLocal(String name, String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final trimmedEmail = email.trim();
      final trimmedName = name.trim();

      final prefs = await SharedPreferences.getInstance();
      final storedEmail = prefs.getString(_kAuthEmail);
      final storedPassword = prefs.getString(_kAuthPassword);

      if ((storedEmail ?? '').trim().isEmpty || (storedPassword ?? '').isEmpty) {
        _userEmail = trimmedEmail;
        _userName = trimmedName.isEmpty ? trimmedEmail : trimmedName;
        _localPassword = password;
        _isAuthenticated = true;
        _userRole = UserRole.admin;
        await _persistLocalAuthState();
        _isLoading = false;
        notifyListeners();
        return true;
      }

      final emailMatches = storedEmail!.trim().toLowerCase() == trimmedEmail.toLowerCase();
      final passwordMatches = storedPassword == password;

      if (emailMatches && passwordMatches) {
        _userEmail = storedEmail;
        _userName = (prefs.getString(_kAuthName) ?? '').trim().isEmpty ? storedEmail : prefs.getString(_kAuthName);
        _localPassword = storedPassword;
        _isAuthenticated = true;
        _userRole = UserRole.admin;
        await _persistLocalAuthState();
        _isLoading = false;
        notifyListeners();
        return true;
      }

      _isAuthenticated = false;
      await _persistLocalAuthState();
    } catch (e) {
      debugPrint('خطأ في المصادقة: $e');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
    SyncService.instance.stop();
    super.dispose();
  }
}

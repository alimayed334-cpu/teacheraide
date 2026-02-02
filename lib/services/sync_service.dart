import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import '../models/class_model.dart';
import '../models/student_model.dart';

class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final DatabaseHelper _db = DatabaseHelper();
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _subs = [];
  Timer? _outboxTimer;

  final StreamController<void> _changesController = StreamController<void>.broadcast();
  Stream<void> get changes => _changesController.stream;

  String? _workspaceId;
  bool _running = false;
  bool _bootstrapOutboxDone = false;

  bool get isRunning => _running;

  Future<void> flushOutboxOnce() async {
    if (!_running) return;
    await _processOutboxOnce();
  }

  Future<void> start({required String workspaceId}) async {
    if (Firebase.apps.isEmpty) return;
    if (_running && _workspaceId == workspaceId) return;

    await stop();

    _workspaceId = workspaceId;
    _running = true;
    _bootstrapOutboxDone = false;

    try {
      debugPrint('SyncService.start workspaceId=$workspaceId');
    } catch (_) {}

    await _startListeners();
    _startOutboxLoop();
  }

  Future<void> stop() async {
    _running = false;
    _workspaceId = null;

    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();

    _outboxTimer?.cancel();
    _outboxTimer = null;

    _bootstrapOutboxDone = false;
  }

  Future<void> _startListeners() async {
    final ws = _workspaceId;
    if (ws == null) return;

    final firestore = FirebaseFirestore.instance;

    // Collections to sync 1:1 with SQLite tables.
    final collections = <String>{
      'classes',
      'students',
      'lectures',
      'attendance',
      'exams',
      'grades',
      'notes',
      'student_notes',
      'courses',
      'class_course_prices',
      'installments',
      'course_due_dates',
      // messages table exists locally; add when you implement message CRUD.
      // 'messages',
      'settings',
    };

    for (final c in collections) {
      try {
        final initial = await firestore.collection('workspaces').doc(ws).collection(c).get();
        for (final doc in initial.docs) {
          await _db.upsertFromCloud(tableName: c, docId: doc.id, cloudData: doc.data());
          _changesController.add(null);
        }
      } catch (e) {
        // Keep sync running even if initial fetch fails; snapshots may still recover.
        try {
          debugPrint('SyncService initial fetch failed: workspaces/$ws/$c error=$e');
        } catch (_) {}
      }

      final sub = firestore
          .collection('workspaces')
          .doc(ws)
          .collection(c)
          .snapshots()
          .listen((snap) async {
        for (final doc in snap.docs) {
          await _db.upsertFromCloud(tableName: c, docId: doc.id, cloudData: doc.data());
          _changesController.add(null);
        }
      }, onError: (e) {
        try {
          debugPrint('SyncService snapshots error: workspaces/$ws/$c error=$e');
        } catch (_) {}
      });
      _subs.add(sub);
    }
  }

  void _startOutboxLoop() {
    _outboxTimer?.cancel();
    _outboxTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!_running) return;
      await _processOutboxOnce();
    });
  }

  Future<void> _processOutboxOnce() async {
    final ws = _workspaceId;
    if (ws == null) return;

    if (!_bootstrapOutboxDone) {
      // In this project we may have pending legacy rows; skip them so we don't upload old/test data.
      await _db.markPendingOutboxAsSkippedForTables({
        'classes',
        'students',
        'lectures',
        'attendance',
        'exams',
        'grades',
        'notes',
        'student_notes',
        'courses',
        'class_course_prices',
        'installments',
        'course_due_dates',
        'settings',
      });
      _bootstrapOutboxDone = true;
    }

    final db = await _db.database;
    final rows = await db.query(
      'sync_outbox',
      where: "status = 'pending'",
      orderBy: 'id ASC',
      limit: 25,
    );

    if (rows.isEmpty) return;

    final firestore = FirebaseFirestore.instance;

    for (final r in rows) {
      final id = r['id'] as int;
      final table = (r['table_name'] ?? '').toString();
      final localId = (r['local_id'] ?? '').toString();
      final op = (r['op'] ?? '').toString();
      final payloadJson = r['payload_json']?.toString();

      try {
        if (localId.isEmpty || op.isEmpty || table.isEmpty) {
          await _setOutboxStatus(id: id, status: 'skipped', lastError: 'invalid_row');
          continue;
        }

        final col = firestore.collection('workspaces').doc(ws).collection(table);

        final docId = _toCloudDocId(table: table, localId: localId, payloadJson: payloadJson);
        if (docId == null || docId.isEmpty) {
          await _setOutboxStatus(id: id, status: 'skipped', lastError: 'invalid_doc_id');
          continue;
        }

        if (op == 'delete') {
          await col.doc(docId).delete();
        } else {
          final payload = payloadJson == null || payloadJson.isEmpty
              ? <String, dynamic>{}
              : (jsonDecode(payloadJson) as Map).cast<String, dynamic>();

          payload['local_id'] = localId;
          payload['updated_at'] = FieldValue.serverTimestamp();

          await col.doc(docId).set(payload, SetOptions(merge: true));
        }

        await _setOutboxStatus(id: id, status: 'done');
      } catch (e) {
        await _setOutboxStatus(id: id, status: 'pending', lastError: e.toString(), incrementRetry: true);
      }
    }
  }

  Future<void> _setOutboxStatus({
    required int id,
    required String status,
    String? lastError,
    bool incrementRetry = false,
  }) async {
    final db = await _db.database;
    final nowIso = DateTime.now().toIso8601String();

    final values = <String, dynamic>{
      'status': status,
      'updated_at': nowIso,
      'last_error': lastError,
    };

    if (incrementRetry) {
      await db.rawUpdate(
        'UPDATE sync_outbox SET retry_count = retry_count + 1, status = ?, updated_at = ?, last_error = ? WHERE id = ?',
        [status, nowIso, lastError, id],
      );
      return;
    }

    await db.update(
      'sync_outbox',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  String? _toCloudDocId({
    required String table,
    required String localId,
    required String? payloadJson,
  }) {
    switch (table) {
      case 'courses':
      case 'settings':
        return localId;
      case 'course_due_dates':
        // Stored as "{classId}_{courseId}" already.
        return localId;
      default:
        // Most tables use INTEGER PK locally, represented as string.
        return localId;
    }
  }

  static Map<String, dynamic> classToCloudMap(ClassModel m) {
    final map = m.toMap();
    map['id'] = m.id;
    return map;
  }

  static Map<String, dynamic> studentToCloudMap(StudentModel m) {
    final map = m.toMap();
    map['id'] = m.id;
    return map;
  }
}

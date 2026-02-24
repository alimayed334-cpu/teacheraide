import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/class_model.dart';
import '../models/student_model.dart';
import '../models/attendance_model.dart';
import '../models/grade_model.dart';
import '../models/student_note_model.dart';
import '../models/lecture_model.dart';
import '../models/exam_model.dart';
import '../models/note_model.dart';
import '../models/message_model.dart';
import '../models/assignment_model.dart';
import '../models/assignment_student_model.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const String _databaseName = 'teacher_aide.db';

  static Database? _database;
  static const int _databaseVersion = 26;
  static bool _forceReinit = false;

  Future<bool> hasLocalAppData() async {
    final db = await database;
    Future<int> count(String table) async {
      try {
        final r = await db.rawQuery('SELECT COUNT(*) as c FROM $table');
        return (r.isNotEmpty ? (r.first['c'] as int? ?? 0) : 0);
      } catch (_) {
        return 0;
      }
    }

    final classes = await count('classes');
    final students = await count('students');
    final attendance = await count('attendance');
    final exams = await count('exams');
    final grades = await count('grades');
    final notes = await count('notes');
    final studentNotes = await count('student_notes');

    return classes > 0 ||
        students > 0 ||
        attendance > 0 ||
        exams > 0 ||
        grades > 0 ||
        notes > 0 ||
        studentNotes > 0;
  }

  Future<Database> get database async {
    if (_database != null && !_forceReinit) return _database!;
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _database = await _initDatabase();
    _forceReinit = false;
    return _database!;
  }

  Future<bool> _tableExists(Database db, String tableName) async {
    try {
      final r = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [tableName],
      );
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<int> addCashWithdrawal({
    required int amount,
    required String withdrawDate,
    String? purpose,
    String? withdrawerName,
    String? note,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert(
      'cash_withdrawals',
      {
        'amount': amount,
        'purpose': purpose,
        'withdrawer_name': withdrawerName,
        'withdraw_date': withdrawDate,
        'note': note,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> deleteCashWithdrawal(int id) async {
    final db = await database;
    return db.delete(
      'cash_withdrawals',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getCashWithdrawals() async {
    final db = await database;
    return db.query(
      'cash_withdrawals',
      orderBy: 'withdraw_date DESC, id DESC',
    );
  }

  Future<int> getTotalCashWithdrawalsAmount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM cash_withdrawals');
    return int.tryParse(r.first['t']?.toString() ?? '') ?? 0;
  }

  Future<int> addCashIncome({
    required int amount,
    required String incomeDate,
    String? purpose,
    String? supplierName,
    String? note,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.insert(
      'cash_incomes',
      {
        'amount': amount,
        'purpose': purpose,
        'supplier_name': supplierName,
        'income_date': incomeDate,
        'note': note,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<int> deleteCashIncome(int id) async {
    final db = await database;
    return db.delete(
      'cash_incomes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getCashIncomes() async {
    final db = await database;
    return db.query(
      'cash_incomes',
      orderBy: 'income_date DESC, id DESC',
    );
  }

  Future<int> getTotalCashIncomesAmount() async {
    final db = await database;
    final r = await db.rawQuery('SELECT COALESCE(SUM(amount), 0) AS t FROM cash_incomes');
    return int.tryParse(r.first['t']?.toString() ?? '') ?? 0;
  }

  Future<void> _repairSchema(Database db) async {
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='course_due_dates'",
      );
      if (tables.isNotEmpty) {
        final columns = await db.rawQuery("PRAGMA table_info('course_due_dates')");
        final existing = columns
            .map((c) => (c['name']?.toString() ?? '').trim())
            .where((c) => c.isNotEmpty)
            .toSet();

        if (!existing.contains('class_id') ||
            !existing.contains('course_id') ||
            !existing.contains('due_date')) {
          await db.execute('DROP TABLE IF EXISTS course_due_dates');
          await db.execute('''
          CREATE TABLE course_due_dates (
            class_id TEXT NOT NULL,
            course_id TEXT NOT NULL,
            due_date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (class_id, course_id)
          )
        ''');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_course_due_dates_class_id ON course_due_dates(class_id)',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_course_due_dates_course_id ON course_due_dates(course_id)',
          );
        }
      }

      final gradeTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='grades'",
      );
      if (gradeTables.isNotEmpty) {
        final gradeColumns =
            await db.rawQuery("PRAGMA table_info('grades')");
        final existingGradeColumns = gradeColumns
            .map((c) => (c['name']?.toString() ?? '').trim())
            .where((c) => c.isNotEmpty)
            .toSet();

        if (!existingGradeColumns.contains('status')) {
          await db.execute(
            "ALTER TABLE grades ADD COLUMN status TEXT DEFAULT 'حاضر'",
          );
        }
      }
    } catch (e) {
      print('❌ Error in _repairSchema: $e');
    }
  }

  Future<void> _ensureGradesStatusColumn(Database db) async {
    try {
      final gradeTables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='grades'",
      );
      if (gradeTables.isEmpty) return;

      final gradeColumns = await db.rawQuery("PRAGMA table_info('grades')");
      final existingGradeColumns = gradeColumns
          .map((c) => (c['name']?.toString() ?? '').trim())
          .where((c) => c.isNotEmpty)
          .toSet();

      if (!existingGradeColumns.contains('status')) {
        await db.execute(
          "ALTER TABLE grades ADD COLUMN status TEXT DEFAULT 'حاضر'",
        );
      }
    } catch (_) {
      // Ignore; caller will handle errors/retry.
    }
  }

  Future<void> _enqueueSyncOutbox({
    required String tableName,
    required String localId,
    required String op,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final db = await database;
      final nowIso = DateTime.now().toIso8601String();
      await db.insert(
        'sync_outbox',
        {
          'table_name': tableName,
          'local_id': localId,
          'op': op,
          'payload_json': payload == null ? null : jsonEncode(payload),
          'status': 'pending',
          'retry_count': 0,
          'last_error': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        },
      );
    } catch (e) {
      // Do not break the app if sync queue fails.
      debugPrint('⚠️ Sync outbox enqueue failed ($tableName/$localId/$op): $e');
    }
  }

  Map<String, dynamic> _normalizeCloudData(Map<String, dynamic> data) {
    final out = <String, dynamic>{};
    for (final entry in data.entries) {
      // local_id is used as a helper field in cloud sync payloads, but not all
      // local SQLite tables have that column.
      if (entry.key == 'local_id') {
        continue;
      }
      final v = entry.value;
      if (v is Timestamp) {
        out[entry.key] = v.toDate().toIso8601String();
      } else {
        out[entry.key] = v;
      }
    }
    return out;
  }

  Future<void> _safeUpsert(
    Database db, {
    required String tableName,
    required Map<String, dynamic> values,
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final updated = await db.update(
      tableName,
      values,
      where: where,
      whereArgs: whereArgs,
    );
    if (updated == 0) {
      await db.insert(tableName, values);
    }
  }

  Future<void> upsertFromCloud({
    required String tableName,
    required String docId,
    required Map<String, dynamic> cloudData,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final data = _normalizeCloudData(cloudData);

    Map<String, dynamic> values;
    String localId;

    switch (tableName) {
      case 'classes':
      case 'students':
      case 'attendance':
      case 'grades':
      case 'lectures':
      case 'exams':
      case 'notes':
      case 'student_notes':
      case 'class_course_prices':
      case 'installments':
      case 'assignments':
        int? id = int.tryParse(docId);
        if (id == null) {
          // بعض الوثائق قد تستخدم معرّفاً نصياً في Firestore، بينما نخزن المعرف الرقمي في الحقل id/local_id.
          final fromIdField = data['id'];
          final fromLocalIdField = data['local_id'];
          id = fromIdField is int
              ? fromIdField
              : int.tryParse(fromIdField?.toString() ?? '') ??
                  (fromLocalIdField is int ? fromLocalIdField : int.tryParse(fromLocalIdField?.toString() ?? ''));
          if (id == null) {
            // لا يمكن ربط الوثيقة بسجل محلي رقمي، تجاهل بهدوء.
            return;
          }
        }

        localId = id.toString();
        values = <String, dynamic>{...data, 'id': id};
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        // تأكد من وجود updated_at دائماً
        values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        break;

      case 'class_tuition_plans':
      case 'tuition_plan_installments':
      case 'tuition_payments':
      case 'student_financial_notes':
        final id = int.tryParse(docId);
        if (id == null) return;
        localId = id.toString();
        values = <String, dynamic>{...data, 'id': id};
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        break;

      case 'student_tuition_overrides':
      case 'student_plan_discount_reasons':
        localId = docId;
        values = <String, dynamic>{...data};
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        break;

      case 'assignment_students':
        // Stored/identified as "{assignmentId}_{studentId}".
        localId = docId;
        final parts = docId.split('_');
        final assignmentId = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final studentId = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (assignmentId == null || studentId == null) return;

        values = <String, dynamic>{
          ...data,
          // Ensure required composite keys exist.
          'assignment_id': data['assignment_id'] ?? assignmentId,
          'student_id': data['student_id'] ?? studentId,
        };
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        break;

      case 'courses':
        localId = docId;
        values = <String, dynamic>{...data, 'id': docId};
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        break;

      case 'settings':
        localId = docId;
        values = <String, dynamic>{
          'key': docId,
          'value': (data['value'] ?? '').toString(),
        };
        break;

      case 'course_due_dates':
        localId = docId;
        final classId = (data['class_id'] ?? '').toString();
        final courseId = (data['course_id'] ?? '').toString();
        if (classId.isEmpty || courseId.isEmpty) return;
        values = <String, dynamic>{
          'class_id': classId,
          'course_id': courseId,
          'due_date': (data['due_date'] ?? '').toString(),
          'created_at': (data['created_at'] ?? data['createdAt'] ?? nowIso).toString(),
          'updated_at': (data['updated_at'] ?? data['updatedAt'] ?? nowIso).toString(),
        };
        break;

      default:
        return;
    }

    try {
      if (tableName == 'settings') {
        await _safeUpsert(
          db,
          tableName: tableName,
          values: values,
          where: 'key = ?',
          whereArgs: [values['key']],
        );
      } else if (tableName == 'course_due_dates') {
        await _safeUpsert(
          db,
          tableName: tableName,
          values: values,
          where: 'class_id = ? AND course_id = ?',
          whereArgs: [values['class_id'], values['course_id']],
        );
      } else if (tableName == 'assignment_students') {
        // Remove 'id' from values to avoid datatype mismatch; assignment_students uses composite key only
        final valuesWithoutId = Map<String, dynamic>.from(values);
        valuesWithoutId.remove('id');
        await _safeUpsert(
          db,
          tableName: tableName,
          values: valuesWithoutId,
          where: 'assignment_id = ? AND student_id = ?',
          whereArgs: [valuesWithoutId['assignment_id'], valuesWithoutId['student_id']],
        );
      } else if (tableName == 'student_tuition_overrides') {
        final valuesWithoutId = Map<String, dynamic>.from(values);
        valuesWithoutId.remove('id');
        await _safeUpsert(
          db,
          tableName: tableName,
          values: valuesWithoutId,
          where: 'student_id = ? AND plan_id = ? AND installment_no = ?',
          whereArgs: [
            valuesWithoutId['student_id'],
            valuesWithoutId['plan_id'],
            valuesWithoutId['installment_no'],
          ],
        );
      } else if (tableName == 'student_plan_discount_reasons') {
        final valuesWithoutId = Map<String, dynamic>.from(values);
        valuesWithoutId.remove('id');
        await _safeUpsert(
          db,
          tableName: tableName,
          values: valuesWithoutId,
          where: 'student_id = ? AND plan_id = ?',
          whereArgs: [
            valuesWithoutId['student_id'],
            valuesWithoutId['plan_id'],
          ],
        );
      } else {
        await _safeUpsert(
          db,
          tableName: tableName,
          values: values,
          where: 'id = ?',
          whereArgs: [values['id']],
        );
      }
    } catch (e) {
      // Ignore foreign key constraint failures during cloud sync
      if (e.toString().contains('FOREIGN KEY constraint failed')) {
        print('⚠️ Skipping sync for $tableName due to missing parent (docId: $docId)');
        return;
      }
      rethrow;
    }

    await db.insert(
      'sync_meta',
      {
        'table_name': tableName,
        'local_id': localId,
        'cloud_id': docId,
        'server_updated_at': (data['updated_at'] ?? data['updatedAt'])?.toString(),
        'local_updated_at': nowIso,
        'is_deleted': 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> wipeLocalAppDataPreservingSync() async {
    print('⚠️ wipeLocalAppDataPreservingSync called');
    print(StackTrace.current);
    final db = await database;
    final hasMessages = await _tableExists(db, 'messages');
    await db.transaction((txn) async {
      // Delete children before parents to respect foreign keys.
      await txn.delete('attendance');
      await txn.delete('grades');
      try {
        await txn.delete('assignment_students');
      } catch (_) {}
      try {
        await txn.delete('assignments');
      } catch (_) {}
      await txn.delete('student_notes');
      await txn.delete('notes');
      if (hasMessages) {
        try {
          await txn.delete('messages');
        } catch (_) {}
      }
      await txn.delete('exams');
      await txn.delete('lectures');

      await txn.delete('installments');
      await txn.delete('class_course_prices');
      await txn.delete('course_due_dates');
      await txn.delete('courses');

      await txn.delete('students');
      await txn.delete('classes');

      // Local-only auth table (legacy)
      try {
        await txn.delete('users');
      } catch (_) {
        // ignore
      }

      // Settings are part of app state; clear them as well.
      try {
        await txn.delete('settings');
      } catch (_) {
        // ignore
      }

      // Reset sync tables so we start clean.
      await txn.delete('sync_outbox');
      await txn.delete('sync_meta');
    });
  }

  Future<void> markPendingOutboxAsSkippedForTables(core.List<String> tableNames) async {
    if (tableNames.isEmpty) return;
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final placeholders = core.List.filled(tableNames.length, '?').join(',');
    await db.rawUpdate(
      "UPDATE sync_outbox SET status = 'skipped', updated_at = ? WHERE status = 'pending' AND table_name IN ($placeholders)",
      [nowIso, ...tableNames.toList()],
    );
  }

  Future<void> upsertClassFromCloud(String cloudId, Map<String, dynamic> cloudData) async {
    await upsertFromCloud(tableName: 'classes', docId: cloudId, cloudData: cloudData);
  }

  Future<void> upsertStudentFromCloud(String cloudId, Map<String, dynamic> cloudData) async {
    await upsertFromCloud(tableName: 'students', docId: cloudId, cloudData: cloudData);
  }

  // إجبار إعادة تهيئة قاعدة البيانات
  Future<void> forceReinit() async {
    _forceReinit = true;
    await database;
  }

  Future<void> resetDatabaseFile() async {
    try {
      print('⚠️ resetDatabaseFile called');
      print(StackTrace.current);
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      final Directory appDocDir = (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? await getApplicationSupportDirectory()
          : await getApplicationDocumentsDirectory();
      final String path = join(appDocDir.path, 'teacher_aide.db');
      final dbFile = File(path);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }

      _forceReinit = true;
    } catch (e) {
      print('❌ Error resetting database file: $e');
    }
  }

  Future<Database> _initDatabase() async {
    try {
      // استخدام مجلد آمن للكتابة على سطح المكتب (تجنب مشاكل OneDrive/Documents)
      final Directory appDocDir = (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          ? await getApplicationSupportDirectory()
          : await getApplicationDocumentsDirectory();
      final String path = join(appDocDir.path, 'teacher_aide.db');
      final String oldPath = join((await getApplicationDocumentsDirectory()).path, 'teacher_aide.db');
      
      print('📂 Database path: $path');
      print('📂 Documents directory: ${appDocDir.path}');

      // ترحيل قاعدة البيانات من Documents إلى ApplicationSupport (أفضل مجهود)
      if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        try {
          final oldFile = File(oldPath);
          final newFile = File(path);

          if (await oldFile.exists() && !await newFile.exists()) {
            await Directory(appDocDir.path).create(recursive: true);
            await oldFile.copy(path);
            print('✅ Migrated database from Documents to ApplicationSupport');
          }
        } catch (e) {
          print('⚠️ Database migration skipped/failed: $e');
        }
      }
      
      // التحقق من وجود الملف وحقوق الكتابة
      final dbFile = File(path);
      bool isNewDb = !await dbFile.exists();
      
      if (!isNewDb) {
        try {
          // التحقق من إمكانية الكتابة على الملف
          final raf = await dbFile.open(mode: FileMode.writeOnlyAppend);
          await raf.writeString('');
          await raf.close();
          print('✅ Database file is writable');
          
          // التحقق من صلاحيات الملف
          final stat = await dbFile.stat();
          print('🔒 File permissions: ${stat.modeString()}');
          
        } catch (e) {
          print('❌ Cannot write to database file (will NOT delete): $e');
          print(StackTrace.current);
        }
      }
      
      // فتح قاعدة البيانات مع خيارات إضافية
      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onOpen: (db) async {
          print('✅ Database opened successfully');
          // تفعيل المفاتيح الأجنبية
          await db.rawQuery('PRAGMA foreign_keys = ON');
          
          // تمكين الكتابة بشكل صريح
          await db.rawQuery('PRAGMA journal_mode=WAL');
          
          // إصلاح مخطط قاعدة البيانات
          await _repairSchema(db);
          
          // الحصول على قائمة بالجداول الموجودة
          final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'",
          );
          print('📊 Tables in database: ${tables.length}');
          
          // التحقق من الجداول المفقودة وإنشاؤها
          await _createMissingTables(db, tables);
        },
        // تمكين الكتابة بشكل صريح
        readOnly: false,
      );
      
      // التحقق من إمكانية الكتابة على قاعدة البيانات
      try {
        await db.rawQuery('PRAGMA integrity_check');
        print('✅ Database integrity check passed');
      } catch (e) {
        print('⚠️ Database integrity check warning: $e');
      }
      
      return db;
    } catch (e) {
      print('❌ Error initializing database: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    print('🔨 Creating database tables...');
    
    // إنشاء جدول الفصول
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        subject TEXT NOT NULL,
        year TEXT NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // إنشاء جدول الطلاب
    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER,
        name TEXT NOT NULL,
        photo TEXT,
        photo_path TEXT,
        notes TEXT,
        parent_phone TEXT,
        parent_email TEXT,
        student_id TEXT,
        email TEXT,
        phone TEXT,
        location TEXT,
        birth_date TEXT,
        primary_guardian TEXT,
        secondary_guardian TEXT,
        average_grade REAL,
        attended_lectures INTEGER,
        absent_lectures INTEGER,
        absence_percentage REAL,
        attended_exams INTEGER,
        absent_exams INTEGER,
        cheating_count INTEGER DEFAULT 0,
        missing_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
      )
    ''');

    // إنشاء جدول الحضور
    await db.execute('''
      CREATE TABLE attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        lecture_id INTEGER,
        date TEXT NOT NULL,
        status INTEGER NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (lecture_id) REFERENCES lectures (id) ON DELETE CASCADE,
        UNIQUE(student_id, lecture_id)
      )
    ''');

    // إنشاء جدول الدرجات
    await db.execute('''
      CREATE TABLE grades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        exam_name TEXT NOT NULL,
        score REAL NOT NULL,
        max_score REAL NOT NULL,
        exam_date TEXT NOT NULL,
        notes TEXT,
        status TEXT DEFAULT 'حاضر',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الإعدادات
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.insert(
      'settings',
      {'key': 'tuition_receipt_seq', 'value': '0'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    // إنشاء جدول المحاضرات
    await db.execute('''
      CREATE TABLE lectures (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الامتحانات
    await db.execute('''
      CREATE TABLE exams (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        max_score REAL NOT NULL,
        description TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الملاحظات
    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        item_type TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول ملاحظات الطلاب
    await db.execute('''
      CREATE TABLE student_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        note TEXT NOT NULL,
        note_type TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الرسائل
    await db.execute('''
      CREATE TABLE messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        attached_file TEXT NOT NULL,
        send_methods TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_sent INTEGER NOT NULL DEFAULT 0,
        sent_at TEXT,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الكورسات
    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price INTEGER NOT NULL,
        location TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // إنشاء جدول أسعار الكورسات للفصول
    await db.execute('''
      CREATE TABLE class_course_prices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        amount INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        paid INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول الأقساط
    await db.execute('''
      CREATE TABLE installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        course_id TEXT NOT NULL,
        amount INTEGER NOT NULL,
        date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول المستخدمين
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // إنشاء جدول تواريخ آخر موعد للسداد (لكل فصل + كورس)
    await db.execute('''
      CREATE TABLE course_due_dates (
        class_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        due_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (class_id, course_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE class_tuition_plans (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        total_amount INTEGER NOT NULL,
        installments_count INTEGER NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE tuition_plan_installments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id INTEGER NOT NULL,
        installment_no INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
        UNIQUE(plan_id, installment_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE student_tuition_overrides (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        plan_id INTEGER NOT NULL,
        installment_no INTEGER NOT NULL,
        amount INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
        UNIQUE(student_id, plan_id, installment_no)
      )
    ''');

    await db.execute('''
      CREATE TABLE student_plan_discount_reasons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        plan_id INTEGER NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
        UNIQUE(student_id, plan_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE student_financial_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        plan_id INTEGER,
        note TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tuition_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        receipt_no INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        plan_id INTEGER NOT NULL,
        installment_no INTEGER NOT NULL,
        due_amount INTEGER NOT NULL,
        paid_amount INTEGER NOT NULL,
        payment_date TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
        UNIQUE(receipt_no)
      )
    ''');

    // إنشاء جدول الواجبات
    await db.execute('''
      CREATE TABLE assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        class_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        due_date TEXT NOT NULL,
        required_count INTEGER,
        reason TEXT,
        scope TEXT NOT NULL DEFAULT 'all',
        assigned_student_ids_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    // إنشاء جدول حالة الواجب لكل طالب
    await db.execute('''
      CREATE TABLE assignment_students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        assignment_id INTEGER NOT NULL,
        student_id INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        done_count INTEGER NOT NULL DEFAULT 0,
        comment TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (assignment_id) REFERENCES assignments (id) ON DELETE CASCADE,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        UNIQUE(assignment_id, student_id)
      )
    ''');

    // إنشاء فهارس لتحسين الأداء
    await db.execute('CREATE INDEX idx_notes_class_id ON notes(class_id)');
    await db.execute('CREATE INDEX idx_notes_item ON notes(item_type, item_id)');
    await db.execute('CREATE INDEX idx_student_notes_student_id ON student_notes(student_id)');
    await db.execute('CREATE INDEX idx_student_notes_class_id ON student_notes(class_id)');
    await db.execute('CREATE INDEX idx_student_notes_date ON student_notes(date)');
    await db.execute('CREATE INDEX idx_lectures_class_id ON lectures(class_id)');
    await db.execute('CREATE INDEX idx_exams_class_id ON exams(class_id)');
    await db.execute('CREATE INDEX idx_students_class_id ON students(class_id)');
    await db.execute('CREATE INDEX idx_attendance_student_id ON attendance(student_id)');
    await db.execute('CREATE INDEX idx_grades_student_id ON grades(student_id)');
    await db.execute('CREATE INDEX idx_messages_student_id ON messages(student_id)');
    await db.execute('CREATE INDEX idx_messages_class_id ON messages(class_id)');
    await db.execute('CREATE INDEX idx_messages_created_at ON messages(created_at)');
    await db.execute('CREATE INDEX idx_courses_location ON courses(location)');
    await db.execute('CREATE INDEX idx_class_course_prices_class_id ON class_course_prices(class_id)');
    await db.execute('CREATE INDEX idx_class_course_prices_course_id ON class_course_prices(course_id)');
    await db.execute('CREATE INDEX idx_installments_student_id ON installments(student_id)');
    await db.execute('CREATE INDEX idx_installments_course_id ON installments(course_id)');
    await db.execute('CREATE INDEX idx_installments_date ON installments(date)');
    await db.execute('CREATE INDEX idx_course_due_dates_class_id ON course_due_dates(class_id)');
    await db.execute('CREATE INDEX idx_course_due_dates_course_id ON course_due_dates(course_id)');
    await db.execute('CREATE INDEX idx_users_email ON users(email)');

    await db.execute('CREATE INDEX idx_class_tuition_plans_class_id ON class_tuition_plans(class_id)');
    await db.execute('CREATE INDEX idx_tuition_plan_installments_plan_id ON tuition_plan_installments(plan_id)');
    await db.execute('CREATE INDEX idx_student_tuition_overrides_student_id ON student_tuition_overrides(student_id)');
    await db.execute('CREATE INDEX idx_student_tuition_overrides_plan_id ON student_tuition_overrides(plan_id)');
    await db.execute('CREATE INDEX idx_tuition_payments_student_id ON tuition_payments(student_id)');
    await db.execute('CREATE INDEX idx_tuition_payments_plan_id ON tuition_payments(plan_id)');
    await db.execute('CREATE INDEX idx_tuition_payments_installment_no ON tuition_payments(installment_no)');
    await db.execute('CREATE INDEX idx_tuition_payments_payment_date ON tuition_payments(payment_date)');

    await db.execute('CREATE INDEX idx_assignments_class_id ON assignments(class_id)');
    await db.execute('CREATE INDEX idx_assignments_due_date ON assignments(due_date)');
    await db.execute('CREATE INDEX idx_assignment_students_assignment_id ON assignment_students(assignment_id)');
    await db.execute('CREATE INDEX idx_assignment_students_student_id ON assignment_students(student_id)');

    await db.execute('''
      CREATE TABLE sync_meta (
        table_name TEXT NOT NULL,
        local_id TEXT NOT NULL,
        cloud_id TEXT,
        server_updated_at TEXT,
        local_updated_at TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (table_name, local_id)
      )
    ''');
    await db.execute('CREATE INDEX idx_sync_meta_table_name ON sync_meta(table_name)');
    await db.execute('CREATE INDEX idx_sync_meta_cloud_id ON sync_meta(cloud_id)');

    await db.execute('''
      CREATE TABLE sync_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        local_id TEXT NOT NULL,
        op TEXT NOT NULL,
        payload_json TEXT,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_sync_outbox_status ON sync_outbox(status)');
    await db.execute('CREATE INDEX idx_sync_outbox_table_local ON sync_outbox(table_name, local_id)');
    
    print('✅ All database tables and indexes created successfully');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // إضافة جدول المحاضرات في الإصدار 2
      await db.execute('''
        CREATE TABLE lectures (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');
      print('✅ Database upgraded to version 2: lectures table added');
    }
    
    if (oldVersion < 3) {
      // إضافة عمود lecture_id إلى جدول الحضور في الإصدار 3
      try {
        await db.execute('ALTER TABLE attendance ADD COLUMN lecture_id INTEGER');
        print('✅ Database upgraded to version 3: lecture_id column added to attendance table');
      } catch (e) {
        print('⚠️ lecture_id column already exists or failed to add: $e');
      }
    }
    
    if (oldVersion < 4) {
      // إضافة جدول الامتحانات في الإصدار 4
      await db.execute('''
        CREATE TABLE exams (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          date TEXT NOT NULL,
          max_score REAL NOT NULL,
          description TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');
      print('✅ Database upgraded to version 4: exams table added');
    }
    
    if (oldVersion < 5) {
      // إضافة جدول الملاحظات في الإصدار 5
      await db.execute('''
        CREATE TABLE notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          item_type TEXT NOT NULL,
          item_id INTEGER NOT NULL,
          content TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');
      
      // إضافة جدول الكورسات
      await db.execute('''
        CREATE TABLE courses (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          price INTEGER NOT NULL,
          location TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

      // إضافة جدول أسعار الكورسات للفصول
      await db.execute('''
        CREATE TABLE class_course_prices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id TEXT NOT NULL,
          course_id TEXT NOT NULL,
          amount INTEGER NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          paid INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
        )
      ''');

      // إنشاء جدول الأقساط
      await db.execute('''
        CREATE TABLE installments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          course_id TEXT NOT NULL,
          amount INTEGER NOT NULL,
          date TEXT NOT NULL,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
        )
      ''');
      
      // إضافة فهارس للأداء
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_class_id ON notes(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_item ON notes(item_type, item_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_lectures_class_id ON lectures(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_exams_class_id ON exams(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_students_class_id ON students(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_attendance_student_id ON attendance(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_grades_student_id ON grades(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_courses_location ON courses(location)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_class_course_prices_class_id ON class_course_prices(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_class_course_prices_course_id ON class_course_prices(course_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_student_id ON installments(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_course_id ON installments(course_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_date ON installments(date)');
      
      print('✅ Database upgraded to version 5: Added notes, courses, class_course_prices, installments tables and indexes');
    }
    
    if (oldVersion < 6) {
      // إضافة عمود location إلى جدول الطلاب في الإصدار 6
      try {
        await db.execute('ALTER TABLE students ADD COLUMN location TEXT');
        print('✅ Database upgraded to version 6: location column added to students table');
      } catch (e) {
        print('⚠️ location column already exists or failed to add: $e');
      }
    }
    
    if (oldVersion < 7) {
      // ترقية قاعدة البيانات للإصدار 7 - إعادة التحقق من عمود location
      try {
        await db.execute('ALTER TABLE students ADD COLUMN location TEXT');
        print('✅ Database upgraded to version 7: location column verified');
      } catch (e) {
        print('⚠️ location column already exists in version 7: $e');
      }
    }
    
    if (oldVersion < 8) {
    // الإصدار 8: جدول ملاحظات الطلاب
    await db.execute('''
      CREATE TABLE student_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id INTEGER NOT NULL,
        class_id INTEGER NOT NULL,
        note TEXT NOT NULL,
        note_type TEXT NOT NULL,
        date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
        FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_student_id ON student_notes(student_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_class_id ON student_notes(class_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_date ON student_notes(date)');

    print('✅ Database upgraded to version 8: student_notes table added');
  }

    if (oldVersion < 26) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_withdrawals (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount INTEGER NOT NULL,
          purpose TEXT,
          withdrawer_name TEXT,
          withdraw_date TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_withdrawals_date ON cash_withdrawals(withdraw_date)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_withdrawals_withdrawer ON cash_withdrawals(withdrawer_name)',
      );

      await db.execute('''
        CREATE TABLE IF NOT EXISTS cash_incomes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          amount INTEGER NOT NULL,
          purpose TEXT,
          supplier_name TEXT,
          income_date TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_incomes_date ON cash_incomes(income_date)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_incomes_supplier ON cash_incomes(supplier_name)',
      );

      print('✅ Database upgraded to version 26: cash_withdrawals & cash_incomes tables added');
    }

    if (oldVersion < 15) {
      final nowIso = DateTime.now().toIso8601String();

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_meta (
          table_name TEXT NOT NULL,
          local_id TEXT NOT NULL,
          cloud_id TEXT,
          server_updated_at TEXT,
          local_updated_at TEXT,
          is_deleted INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          PRIMARY KEY (table_name, local_id)
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_meta_table_name ON sync_meta(table_name)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_meta_cloud_id ON sync_meta(cloud_id)');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_outbox (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          local_id TEXT NOT NULL,
          op TEXT NOT NULL,
          payload_json TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          retry_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_status ON sync_outbox(status)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_table_local ON sync_outbox(table_name, local_id)');

      // Seed timestamps for existing installs (best-effort only).
      try {
        await db.insert(
          'sync_meta',
          {
            'table_name': '__init__',
            'local_id': '1',
            'cloud_id': null,
            'server_updated_at': null,
            'local_updated_at': nowIso,
            'is_deleted': 0,
            'created_at': nowIso,
            'updated_at': nowIso,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {
        // ignore
      }

      print('✅ Database upgraded to version 15: sync_meta and sync_outbox tables added');
    }

    if (oldVersion < 9) {
      // الإصدار 9: أعمدة إحصائيات الطلاب
      final columns = await db.rawQuery('PRAGMA table_info(students)');
      final columnNames = columns.map((col) => col['name'].toString().toLowerCase()).toList();
      
      if (!columnNames.contains('average_grade')) {
        await db.execute('ALTER TABLE students ADD COLUMN average_grade REAL');
      }
      
      if (!columnNames.contains('attended_lectures')) {
        await db.execute('ALTER TABLE students ADD COLUMN attended_lectures INTEGER');
      }
      
      if (!columnNames.contains('absent_lectures')) {
        await db.execute('ALTER TABLE students ADD COLUMN absent_lectures INTEGER');
      }
      
      if (!columnNames.contains('absence_percentage')) {
        await db.execute('ALTER TABLE students ADD COLUMN absence_percentage REAL');
      }
      
      if (!columnNames.contains('attended_exams')) {
        await db.execute('ALTER TABLE students ADD COLUMN attended_exams INTEGER');
      }
      
      if (!columnNames.contains('absent_exams')) {
        await db.execute('ALTER TABLE students ADD COLUMN absent_exams INTEGER');
      }
      
      print('✅ Database upgraded to version 9: student statistics columns added');
    }
    
    if (oldVersion < 10) {
      // الإصدار 10: إضافة الأعمدة المفقودة في جدول الطلاب
      final columns = await db.rawQuery('PRAGMA table_info(students)');
      final columnNames = columns.map((col) => col['name'].toString().toLowerCase()).toList();
      
      if (!columnNames.contains('cheating_count')) {
        await db.execute('ALTER TABLE students ADD COLUMN cheating_count INTEGER DEFAULT 0');
      }
      
      if (!columnNames.contains('missing_count')) {
        await db.execute('ALTER TABLE students ADD COLUMN missing_count INTEGER DEFAULT 0');
      }
      
      if (!columnNames.contains('primary_guardian')) {
        await db.execute('ALTER TABLE students ADD COLUMN primary_guardian TEXT');
      }
      
      if (!columnNames.contains('secondary_guardian')) {
        await db.execute('ALTER TABLE students ADD COLUMN secondary_guardian TEXT');
      }
      
      if (!columnNames.contains('average_grade')) {
        await db.execute('ALTER TABLE students ADD COLUMN average_grade REAL DEFAULT 0');
      }
      
      if (!columnNames.contains('attended_lectures')) {
        await db.execute('ALTER TABLE students ADD COLUMN attended_lectures INTEGER DEFAULT 0');
      }
      
      if (!columnNames.contains('absent_lectures')) {
        await db.execute('ALTER TABLE students ADD COLUMN absent_lectures INTEGER DEFAULT 0');
      }
      
      if (!columnNames.contains('absence_percentage')) {
        await db.execute('ALTER TABLE students ADD COLUMN absence_percentage REAL DEFAULT 0');
      }
      
      if (!columnNames.contains('attended_exams')) {
        await db.execute('ALTER TABLE students ADD COLUMN attended_exams INTEGER DEFAULT 0');
      }
      
      if (!columnNames.contains('absent_exams')) {
        await db.execute('ALTER TABLE students ADD COLUMN absent_exams INTEGER DEFAULT 0');
      }
      
      print('✅ Database upgraded to version 10: Added missing student columns');
    }
    
    if (oldVersion < 11) {
      // الإصدار 11: تحديثات إضافية
      // أضف التحديثات هنا
      print('✅ Database upgraded to version 11');
    }
    
    if (oldVersion < 12) {
      // الإصدار 12: إضافة حقل photo_path للصور المحلية
      try {
        final columns = await db.rawQuery('PRAGMA table_info(students)');
        final columnNames = columns.map((col) => col['name'].toString().toLowerCase()).toList();
        
        if (!columnNames.contains('photo_path')) {
          await db.execute('ALTER TABLE students ADD COLUMN photo_path TEXT');
          print('✅ Database upgraded to version 12: photo_path column added to students table');
        } else {
          print('✅ photo_path column already exists in version 12');
        }
      } catch (e) {
        print('⚠️ photo_path column already exists or failed to add in version 12: $e');
      }
    }
    
    if (oldVersion < 14) {
      // الإصدار 14: التأكد من وجود حقل photo_path
      try {
        final columns = await db.rawQuery('PRAGMA table_info(students)');
        final columnNames = columns.map((col) => col['name'].toString().toLowerCase()).toList();
        
        if (!columnNames.contains('photo_path')) {
          await db.execute('ALTER TABLE students ADD COLUMN photo_path TEXT');
          print('✅ Database upgraded to version 14: photo_path column added to students table');
        } else {
          print('✅ photo_path column already exists in version 14');
        }
      } catch (e) {
        print('⚠️ photo_path column already exists or failed to add in version 14: $e');
      }
    }
    
    if (oldVersion < 18) {
      // الإصدار 18: إضافة حقل updated_at لجدول attendance
      try {
        final columns = await db.rawQuery('PRAGMA table_info(attendance)');
        final columnNames = columns.map((col) => col['name'].toString().toLowerCase()).toList();
        
        if (!columnNames.contains('updated_at')) {
          // أولاً أضيف العمود مع قيمة افتراضية
          await db.execute('ALTER TABLE attendance ADD COLUMN updated_at TEXT');
          
          // ثم حدث جميع السجلات الموجودة بقيمة افتراضية
          await db.execute('UPDATE attendance SET updated_at = created_at WHERE updated_at IS NULL');
          
          print('✅ Database upgraded to version 18: updated_at column added to attendance table');
        } else {
          print('✅ updated_at column already exists in version 18');
        }
      } catch (e) {
        print('⚠️ updated_at column already exists or failed to add in version 18: $e');
      }
    }

    if (oldVersion < 19) {
      // الإصدار 19: إضافة جدول messages إذا لم يكن موجوداً
      try {
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='messages'",
        );
        if (tables.isEmpty) {
          await db.execute('''
            CREATE TABLE messages (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              student_id INTEGER NOT NULL,
              class_id INTEGER NOT NULL,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              attached_file TEXT NOT NULL,
              send_methods TEXT NOT NULL,
              created_at TEXT NOT NULL,
              is_sent INTEGER NOT NULL DEFAULT 0,
              sent_at TEXT,
              FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
              FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_student_id ON messages(student_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_class_id ON messages(class_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at)');
          print('✅ Database upgraded to version 19: messages table added');
        }
      } catch (e) {
        print('⚠️ messages table creation failed in version 19: $e');
      }
    }

    if (oldVersion < 20) {
      // الإصدار 20: إصلاح ON DELETE CASCADE في جدول students
      try {
        // نسخ البيانات الحالية
        final studentsData = await db.query('students');
        
        // حذف الجدول القديم
        await db.execute('DROP TABLE IF EXISTS students');
        
        // إنشاء الجدول الجديد بدون CASCADE
        await db.execute('''
          CREATE TABLE students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER,
            name TEXT NOT NULL,
            photo TEXT,
            photo_path TEXT,
            notes TEXT,
            parent_phone TEXT,
            parent_email TEXT,
            student_id TEXT,
            email TEXT,
            phone TEXT,
            location TEXT,
            birth_date TEXT,
            primary_guardian TEXT,
            secondary_guardian TEXT,
            average_grade REAL,
            attended_lectures INTEGER,
            absent_lectures INTEGER,
            absence_percentage REAL,
            attended_exams INTEGER,
            absent_exams INTEGER,
            cheating_count INTEGER DEFAULT 0,
            missing_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE SET NULL
          )
        ''');
        
        // استعادة البيانات
        for (final student in studentsData) {
          await db.insert('students', student);
        }
        
        print('✅ Database upgraded to version 20: Fixed students table foreign key');
      } catch (e) {
        print('⚠️ Failed to upgrade students table in version 20: $e');
      }
    }

    if (oldVersion < 21) {
      // الإصدار 21: جعل class_id إلزامي + تفعيل ON DELETE CASCADE لجدول students
      try {
        // IMPORTANT:
        // - نغلق foreign keys مؤقتاً حتى لا يفشل DROP/CREATE.
        // - ننظف سجلات الجداول التابعة للطلاب اليتامى (class_id IS NULL) حتى لا تبقى Orphans.
        await db.execute('PRAGMA foreign_keys = OFF');

        final orphanRows = await db.query('students', columns: ['id'], where: 'class_id IS NULL');
        final orphanIds = <int>[];
        for (final r in orphanRows) {
          final v = r['id'];
          if (v is int) orphanIds.add(v);
        }

        for (final sid in orphanIds) {
          try {
            await db.delete('attendance', where: 'student_id = ?', whereArgs: [sid]);
          } catch (_) {}
          try {
            await db.delete('grades', where: 'student_id = ?', whereArgs: [sid]);
          } catch (_) {}
          try {
            await db.delete('student_notes', where: 'student_id = ?', whereArgs: [sid]);
          } catch (_) {}
          try {
            if (await _tableExists(db, 'messages')) {
              await db.delete('messages', where: 'student_id = ?', whereArgs: [sid]);
            }
          } catch (_) {}
        }

        // احذف الطلاب اليتامى الذين ليس لديهم class_id لأن الإصدار الجديد سيجعل الحقل NOT NULL.
        try {
          await db.delete('students', where: 'class_id IS NULL');
        } catch (_) {}

        final studentsData = await db.query('students');

        await db.execute('DROP TABLE IF EXISTS students');

        await db.execute('''
          CREATE TABLE students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            photo TEXT,
            photo_path TEXT,
            notes TEXT,
            parent_phone TEXT,
            parent_email TEXT,
            student_id TEXT,
            email TEXT,
            phone TEXT,
            location TEXT,
            birth_date TEXT,
            primary_guardian TEXT,
            secondary_guardian TEXT,
            average_grade REAL,
            attended_lectures INTEGER,
            absent_lectures INTEGER,
            absence_percentage REAL,
            attended_exams INTEGER,
            absent_exams INTEGER,
            cheating_count INTEGER DEFAULT 0,
            missing_count INTEGER DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
          )
        ''');

        await db.execute('CREATE INDEX IF NOT EXISTS idx_students_class_id ON students(class_id)');

        for (final student in studentsData) {
          final classId = student['class_id'];
          if (classId == null) continue;
          final s = Map<String, Object?>.from(student);

          // Legacy rows may miss timestamps; v21 schema makes them NOT NULL.
          final nowIso = DateTime.now().toIso8601String();
          final createdAt = (s['created_at']?.toString().trim().isNotEmpty ?? false)
              ? s['created_at']
              : null;
          final updatedAt = (s['updated_at']?.toString().trim().isNotEmpty ?? false)
              ? s['updated_at']
              : null;

          s['created_at'] = createdAt ?? updatedAt ?? nowIso;
          s['updated_at'] = updatedAt ?? createdAt ?? nowIso;

          await db.insert('students', s);
        }

        await db.execute('PRAGMA foreign_keys = ON');

        print('✅ Database upgraded to version 21: students.class_id NOT NULL + ON DELETE CASCADE');
      } catch (e) {
        try {
          await db.execute('PRAGMA foreign_keys = ON');
        } catch (_) {}
        print('⚠️ Failed to upgrade students table in version 21: $e');
      }
    }

    if (oldVersion < 22) {
      // الإصدار 22: إضافة جداول الواجبات
      await db.execute('''
        CREATE TABLE IF NOT EXISTS assignments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          due_date TEXT NOT NULL,
          required_count INTEGER,
          reason TEXT,
          scope TEXT NOT NULL DEFAULT 'all',
          assigned_student_ids_json TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS assignment_students (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          assignment_id INTEGER NOT NULL,
          student_id INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          done_count INTEGER NOT NULL DEFAULT 0,
          comment TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (assignment_id) REFERENCES assignments (id) ON DELETE CASCADE,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          UNIQUE(assignment_id, student_id)
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_assignments_class_id ON assignments(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_assignments_due_date ON assignments(due_date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_assignment_students_assignment_id ON assignment_students(assignment_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_assignment_students_student_id ON assignment_students(student_id)');

      print('✅ Database upgraded to version 22: assignments tables added');
    }

    if (oldVersion < 23) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS class_tuition_plans (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          class_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          total_amount INTEGER NOT NULL,
          installments_count INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS tuition_plan_installments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          plan_id INTEGER NOT NULL,
          installment_no INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          due_date TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
          UNIQUE(plan_id, installment_no)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_tuition_overrides (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          plan_id INTEGER NOT NULL,
          installment_no INTEGER NOT NULL,
          amount INTEGER NOT NULL,
          due_date TEXT NOT NULL,
          reason TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
          UNIQUE(student_id, plan_id, installment_no)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_plan_discount_reasons (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          plan_id INTEGER NOT NULL,
          reason TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
          UNIQUE(student_id, plan_id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_financial_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          plan_id INTEGER,
          note TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE SET NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS tuition_payments (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          receipt_no INTEGER NOT NULL,
          student_id INTEGER NOT NULL,
          plan_id INTEGER NOT NULL,
          installment_no INTEGER NOT NULL,
          due_amount INTEGER NOT NULL,
          paid_amount INTEGER NOT NULL,
          payment_date TEXT NOT NULL,
          notes TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
          UNIQUE(receipt_no)
        )
      ''');

      try {
        await db.insert(
          'settings',
          {'key': 'tuition_receipt_seq', 'value': '0'},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {
        // ignore
      }

      await db.execute('CREATE INDEX IF NOT EXISTS idx_class_tuition_plans_class_id ON class_tuition_plans(class_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tuition_plan_installments_plan_id ON tuition_plan_installments(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_tuition_overrides_student_id ON student_tuition_overrides(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_tuition_overrides_plan_id ON student_tuition_overrides(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_plan_discount_reasons_student_id ON student_plan_discount_reasons(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_plan_discount_reasons_plan_id ON student_plan_discount_reasons(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_financial_notes_student_id ON student_financial_notes(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_financial_notes_plan_id ON student_financial_notes(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tuition_payments_student_id ON tuition_payments(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tuition_payments_plan_id ON tuition_payments(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tuition_payments_installment_no ON tuition_payments(installment_no)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_tuition_payments_payment_date ON tuition_payments(payment_date)');

      print('✅ Database upgraded to version 23: tuition plans tables added');
    }

    if (oldVersion < 24) {
      try {
        await db.execute('ALTER TABLE student_tuition_overrides ADD COLUMN reason TEXT');
      } catch (_) {
        // ignore (column may already exist)
      }
      print('✅ Database upgraded to version 24: student tuition override reason added');
    }

    if (oldVersion < 25) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_plan_discount_reasons (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          plan_id INTEGER NOT NULL,
          reason TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE CASCADE,
          UNIQUE(student_id, plan_id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS student_financial_notes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          student_id INTEGER NOT NULL,
          plan_id INTEGER,
          note TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
          FOREIGN KEY (plan_id) REFERENCES class_tuition_plans (id) ON DELETE SET NULL
        )
      ''');

      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_plan_discount_reasons_student_id ON student_plan_discount_reasons(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_plan_discount_reasons_plan_id ON student_plan_discount_reasons(plan_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_financial_notes_student_id ON student_financial_notes(student_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_student_financial_notes_plan_id ON student_financial_notes(plan_id)');

      try {
        final nowIso = DateTime.now().toIso8601String();
        final rows = await db.rawQuery(
          '''
          SELECT student_id, plan_id, reason, MAX(updated_at) AS max_updated
          FROM student_tuition_overrides
          WHERE reason IS NOT NULL AND TRIM(reason) <> ''
          GROUP BY student_id, plan_id
          ''',
        );
        for (final r in rows) {
          final sid = r['student_id'];
          final pid = r['plan_id'];
          final reason = r['reason']?.toString();
          final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
          final pidInt = (pid is int) ? pid : int.tryParse(pid?.toString() ?? '');
          if (sidInt == null || pidInt == null) continue;
          if (reason == null || reason.trim().isEmpty) continue;
          await db.insert(
            'student_plan_discount_reasons',
            {
              'student_id': sidInt,
              'plan_id': pidInt,
              'reason': reason.trim(),
              'created_at': nowIso,
              'updated_at': nowIso,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (_) {
        // ignore
      }

      print('✅ Database upgraded to version 25: per-plan discount reasons + financial notes added');
    }
  }

  Future<String?> getStudentPlanDiscountReason({
    required int studentId,
    required int planId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'student_plan_discount_reasons',
      columns: ['reason'],
      where: 'student_id = ? AND plan_id = ?',
      whereArgs: [studentId, planId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final r = rows.first['reason']?.toString();
    if (r == null) return null;
    final t = r.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> upsertStudentPlanDiscountReason({
    required int studentId,
    required int planId,
    String? reason,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final trimmed = reason?.trim();

    if (trimmed == null || trimmed.isEmpty) {
      await db.delete(
        'student_plan_discount_reasons',
        where: 'student_id = ? AND plan_id = ?',
        whereArgs: [studentId, planId],
      );
      await _enqueueSyncOutbox(
        tableName: 'student_plan_discount_reasons',
        localId: '${studentId}_$planId',
        op: 'delete',
      );
      return;
    }

    await db.insert(
      'student_plan_discount_reasons',
      {
        'student_id': studentId,
        'plan_id': planId,
        'reason': trimmed,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enqueueSyncOutbox(
      tableName: 'student_plan_discount_reasons',
      localId: '${studentId}_$planId',
      op: 'upsert',
      payload: {
        'student_id': studentId,
        'plan_id': planId,
        'reason': trimmed,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<int> addStudentFinancialNote({
    required int studentId,
    int? planId,
    required String note,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final id = await db.insert(
      'student_financial_notes',
      {
        'student_id': studentId,
        'plan_id': planId,
        'note': note,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );
    await _enqueueSyncOutbox(
      tableName: 'student_financial_notes',
      localId: id.toString(),
      op: 'insert',
      payload: {
        'id': id,
        'student_id': studentId,
        'plan_id': planId,
        'note': note,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> getStudentFinancialNotes({
    required int studentId,
    int? planId,
  }) async {
    final db = await database;
    final where = <String>['student_id = ?'];
    final args = <Object?>[studentId];
    if (planId != null) {
      where.add('plan_id = ?');
      args.add(planId);
    }
    return await db.query(
      'student_financial_notes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
    );
  }

  Future<Map<int, String>> getStudentPlanDiscountReasonsMap({
    required int planId,
    required List<int> studentIds,
  }) async {
    final db = await database;
    if (studentIds.isEmpty) return {};
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT student_id, reason FROM student_plan_discount_reasons '
      'WHERE plan_id = ? AND student_id IN ($placeholders)',
      [planId, ...studentIds],
    );
    final map = <int, String>{};
    for (final r in rows) {
      final sid = (r['student_id'] is int) ? (r['student_id'] as int) : int.tryParse(r['student_id']?.toString() ?? '');
      if (sid == null) continue;
      map[sid] = r['reason']?.toString() ?? '';
    }
    return map;
  }

  Future<Map<int, String>> getLatestStudentFinancialNotesMap({
    required int planId,
    required List<int> studentIds,
  }) async {
    final db = await database;
    if (studentIds.isEmpty) return {};
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT student_id, note, created_at, id FROM student_financial_notes '
      'WHERE plan_id = ? AND student_id IN ($placeholders) '
      'ORDER BY created_at DESC, id DESC',
      [planId, ...studentIds],
    );
    final map = <int, String>{};
    for (final r in rows) {
      final sid = (r['student_id'] is int) ? (r['student_id'] as int) : int.tryParse(r['student_id']?.toString() ?? '');
      if (sid == null) continue;
      if (map.containsKey(sid)) continue;
      map[sid] = r['note']?.toString() ?? '';
    }
    return map;
  }

  Future<Map<int, Map<int, int>>> getTuitionPaidTotalsByStudentInstallment({
    required int planId,
    required List<int> studentIds,
  }) async {
    final db = await database;
    if (studentIds.isEmpty) return {};
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT student_id, installment_no, SUM(paid_amount) AS paid_sum '
      'FROM tuition_payments '
      'WHERE plan_id = ? AND student_id IN ($placeholders) '
      'GROUP BY student_id, installment_no',
      [planId, ...studentIds],
    );
    final result = <int, Map<int, int>>{};
    for (final r in rows) {
      final sid = (r['student_id'] is int) ? (r['student_id'] as int) : int.tryParse(r['student_id']?.toString() ?? '');
      final ino = (r['installment_no'] is int) ? (r['installment_no'] as int) : int.tryParse(r['installment_no']?.toString() ?? '');
      if (sid == null || ino == null) continue;
      final paid = (r['paid_sum'] is num) ? (r['paid_sum'] as num).toInt() : int.tryParse(r['paid_sum']?.toString() ?? '') ?? 0;
      final byInst = result.putIfAbsent(sid, () => <int, int>{});
      byInst[ino] = paid;
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getLateTuitionInstallmentsBatch({
    required int planId,
    required List<int> studentIds,
  }) async {
    final db = await database;
    if (studentIds.isEmpty) return [];

    final placeholders = core.List.filled(studentIds.length, '?').join(',');

    // ملاحظة: نستخدم date('now') لتجاهل الوقت وإبقاء المقارنة حسب اليوم
    // بعض البيانات قد تُخزَّن بصيغة YYYY/MM/DD؛ لذلك نطبّعها إلى YYYY-MM-DD عبر replace قبل date/julianday.
    final rows = await db.rawQuery(
      'SELECT s.student_id AS student_id, '
      't.installment_no AS installment_no, '
      'COALESCE(o.due_date, t.due_date) AS due_date, '
      'COALESCE(o.amount, t.amount) AS due_amount, '
      'COALESCE(p.paid_sum, 0) AS paid_amount, '
      '(COALESCE(o.amount, t.amount) - COALESCE(p.paid_sum, 0)) AS remaining_amount, '
      'CAST((julianday(date(\'now\')) - julianday(date(replace(COALESCE(o.due_date, t.due_date), \"/\", \"-\")))) AS INTEGER) AS days_late '
      'FROM tuition_plan_installments t '
      'CROSS JOIN (SELECT id AS student_id FROM students WHERE id IN ($placeholders)) s '
      'LEFT JOIN student_tuition_overrides o '
      '  ON o.plan_id = t.plan_id AND o.student_id = s.student_id AND o.installment_no = t.installment_no '
      'LEFT JOIN ( '
      '  SELECT student_id, installment_no, SUM(paid_amount) AS paid_sum '
      '  FROM tuition_payments '
      '  WHERE plan_id = ? AND student_id IN ($placeholders) '
      '  GROUP BY student_id, installment_no '
      ') p '
      '  ON p.student_id = s.student_id AND p.installment_no = t.installment_no '
      'WHERE t.plan_id = ? '
      '  AND date(replace(COALESCE(o.due_date, t.due_date), \"/\", \"-\")) < date(\'now\') '
      '  AND (COALESCE(o.amount, t.amount) - COALESCE(p.paid_sum, 0)) > 0 '
      'ORDER BY s.student_id ASC, t.installment_no ASC',
      [
        ...studentIds,
        planId,
        ...studentIds,
        planId,
      ],
    );

    return rows;
  }

  Future<void> updateStudentFinancialNote({
    required int noteId,
    required String note,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    await db.update(
      'student_financial_notes',
      {
        'note': note,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [noteId],
    );
    await _enqueueSyncOutbox(
      tableName: 'student_financial_notes',
      localId: noteId.toString(),
      op: 'update',
      payload: {
        'id': noteId,
        'note': note,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> deleteStudentFinancialNote({
    required int noteId,
  }) async {
    final db = await database;
    await db.delete(
      'student_financial_notes',
      where: 'id = ?',
      whereArgs: [noteId],
    );
    await _enqueueSyncOutbox(
      tableName: 'student_financial_notes',
      localId: noteId.toString(),
      op: 'delete',
    );
  }

  // عمليات الفصول
  Future<int> insertClass(ClassModel classModel) async {
    final db = await database;
    final id = await db.insert('classes', classModel.toMap());
    await _enqueueSyncOutbox(
      tableName: 'classes',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...classModel.toMap(),
        'id': id,
      },
    );
    
    // تحقق تلقائي بعد الإضافة - معطل مؤقتًا
    // await _validateDatabaseIntegrity();
    
    return id;
  }

  Future<List<ClassModel>> getAllClasses() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('classes');
    print('📚 Retrieved ${maps.length} classes from database');
    return List.generate(maps.length, (i) => ClassModel.fromMap(maps[i]));
  }

  Future<ClassModel?> getClass(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'classes',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return ClassModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateClass(ClassModel classModel) async {
    final db = await database;
    final result = await db.update(
      'classes',
      classModel.toMap(),
      where: 'id = ?',
      whereArgs: [classModel.id],
    );
    if ((classModel.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'classes',
        localId: classModel.id.toString(),
        op: 'update',
        payload: classModel.toMap(),
      );
    }
    
    // تحقق تلقائي بعد التحديث - معطل مؤقتًا
    // await _validateDatabaseIntegrity();
    
    return result;
  }

  // عمليات الواجبات
  Future<int> insertAssignment(AssignmentModel assignment) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final map = assignment.toMap();
    map['created_at'] = (map['created_at'] ?? nowIso).toString();
    map['updated_at'] = (map['updated_at'] ?? nowIso).toString();
    final id = await db.insert('assignments', map);

    await _enqueueSyncOutbox(
      tableName: 'assignments',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...map,
        'id': id,
      },
    );

    return id;
  }

  Future<List<AssignmentModel>> getAssignmentsByClass(int classId) async {
    final db = await database;
    final maps = await db.query(
      'assignments',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'due_date DESC, created_at DESC',
    );
    return List.generate(maps.length, (i) => AssignmentModel.fromMap(maps[i]));
  }

  Future<List<AssignmentStudentModel>> getAssignmentStudentStatusesByClass(int classId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT s.*
      FROM assignment_students s
      INNER JOIN assignments a ON a.id = s.assignment_id
      WHERE a.class_id = ?
      ''',
      [classId],
    );
    return List.generate(rows.length, (i) => AssignmentStudentModel.fromMap(rows[i]));
  }

  Future<int> updateAssignment(AssignmentModel assignment) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final map = assignment.toMap();
    map['updated_at'] = nowIso;
    final result = await db.update(
      'assignments',
      map,
      where: 'id = ?',
      whereArgs: [assignment.id],
    );

    if ((assignment.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'assignments',
        localId: assignment.id.toString(),
        op: 'update',
        payload: map,
      );
    }

    return result;
  }

  Future<int> deleteAssignment(int assignmentId) async {
    final db = await database;
    List<Map<String, Object?>>? studentRows;
    try {
      studentRows = await db.query(
        'assignment_students',
        columns: ['student_id'],
        where: 'assignment_id = ?',
        whereArgs: [assignmentId],
      );
    } catch (_) {
      studentRows = null;
    }

    final result = await db.transaction((txn) async {
      try {
        await txn.delete(
          'assignment_students',
          where: 'assignment_id = ?',
          whereArgs: [assignmentId],
        );
      } catch (_) {}

      return await txn.delete(
        'assignments',
        where: 'id = ?',
        whereArgs: [assignmentId],
      );
    });

    await _enqueueSyncOutbox(
      tableName: 'assignments',
      localId: assignmentId.toString(),
      op: 'delete',
    );

    if (studentRows != null) {
      for (final r in studentRows) {
        final sid = r['student_id'];
        if (sid is int) {
          await _enqueueSyncOutbox(
            tableName: 'assignment_students',
            localId: '${assignmentId}_$sid',
            op: 'delete',
          );
        }
      }
    }

    return result;
  }

  Future<void> upsertAssignmentStudentStatus(AssignmentStudentModel status) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final values = status.toMap();
    // assignment_students.id is AUTOINCREMENT; never include it in updates/inserts.
    values.remove('id');
    values['created_at'] = (values['created_at'] ?? nowIso).toString();
    values['updated_at'] = nowIso;

    final updated = await db.update(
      'assignment_students',
      values,
      where: 'assignment_id = ? AND student_id = ?',
      whereArgs: [status.assignmentId, status.studentId],
    );
    if (updated == 0) {
      await db.insert('assignment_students', values);
    }

    await _enqueueSyncOutbox(
      tableName: 'assignment_students',
      localId: '${status.assignmentId}_${status.studentId}',
      op: 'upsert',
      payload: values,
    );
  }

  Future<int> deleteClass(int id) async {
    final db = await database;
    final result = await db.delete(
      'classes',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (result > 0) {
      await _enqueueSyncOutbox(
        tableName: 'classes',
        localId: id.toString(),
        op: 'delete',
      );
    }

    // تحقق تلقائي بعد الحذف - معطل مؤقتًا
    // await _validateDatabaseIntegrity();

    return result;
  }

  Future<int> getNextStudentSerialForClass(int classId) async {
    final db = await database;
    final rows = await db.query(
      'students',
      columns: ['student_id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );

    var maxSerial = 0;
    for (final r in rows) {
      final raw = r['student_id']?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final v = int.tryParse(raw);
      if (v == null) continue;
      if (v > maxSerial) maxSerial = v;
    }
    return maxSerial + 1;
  }

  Future<bool> isStudentIdTaken(String studentId) async {
    final db = await database;
    final trimmed = studentId.trim();
    if (trimmed.isEmpty) return false;
    final rows = await db.query(
      'students',
      columns: ['id'],
      where: 'student_id = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<String> getNextUniqueStudentId() async {
    // Keep generating until we find a student_id that doesn't exist.
    var next = await getNextStudentSerial();
    while (await isStudentIdTaken(next.toString())) {
      next++;
    }
    return next.toString();
  }

  Future<int> getNextStudentSerial() async {
    final db = await database;
    final rows = await db.query(
      'students',
      columns: ['student_id'],
    );

    var maxSerial = 0;
    for (final r in rows) {
      final raw = r['student_id']?.toString().trim();
      if (raw == null || raw.isEmpty) continue;
      final v = int.tryParse(raw);
      if (v == null) continue;
      if (v > maxSerial) maxSerial = v;
    }
    return maxSerial + 1;
  }

  Future<void> deleteClassCascade(int classId) async {
    final db = await database;

    final studentRows = await db.query(
      'students',
      columns: ['id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    final studentIds = studentRows.map((r) => r['id']).whereType<int>().toList();

    final lectureRows = await db.query(
      'lectures',
      columns: ['id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    final lectureIds = lectureRows.map((r) => r['id']).whereType<int>().toList();

    final examRows = await db.query(
      'exams',
      columns: ['id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    final examIds = examRows.map((r) => r['id']).whereType<int>().toList();

    for (final id in lectureIds) {
      final attendanceRows = await db.query(
        'attendance',
        columns: ['id'],
        where: 'lecture_id = ?',
        whereArgs: [id],
      );
      for (final a in attendanceRows) {
        final aid = a['id'];
        if (aid is int) {
          await _enqueueSyncOutbox(tableName: 'attendance', localId: aid.toString(), op: 'delete');
        }
      }
    }

    final hasMessagesTable = await _tableExists(db, 'messages');
    for (final id in studentIds) {
      final attendanceRows = await db.query(
        'attendance',
        columns: ['id'],
        where: 'student_id = ?',
        whereArgs: [id],
      );
      for (final a in attendanceRows) {
        final aid = a['id'];
        if (aid is int) {
          await _enqueueSyncOutbox(tableName: 'attendance', localId: aid.toString(), op: 'delete');
        }
      }

      final gradeRows = await db.query(
        'grades',
        columns: ['id'],
        where: 'student_id = ?',
        whereArgs: [id],
      );
      for (final g in gradeRows) {
        final gid = g['id'];
        if (gid is int) {
          await _enqueueSyncOutbox(tableName: 'grades', localId: gid.toString(), op: 'delete');
        }
      }

      final studentNoteRows = await db.query(
        'student_notes',
        columns: ['id'],
        where: 'student_id = ?',
        whereArgs: [id],
      );
      for (final sn in studentNoteRows) {
        final sid = sn['id'];
        if (sid is int) {
          await _enqueueSyncOutbox(tableName: 'student_notes', localId: sid.toString(), op: 'delete');
        }
      }

      if (hasMessagesTable) {
        try {
          final messageRows = await db.query(
            'messages',
            columns: ['id'],
            where: 'student_id = ?',
            whereArgs: [id],
          );
          for (final m in messageRows) {
            final mid = m['id'];
            if (mid is int) {
              await _enqueueSyncOutbox(tableName: 'messages', localId: mid.toString(), op: 'delete');
            }
          }
        } catch (e) {
          print('⚠️ Error deleting class messages: $e');
        }
      }
    }

    final noteRows = await db.query(
      'notes',
      columns: ['id'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    for (final n in noteRows) {
      final nid = n['id'];
      if (nid is int) {
        await _enqueueSyncOutbox(tableName: 'notes', localId: nid.toString(), op: 'delete');
      }
    }

    for (final id in lectureIds) {
      await _enqueueSyncOutbox(tableName: 'lectures', localId: id.toString(), op: 'delete');
    }
    for (final id in examIds) {
      await _enqueueSyncOutbox(tableName: 'exams', localId: id.toString(), op: 'delete');
    }
    for (final id in studentIds) {
      await _enqueueSyncOutbox(tableName: 'students', localId: id.toString(), op: 'delete');
    }
    await _enqueueSyncOutbox(tableName: 'classes', localId: classId.toString(), op: 'delete');

    await db.transaction((txn) async {
      if (lectureIds.isNotEmpty) {
        await txn.delete(
          'attendance',
          where: 'lecture_id IN (${core.List.filled(lectureIds.length, '?').join(',')})',
          whereArgs: lectureIds,
        );
      }
      if (studentIds.isNotEmpty) {
        await txn.delete(
          'attendance',
          where: 'student_id IN (${core.List.filled(studentIds.length, '?').join(',')})',
          whereArgs: studentIds,
        );
        await txn.delete(
          'grades',
          where: 'student_id IN (${core.List.filled(studentIds.length, '?').join(',')})',
          whereArgs: studentIds,
        );
      }
      await txn.delete('student_notes', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('notes', where: 'class_id = ?', whereArgs: [classId]);
      if (hasMessagesTable) {
        try {
          await txn.delete('messages', where: 'class_id = ?', whereArgs: [classId]);
        } catch (_) {}
      }
      await txn.delete('lectures', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('exams', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('students', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('classes', where: 'id = ?', whereArgs: [classId]);
    });
  }

  // عمليات الطلاب
  Future<int> insertStudent(StudentModel student) async {
    final db = await database;
    // Insert should not include an explicit null id.
    // Also, some app installs might still have an older schema missing newer columns.
    // Filter payload to existing columns to avoid "no such column" errors.
    final studentMap = Map<String, dynamic>.from(student.toMap());
    studentMap.remove('id');

    final columns = await db.rawQuery("PRAGMA table_info('students')");
    final existingCols = columns
        .map((c) => (c['name']?.toString() ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    studentMap.removeWhere((key, value) => !existingCols.contains(key));
    print('📝 Inserting student: ${student.name} for class_id: ${student.classId}');
    print('📊 Student data: $studentMap');
    final id = await db.insert('students', studentMap);
    print('✅ Student inserted: ${student.name} with ID: $id');
    
    // التحقق من الحفظ
    final saved = await db.query('students', where: 'id = ?', whereArgs: [id]);
    print('🔍 Verification - Student saved: $saved');
    
    final payload = <String, dynamic>{
      ...studentMap,
      'id': id,
    };
    // photo_path مسار محلي على الجهاز، لا يجب مزامنته مع السحابة
    payload.remove('photo_path');

    await _enqueueSyncOutbox(
      tableName: 'students',
      localId: id.toString(),
      op: 'insert',
      payload: payload,
    );
    return id;
  }

  Future<List<StudentModel>> getStudentsByClass(int classId) async {
    final db = await database;
    
    // فحص جميع الطلاب أولاً
    final allStudents = await db.query('students');
    print('📊 Total students in database: ${allStudents.length}');
    if (allStudents.isNotEmpty) {
      print('📋 All students class_ids: ${allStudents.map((s) => s['class_id']).toList()}');
    }
    
    // الآن البحث عن طلاب الفصل المحدد
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: 'class_id = ?',
      whereArgs: [classId],
    );
    print('👥 Retrieved ${maps.length} students for class $classId');
    if (maps.isEmpty && allStudents.isNotEmpty) {
      print('⚠️ WARNING: Students exist but none match class_id: $classId');
    }
    return List.generate(maps.length, (i) => StudentModel.fromMap(maps[i]));
  }

  Future<List<StudentModel>> getAllStudents() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('students');
    return List.generate(maps.length, (i) => StudentModel.fromMap(maps[i]));
  }

  Future<StudentModel?> getStudent(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'students',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return StudentModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateStudent(StudentModel student) async {
    final db = await database;
    final map = Map<String, dynamic>.from(student.toMap());
    // Never update the primary key via the payload.
    map.remove('id');

    // Filter to existing columns for forward/backward compatible schemas.
    final columns = await db.rawQuery("PRAGMA table_info('students')");
    final existingCols = columns
        .map((c) => (c['name']?.toString() ?? '').trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    map.removeWhere((key, value) => !existingCols.contains(key));

    final result = await db.update(
      'students',
      map,
      where: 'id = ?',
      whereArgs: [student.id],
    );
    if ((student.id ?? 0) > 0) {
      final payload = Map<String, dynamic>.from(map);
      // photo_path مسار محلي على الجهاز، لا يجب مزامنته مع السحابة
      payload.remove('photo_path');

      await _enqueueSyncOutbox(
        tableName: 'students',
        localId: student.id.toString(),
        op: 'update',
        payload: payload,
      );
    }
    return result;
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;

    // Explicit cascade delete to avoid FK/constraint issues and ensure multi-delete works reliably.
    final result = await db.transaction<int>((txn) async {
      // attendance rows for student
      await txn.delete('attendance', where: 'student_id = ?', whereArgs: [id]);
      // grades rows for student (if table exists)
      try {
        await txn.delete('grades', where: 'student_id = ?', whereArgs: [id]);
      } catch (_) {}
      // student notes rows (if table exists)
      try {
        await txn.delete('student_notes', where: 'student_id = ?', whereArgs: [id]);
      } catch (_) {}
      // messaging rows (if table exists)
      try {
        await txn.delete('messages', where: 'student_id = ?', whereArgs: [id]);
      } catch (_) {}

      return await txn.delete('students', where: 'id = ?', whereArgs: [id]);
    });

    if (result > 0) {
      await _enqueueSyncOutbox(
        tableName: 'students',
        localId: id.toString(),
        op: 'delete',
      );
    }

    return result;
  }

  // عمليات الحضور
  Future<int> insertAttendance(AttendanceModel attendance) async {
    final db = await database;
    
    try {
      final attendanceMap = Map<String, dynamic>.from(attendance.toMap())..remove('id');
      
      // التأكد من وجود updated_at
      if (!attendanceMap.containsKey('updated_at')) {
        attendanceMap['updated_at'] = DateTime.now().toIso8601String();
      }

      // التحقق من وجود سجل حضور لنفس الطالب في نفس المحاضرة
      if (attendance.lectureId != null) {
        final existing = await db.query(
          'attendance',
          where: 'student_id = ? AND lecture_id = ?',
          whereArgs: [attendance.studentId, attendance.lectureId],
        );
        
        if (existing.isNotEmpty) {
          // تحديث السجل الموجود
          debugPrint('📝 تحديث حضور الطالب ${attendance.studentId} للمحاضرة ${attendance.lectureId}');
          final existingId = existing.first['id'];
          final result = await db.update(
            'attendance',
            attendanceMap,
            where: 'student_id = ? AND lecture_id = ?',
            whereArgs: [attendance.studentId, attendance.lectureId],
          );
          if (existingId != null) {
            await _enqueueSyncOutbox(
              tableName: 'attendance',
              localId: existingId.toString(),
              op: 'update',
              payload: attendanceMap,
            );
          }
          debugPrint('✅ تم التحديث بنجاح');
          return result;
        }
      }
      
      // إدراج سجل جديد
      debugPrint('➕ إضافة حضور جديد للطالب ${attendance.studentId} للمحاضرة ${attendance.lectureId}');
      final result = await db.insert(
        'attendance',
        attendanceMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      debugPrint('✅ تم الإدراج بنجاح - ID: $result');
      await _enqueueSyncOutbox(
        tableName: 'attendance',
        localId: result.toString(),
        op: 'insert',
        payload: attendanceMap,
      );
      return result;
    } catch (e) {
      debugPrint('❌ خطأ في حفظ الحضور: $e');
      rethrow;
    }
  }

  Future<List<AttendanceModel>> getAttendanceByStudent(int studentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => AttendanceModel.fromMap(maps[i]));
  }

  Future<List<AttendanceModel>> getAttendancesByLectureId(int lectureId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'lecture_id = ?',
      whereArgs: [lectureId],
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => AttendanceModel.fromMap(maps[i]));
  }

  Future<List<AttendanceModel>> getAttendancesByStudent(int studentId) async {
    return getAttendanceByStudent(studentId);
  }

  Future<AttendanceModel?> getAttendanceByStudentAndLecture({
    required int studentId,
    required int lectureId,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'student_id = ? AND lecture_id = ?',
      whereArgs: [studentId, lectureId],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return AttendanceModel.fromMap(maps.first);
    }
    return null;
  }

  Future<AttendanceModel?> getAttendanceByStudentAndDate({
    required int studentId,
    required DateTime date,
  }) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'student_id = ? AND date = ?',
      whereArgs: [studentId, dateStr],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      return AttendanceModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateAttendance(AttendanceModel attendance) async {
    final db = await database;
    final attendanceMap = Map<String, dynamic>.from(attendance.toMap())..remove('id');
    final result = await db.update(
      'attendance',
      attendanceMap,
      where: 'id = ?',
      whereArgs: [attendance.id],
    );
    if ((attendance.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'attendance',
        localId: attendance.id.toString(),
        op: 'update',
        payload: attendanceMap,
      );
    }
    return result;
  }

  Future<List<AttendanceModel>> getAttendanceByDate(DateTime date) async {
    final db = await database;
    final dateStr = date.toIso8601String().split('T')[0];
    final List<Map<String, dynamic>> maps = await db.query(
      'attendance',
      where: 'date = ?',
      whereArgs: [dateStr],
    );
    return List.generate(maps.length, (i) => AttendanceModel.fromMap(maps[i]));
  }

  // تنظيف البيانات المكررة
  Future<void> cleanDuplicateData() async {
    final db = await database;
    
    try {
      print('\n🧹 ════════════════════════════════════════');
      print('🧹 بدء فحص وتنظيف قاعدة البيانات...');
      print('🧹 ════════════════════════════════════════\n');
      
      // إحصائيات قبل التنظيف
      final totalStudentsBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM students')) ?? 0;
      final totalGradesBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM grades')) ?? 0;
      final totalAttendancesBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM attendance')) ?? 0;
      
      print('📊 إحصائيات قبل التنظيف:');
      print('   👥 الطلاب: $totalStudentsBefore');
      print('   📝 الدرجات: $totalGradesBefore');
      print('   ✅ الحضور: $totalAttendancesBefore\n');
      
      // 1. تنظيف الدرجات المكررة (نفس الطالب + نفس الامتحان)
      print('🔍 فحص الدرجات المكررة...');
      final duplicateGrades = await db.rawQuery('''
        SELECT student_id, exam_name, COUNT(*) as count
        FROM grades
        GROUP BY student_id, exam_name
        HAVING COUNT(*) > 1
      ''');
      
      if (duplicateGrades.isNotEmpty) {
        print('⚠️  وجدت ${duplicateGrades.length} درجة مكررة');
        
        for (var grade in duplicateGrades) {
          final studentId = grade['student_id'];
          final examName = grade['exam_name'];
          
          // الاحتفاظ بآخر درجة فقط (أحدث created_at)
          final allGrades = await db.query(
            'grades',
            where: 'student_id = ? AND exam_name = ?',
            whereArgs: [studentId, examName],
            orderBy: 'created_at DESC',
          );
          
          // حذف جميع الدرجات ماعدا الأولى (الأحدث)
          for (int i = 1; i < allGrades.length; i++) {
            await db.delete('grades', where: 'id = ?', whereArgs: [allGrades[i]['id']]);
          }
        }
        print('✅ تم تنظيف الدرجات المكررة\n');
      } else {
        print('✅ لا توجد درجات مكررة\n');
      }
      
      // 2. تنظيف الحضور المكرر (نفس الطالب + نفس المحاضرة)
      print('🔍 فحص الحضور المكرر...');
      final duplicateAttendances = await db.rawQuery('''
        SELECT student_id, lecture_id, COUNT(*) as count
        FROM attendance
        WHERE lecture_id IS NOT NULL
        GROUP BY student_id, lecture_id
        HAVING COUNT(*) > 1
      ''');
      
      if (duplicateAttendances.isNotEmpty) {
        print('⚠️  وجدت ${duplicateAttendances.length} حضور مكرر');
        
        for (var attendance in duplicateAttendances) {
          final studentId = attendance['student_id'];
          final lectureId = attendance['lecture_id'];
          
          // الاحتفاظ بآخر حضور فقط (أحدث id)
          final allAttendances = await db.query(
            'attendance',
            where: 'student_id = ? AND lecture_id = ?',
            whereArgs: [studentId, lectureId],
            orderBy: 'id DESC',
          );
          
          // حذف جميع السجلات ماعدا الأول (الأحدث)
          for (int i = 1; i < allAttendances.length; i++) {
            await db.delete('attendance', where: 'id = ?', whereArgs: [allAttendances[i]['id']]);
          }
        }
        print('✅ تم تنظيف الحضور المكرر\n');
      } else {
        print('✅ لا يوجد حضور مكرر\n');
      }
      
      // 3. حذف الطلاب الذين لا ينتمون لأي فصل موجود
      print('🔍 فحص الطلاب اليتامى (بدون فصل)...');
      final classes = await db.query('classes', columns: ['id']);
      final classIds = classes.map((c) => c['id']).toList();
      
      int orphanStudents = 0;
      if (classIds.isNotEmpty) {
        final placeholders = core.List.filled(classIds.length, '?').join(',');
        orphanStudents = await db.delete(
          'students',
          where: 'class_id NOT IN ($placeholders)',
          whereArgs: classIds,
        );
      }
      
      if (orphanStudents > 0) {
        print('⚠️  تم حذف $orphanStudents طالب يتيم\n');
      } else {
        print('✅ لا يوجد طلاب يتامى\n');
      }
      
      // 4. حذف الدرجات اليتيمة (لطلاب محذوفين)
      print('🔍 فحص الدرجات اليتيمة...');
      final studentIds = (await db.query('students', columns: ['id'])).map((s) => s['id']).toList();
      int orphanGrades = 0;
      if (studentIds.isNotEmpty) {
        final placeholders = core.List.filled(studentIds.length, '?').join(',');
        orphanGrades = await db.delete(
          'grades',
          where: 'student_id NOT IN ($placeholders)',
          whereArgs: studentIds,
        );
      }
      
      if (orphanGrades > 0) {
        print('⚠️  تم حذف $orphanGrades درجة يتيمة\n');
      } else {
        print('✅ لا توجد درجات يتيمة\n');
      }
      
      // 5. حذف الحضور اليتيم (لطلاب محذوفين)
      print('🔍 فحص الحضور اليتيم...');
      int orphanAttendances = 0;
      if (studentIds.isNotEmpty) {
        final placeholders = core.List.filled(studentIds.length, '?').join(',');
        orphanAttendances = await db.delete(
          'attendance',
          where: 'student_id NOT IN ($placeholders)',
          whereArgs: studentIds,
        );
      }
      
      if (orphanAttendances > 0) {
        print('⚠️  تم حذف $orphanAttendances حضور يتيم\n');
      } else {
        print('✅ لا يوجد حضور يتيم\n');
      }
      
      // إحصائيات بعد التنظيف
      final totalStudentsAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM students')) ?? 0;
      final totalGradesAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM grades')) ?? 0;
      final totalAttendancesAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM attendance')) ?? 0;
      
      print('📊 إحصائيات بعد التنظيف:');
      print('   👥 الطلاب: $totalStudentsAfter (تم حذف ${totalStudentsBefore - totalStudentsAfter})');
      print('   📝 الدرجات: $totalGradesAfter (تم حذف ${totalGradesBefore - totalGradesAfter})');
      print('   ✅ الحضور: $totalAttendancesAfter (تم حذف ${totalAttendancesBefore - totalAttendancesAfter})\n');
      
      print('🧹 ════════════════════════════════════════');
      print('✅ تم تنظيف قاعدة البيانات بنجاح!');
      print('🧹 ════════════════════════════════════════\n');
    } catch (e) {
      print('❌ خطأ في تنظيف البيانات: $e');
    }
  }

  // عمليات الدرجات
  Future<int> insertGrade(GradeModel grade) async {
    final db = await database;
    final map = Map<String, dynamic>.from(grade.toMap());
    if (grade.status == null) {
      map.remove('status');
    }
    try {
      final id = await db.insert('grades', map);
      await _enqueueSyncOutbox(
        tableName: 'grades',
        localId: id.toString(),
        op: 'insert',
        payload: {
          ...map,
          'id': id,
        },
      );
      return id;
    } on DatabaseException catch (e) {
      if (e.toString().contains('no column named status')) {
        await _ensureGradesStatusColumn(db);
        try {
          final id = await db.insert('grades', map);
          await _enqueueSyncOutbox(
            tableName: 'grades',
            localId: id.toString(),
            op: 'insert',
            payload: {
              ...map,
              'id': id,
            },
          );
          return id;
        } on DatabaseException {
          final fallback = Map<String, dynamic>.from(map)..remove('status');
          final id = await db.insert('grades', fallback);
          await _enqueueSyncOutbox(
            tableName: 'grades',
            localId: id.toString(),
            op: 'insert',
            payload: {
              ...fallback,
              'id': id,
            },
          );
          return id;
        }
      }
      rethrow;
    }
  }

  Future<GradeInfo?> getStudentGradeForExam(int studentId, int examId) async {
    final db = await database;
    
    // أولاً جلب اسم الامتحان من جدول exams
    final examResult = await db.query(
      'exams',
      where: 'id = ?',
      whereArgs: [examId],
      limit: 1,
    );
    
    if (examResult.isEmpty) return null;
    
    final examTitle = examResult.first['title'] as String;
    
    // الآن جلب درجة الطالب لهذا الامتحان
    final List<Map<String, dynamic>> maps = await db.query(
      'grades',
      where: 'student_id = ? AND (exam_name = ? OR exam_name = ?)',
      whereArgs: [studentId, examTitle, examId.toString()],
      limit: 1,
    );
    
    if (maps.isNotEmpty) {
      final grade = GradeModel.fromMap(maps.first);
      return GradeInfo(
        obtainedMarks: grade.score,
        totalMarks: grade.maxScore,
        comment: grade.notes,
        status: grade.status, // قراءة الحالة من نموذج GradeModel
      );
    }
    return null;
  }

  Future<void> updateComment(int studentId, int examId, String comment) async {
    final db = await database;
    
    // البحث عن سجل الدرجة الموجود
    final List<Map<String, dynamic>> existingRecords = await db.query(
      'grades',
      where: 'student_id = ? AND exam_name = (SELECT title FROM exams WHERE id = ?)',
      whereArgs: [studentId, examId],
    );
    
    if (existingRecords.isNotEmpty) {
      // تحديث السجل الموجود
      await db.update(
        'grades',
        {'notes': comment, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [existingRecords.first['id']],
      );

      final gradeId = existingRecords.first['id'];
      if (gradeId != null) {
        await _enqueueSyncOutbox(
          tableName: 'grades',
          localId: gradeId.toString(),
          op: 'update',
          payload: {
            ...existingRecords.first,
            'notes': comment,
            'updated_at': DateTime.now().toIso8601String(),
          },
        );
      }
    } else {
      // إضافة سجل جديد إذا لم يكن موجوداً
      // TODO: الحصول على معلومات الامتحان لإنشاء سجل جديد
    }
  }

  Future<List<GradeModel>> getGradesByStudent(int studentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'grades',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'exam_date DESC',
    );
    return List.generate(maps.length, (i) => GradeModel.fromMap(maps[i]));
  }

  Future<int> updateGrade(GradeModel grade) async {
    final db = await database;
    final map = Map<String, dynamic>.from(grade.toMap());
    if (grade.status == null) {
      map.remove('status');
    }
    final result = await db.update(
      'grades',
      map,
      where: 'id = ?',
      whereArgs: [grade.id],
    );
    if ((grade.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'grades',
        localId: grade.id.toString(),
        op: 'update',
        payload: map,
      );
    }
    return result;
  }

  // دالة جديدة لتحديث الدرجة بناءً على الطالب والامتحان
  Future<int> updateGradeByStudentAndExam(int studentId, String examName, GradeModel grade) async {
    final db = await database;
    final map = Map<String, dynamic>.from(grade.toMap());
    if (grade.status == null) {
      map.remove('status');
    }
    final result = await db.update(
      'grades',
      map,
      where: 'student_id = ? AND exam_name = ?',
      whereArgs: [studentId, examName],
    );

    try {
      final rows = await db.query(
        'grades',
        where: 'student_id = ? AND exam_name = ?',
        whereArgs: [studentId, examName],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final id = rows.first['id'];
        if (id != null) {
          await _enqueueSyncOutbox(
            tableName: 'grades',
            localId: id.toString(),
            op: 'update',
            payload: map,
          );
        }
      }
    } catch (_) {
      // ignore
    }

    return result;
  }

  // New function to update grade with status
  Future<int> updateGradeWithStatus(int studentId, String examName, double score, double maxScore, DateTime examDate, String notes, String status) async {
    final db = await database;
    
    // إذا كانت الحالة "حاضر" والدرجة صفر، احتفظ بها كـ "حاضر"
    String finalStatus = status;
    if (status == 'حاضر' && score == 0.0) {
      finalStatus = 'حاضر'; // تأكد من بقاء الحالة "حاضر" حتى مع درجة صفر
    }
    
    final Map<String, dynamic> gradeData = {
      'student_id': studentId,
      'exam_name': examName,
      'score': score,
      'max_score': maxScore,
      'exam_date': examDate.toIso8601String().split('T')[0],
      'notes': notes,
      'status': finalStatus, // Use the corrected status
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      final result = await db.update(
        'grades',
        gradeData,
        where: 'student_id = ? AND exam_name = ?',
        whereArgs: [studentId, examName],
      );

      try {
        final rows = await db.query(
          'grades',
          where: 'student_id = ? AND exam_name = ?',
          whereArgs: [studentId, examName],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          final id = rows.first['id'];
          if (id != null) {
            await _enqueueSyncOutbox(
              tableName: 'grades',
              localId: id.toString(),
              op: 'update',
              payload: gradeData,
            );
          }
        }
      } catch (_) {
        // ignore
      }

      return result;
    } on DatabaseException catch (e) {
      if (e.toString().contains('no column named status')) {
        await _ensureGradesStatusColumn(db);
        final fallback = Map<String, dynamic>.from(gradeData)..remove('status');
        final result = await db.update(
          'grades',
          fallback,
          where: 'student_id = ? AND exam_name = ?',
          whereArgs: [studentId, examName],
        );

        try {
          final rows = await db.query(
            'grades',
            where: 'student_id = ? AND exam_name = ?',
            whereArgs: [studentId, examName],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final id = rows.first['id'];
            if (id != null) {
              await _enqueueSyncOutbox(
                tableName: 'grades',
                localId: id.toString(),
                op: 'update',
                payload: fallback,
              );
            }
          }
        } catch (_) {
          // ignore
        }

        return result;
      }
      rethrow;
    }
  }

  // New function to insert grade with status
  Future<int> insertGradeWithStatus(int studentId, String examName, double score, double maxScore, DateTime examDate, String notes, String status) async {
    final db = await database;
    
    // إذا كانت الحالة "حاضر" والدرجة صفر، احتفظ بها كـ "حاضر"
    String finalStatus = status;
    if (status == 'حاضر' && score == 0.0) {
      finalStatus = 'حاضر'; // تأكد من بقاء الحالة "حاضر" حتى مع درجة صفر
    }
    
    final Map<String, dynamic> gradeData = {
      'student_id': studentId,
      'exam_name': examName,
      'score': score,
      'max_score': maxScore,
      'exam_date': examDate.toIso8601String().split('T')[0],
      'notes': notes,
      'status': finalStatus, // Use the corrected status
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };

    try {
      final id = await db.insert('grades', gradeData);
      await _enqueueSyncOutbox(
        tableName: 'grades',
        localId: id.toString(),
        op: 'insert',
        payload: {
          ...gradeData,
          'id': id,
        },
      );
      return id;
    } on DatabaseException catch (e) {
      if (e.toString().contains('no column named status')) {
        await _ensureGradesStatusColumn(db);
        final fallback = Map<String, dynamic>.from(gradeData)..remove('status');
        final id = await db.insert('grades', fallback);
        await _enqueueSyncOutbox(
          tableName: 'grades',
          localId: id.toString(),
          op: 'insert',
          payload: {
            ...fallback,
            'id': id,
          },
        );
        return id;
      }
      rethrow;
    }
  }

  Future<int> deleteGrade(int id) async {
    final db = await database;
    final result = await db.delete(
      'grades',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'grades',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  // إحصائيات
  Future<double> getStudentAverage(int studentId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT AVG(
        CASE
          WHEN max_score IS NULL OR max_score <= 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'غائب') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'غياب') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'absent') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'غائب') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'غياب') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'absent') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'غش') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'cheat') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'غش') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'cheat') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'مفقودة') > 0 THEN 0
          WHEN instr(lower(COALESCE(status, '')), 'missing') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'مفقودة') > 0 THEN 0
          WHEN instr(lower(COALESCE(notes, '')), 'missing') > 0 THEN 0
          ELSE (score / max_score) * 100
        END
      ) as average
      FROM grades
      WHERE student_id = ?
    ''', [studentId]);
    
    if (result.isNotEmpty && result.first['average'] != null) {
      return result.first['average'] as double;
    }
    return 0.0;
  }

  Future<Map<String, int>> getAttendanceStats(int studentId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT status, COUNT(*) as count
      FROM attendance
      WHERE student_id = ?
      GROUP BY status
    ''', [studentId]);
    
    Map<String, int> stats = {
      'present': 0,
      'absent': 0,
      'late': 0,
      'expelled': 0,
      'excused': 0,
    };

    for (var row in result) {
      int status = row['status'] as int;
      int count = row['count'] as int;
      
      switch (status) {
        case 0:
          stats['present'] = count;
          break;
        case 1:
          stats['absent'] = count;
          break;
        case 2:
          stats['late'] = count;
          break;
        case 3:
          stats['expelled'] = count;
          break;
        case 4:
          stats['excused'] = count;
          break;
      }
    }

    return stats;
  }

  // إعدادات
  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _enqueueSyncOutbox(
      tableName: 'settings',
      localId: key,
      op: 'upsert',
      payload: {'key': key, 'value': value},
    );
  }

  Future<Map<String, String>> getAllCourseDueDates() async {
    final db = await database;
    final rows = await db.query(
      'course_due_dates',
      columns: ['class_id', 'course_id', 'due_date'],
    );

    final map = <String, String>{};
    for (final r in rows) {
      final classId = r['class_id']?.toString() ?? '';
      final courseId = r['course_id']?.toString() ?? '';
      final dueDate = r['due_date']?.toString() ?? '';
      if (classId.isEmpty || courseId.isEmpty || dueDate.isEmpty) continue;
      map['$classId|$courseId'] = dueDate;
    }
    return map;
  }

  Future<int> getTotalInstallmentsAmount({
    String? location,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (location != null && location.isNotEmpty) {
      where.add('COALESCE(students.location, classes.subject) = ?');
      args.add(location);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(installments.amount), 0) AS total
      FROM installments
      INNER JOIN students ON students.id = installments.student_id
      LEFT JOIN classes ON classes.id = students.class_id
      $whereSql
      ''',
      args,
    );

    final total = rows.isNotEmpty ? rows.first['total'] : 0;
    return int.tryParse(total?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, dynamic>>> getMonthlyInstallmentsTotals({
    String? location,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (location != null && location.isNotEmpty) {
      where.add('COALESCE(students.location, classes.subject) = ?');
      args.add(location);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return await db.rawQuery(
      '''
      SELECT
        substr(installments.date, 1, 10) AS month,
        COALESCE(SUM(installments.amount), 0) AS total
      FROM installments
      INNER JOIN students ON students.id = installments.student_id
      LEFT JOIN classes ON classes.id = students.class_id
      $whereSql
      GROUP BY substr(installments.date, 1, 10)
      ORDER BY month ASC
      ''',
      args,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (maps.isNotEmpty) {
      return maps.first['value'] as String;
    }
    return null;
  }

  // عمليات المحاضرات
  Future<int> insertLecture(LectureModel lecture) async {
    final db = await database;
    final id = await db.insert('lectures', lecture.toMap());
    print('✅ Lecture inserted: ${lecture.title} with ID: $id');
    await _enqueueSyncOutbox(
      tableName: 'lectures',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...lecture.toMap(),
        'id': id,
      },
    );
    return id;
  }

  Future<List<LectureModel>> getLecturesByClass(int classId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'lectures',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'date ASC',
    );
    print('📚 Retrieved ${maps.length} lectures for class $classId');
    return List.generate(maps.length, (i) => LectureModel.fromMap(maps[i]));
  }

  Future<int> updateLecture(LectureModel lecture) async {
    final db = await database;
    final result = await db.update(
      'lectures',
      lecture.toMap(),
      where: 'id = ?',
      whereArgs: [lecture.id],
    );
    if ((lecture.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'lectures',
        localId: lecture.id.toString(),
        op: 'update',
        payload: lecture.toMap(),
      );
    }
    return result;
  }

  Future<int> deleteLecture(int id) async {
    final db = await database;
    final result = await db.delete(
      'lectures',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'lectures',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  // عمليات الامتحانات
  Future<int> insertExam(ExamModel exam) async {
    final db = await database;
    final examMap = exam.toMap();
    print('📝 Inserting exam: ${exam.title} for class_id: ${exam.classId}');
    print('📊 Exam data: $examMap');
    final id = await db.insert('exams', examMap);
    print('✅ Exam inserted: ${exam.title} with ID: $id');
    
    // التحقق من الحفظ
    final saved = await db.query('exams', where: 'id = ?', whereArgs: [id]);
    print('🔍 Verification - Exam saved: $saved');

    await _enqueueSyncOutbox(
      tableName: 'exams',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...examMap,
        'id': id,
      },
    );

    return id;
  }

  Future<List<ExamModel>> getExamsByClass(int classId) async {
    final db = await database;
    
    // فحص جميع الامتحانات أولاً
    final allExams = await db.query('exams');
    print('📊 Total exams in database: ${allExams.length}');
    if (allExams.isNotEmpty) {
      print('📋 All exams class_ids: ${allExams.map((e) => e['class_id']).toList()}');
    }
    
    // الآن البحث عن امتحانات الفصل المحدد
    final List<Map<String, dynamic>> maps = await db.query(
      'exams',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'date DESC',
    );
    print('📚 Retrieved ${maps.length} exams for class $classId');
    if (maps.isEmpty && allExams.isNotEmpty) {
      print('⚠️ WARNING: Exams exist but none match class_id: $classId');
    }
    return List.generate(maps.length, (i) => ExamModel.fromMap(maps[i]));
  }

  Future<List<ExamModel>> getAllExams() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exams',
      orderBy: 'date DESC',
    );
    return List.generate(maps.length, (i) => ExamModel.fromMap(maps[i]));
  }

  Future<ExamModel?> getExam(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'exams',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return ExamModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateExam(ExamModel exam) async {
    final db = await database;
    final result = await db.update(
      'exams',
      exam.toMap(),
      where: 'id = ?',
      whereArgs: [exam.id],
    );
    if ((exam.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'exams',
        localId: exam.id.toString(),
        op: 'update',
        payload: exam.toMap(),
      );
    }
    return result;
  }

  Future<int> deleteExam(int id) async {
    final db = await database;
    final result = await db.transaction((txn) async {
      ExamModel? exam;
      try {
        final maps = await txn.query(
          'exams',
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        );
        if (maps.isNotEmpty) {
          exam = ExamModel.fromMap(maps.first);
        }
      } catch (_) {
        exam = null;
      }

      // Delete grades tied to this exam.
      // exam_name is inconsistent: sometimes exam id stored as string, sometimes exam title.
      if (exam != null) {
        final dateKey = exam!.date.toIso8601String().split('T')[0];
        await txn.delete(
          'grades',
          where: "exam_name = ? OR (exam_name = ? AND exam_date = ?)",
          whereArgs: [id.toString(), exam!.title, dateKey],
        );
      } else {
        // Best-effort cleanup when exam row can't be read.
        await txn.delete(
          'grades',
          where: 'exam_name = ?',
          whereArgs: [id.toString()],
        );
      }

      return await txn.delete(
        'exams',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _enqueueSyncOutbox(
      tableName: 'exams',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  Future<List<ExamModel>> getExamsByStudent(int studentId) async {
    final db = await database;
    
    // جلب الفصل الخاص بالطالب
    final studentMaps = await db.query(
      'students',
      where: 'id = ?',
      whereArgs: [studentId],
    );
    
    if (studentMaps.isEmpty) {
      return [];
    }
    
    final classId = studentMaps.first['class_id'];
    
    // جلب امتحانات الفصل
    final List<Map<String, dynamic>> maps = await db.query(
      'exams',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'date DESC',
    );
    
    return List.generate(maps.length, (i) {
      return ExamModel.fromMap(maps[i]);
    });
  }

  // عمليات الملاحظات
  Future<int> insertNote(NoteModel note) async {
    final db = await database;
    final noteMap = note.toMap();
    print('📝 Inserting note for ${note.itemType}_${note.itemId}');
    print('📊 Note data: $noteMap');
    final id = await db.insert('notes', noteMap);
    print('✅ Note inserted with ID: $id');

    // مزامنة مع السحابة
    await _enqueueSyncOutbox(
      tableName: 'notes',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...noteMap,
        'id': id,
      },
    );

    return id;
  }

  Future<List<NoteModel>> getNotesByClass(int classId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'updated_at DESC',
    );
    print('📚 Retrieved ${maps.length} notes for class $classId');
    return List.generate(maps.length, (i) => NoteModel.fromMap(maps[i]));
  }

  Future<NoteModel?> getNote(String itemType, int itemId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notes',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: [itemType, itemId],
    );
    if (maps.isNotEmpty) {
      return NoteModel.fromMap(maps.first);
    }
    return null;
  }

  Future<int> updateNote(NoteModel note) async {
    final db = await database;
    final result = await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
    if ((note.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'notes',
        localId: note.id.toString(),
        op: 'update',
        payload: note.toMap(),
      );
    }
    return result;
  }

  Future<int> deleteNote(int id) async {
    final db = await database;
    final result = await db.delete(
      'notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'notes',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  Future<int> deleteNotesByItem(String itemType, int itemId) async {
    final db = await database;
    return await db.delete(
      'notes',
      where: 'item_type = ? AND item_id = ?',
      whereArgs: [itemType, itemId],
    );
  }

  // عمليات ملاحظات الطلاب
  Future<int> insertStudentNote(StudentNoteModel note) async {
    final db = await database;
    final noteMap = note.toMap();
    print('📝 Inserting student note for student ${note.studentId}');
    final id = await db.insert('student_notes', noteMap);
    print('✅ Student note inserted with ID: $id');

    await _enqueueSyncOutbox(
      tableName: 'student_notes',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...noteMap,
        'id': id,
      },
    );

    return id;
  }

  Future<List<StudentNoteModel>> getStudentNotesByClass(int classId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'student_notes',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'date DESC, updated_at DESC',
    );
    print('📚 Retrieved ${maps.length} student notes for class $classId');
    return List.generate(maps.length, (i) => StudentNoteModel.fromMap(maps[i]));
  }

  Future<List<StudentNoteModel>> getStudentNotesByStudent(int studentId) async {
    final db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(
      'student_notes',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC, updated_at DESC',
    );
    return List.generate(maps.length, (i) => StudentNoteModel.fromMap(maps[i]));
  }

  Future<int> updateStudentNote(StudentNoteModel note) async {
    final db = await database;
    final result = await db.update(
      'student_notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
    if ((note.id ?? 0) > 0) {
      await _enqueueSyncOutbox(
        tableName: 'student_notes',
        localId: note.id.toString(),
        op: 'update',
        payload: note.toMap(),
      );
    }
    return result;
  }

  Future<int> deleteStudentNote(int id) async {
    final db = await database;
    final result = await db.delete(
      'student_notes',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'student_notes',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  // إغلاق قاعدة البيانات
  Future<void> close() async {
    final db = await database;
    await db.close();
  }

  // ============================================
  // Tuition plans (class-centric finance revamp)
  // ============================================

  Future<List<Map<String, dynamic>>> getClassTuitionPlans(int classId) async {
    final db = await database;
    return await db.query(
      'class_tuition_plans',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'id ASC',
    );
  }

  Future<void> deleteTuitionPlanInstallment(int planId, int installmentNo) async {
    final db = await database;
    int? installmentId;
    try {
      final rows = await db.query(
        'tuition_plan_installments',
        columns: ['id'],
        where: 'plan_id = ? AND installment_no = ?',
        whereArgs: [planId, installmentNo],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final v = rows.first['id'];
        installmentId = (v is int) ? v : int.tryParse(v?.toString() ?? '');
      }
    } catch (_) {}

    await db.delete(
      'tuition_plan_installments',
      where: 'plan_id = ? AND installment_no = ?',
      whereArgs: [planId, installmentNo],
    );
    if (installmentId != null) {
      await _enqueueSyncOutbox(
        tableName: 'tuition_plan_installments',
        localId: installmentId.toString(),
        op: 'delete',
      );
    }
  }

  Future<void> deleteTuitionPlanInstallmentDeep({
    required int planId,
    required int installmentNo,
  }) async {
    final db = await database;
    final deletedPaymentIds = <int>[];
    final deletedOverrideLocalIds = <String>[];

    int? installmentId;
    try {
      final rows = await db.query(
        'tuition_plan_installments',
        columns: ['id'],
        where: 'plan_id = ? AND installment_no = ?',
        whereArgs: [planId, installmentNo],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final v = rows.first['id'];
        installmentId = (v is int) ? v : int.tryParse(v?.toString() ?? '');
      }
    } catch (_) {}

    await db.transaction((txn) async {
      try {
        final paymentRows = await txn.query(
          'tuition_payments',
          columns: ['id'],
          where: 'plan_id = ? AND installment_no = ?',
          whereArgs: [planId, installmentNo],
        );
        for (final r in paymentRows) {
          final v = r['id'];
          final id = (v is int) ? v : int.tryParse(v?.toString() ?? '') ?? 0;
          if (id > 0) deletedPaymentIds.add(id);
        }
      } catch (_) {}

      try {
        final overrideRows = await txn.query(
          'student_tuition_overrides',
          columns: ['student_id'],
          where: 'plan_id = ? AND installment_no = ?',
          whereArgs: [planId, installmentNo],
        );
        for (final r in overrideRows) {
          final v = r['student_id'];
          final sid = (v is int) ? v : int.tryParse(v?.toString() ?? '') ?? 0;
          if (sid > 0) deletedOverrideLocalIds.add('${sid}_${planId}_$installmentNo');
        }
      } catch (_) {}

      await txn.delete(
        'tuition_payments',
        where: 'plan_id = ? AND installment_no = ?',
        whereArgs: [planId, installmentNo],
      );

      await txn.delete(
        'student_tuition_overrides',
        where: 'plan_id = ? AND installment_no = ?',
        whereArgs: [planId, installmentNo],
      );

      await txn.delete(
        'tuition_plan_installments',
        where: 'plan_id = ? AND installment_no = ?',
        whereArgs: [planId, installmentNo],
      );
    });

    for (final pid in deletedPaymentIds) {
      await _enqueueSyncOutbox(
        tableName: 'tuition_payments',
        localId: pid.toString(),
        op: 'delete',
      );
    }

    for (final lid in deletedOverrideLocalIds) {
      await _enqueueSyncOutbox(
        tableName: 'student_tuition_overrides',
        localId: lid,
        op: 'delete',
      );
    }

    if (installmentId != null) {
      await _enqueueSyncOutbox(
        tableName: 'tuition_plan_installments',
        localId: installmentId.toString(),
        op: 'delete',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getAllTuitionPaymentsWithDetails() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        tp.*,
        tp.paid_amount AS amount,
        tp.payment_date AS date,
        s.name AS student_name,
        s.class_id,
        c.name AS class_name,
        cp.name AS plan_name
      FROM tuition_payments tp
      JOIN students s ON tp.student_id = s.id
      JOIN classes c ON s.class_id = c.id
      JOIN class_tuition_plans cp ON tp.plan_id = cp.id
      ORDER BY tp.payment_date DESC, tp.id DESC
    ''');
  }

  Future<int> getTotalTuitionPaymentsAmount({
    int? classId,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (classId != null) {
      where.add('s.class_id = ?');
      args.add(classId);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(tp.paid_amount), 0) AS total
      FROM tuition_payments tp
      JOIN students s ON s.id = tp.student_id
      $whereSql
      ''',
      args,
    );
    final total = rows.isNotEmpty ? rows.first['total'] : 0;
    if (total is int) return total;
    if (total is num) return total.toInt();
    return int.tryParse(total?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, dynamic>>> getMonthlyTuitionPaymentsTotals({
    int? classId,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (classId != null) {
      where.add('s.class_id = ?');
      args.add(classId);
    }

    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    return await db.rawQuery(
      '''
      SELECT
        substr(tp.payment_date, 1, 7) AS month,
        COALESCE(SUM(tp.paid_amount), 0) AS total
      FROM tuition_payments tp
      JOIN students s ON s.id = tp.student_id
      $whereSql
      GROUP BY substr(tp.payment_date, 1, 7)
      ORDER BY month ASC
      ''',
      args,
    );
  }

  Future<void> updateTuitionPaymentAmount(int paymentId, int newAmount, String newDate) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    await db.update(
      'tuition_payments',
      {
        'paid_amount': newAmount,
        'payment_date': newDate,
        'updated_at': nowIso,
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    await _enqueueSyncOutbox(
      tableName: 'tuition_payments',
      localId: paymentId.toString(),
      op: 'update',
      payload: {
        'id': paymentId,
        'paid_amount': newAmount,
        'payment_date': newDate,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> deleteTuitionPayment(int paymentId) async {
    final db = await database;
    await db.delete(
      'tuition_payments',
      where: 'id = ?',
      whereArgs: [paymentId],
    );
    await _enqueueSyncOutbox(
      tableName: 'tuition_payments',
      localId: paymentId.toString(),
      op: 'delete',
    );
  }

  Future<List<Map<String, dynamic>>> getTuitionPlanInstallments(int planId) async {
    final db = await database;
    return await db.query(
      'tuition_plan_installments',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'installment_no ASC',
    );
  }

  Future<int> createClassTuitionPlan({
    required int classId,
    required String name,
    required int totalAmount,
    required List<Map<String, dynamic>> installments,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    int planId = 0;
    final createdInstallments = <Map<String, dynamic>>[];

    planId = await db.transaction((txn) async {
      final pid = await txn.insert('class_tuition_plans', {
        'class_id': classId,
        'name': name,
        'total_amount': totalAmount,
        'installments_count': installments.length,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      for (final inst in installments) {
        final no = (inst['installment_no'] as int?) ?? 0;
        final amount = (inst['amount'] as int?) ?? 0;
        final dueDate = (inst['due_date'] ?? '').toString();
        final installmentId = await txn.insert('tuition_plan_installments', {
          'plan_id': pid,
          'installment_no': no,
          'amount': amount,
          'due_date': dueDate,
          'created_at': nowIso,
          'updated_at': nowIso,
        });

        createdInstallments.add({
          'id': installmentId,
          'plan_id': pid,
          'installment_no': no,
          'amount': amount,
          'due_date': dueDate,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }

      return pid;
    });

    await _enqueueSyncOutbox(
      tableName: 'class_tuition_plans',
      localId: planId.toString(),
      op: 'insert',
      payload: {
        'id': planId,
        'class_id': classId,
        'name': name,
        'total_amount': totalAmount,
        'installments_count': installments.length,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );

    for (final inst in createdInstallments) {
      final id = (inst['id'] is int) ? inst['id'] as int : int.tryParse(inst['id']?.toString() ?? '') ?? 0;
      if (id <= 0) continue;
      await _enqueueSyncOutbox(
        tableName: 'tuition_plan_installments',
        localId: id.toString(),
        op: 'insert',
        payload: inst,
      );
    }

    return planId;
  }

  Future<Map<int, Map<int, Map<String, dynamic>>>> getStudentTuitionOverridesMap({
    required int planId,
    required List<int> studentIds,
  }) async {
    if (studentIds.isEmpty) return {};
    final db = await database;
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final rows = await db.query(
      'student_tuition_overrides',
      where: 'plan_id = ? AND student_id IN ($placeholders)',
      whereArgs: [planId, ...studentIds],
      orderBy: 'student_id ASC, installment_no ASC',
    );

    final result = <int, Map<int, Map<String, dynamic>>>{};
    for (final r in rows) {
      final sid = r['student_id'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;

      final ino = r['installment_no'];
      final noInt = (ino is int) ? ino : int.tryParse(ino?.toString() ?? '');
      if (noInt == null) continue;

      (result[sidInt] ??= <int, Map<String, dynamic>>{})[noInt] = r;
    }
    return result;
  }

  Future<void> upsertStudentTuitionOverride({
    required int studentId,
    required int planId,
    required int installmentNo,
    required int amount,
    required String dueDate,
    String? reason,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();

    await db.insert(
      'student_tuition_overrides',
      {
        'student_id': studentId,
        'plan_id': planId,
        'installment_no': installmentNo,
        'amount': amount,
        'due_date': dueDate,
        'reason': reason,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _enqueueSyncOutbox(
      tableName: 'student_tuition_overrides',
      localId: '${studentId}_${planId}_$installmentNo',
      op: 'upsert',
      payload: {
        'student_id': studentId,
        'plan_id': planId,
        'installment_no': installmentNo,
        'amount': amount,
        'due_date': dueDate,
        'reason': reason,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> deleteStudentTuitionOverride({
    required int studentId,
    required int planId,
    required int installmentNo,
  }) async {
    final db = await database;
    await db.delete(
      'student_tuition_overrides',
      where: 'student_id = ? AND plan_id = ? AND installment_no = ?',
      whereArgs: [studentId, planId, installmentNo],
    );
    await _enqueueSyncOutbox(
      tableName: 'student_tuition_overrides',
      localId: '${studentId}_${planId}_$installmentNo',
      op: 'delete',
    );
  }

  Future<int> getNextTuitionReceiptNo() async {
    final db = await database;
    return await db.transaction((txn) async {
      final rows = await txn.query(
        'settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['tuition_receipt_seq'],
        limit: 1,
      );

      final current = rows.isNotEmpty
          ? int.tryParse(rows.first['value']?.toString() ?? '') ?? 0
          : 0;
      final next = current + 1;

      await txn.insert(
        'settings',
        {'key': 'tuition_receipt_seq', 'value': next.toString()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return next;
    });
  }

  Future<Map<String, dynamic>?> getEffectiveTuitionInstallment({
    required int studentId,
    required int planId,
    required int installmentNo,
  }) async {
    final db = await database;

    final overrideRows = await db.query(
      'student_tuition_overrides',
      where: 'student_id = ? AND plan_id = ? AND installment_no = ?',
      whereArgs: [studentId, planId, installmentNo],
      limit: 1,
    );
    final baseRows = await db.query(
      'tuition_plan_installments',
      where: 'plan_id = ? AND installment_no = ?',
      whereArgs: [planId, installmentNo],
      limit: 1,
    );
    final base = baseRows.isNotEmpty ? Map<String, dynamic>.from(baseRows.first) : <String, dynamic>{};

    if (overrideRows.isEmpty) {
      return base.isEmpty ? null : base;
    }

    final o = Map<String, dynamic>.from(overrideRows.first);
    final merged = <String, dynamic>{...base, ...o};

    final oAmount = o['amount'];
    final oa = (oAmount is int) ? oAmount : int.tryParse(oAmount?.toString() ?? '');
    if (oa == null || oa <= 0) {
      merged['amount'] = base['amount'];
    }

    final oDue = (o['due_date']?.toString() ?? '').trim();
    if (oDue.isEmpty) {
      merged['due_date'] = base['due_date'];
    }

    return merged;
  }

  Future<int> getTotalPaidForTuitionInstallment({
    required int studentId,
    required int planId,
    required int installmentNo,
  }) async {
    final db = await database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(paid_amount), 0) AS total_paid '
      'FROM tuition_payments '
      'WHERE student_id = ? AND plan_id = ? AND installment_no = ?',
      [studentId, planId, installmentNo],
    );
    final total = rows.isNotEmpty ? rows.first['total_paid'] : 0;
    if (total is int) return total;
    if (total is num) return total.toInt();
    return int.tryParse(total?.toString() ?? '') ?? 0;
  }

  Future<List<Map<String, dynamic>>> getTuitionPaymentsForStudentPlan({
    required int studentId,
    required int planId,
  }) async {
    final db = await database;
    return await db.query(
      'tuition_payments',
      where: 'student_id = ? AND plan_id = ?',
      whereArgs: [studentId, planId],
      orderBy: 'payment_date ASC, id ASC',
    );
  }

  Future<List<Map<String, dynamic>>> getTuitionPaymentsForStudentsPlan({
    required int planId,
    required List<int> studentIds,
  }) async {
    final db = await database;
    if (studentIds.isEmpty) return [];
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    return await db.query(
      'tuition_payments',
      where: 'plan_id = ? AND student_id IN ($placeholders)',
      whereArgs: [planId, ...studentIds],
      orderBy: 'student_id ASC, payment_date ASC, id ASC',
    );
  }

  Future<int> insertTuitionPayment({
    required int receiptNo,
    required int studentId,
    required int planId,
    required int installmentNo,
    required int dueAmount,
    required int paidAmount,
    required String paymentDate,
    String? notes,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final id = await db.insert('tuition_payments', {
      'receipt_no': receiptNo,
      'student_id': studentId,
      'plan_id': planId,
      'installment_no': installmentNo,
      'due_amount': dueAmount,
      'paid_amount': paidAmount,
      'payment_date': paymentDate,
      'notes': notes,
      'created_at': nowIso,
      'updated_at': nowIso,
    });

    await _enqueueSyncOutbox(
      tableName: 'tuition_payments',
      localId: id.toString(),
      op: 'insert',
      payload: {
        'id': id,
        'receipt_no': receiptNo,
        'student_id': studentId,
        'plan_id': planId,
        'installment_no': installmentNo,
        'due_amount': dueAmount,
        'paid_amount': paidAmount,
        'payment_date': paymentDate,
        'notes': notes,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );

    return id;
  }

  Future<void> deleteClassTuitionPlan(int planId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('tuition_payments', where: 'plan_id = ?', whereArgs: [planId]);
      await txn.delete('student_tuition_overrides', where: 'plan_id = ?', whereArgs: [planId]);
      await txn.delete('tuition_plan_installments', where: 'plan_id = ?', whereArgs: [planId]);
      await txn.delete('class_tuition_plans', where: 'id = ?', whereArgs: [planId]);
    });

    await _enqueueSyncOutbox(
      tableName: 'class_tuition_plans',
      localId: planId.toString(),
      op: 'delete',
    );
  }

  Future<Map<int, int>> getTotalPaidByStudentIdsForTuitionPlan({
    required List<int> studentIds,
    required int planId,
    int? installmentNo,
  }) async {
    if (studentIds.isEmpty) return {};
    final db = await database;
    final placeholders = core.List.filled(studentIds.length, '?').join(',');

    final args = <Object?>[planId, ...studentIds];
    var sql =
        'SELECT student_id, COALESCE(SUM(paid_amount), 0) AS total_paid '
        'FROM tuition_payments '
        'WHERE plan_id = ? AND student_id IN ($placeholders)';
    if (installmentNo != null) {
      sql += ' AND installment_no = ?';
      args.add(installmentNo);
    }
    sql += ' GROUP BY student_id';

    final rows = await db.rawQuery(sql, args);
    final result = <int, int>{};
    for (final r in rows) {
      final sid = r['student_id'];
      final total = r['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;
      final totalInt = (total is int)
          ? total
          : (total is num)
              ? total.toInt()
              : int.tryParse(total?.toString() ?? '') ?? 0;
      result[sidInt] = totalInt;
    }
    return result;
  }

  Future<Map<int, int>> getTotalPaidByStudentIdsForTuitionPlans({
    required List<int> studentIds,
    required List<int> planIds,
    int? installmentNo,
  }) async {
    if (studentIds.isEmpty || planIds.isEmpty) return {};
    final db = await database;

    final studentPlaceholders = core.List.filled(studentIds.length, '?').join(',');
    final planPlaceholders = core.List.filled(planIds.length, '?').join(',');

    final args = <Object?>[...planIds, ...studentIds];

    var sql =
        'SELECT student_id, COALESCE(SUM(paid_amount), 0) AS total_paid '
        'FROM tuition_payments '
        'WHERE plan_id IN ($planPlaceholders) AND student_id IN ($studentPlaceholders)';
    if (installmentNo != null) {
      sql += ' AND installment_no = ?';
      args.add(installmentNo);
    }
    sql += ' GROUP BY student_id';

    final rows = await db.rawQuery(sql, args);
    final result = <int, int>{};
    for (final r in rows) {
      final sid = r['student_id'];
      final total = r['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;
      final totalInt = (total is int)
          ? total
          : (total is num)
              ? total.toInt()
              : int.tryParse(total?.toString() ?? '') ?? 0;
      result[sidInt] = totalInt;
    }
    return result;
  }

  Future<Map<int, Map<int, Map<int, Map<String, dynamic>>>>> getStudentTuitionOverridesMapForPlans({
    required List<int> studentIds,
    required List<int> planIds,
  }) async {
    if (studentIds.isEmpty || planIds.isEmpty) return {};
    final db = await database;

    final studentPlaceholders = core.List.filled(studentIds.length, '?').join(',');
    final planPlaceholders = core.List.filled(planIds.length, '?').join(',');

    final rows = await db.rawQuery(
      'SELECT * FROM student_tuition_overrides '
      'WHERE plan_id IN ($planPlaceholders) AND student_id IN ($studentPlaceholders) '
      'ORDER BY plan_id ASC, student_id ASC, installment_no ASC',
      [...planIds, ...studentIds],
    );

    final result = <int, Map<int, Map<int, Map<String, dynamic>>>>{};
    for (final r in rows) {
      final pid = r['plan_id'];
      final sid = r['student_id'];
      final ino = r['installment_no'];

      final planId = (pid is int) ? pid : int.tryParse(pid?.toString() ?? '');
      final studentId = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      final installmentNo = (ino is int) ? ino : int.tryParse(ino?.toString() ?? '');
      if (planId == null || studentId == null || installmentNo == null) continue;

      (result[planId] ??= <int, Map<int, Map<String, dynamic>>>{});
      (result[planId]![studentId] ??= <int, Map<String, dynamic>>{});
      result[planId]![studentId]![installmentNo] = Map<String, dynamic>.from(r);
    }
    return result;
  }

  // ============================================
  // دوال جدول الكورسات (courses)
  // ============================================

  Future<int> insertCourse(Map<String, dynamic> course) async {
    final db = await database;
    course['created_at'] = DateTime.now().toIso8601String();
    course['updated_at'] = DateTime.now().toIso8601String();
    
    final id = await db.insert('courses', course);
    print('✅ تم إضافة كورس جديد برقم: $id');
    final courseId = (course['id'] ?? '').toString();
    if (courseId.isNotEmpty) {
      await _enqueueSyncOutbox(
        tableName: 'courses',
        localId: courseId,
        op: 'upsert',
        payload: course,
      );
    }
    return id;
  }

  Future<List<Map<String, dynamic>>> getCourses() async {
    final db = await database;
    return await db.query('courses', orderBy: 'name ASC');
  }

  Future<List<Map<String, dynamic>>> getCoursesByLocation(String location) async {
    final db = await database;
    return await db.query(
      'courses',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'name ASC',
    );
  }

  Future<int> updateCourse(Map<String, dynamic> course) async {
    final db = await database;
    course['updated_at'] = DateTime.now().toIso8601String();
    
    final result = await db.update(
      'courses',
      course,
      where: 'id = ?',
      whereArgs: [course['id']],
    );
    final courseId = (course['id'] ?? '').toString();
    if (courseId.isNotEmpty) {
      await _enqueueSyncOutbox(
        tableName: 'courses',
        localId: courseId,
        op: 'upsert',
        payload: course,
      );
    }
    return result;
  }

  Future<int> deleteCourse(String id) async {
    final db = await database;

    final result = await db.transaction((txn) async {
      // حذف العلاقات أولاً لضمان عدم وجود مراجع (حتى لو لم تعمل cascades)
      await txn.delete(
        'class_course_prices',
        where: 'course_id = ?',
        whereArgs: [id],
      );

      await txn.delete(
        'installments',
        where: 'course_id = ?',
        whereArgs: [id],
      );

      return await txn.delete(
        'courses',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    await _enqueueSyncOutbox(
      tableName: 'courses',
      localId: id,
      op: 'delete',
    );
    return result;
  }

  // ============================================
  // دوال جدول أسعار الكورسات للفصول (class_course_prices)
  // ============================================

  Future<int> insertClassCoursePrice(Map<String, dynamic> price) async {
    final db = await database;
    price['created_at'] = DateTime.now().toIso8601String();
    price['updated_at'] = DateTime.now().toIso8601String();
    
    final id = await db.insert('class_course_prices', price);
    print('✅ تم إضافة سعر كورس جديد للفصل برقم: $id');
    await _enqueueSyncOutbox(
      tableName: 'class_course_prices',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...price,
        'id': id,
      },
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> getClassCoursePrices(int classId) async {
    final db = await database;
    return await db.query(
      'class_course_prices',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'course_id ASC',
    );
  }

  Future<Map<String, dynamic>?> getClassCoursePrice(int classId, int courseId) async {
    final db = await database;
    final core.List<Map<String, dynamic>> result = await db.query(
      'class_course_prices',
      where: 'class_id = ? AND course_id = ?',
      whereArgs: [classId, courseId],
    );
    
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }

  Future<int> updateClassCoursePrice(Map<String, dynamic> price) async {
    final db = await database;
    price['updated_at'] = DateTime.now().toIso8601String();
    
    final result = await db.update(
      'class_course_prices',
      price,
      where: 'id = ?',
      whereArgs: [price['id']],
    );
    final pid = price['id'];
    if (pid != null) {
      await _enqueueSyncOutbox(
        tableName: 'class_course_prices',
        localId: pid.toString(),
        op: 'update',
        payload: price,
      );
    }
    return result;
  }

  Future<int> deleteClassCoursePrice(int id) async {
    final db = await database;
    final result = await db.delete(
      'class_course_prices',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'class_course_prices',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  // ============================================
  // دوال جدول الأقساط (installments)
  // ============================================

  Future<int> insertInstallment(Map<String, dynamic> installment) async {
    final db = await database;
    installment['created_at'] = DateTime.now().toIso8601String();
    installment['updated_at'] = DateTime.now().toIso8601String();
    
    final id = await db.insert('installments', installment);
    print('✅ تم إضافة قسط جديد برقم: $id');
    await _enqueueSyncOutbox(
      tableName: 'installments',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...installment,
        'id': id,
      },
    );
    return id;
  }

  Future<List<Map<String, dynamic>>> getInstallmentsByStudent(int studentId) async {
    final db = await database;
    return await db.query(
      'installments',
      where: 'student_id = ?',
      whereArgs: [studentId],
      orderBy: 'date DESC, created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getInstallmentsByCourse(int courseId) async {
    final db = await database;
    return await db.query(
      'installments',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'date DESC, created_at DESC',
    );
  }

  Future<int> getTotalPaidByStudentAndCourse({
    required int studentId,
    required String courseId,
  }) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS total_paid '
      'FROM installments '
      'WHERE student_id = ? AND course_id = ?',
      [studentId, courseId],
    );

    final total = result.isNotEmpty ? result.first['total_paid'] : 0;
    if (total is int) return total;
    if (total is num) return total.toInt();
    return int.tryParse(total?.toString() ?? '') ?? 0;
  }

  Future<Map<int, int>> getTotalPaidByStudentIds(List<int> studentIds) async {
    if (studentIds.isEmpty) return {};

    final db = await database;
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT student_id, COALESCE(SUM(amount), 0) AS total_paid '
      'FROM installments '
      'WHERE student_id IN ($placeholders) '
      'GROUP BY student_id',
      studentIds,
    );

    final map = <int, int>{};
    for (final row in result) {
      final sid = row['student_id'];
      final total = row['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;

      int totalInt;
      if (total is int) {
        totalInt = total;
      } else if (total is num) {
        totalInt = total.toInt();
      } else {
        totalInt = int.tryParse(total?.toString() ?? '') ?? 0;
      }
      map[sidInt] = totalInt;
    }

    return map;
  }

  Future<Map<int, int>> getTotalPaidByStudentIdsForCourse({
    required List<int> studentIds,
    required String courseId,
  }) async {
    if (studentIds.isEmpty) return {};
    if (courseId.isEmpty) return {};

    final db = await database;
    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final args = <Object?>[...studentIds, courseId];
    final result = await db.rawQuery(
      'SELECT student_id, COALESCE(SUM(amount), 0) AS total_paid '
      'FROM installments '
      'WHERE student_id IN ($placeholders) AND course_id = ? '
      'GROUP BY student_id',
      args,
    );

    final map = <int, int>{};
    for (final row in result) {
      final sid = row['student_id'];
      final total = row['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;

      int totalInt;
      if (total is int) {
        totalInt = total;
      } else if (total is num) {
        totalInt = total.toInt();
      } else {
        totalInt = int.tryParse(total?.toString() ?? '') ?? 0;
      }
      map[sidInt] = totalInt;
    }

    return map;
  }

  Future<int> updateInstallment(Map<String, dynamic> installment) async {
    final db = await database;
    installment['updated_at'] = DateTime.now().toIso8601String();
    
    final result = await db.update(
      'installments',
      installment,
      where: 'id = ?',
      whereArgs: [installment['id']],
    );
    final iid = installment['id'];
    if (iid != null) {
      await _enqueueSyncOutbox(
        tableName: 'installments',
        localId: iid.toString(),
        op: 'update',
        payload: installment,
      );
    }
    return result;
  }

  Future<int> deleteInstallment(int id) async {
    final db = await database;
    final result = await db.delete(
      'installments',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'installments',
      localId: id.toString(),
      op: 'delete',
    );
    return result;
  }

  // دالة لجلب جميع الأقساط مع معلومات الطالب والكورس والفصل
  Future<List<Map<String, dynamic>>> getAllInstallmentsWithDetails({
    String? locationFilter,
    String? courseFilter,
    String? studentNameFilter,
    int? classIdFilter,
  }) async {
    final db = await database;
    
    String whereClause = '';
    core.List<dynamic> whereArgs = [];
    
    if (locationFilter != null && locationFilter.isNotEmpty) {
      whereClause += ' AND courses.location = ?';
      whereArgs.add(locationFilter);
    }
    
    if (courseFilter != null && courseFilter.isNotEmpty) {
      whereClause += ' AND courses.id = ?';
      whereArgs.add(courseFilter);
    }
    
    if (studentNameFilter != null && studentNameFilter.isNotEmpty) {
      whereClause += ' AND students.name LIKE ?';
      whereArgs.add('%$studentNameFilter%');
    }

    if (classIdFilter != null) {
      whereClause += ' AND students.class_id = ?';
      whereArgs.add(classIdFilter);
    }
    
    final result = await db.rawQuery('''
      SELECT 
        installments.id,
        installments.student_id,
        installments.course_id,
        installments.amount,
        installments.date,
        installments.notes,
        installments.created_at,
        installments.updated_at,
        students.name as student_name,
        students.class_id,
        classes.name as class_name,
        courses.name as course_name,
        courses.location as course_location
      FROM installments
      INNER JOIN students ON installments.student_id = students.id
      INNER JOIN classes ON students.class_id = classes.id
      INNER JOIN courses ON installments.course_id = courses.id
      WHERE 1=1 $whereClause
      ORDER BY installments.date DESC, installments.created_at DESC
    ''', whereArgs);
    
    return result;
  }

  Future<Map<int, int>> getTotalPaidByStudentIdsForLocation({
    required List<int> studentIds,
    required String location,
  }) async {
    if (studentIds.isEmpty) return <int, int>{};
    final db = await database;

    final placeholders = core.List.filled(studentIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT installments.student_id AS student_id,
             COALESCE(SUM(installments.amount), 0) AS total_paid
      FROM installments
      INNER JOIN courses ON courses.id = installments.course_id
      WHERE installments.student_id IN ($placeholders)
        AND courses.location = ?
      GROUP BY installments.student_id
      ''',
      [...studentIds, location],
    );

    final map = <int, int>{};
    for (final r in rows) {
      final sid = r['student_id'];
      final total = r['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;
      final totalInt = (total is int)
          ? total
          : (total is num)
              ? total.toInt()
              : int.tryParse(total?.toString() ?? '') ?? 0;
      map[sidInt] = totalInt;
    }
    return map;
  }

  // دالة لجلب المواقع المتاحة
  Future<List<String>> getAvailableLocations() async {
    final db = await database;
    final result = await db.rawQuery('SELECT DISTINCT location FROM courses ORDER BY location');
    return result.map((row) => row['location'] as String).toList();
  }

  // دالة لجلب الكورسات حسب الموقع
  Future<List<Map<String, dynamic>>> getCoursesByLocationForFilter(String location) async {
    final db = await database;
    return await db.query(
      'courses',
      where: 'location = ?',
      whereArgs: [location],
      orderBy: 'name ASC',
    );
  }

  // دالة للحصول على إحصائيات الأقساط
  Future<Map<String, dynamic>> getInstallmentsStatistics({
    String? locationFilter,
    String? courseFilter,
  }) async {
    final db = await database;
    
    String whereClause = '';
    core.List<dynamic> whereArgs = [];
    
    if (locationFilter != null && locationFilter.isNotEmpty) {
      whereClause += ' AND courses.location = ?';
      whereArgs.add(locationFilter);
    }
    
    if (courseFilter != null && courseFilter.isNotEmpty) {
      whereClause += ' AND courses.id = ?';
      whereArgs.add(courseFilter);
    }
    
    // جلب إحصائيات الأقساط
    final statsResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_payments,
        COALESCE(SUM(installments.amount), 0) as total_amount,
        COUNT(CASE WHEN courses.name LIKE '%الأول%' OR courses.name LIKE '%1%' THEN 1 END) as first_installment_count,
        COUNT(CASE WHEN courses.name LIKE '%الثاني%' OR courses.name LIKE '%2%' THEN 1 END) as second_installment_count
      FROM installments
      INNER JOIN courses ON installments.course_id = courses.id
      WHERE 1=1 $whereClause
    ''', whereArgs);
    
    final stats = statsResult.first;
    
    return {
      'total_payments': stats['total_payments'] ?? 0,
      'total_amount': stats['total_amount'] ?? 0,
      'first_installment_count': stats['first_installment_count'] ?? 0,
      'second_installment_count': stats['second_installment_count'] ?? 0,
    };
  }
  // دالة إنشاء الجداول المفقودة
  // ============================================

  Future<void> _createMissingTables(Database db, List<Map<String, dynamic>> existingTables) async {
    try {
      final tableNames = existingTables.map((table) => table['name'] as String).toSet();
      
      // إنشاء جدول الملاحظات إذا لم يكن موجوداً
      if (!tableNames.contains('notes')) {
        await db.execute('''
          CREATE TABLE notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            item_type TEXT NOT NULL,
            item_id INTEGER NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
          )
        ''');
        print('✅ Created notes table');
      }

      // إنشاء جدول الكورسات إذا لم يكن موجوداً
      if (!tableNames.contains('courses')) {
        await db.execute('''
          CREATE TABLE courses (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price INTEGER NOT NULL,
            location TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        print('✅ Created courses table');
      }

      // إنشاء جدول أسعار الكورسات للفصول إذا لم يكن موجوداً
      if (!tableNames.contains('class_course_prices')) {
        await db.execute('''
          CREATE TABLE class_course_prices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id TEXT NOT NULL,
            course_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            enabled INTEGER NOT NULL DEFAULT 1,
            paid INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
          )
        ''');
        print('✅ Created class_course_prices table');
      }

      // إنشاء جدول الأقساط إذا لم يكن موجوداً
      if (!tableNames.contains('installments')) {
        await db.execute('''
          CREATE TABLE installments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            course_id TEXT NOT NULL,
            amount INTEGER NOT NULL,
            date TEXT NOT NULL,
            notes TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
            FOREIGN KEY (course_id) REFERENCES courses (id) ON DELETE CASCADE
          )
        ''');
        print('✅ Created installments table');
      }

      // إنشاء جدول تواريخ آخر موعد للسداد إذا لم يكن موجوداً
      if (!tableNames.contains('course_due_dates')) {
        await db.execute('''
          CREATE TABLE course_due_dates (
            class_id TEXT NOT NULL,
            course_id TEXT NOT NULL,
            due_date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (class_id, course_id)
          )
        ''');
        print('✅ Created course_due_dates table');
      } else {
        // إصلاح قواعد البيانات القديمة التي تحتوي على الجدول بدون أعمدة مطلوبة
        try {
          final columns = await db.rawQuery("PRAGMA table_info('course_due_dates')");
          final existing = columns
              .map((c) => (c['name']?.toString() ?? '').trim())
              .where((c) => c.isNotEmpty)
              .toSet();

          if (!existing.contains('class_id') || !existing.contains('course_id') || !existing.contains('due_date')) {
            await db.execute('DROP TABLE IF EXISTS course_due_dates');
            await db.execute('''
              CREATE TABLE course_due_dates (
                class_id TEXT NOT NULL,
                course_id TEXT NOT NULL,
                due_date TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (class_id, course_id)
              )
            ''');
            print('✅ Recreated course_due_dates table (schema repaired)');
          }
        } catch (e) {
          print('❌ Error repairing course_due_dates schema: $e');
        }
      }

      // إنشاء جدول المستخدمين إذا لم يكن موجوداً
      if (!tableNames.contains('users')) {
        await db.execute('''
          CREATE TABLE users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            email TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        print('✅ Created users table');
      }

      // إنشاء جدول ملاحظات الطلاب إذا لم يكن موجوداً
      if (!tableNames.contains('student_notes')) {
        await db.execute('''
          CREATE TABLE student_notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            student_id INTEGER NOT NULL,
            class_id INTEGER NOT NULL,
            note TEXT NOT NULL,
            note_type TEXT NOT NULL,
            date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
          )
        ''');
        print('✅ Created student_notes table');
      }

      if (!tableNames.contains('assignments')) {
        await db.execute('''
          CREATE TABLE assignments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            class_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            due_date TEXT NOT NULL,
            required_count INTEGER,
            reason TEXT,
            scope TEXT NOT NULL DEFAULT 'all',
            assigned_student_ids_json TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (class_id) REFERENCES classes (id) ON DELETE CASCADE
          )
        ''');
        print('✅ Created assignments table');
      }

      if (!tableNames.contains('assignment_students')) {
        await db.execute('''
          CREATE TABLE assignment_students (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            assignment_id INTEGER NOT NULL,
            student_id INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            done_count INTEGER NOT NULL DEFAULT 0,
            comment TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY (assignment_id) REFERENCES assignments (id) ON DELETE CASCADE,
            FOREIGN KEY (student_id) REFERENCES students (id) ON DELETE CASCADE,
            UNIQUE(assignment_id, student_id)
          )
        ''');
        print('✅ Created assignment_students table');
      }

      if (!tableNames.contains('cash_withdrawals')) {
        await db.execute('''
          CREATE TABLE cash_withdrawals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount INTEGER NOT NULL,
            purpose TEXT,
            withdrawer_name TEXT,
            withdraw_date TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_withdrawals_date ON cash_withdrawals(withdraw_date)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_withdrawals_withdrawer ON cash_withdrawals(withdrawer_name)',
        );
        print('✅ Created cash_withdrawals table');
      }

      if (!tableNames.contains('cash_incomes')) {
        await db.execute('''
          CREATE TABLE cash_incomes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            amount INTEGER NOT NULL,
            purpose TEXT,
            supplier_name TEXT,
            income_date TEXT NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_incomes_date ON cash_incomes(income_date)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_cash_incomes_supplier ON cash_incomes(supplier_name)',
        );
        print('✅ Created cash_incomes table');
      }

      // إنشاء الفهارس المفقودة
      await _createMissingIndexes(db, tableNames);
      
    } catch (e) {
      print('❌ Error creating missing tables: $e');
    }
  }

  Future<Map<String, String>> getCourseDueDatesForClass(String classId) async {
    final db = await database;
    final rows = await db.query(
      'course_due_dates',
      columns: ['course_id', 'due_date'],
      where: 'class_id = ?',
      whereArgs: [classId],
    );

    final map = <String, String>{};
    for (final r in rows) {
      final courseId = r['course_id']?.toString() ?? '';
      final dueDate = r['due_date']?.toString() ?? '';
      if (courseId.isEmpty || dueDate.isEmpty) continue;
      map[courseId] = dueDate;
    }
    return map;
  }

  Future<String?> getCourseDueDate({
    required String classId,
    required String courseId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'course_due_dates',
      columns: ['due_date'],
      where: 'class_id = ? AND course_id = ?',
      whereArgs: [classId, courseId],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['due_date']?.toString();
  }

  Future<void> upsertCourseDueDate({
    required String classId,
    required String courseId,
    required String dueDateIso,
  }) async {
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    await db.insert(
      'course_due_dates',
      {
        'class_id': classId,
        'course_id': courseId,
        'due_date': dueDateIso,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await _enqueueSyncOutbox(
      tableName: 'course_due_dates',
      localId: '${classId}_$courseId',
      op: 'upsert',
      payload: {
        'class_id': classId,
        'course_id': courseId,
        'due_date': dueDateIso,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
    );
  }

  Future<void> _createMissingIndexes(Database db, Set<String> tableNames) async {
    try {
      if (!tableNames.contains('notes')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_class_id ON notes(class_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_notes_item ON notes(item_type, item_id)');
      }
      
      if (!tableNames.contains('courses')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_courses_location ON courses(location)');
      }
      
      if (!tableNames.contains('class_course_prices')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_class_course_prices_class_id ON class_course_prices(class_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_class_course_prices_course_id ON class_course_prices(course_id)');
      }
      
      if (!tableNames.contains('installments')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_student_id ON installments(student_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_course_id ON installments(course_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_installments_date ON installments(date)');
      }
      
      if (!tableNames.contains('student_notes')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_student_id ON student_notes(student_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_class_id ON student_notes(class_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_student_notes_date ON student_notes(date)');
      }

      if (tableNames.contains('assignments')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_assignments_class_id ON assignments(class_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_assignments_due_date ON assignments(due_date)');
      }

      if (tableNames.contains('assignment_students')) {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_assignment_students_assignment_id ON assignment_students(assignment_id)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_assignment_students_student_id ON assignment_students(student_id)');
      }
      
      print('✅ Created missing indexes');
    } catch (e) {
      print('❌ Error creating missing indexes: $e');
    }
  }

  // التحقق من سلامة قاعدة البيانات بعد العمليات الحساسة
  Future<void> _validateDatabaseIntegrity() async {
    try {
      final db = await database;
      
      // التحقق من عدم وجود سجلات يتيمة (بدون فصل) - استخدام LEFT JOIN أكثر دقة
      final orphanedStudents = await db.rawQuery('''
        SELECT s.id, s.name, s.class_id 
        FROM students s
        LEFT JOIN classes c ON s.class_id = c.id
        WHERE c.id IS NULL AND s.class_id IS NOT NULL
      ''');
      
      final orphanedLectures = await db.rawQuery('''
        SELECT l.id, l.class_id 
        FROM lectures l
        LEFT JOIN classes c ON l.class_id = c.id
        WHERE c.id IS NULL AND l.class_id IS NOT NULL
      ''');
      
      final orphanedExams = await db.rawQuery('''
        SELECT e.id, e.class_id 
        FROM exams e
        LEFT JOIN classes c ON e.class_id = c.id
        WHERE c.id IS NULL AND e.class_id IS NOT NULL
      ''');
      
      final studentCount = orphanedStudents.length;
      final lectureCount = orphanedLectures.length;
      final examCount = orphanedExams.length;
      
      if (studentCount > 0 || lectureCount > 0 || examCount > 0) {
        print('⚠️ Database integrity warning:');
        print('   - Orphaned students: $studentCount');
        if (studentCount > 0) {
          print('     Details: ${orphanedStudents.map((s) => "ID:${s['id']}, Class:${s['class_id']}").join(', ')}');
        }
        print('   - Orphaned lectures: $lectureCount');
        print('   - Orphaned exams: $examCount');
        
        // تنظيف السجلات اليتيمة تلقائيًا - فقط الطلاب الذين class_id ليس NULL وغير موجود
        if (studentCount > 0) {
          final orphanedIds = orphanedStudents.map((s) => s['id']).whereType<int>().toList();
          if (orphanedIds.isNotEmpty) {
            await db.delete('students', where: '''
              id IN (${core.List.filled(orphanedIds.length, '?').join(',')})
            ''', whereArgs: orphanedIds);
            print('✅ Cleaned orphaned students: ${orphanedIds.join(', ')}');
          }
        }
        
        if (lectureCount > 0) {
          final orphanedIds = orphanedLectures.map((l) => l['id']).whereType<int>().toList();
          if (orphanedIds.isNotEmpty) {
            await db.delete('lectures', where: '''
              id IN (${core.List.filled(orphanedIds.length, '?').join(',')})
            ''', whereArgs: orphanedIds);
            print('✅ Cleaned orphaned lectures: ${orphanedIds.join(', ')}');
          }
        }
        
        if (examCount > 0) {
          final orphanedIds = orphanedExams.map((e) => e['id']).whereType<int>().toList();
          if (orphanedIds.isNotEmpty) {
            await db.delete('exams', where: '''
              id IN (${core.List.filled(orphanedIds.length, '?').join(',')})
            ''', whereArgs: orphanedIds);
            print('✅ Cleaned orphaned exams: ${orphanedIds.join(', ')}');
          }
        }
      } else {
        print('✅ Database integrity check passed');
      }
      
      // التحقق من تطابق الإحصائيات
      final totalClasses = await db.rawQuery('SELECT COUNT(*) as count FROM classes');
      final totalStudents = await db.rawQuery('SELECT COUNT(*) as count FROM students');
      final totalLectures = await db.rawQuery('SELECT COUNT(*) as count FROM lectures');
      final totalExams = await db.rawQuery('SELECT COUNT(*) as count FROM exams');
      
      print('📊 Database stats:');
      print('   - Classes: ${totalClasses.first['count']}');
      print('   - Students: ${totalStudents.first['count']}');
      print('   - Lectures: ${totalLectures.first['count']}');
      print('   - Exams: ${totalExams.first['count']}');
      
    } catch (e) {
      print('❌ Database integrity check failed: $e');
    }
  }

  // Generic database operations for auth
  Future<List<Map<String, dynamic>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<dynamic>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    final db = await database;
    return await db.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> insert(String table, Map<String, dynamic> values) async {
    final db = await database;
    return await db.insert(table, values);
  }

  Future<int> update(
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<dynamic>? whereArgs,
  }) async {
    final db = await database;
    return await db.update(table, values, where: where, whereArgs: whereArgs);
  }
}


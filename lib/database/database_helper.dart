import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;
  static const int _databaseVersion = 15;
  static bool _forceReinit = false;

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
        final id = int.tryParse(docId);
        if (id == null) return;
        localId = id.toString();
        values = <String, dynamic>{...data, 'id': id};
        values['created_at'] = (values['created_at'] ?? values['createdAt'] ?? nowIso).toString();
        if (values.containsKey('updated_at') || values.containsKey('updatedAt')) {
          values['updated_at'] = (values['updated_at'] ?? values['updatedAt'] ?? nowIso).toString();
        }
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

    await db.insert(
      tableName,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

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
    final db = await database;
    await db.transaction((txn) async {
      // Delete children before parents to respect foreign keys.
      await txn.delete('attendance');
      await txn.delete('grades');
      await txn.delete('student_notes');
      await txn.delete('notes');
      await txn.delete('messages');
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

  Future<void> markPendingOutboxAsSkippedForTables(Set<String> tableNames) async {
    if (tableNames.isEmpty) return;
    final db = await database;
    final nowIso = DateTime.now().toIso8601String();
    final placeholders = List.filled(tableNames.length, '?').join(',');
    await db.rawUpdate(
      "UPDATE sync_outbox SET status = 'skipped', updated_at = ? WHERE status = 'pending' AND table_name IN ($placeholders)",
      [nowIso, ...tableNames.toList()],
    );
  }

  Future<void> upsertClassFromCloud(String cloudId, Map<String, dynamic> cloudData) async {
    final db = await database;
    final id = int.tryParse(cloudId);
    if (id == null) return;

    final nowIso = DateTime.now().toIso8601String();
    final values = <String, dynamic>{
      'id': id,
      'name': cloudData['name'],
      'subject': cloudData['subject'],
      'year': cloudData['year'],
      'description': cloudData['description'],
      'created_at': (cloudData['created_at'] ?? cloudData['createdAt'] ?? nowIso).toString(),
      'updated_at': (cloudData['updated_at'] ?? cloudData['updatedAt'] ?? nowIso).toString(),
    };

    await db.insert(
      'classes',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'sync_meta',
      {
        'table_name': 'classes',
        'local_id': id.toString(),
        'cloud_id': cloudId,
        'server_updated_at': (cloudData['updated_at'] ?? cloudData['updatedAt'])?.toString(),
        'local_updated_at': nowIso,
        'is_deleted': 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertStudentFromCloud(String cloudId, Map<String, dynamic> cloudData) async {
    final db = await database;
    final id = int.tryParse(cloudId);
    if (id == null) return;

    final nowIso = DateTime.now().toIso8601String();
    final values = Map<String, dynamic>.from(cloudData);
    values['id'] = id;
    values['created_at'] = (cloudData['created_at'] ?? cloudData['createdAt'] ?? nowIso).toString();
    values['updated_at'] = (cloudData['updated_at'] ?? cloudData['updatedAt'] ?? nowIso).toString();

    await db.insert(
      'students',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'sync_meta',
      {
        'table_name': 'students',
        'local_id': id.toString(),
        'cloud_id': cloudId,
        'server_updated_at': (cloudData['updated_at'] ?? cloudData['updatedAt'])?.toString(),
        'local_updated_at': nowIso,
        'is_deleted': 0,
        'created_at': nowIso,
        'updated_at': nowIso,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // إجبار إعادة تهيئة قاعدة البيانات
  Future<void> forceReinit() async {
    _forceReinit = true;
    await database;
  }

  Future<void> resetDatabaseFile() async {
    try {
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
          print('❌ Cannot write to database file: $e');
          // محاولة حذف الملف القديم وإنشاء واحد جديد
          try {
            await dbFile.delete();
            print('🗑️ Deleted existing database file');
            isNewDb = true;
          } catch (deleteError) {
            print('❌ Failed to delete database file: $deleteError');
            rethrow;
          }
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
    return result;
  }

  Future<int> deleteClass(int id) async {
    final db = await database;
    final result = await db.delete(
      'classes',
      where: 'id = ?',
      whereArgs: [id],
    );
    await _enqueueSyncOutbox(
      tableName: 'classes',
      localId: id.toString(),
      op: 'delete',
    );
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
          where: 'lecture_id IN (${List.filled(lectureIds.length, '?').join(',')})',
          whereArgs: lectureIds,
        );
      }
      if (studentIds.isNotEmpty) {
        await txn.delete(
          'attendance',
          where: 'student_id IN (${List.filled(studentIds.length, '?').join(',')})',
          whereArgs: studentIds,
        );
        await txn.delete(
          'grades',
          where: 'student_id IN (${List.filled(studentIds.length, '?').join(',')})',
          whereArgs: studentIds,
        );
      }
      await txn.delete('student_notes', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('notes', where: 'class_id = ?', whereArgs: [classId]);
      await txn.delete('messages', where: 'class_id = ?', whereArgs: [classId]);
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
    
    await _enqueueSyncOutbox(
      tableName: 'students',
      localId: id.toString(),
      op: 'insert',
      payload: {
        ...studentMap,
        'id': id,
      },
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
      await _enqueueSyncOutbox(
        tableName: 'students',
        localId: student.id.toString(),
        op: 'update',
        payload: map,
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
        final placeholders = List.filled(classIds.length, '?').join(',');
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
        final placeholders = List.filled(studentIds.length, '?').join(',');
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
        final placeholders = List.filled(studentIds.length, '?').join(',');
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
      where: 'student_id = ? AND exam_name = ?',
      whereArgs: [studentId, examTitle],
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
    final List<Map<String, dynamic>> result = await db.query(
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
    final placeholders = List.filled(studentIds.length, '?').join(',');
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
    final placeholders = List.filled(studentIds.length, '?').join(',');
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
    List<dynamic> whereArgs = [];
    
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

    final placeholders = List.filled(studentIds.length, '?').join(',');
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
    List<dynamic> whereArgs = [];
    
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
      
      print('✅ Created missing indexes');
    } catch (e) {
      print('❌ Error creating missing indexes: $e');
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

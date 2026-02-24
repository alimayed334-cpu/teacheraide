import 'dart:convert';
import 'dart:core';
import 'dart:core' as core;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import '../../models/email_service.dart';
import '../../models/student_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/bot_api_service.dart';

enum AlertsSendMode { auto, manual }

enum AlertsChannel { telegram, email, both }

enum AlertsRecipient { student, parent, both }

class AlertsScreen extends StatefulWidget {
  final ClassModel classModel;

  const AlertsScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // إعدادات القسم الأول
  AlertsSendMode _modeConsecutive = AlertsSendMode.manual;
  AlertsChannel _channelConsecutive = AlertsChannel.telegram;
  AlertsRecipient _recipientConsecutive = AlertsRecipient.parent;
  final TextEditingController _messageConsecutive = TextEditingController();

  // إعدادات القسم الثاني
  AlertsSendMode _modeMonthly = AlertsSendMode.manual;
  AlertsChannel _channelMonthly = AlertsChannel.telegram;
  AlertsRecipient _recipientMonthly = AlertsRecipient.parent;
  final TextEditingController _messageMonthly = TextEditingController();

  bool _loading = true;
  bool _sendingConsecutive = false;
  bool _sendingMonthly = false;

  // بيانات الجداول
  List<_ConsecutiveAlertRow> _consecutiveRows = [];
  List<_MonthlyAlertRow> _monthlyRows = [];

  // ملاحظات الربط (telegram/email)
  List<String> _warningsConsecutive = [];
  List<String> _warningsMonthly = [];

  // مفاتيح التخزين
  static const _prefsKeyConsecutive = 'alerts_consecutive_settings_v1';
  static const _prefsKeyMonthly = 'alerts_monthly_settings_v1';
  static const _prefsSentStateKey = 'alerts_sent_state_v1';
  static const _prefsCountsKey = 'alerts_counts_v1';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndData(autoSendIfEnabled: true);
  }

  @override
  void dispose() {
    _messageConsecutive.dispose();
    _messageMonthly.dispose();
    super.dispose();
  }

  Future<void> _loadSettingsAndData({required bool autoSendIfEnabled}) async {
    setState(() {
      _loading = true;
    });

    try {
      await _loadSettings();
      await _loadAlertsData();
      if (!mounted) return;

      if (autoSendIfEnabled) {
        if (_modeConsecutive == AlertsSendMode.auto) {
          await _sendConsecutiveAlerts(isAuto: true);
        }
        if (_modeMonthly == AlertsSendMode.auto) {
          await _sendMonthlyAlerts(isAuto: true);
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final raw1 = prefs.getString(_prefsKeyConsecutive);
    if (raw1 != null && raw1.trim().isNotEmpty) {
      try {
        final m = jsonDecode(raw1);
        if (m is Map) {
          _modeConsecutive = _parseMode(m['mode']) ?? _modeConsecutive;
          _channelConsecutive = _parseChannel(m['channel']) ?? _channelConsecutive;
          _recipientConsecutive = _parseRecipient(m['recipient']) ?? _recipientConsecutive;
          _messageConsecutive.text = (m['message']?.toString() ?? _messageConsecutive.text).trim();
        }
      } catch (_) {}
    }

    final raw2 = prefs.getString(_prefsKeyMonthly);
    if (raw2 != null && raw2.trim().isNotEmpty) {
      try {
        final m = jsonDecode(raw2);
        if (m is Map) {
          _modeMonthly = _parseMode(m['mode']) ?? _modeMonthly;
          _channelMonthly = _parseChannel(m['channel']) ?? _channelMonthly;
          _recipientMonthly = _parseRecipient(m['recipient']) ?? _recipientMonthly;
          _messageMonthly.text = (m['message']?.toString() ?? _messageMonthly.text).trim();
        }
      } catch (_) {}
    }

    if (_messageConsecutive.text.trim().isEmpty) {
      _messageConsecutive.text = 'تنبيه: تم تسجيل غيابات متكررة لديك. يرجى التواصل مع الإدارة.';
    }
    if (_messageMonthly.text.trim().isEmpty) {
      _messageMonthly.text = 'تنبيه: تم تسجيل عدد غيابات مرتفع خلال آخر 30 يوم. يرجى الالتزام بالحضور.';
    }
  }

  Future<void> _saveSettingsConsecutive() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyConsecutive,
      jsonEncode({
        'mode': _modeConsecutive.name,
        'channel': _channelConsecutive.name,
        'recipient': _recipientConsecutive.name,
        'message': _messageConsecutive.text.trim(),
      }),
    );
  }

  Future<void> _saveSettingsMonthly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKeyMonthly,
      jsonEncode({
        'mode': _modeMonthly.name,
        'channel': _channelMonthly.name,
        'recipient': _recipientMonthly.name,
        'message': _messageMonthly.text.trim(),
      }),
    );
  }

  AlertsSendMode? _parseMode(dynamic v) {
    final s = v?.toString();
    if (s == null) return null;
    return AlertsSendMode.values.where((e) => e.name == s).cast<AlertsSendMode?>().firstWhere((e) => e != null, orElse: () => null);
  }

  AlertsChannel? _parseChannel(dynamic v) {
    final s = v?.toString();
    if (s == null) return null;
    return AlertsChannel.values.where((e) => e.name == s).cast<AlertsChannel?>().firstWhere((e) => e != null, orElse: () => null);
  }

  AlertsRecipient? _parseRecipient(dynamic v) {
    final s = v?.toString();
    if (s == null) return null;
    return AlertsRecipient.values.where((e) => e.name == s).cast<AlertsRecipient?>().firstWhere((e) => e != null, orElse: () => null);
  }

  Future<void> _loadAlertsData() async {
    final classId = widget.classModel.id;
    if (classId == null) {
      _consecutiveRows = [];
      _monthlyRows = [];
      return;
    }

    final countsState = await _loadCountsState();

    final students = await _dbHelper.getStudentsByClass(classId);
    final studentById = {for (final s in students) if (s.id != null) s.id!: s};
    final studentIds = studentById.keys.toList();

    // أحداث الفصل (محاضرات + امتحانات) مرتبة حسب التاريخ
    final db = await _dbHelper.database;

    final lectures = await db.rawQuery(
      'SELECT id, title, date FROM lectures WHERE class_id = ? ORDER BY date ASC, id ASC',
      [classId],
    );
    final exams = await db.rawQuery(
      'SELECT id, title, date FROM exams WHERE class_id = ? ORDER BY date ASC, id ASC',
      [classId],
    );

    final events = <_ClassEvent>[];
    for (final l in lectures) {
      final id = (l['id'] is int) ? l['id'] as int : int.tryParse(l['id']?.toString() ?? '') ?? 0;
      if (id <= 0) continue;
      events.add(_ClassEvent(
        type: _EventType.lecture,
        id: id,
        title: l['title']?.toString() ?? '',
        date: DateTime.tryParse(l['date']?.toString() ?? '') ?? DateTime(1970),
      ));
    }
    for (final e in exams) {
      final id = (e['id'] is int) ? e['id'] as int : int.tryParse(e['id']?.toString() ?? '') ?? 0;
      if (id <= 0) continue;
      events.add(_ClassEvent(
        type: _EventType.exam,
        id: id,
        title: e['title']?.toString() ?? '',
        date: DateTime.tryParse(e['date']?.toString() ?? '') ?? DateTime(1970),
      ));
    }
    events.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      final t = a.type.index.compareTo(b.type.index);
      if (t != 0) return t;
      return a.id.compareTo(b.id);
    });

    // تحميل حضور المحاضرات للطلاب في هذا الفصل (Absent فقط + totals)
    // ملاحظة: بعض السجلات قد تُحفظ بدون lecture_id، لذلك نطابق أيضًا حسب التاريخ.
    final lectureIdToDate = <int, String>{};
    for (final l in lectures) {
      final lid = (l['id'] is int) ? l['id'] as int : int.tryParse(l['id']?.toString() ?? '') ?? 0;
      if (lid <= 0) continue;
      final dt = DateTime.tryParse(l['date']?.toString() ?? '') ?? DateTime(1970);
      lectureIdToDate[lid] = DateFormat('yyyy-MM-dd').format(dt);
    }

    final attendanceRows = await db.rawQuery(
      '''
      SELECT a.student_id, a.lecture_id, a.date, a.status
      FROM attendance a
      WHERE a.student_id IN (${studentIds.isEmpty ? 'NULL' : core.List.filled(studentIds.length, '?').join(',')})
      ''',
      studentIds,
    );

    final lectureAbsent = <int, Set<int>>{}; // studentId -> set(lectureId)
    final lecturePresent = <int, Set<int>>{}; // studentId -> set(lectureId)
    final lectureAbsentTotal = <int, int>{};
    for (final r in attendanceRows) {
      final sid = (r['student_id'] is int) ? r['student_id'] as int : int.tryParse(r['student_id']?.toString() ?? '') ?? 0;
      final status = (r['status'] is num) ? (r['status'] as num).toInt() : int.tryParse(r['status']?.toString() ?? '') ?? 0;
      if (sid <= 0) continue;
      // AttendanceStatus.absent == index 1

      final lidRaw = r['lecture_id'];
      final lid = (lidRaw is int) ? lidRaw : int.tryParse(lidRaw?.toString() ?? '') ?? 0;
      if (lid > 0 && lectureIdToDate.containsKey(lid)) {
        if (status == 1) {
          lectureAbsent.putIfAbsent(sid, () => <int>{}).add(lid);
          lectureAbsentTotal[sid] = (lectureAbsentTotal[sid] ?? 0) + 1;
        } else {
          lecturePresent.putIfAbsent(sid, () => <int>{}).add(lid);
        }
        continue;
      }

      final dateStr = (r['date']?.toString() ?? '').trim();
      if (dateStr.isEmpty) continue;
      final d = DateTime.tryParse(dateStr) ?? DateTime(1970);
      final dOnly = DateFormat('yyyy-MM-dd').format(d);

      // مطابقة حسب التاريخ: نربط سجل الحضور/الغياب بكل محاضرة بنفس التاريخ داخل هذا الفصل.
      for (final e in lectureIdToDate.entries) {
        if (e.value != dOnly) continue;
        if (status == 1) {
          lectureAbsent.putIfAbsent(sid, () => <int>{}).add(e.key);
          lectureAbsentTotal[sid] = (lectureAbsentTotal[sid] ?? 0) + 1;
        } else {
          // أي حالة غير الغياب (حاضر/متأخر/مجاز/مطرود...) تعتبر كاسرة للتتالي.
          lecturePresent.putIfAbsent(sid, () => <int>{}).add(e.key);
        }
      }
    }

    // تحميل غياب/حضور الامتحانات من جدول grades (status/notes)
    final gradeRows = await db.rawQuery(
      '''
      SELECT g.student_id, g.exam_name, g.exam_date, g.status, g.notes
      FROM grades g
      WHERE g.student_id IN (${studentIds.isEmpty ? 'NULL' : core.List.filled(studentIds.length, '?').join(',')})
      ''',
      studentIds,
    );

    bool isExamAbsent(Map<String, dynamic> g) {
      final st = (g['status']?.toString() ?? '').toLowerCase();
      final notes = (g['notes']?.toString() ?? '').toLowerCase();
      if (st.contains('غائب') || st.contains('absent')) return true;
      if (notes.contains('غائب') || notes.contains('absent')) return true;
      return false;
    }

    final examAbsent = <int, Set<String>>{}; // studentId -> set(exam_title)
    final examAbsentByTitle = <int, Set<String>>{};
    final examPresentByTitle = <int, Set<String>>{}; // studentId -> set(exam_title) where we know they attended
    final examAbsentTotal = <int, int>{};

    for (final g in gradeRows) {
      final sid = (g['student_id'] is int) ? g['student_id'] as int : int.tryParse(g['student_id']?.toString() ?? '') ?? 0;
      if (sid <= 0) continue;
      final title = g['exam_name']?.toString() ?? '';
      if (title.trim().isEmpty) continue;
      if (isExamAbsent(g)) {
        examAbsent.putIfAbsent(sid, () => <String>{}).add(title);
        examAbsentByTitle.putIfAbsent(sid, () => <String>{}).add(title);
        examAbsentTotal[sid] = (examAbsentTotal[sid] ?? 0) + 1;
      } else {
        // إذا كان لدينا سجل درجات للامتحان ولم يكن غائباً، فهذا يعني حضور مؤكد ويكسر التتالي.
        examPresentByTitle.putIfAbsent(sid, () => <String>{}).add(title);
      }
    }

    // جدول 1: 3 غيابات متتالية (محاضرات/امتحانات)
    final consecutive = <_ConsecutiveAlertRow>[];
    for (final sid in studentIds) {
      final s = studentById[sid];
      if (s == null) continue;

      int streak = 0;
      final streakLectures = <String>[];
      final streakExams = <String>[];

      for (final ev in events) {
        bool absent;
        if (ev.type == _EventType.lecture) {
          absent = (lectureAbsent[sid]?.contains(ev.id) ?? false);
        } else {
          absent = (examAbsentByTitle[sid]?.contains(ev.title) ?? false);
        }

        if (absent) {
          streak++;
          if (ev.type == _EventType.lecture) {
            streakLectures.add(ev.title);
          } else {
            streakExams.add(ev.title);
          }
        } else {
          // Reset streak only when we *know* the student was not absent.
          // - Lectures: if we have a non-absent attendance row.
          // - Exams: only if we have a grade row indicating the exam was attended.
          final shouldBreak = ev.type == _EventType.exam
              ? (examPresentByTitle[sid]?.contains(ev.title) ?? false)
              : (lecturePresent[sid]?.contains(ev.id) ?? false);
          if (!shouldBreak) {
            continue;
          }
          streak = 0;
          streakLectures.clear();
          streakExams.clear();
        }

        if (streak >= 3) {
          break;
        }
      }

      if (streak >= 3) {
        final totalAbs = (lectureAbsentTotal[sid] ?? 0) + (examAbsentTotal[sid] ?? 0);
        final countKey = 'c3|${widget.classModel.id}|$sid';
        consecutive.add(
          _ConsecutiveAlertRow(
            student: s,
            totalAbsences: totalAbs,
            missedLectureTitles: core.List<String>.from(streakLectures),
            missedExamTitles: core.List<String>.from(streakExams),
            signature: 'c3|${streakLectures.join(',')}|${streakExams.join(',')}',
            alertCount: _getAlertCount(countsState, countKey),
          ),
        );
      }
    }

    // جدول 2: 6 غيابات خلال 30 يوم (محاضرات/امتحانات)
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));

    // absences lectures in last 30 days
    final lectureIdsInWindow = <int>[];
    final lectureTitleById = <int, String>{};
    for (final l in lectures) {
      final id = (l['id'] is int) ? l['id'] as int : int.tryParse(l['id']?.toString() ?? '') ?? 0;
      final dt = DateTime.tryParse(l['date']?.toString() ?? '') ?? DateTime(1970);
      if (id > 0 && !dt.isBefore(DateTime(from.year, from.month, from.day)) && !dt.isAfter(DateTime(now.year, now.month, now.day))) {
        lectureIdsInWindow.add(id);
        lectureTitleById[id] = l['title']?.toString() ?? '';
      }
    }

    final monthly = <_MonthlyAlertRow>[];
    for (final sid in studentIds) {
      final s = studentById[sid];
      if (s == null) continue;

      int count = 0;
      final missedLectures = <String>[];
      final missedExams = <String>[];

      // lecture absences in window
      final absLectIds = lectureAbsent[sid] ?? <int>{};
      for (final lid in lectureIdsInWindow) {
        if (absLectIds.contains(lid)) {
          count++;
          missedLectures.add(lectureTitleById[lid] ?? '');
        }
      }

      // exam absences in window (from gradeRows)
      for (final g in gradeRows) {
        final gsid = (g['student_id'] is int) ? g['student_id'] as int : int.tryParse(g['student_id']?.toString() ?? '') ?? 0;
        if (gsid != sid) continue;
        if (!isExamAbsent(g)) continue;
        final dt = DateTime.tryParse(g['exam_date']?.toString() ?? '') ?? DateTime(1970);
        if (dt.isBefore(DateTime(from.year, from.month, from.day)) || dt.isAfter(DateTime(now.year, now.month, now.day))) continue;
        count++;
        final title = g['exam_name']?.toString() ?? '';
        if (title.trim().isNotEmpty) missedExams.add(title);
      }

      if (count >= 6) {
        final countKey = 'm6|${widget.classModel.id}|$sid';
        monthly.add(
          _MonthlyAlertRow(
            student: s,
            absencesLast30Days: count,
            missedLectureTitles: missedLectures,
            missedExamTitles: missedExams,
            signature: 'm6|$count|${DateFormat('yyyy-MM-dd').format(now)}',
            alertCount: _getAlertCount(countsState, countKey),
          ),
        );
      }
    }

    consecutive.sort((a, b) => b.totalAbsences.compareTo(a.totalAbsences));
    monthly.sort((a, b) => b.absencesLast30Days.compareTo(a.absencesLast30Days));

    if (!mounted) return;
    setState(() {
      _consecutiveRows = consecutive;
      _monthlyRows = monthly;
      _warningsConsecutive = [];
      _warningsMonthly = [];
    });
  }

  Future<Map<String, String>> _loadSentState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsSentStateKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return m.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    return <String, String>{};
  }

  Future<Map<String, dynamic>> _loadCountsState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsCountsKey);
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final m = jsonDecode(raw);
      if (m is Map) {
        return m.map((k, v) => MapEntry(k.toString(), v));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _saveCountsState(Map<String, dynamic> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsCountsKey, jsonEncode(state));
  }

  int _getAlertCount(Map<String, dynamic> countsState, String key) {
    final v = countsState[key];
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String? _getLastMonthlySent(Map<String, dynamic> countsState, String key) {
    final v = countsState['$key|last'];
    final s = v?.toString();
    if (s == null || s.trim().isEmpty) return null;
    return s;
  }

  int _nextMonthlyCountWithReset({
    required Map<String, dynamic> countsState,
    required String key,
    required DateTime now,
  }) {
    final lastRaw = _getLastMonthlySent(countsState, key);
    if (lastRaw != null) {
      final last = DateTime.tryParse(lastRaw);
      if (last != null) {
        final diff = now.difference(last);
        if (diff.inDays >= 30) {
          return 1;
        }
      }
    }
    return _getAlertCount(countsState, key) + 1;
  }

  Future<void> _saveSentState(Map<String, String> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsSentStateKey, jsonEncode(state));
  }

  Future<int?> _getTelegramChatIdForStudent({
    required StudentModel student,
    required AlertsRecipient recipient,
  }) async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final ws = auth.workspaceId;

      // Local cache first
      try {
        final prefs = await SharedPreferences.getInstance();
        final wsKey = (ws ?? '').trim().isEmpty ? 'default' : ws!.trim();
        final sidKey = student.id?.toString() ?? '';
        final recipientKey = (recipient == AlertsRecipient.student) ? 'student' : 'parent';
        final cacheKey = 'tg_chat_id_v1|$wsKey|$recipientKey|$sidKey';
        final cached = prefs.getInt(cacheKey);
        if (cached != null && cached != 0) {
          return cached;
        }
      } catch (_) {}

      final studentsCol = (ws != null && ws.trim().isNotEmpty)
          ? FirebaseFirestore.instance.collection('workspaces').doc(ws).collection('students')
          : FirebaseFirestore.instance.collection('students');

      final sid = student.id?.toString();
      final sidInt = (sid != null && sid.isNotEmpty) ? int.tryParse(sid) : null;
      DocumentSnapshot<Map<String, dynamic>>? doc;
      if (sid != null && sid.isNotEmpty) {
        doc = await studentsCol.doc(sid).get();
      }

      Map<String, dynamic>? data;
      if (doc != null && doc.exists) {
        data = doc.data();
      } else {
        // Fallbacks: some Firestore exports store the student id in fields like
        // local_id / student_id and keep phone null.
        if (sid != null && sid.isNotEmpty) {
          try {
            final qsLocal = await studentsCol.where('local_id', isEqualTo: sid).limit(1).get();
            if (qsLocal.docs.isNotEmpty) {
              data = qsLocal.docs.first.data();
            }
          } catch (_) {}

          if (data == null && sidInt != null) {
            try {
              final qsLocalNum = await studentsCol.where('local_id', isEqualTo: sidInt).limit(1).get();
              if (qsLocalNum.docs.isNotEmpty) {
                data = qsLocalNum.docs.first.data();
              }
            } catch (_) {}
          }

          if (data == null) {
            try {
              final qsStudentId = await studentsCol.where('student_id', isEqualTo: sid).limit(1).get();
              if (qsStudentId.docs.isNotEmpty) {
                data = qsStudentId.docs.first.data();
              }
            } catch (_) {}
          }

          if (data == null && sidInt != null) {
            try {
              final qsStudentIdNum = await studentsCol.where('student_id', isEqualTo: sidInt).limit(1).get();
              if (qsStudentIdNum.docs.isNotEmpty) {
                data = qsStudentIdNum.docs.first.data();
              }
            } catch (_) {}
          }

          if (data == null) {
            if (sidInt != null) {
              try {
                final qsNumeric = await studentsCol.where('id', isEqualTo: sidInt).limit(1).get();
                if (qsNumeric.docs.isNotEmpty) {
                  data = qsNumeric.docs.first.data();
                }
              } catch (_) {}
            }
          }
        }

        final phone = (student.phone ?? '').trim();
        if (phone.isNotEmpty) {
          final qs = await studentsCol.where('phone', isEqualTo: phone).limit(1).get();
          if (qs.docs.isNotEmpty) {
            data = qs.docs.first.data();
          }
        }
      }

      if (data == null) return null;

      final field = (recipient == AlertsRecipient.student)
          ? 'telegram_student_chat_id'
          : 'telegram_parent_chat_id';
      final raw = data[field];
      if (raw == null) return null;
      int? parsed;
      if (raw is int) {
        parsed = raw;
      } else {
        parsed = int.tryParse(raw.toString());
      }

      if (parsed != null && parsed != 0) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final wsKey = (ws ?? '').trim().isEmpty ? 'default' : ws!.trim();
          final sidKey = student.id?.toString() ?? '';
          final recipientKey = (recipient == AlertsRecipient.student) ? 'student' : 'parent';
          final cacheKey = 'tg_chat_id_v1|$wsKey|$recipientKey|$sidKey';
          await prefs.setInt(cacheKey, parsed);
        } catch (_) {}
      }

      return parsed;
    } catch (_) {
      return null;
    }
  }

  List<String> _getEmailsForRecipient(StudentModel student, AlertsRecipient recipient) {
    final emails = <String>[];

    void addIfValid(String? e) {
      final v = (e ?? '').trim();
      if (v.isEmpty) return;
      if (EmailService.isValidEmail(v)) emails.add(v);
    }

    if (recipient == AlertsRecipient.student || recipient == AlertsRecipient.both) {
      addIfValid(student.email);
    }

    if (recipient == AlertsRecipient.parent || recipient == AlertsRecipient.both) {
      addIfValid(student.parentEmail);
      addIfValid(student.primaryGuardian?.email);
      addIfValid(student.secondaryGuardian?.email);
    }

    return emails.toSet().toList();
  }

  Future<void> _sendTextToStudent({
    required StudentModel student,
    required AlertsChannel channel,
    required AlertsRecipient recipient,
    required String message,
    required List<String> warnings,
  }) async {
    final targets = <AlertsRecipient>[];
    if (recipient == AlertsRecipient.both) {
      targets.addAll([AlertsRecipient.student, AlertsRecipient.parent]);
    } else {
      targets.add(recipient);
    }

    for (final tgt in targets) {
      if (channel == AlertsChannel.telegram || channel == AlertsChannel.both) {
        final chatId = await _getTelegramChatIdForStudent(student: student, recipient: tgt);
        if (chatId == null) {
          warnings.add('${student.name}: غير مربوط بتيليجرام (${tgt == AlertsRecipient.student ? 'طالب' : 'ولي أمر'})');
        } else {
          await BotApiService.sendTelegramText(chatId: chatId, text: message);
        }
      }

      if (channel == AlertsChannel.email || channel == AlertsChannel.both) {
        final emails = _getEmailsForRecipient(student, tgt);
        if (emails.isEmpty) {
          warnings.add('${student.name}: لا يوجد بريد إلكتروني (${tgt == AlertsRecipient.student ? 'طالب' : 'ولي أمر'})');
        } else {
          for (final e in emails) {
            await EmailService.sendTextOnlyEmail(
              recipientEmail: e,
              subject: 'إنذار غياب - ${widget.classModel.name}',
              message: message,
            );
          }
        }
      }
    }
  }

  Future<void> _sendConsecutiveAlerts({required bool isAuto}) async {
    if (_consecutiveRows.isEmpty) return;
    final msg = _messageConsecutive.text.trim();
    if (msg.isEmpty) return;

    setState(() {
      _sendingConsecutive = true;
      _warningsConsecutive = [];
    });

    try {
      final sentState = await _loadSentState();
      final countsState = await _loadCountsState();
      final warnings = <String>[];

      final now = DateTime.now();
      int sent = 0;
      for (final r in _consecutiveRows) {
        final sid = r.student.id;
        if (sid == null) continue;
        final key = 'c3|${widget.classModel.id}|$sid';
        final signature = r.signature;

        if (isAuto && sentState[key] == signature) {
          continue;
        }

        await _sendTextToStudent(
          student: r.student,
          channel: _channelConsecutive,
          recipient: _recipientConsecutive,
          message: msg,
          warnings: warnings,
        );

        sentState[key] = signature;
        final nextCount = _nextMonthlyCountWithReset(countsState: countsState, key: key, now: now);
        countsState[key] = nextCount;
        countsState['$key|last'] = DateTime(now.year, now.month, now.day).toIso8601String();
        sent++;
      }

      await _saveSentState(sentState);
      await _saveCountsState(countsState);

      await _loadAlertsData();

      if (!mounted) return;
      setState(() {
        _warningsConsecutive = warnings;
      });

      if (mounted && !isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الإنذار (3 غيابات) إلى $sent طالب/ولي أمر')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الإرسال: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingConsecutive = false;
        });
      }
    }
  }

  Future<void> _sendMonthlyAlerts({required bool isAuto}) async {
    if (_monthlyRows.isEmpty) return;
    final msg = _messageMonthly.text.trim();
    if (msg.isEmpty) return;

    setState(() {
      _sendingMonthly = true;
      _warningsMonthly = [];
    });

    try {
      final sentState = await _loadSentState();
      final now = DateTime.now();
      final countsState = await _loadCountsState();
      final warnings = <String>[];

      int sent = 0;
      for (final r in _monthlyRows) {
        final sid = r.student.id;
        if (sid == null) continue;
        final key = 'm6|${widget.classModel.id}|$sid';
        final signature = r.signature;

        if (isAuto && sentState[key] == signature) {
          continue;
        }

        await _sendTextToStudent(
          student: r.student,
          channel: _channelMonthly,
          recipient: _recipientMonthly,
          message: msg,
          warnings: warnings,
        );

        sentState[key] = signature;
        final nextCount = _nextMonthlyCountWithReset(countsState: countsState, key: key, now: now);
        countsState[key] = nextCount;
        countsState['$key|last'] = DateTime(now.year, now.month, now.day).toIso8601String();
        sent++;
      }

      await _saveSentState(sentState);
      await _saveCountsState(countsState);

      await _loadAlertsData();

      if (!mounted) return;
      setState(() {
        _warningsMonthly = warnings;
      });

      if (mounted && !isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إرسال الإنذار (6 غيابات/30 يوم) إلى $sent طالب/ولي أمر')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ أثناء الإرسال: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sendingMonthly = false;
        });
      }
    }
  }

  Future<void> _exportConsecutivePdf() async {
    await _exportPdf(
      title: 'إنذار 3 غيابات متتالية',
      filePrefix: 'انذار_3_غيابات',
      rows: _consecutiveRows
          .map(
            (r) => {
              'name': r.student.name,
              'count': r.alertCount.toString(),
              'total': r.totalAbsences.toString(),
              'lectures': r.missedLectureTitles.join('، '),
              'exams': r.missedExamTitles.join('، '),
            },
          )
          .toList(),
    );
  }

  Future<void> _exportMonthlyPdf() async {
    await _exportPdf(
      title: 'إنذار 6 غيابات خلال آخر 30 يوم',
      filePrefix: 'انذار_6_غيابات_30_يوم',
      rows: _monthlyRows
          .map(
            (r) => {
              'name': r.student.name,
              'count': r.alertCount.toString(),
              'total': r.absencesLast30Days.toString(),
              'lectures': r.missedLectureTitles.join('، '),
              'exams': r.missedExamTitles.join('، '),
            },
          )
          .toList(),
    );
  }

  Future<void> _exportPdf({
    required String title,
    required String filePrefix,
    required List<Map<String, String>> rows,
  }) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Color(0xFFFEC619)),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final arabicBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
      final fallbackFont = pw.Font.helvetica();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      );

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            pw.Widget headerCell(String t) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    t,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: arabicBold, fontFallback: [fallbackFont], fontSize: 10, color: PdfColor.fromInt(0xFFFEC619)),
                  ),
                );
            pw.Widget cell(String t) => pw.Padding(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    t,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: arabicFont, fontFallback: [fallbackFont], fontSize: 9),
                  ),
                );

            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.DefaultTextStyle(
                style: pw.TextStyle(font: arabicFont, fontFallback: [fallbackFont]),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFFFEC619)),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text('الفصل: ${widget.classModel.name}', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                    pw.SizedBox(height: 12),
                    pw.Table(
                      border: pw.TableBorder.all(color: const PdfColor(0.35, 0.35, 0.35), width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(1.6),
                        1: const pw.FlexColumnWidth(0.7),
                        2: const pw.FlexColumnWidth(0.8),
                        3: const pw.FlexColumnWidth(2.2),
                        4: const pw.FlexColumnWidth(1.8),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A1A)),
                          children: [
                            headerCell('اسم الطالب'),
                            headerCell('عدد الإنذارات'),
                            headerCell('عدد الغيابات'),
                            headerCell('المحاضرات التي غابها'),
                            headerCell('الامتحان الذي غابه'),
                          ],
                        ),
                        ...rows.map(
                          (r) => pw.TableRow(
                            children: [
                              cell(r['name'] ?? ''),
                              cell(r['count'] ?? ''),
                              cell(r['total'] ?? ''),
                              cell(r['lectures'] ?? ''),
                              cell(r['exams'] ?? ''),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      if (context.mounted) Navigator.pop(context);

      final safeClass = widget.classModel.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(now);
      final fileName = '${filePrefix}_${safeClass}_$dateStr.pdf';

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save(), flush: true);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildSettingsRow({
    required AlertsSendMode mode,
    required AlertsChannel channel,
    required AlertsRecipient recipient,
    required ValueChanged<AlertsSendMode> onMode,
    required ValueChanged<AlertsChannel> onChannel,
    required ValueChanged<AlertsRecipient> onRecipient,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        DropdownButton<AlertsSendMode>(
          value: mode,
          items: const [
            DropdownMenuItem(value: AlertsSendMode.auto, child: Text('إرسال تلقائي')),
            DropdownMenuItem(value: AlertsSendMode.manual, child: Text('إرسال يدوي')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onMode(v);
          },
        ),
        DropdownButton<AlertsChannel>(
          value: channel,
          items: const [
            DropdownMenuItem(value: AlertsChannel.telegram, child: Text('تيليجرام')),
            DropdownMenuItem(value: AlertsChannel.email, child: Text('إيميل')),
            DropdownMenuItem(value: AlertsChannel.both, child: Text('كلاهما')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onChannel(v);
          },
        ),
        DropdownButton<AlertsRecipient>(
          value: recipient,
          items: const [
            DropdownMenuItem(value: AlertsRecipient.student, child: Text('طالب')),
            DropdownMenuItem(value: AlertsRecipient.parent, child: Text('ولي أمر')),
            DropdownMenuItem(value: AlertsRecipient.both, child: Text('طالب + ولي أمر')),
          ],
          onChanged: (v) {
            if (v == null) return;
            onRecipient(v);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor.withOpacity(0.3);

    return Scaffold(
      appBar: AppBar(
        title: Text('الإنذارات - ${widget.classModel.name}'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: () => _loadSettingsAndData(autoSendIfEnabled: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: borderColor),
                    ),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded, color: theme.colorScheme.secondary),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'إنذار 3 غيابات متكررة متتالية',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              IconButton(
                                tooltip: 'تصدير PDF',
                                onPressed: _consecutiveRows.isEmpty ? null : _exportConsecutivePdf,
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSettingsRow(
                            mode: _modeConsecutive,
                            channel: _channelConsecutive,
                            recipient: _recipientConsecutive,
                            onMode: (v) {
                              setState(() => _modeConsecutive = v);
                              _saveSettingsConsecutive();
                            },
                            onChannel: (v) {
                              setState(() => _channelConsecutive = v);
                              _saveSettingsConsecutive();
                            },
                            onRecipient: (v) {
                              setState(() => _recipientConsecutive = v);
                              _saveSettingsConsecutive();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _messageConsecutive,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'نص الرسالة المرسلة',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _saveSettingsConsecutive(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await _saveSettingsConsecutive();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الرسالة')));
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('حفظ'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: (_modeConsecutive == AlertsSendMode.manual && !_sendingConsecutive)
                                    ? () => _sendConsecutiveAlerts(isAuto: false)
                                    : null,
                                icon: _sendingConsecutive
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.send),
                                label: const Text('إرسال يدوي الآن'),
                              ),
                            ],
                          ),
                          if (_warningsConsecutive.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('ملاحظات على الإرسال:',
                                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            ..._warningsConsecutive.map(
                              (w) => Text('- $w', style: TextStyle(color: Colors.red[700], fontSize: 13)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text('الطلاب المشمولون بالإنذار:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _ConsecutiveTable(rows: _consecutiveRows),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Card(
                    color: cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: borderColor),
                    ),
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.calendar_month, color: theme.colorScheme.secondary),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'إنذار 6 غيابات خلال الشهر (آخر 30 يوم)',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              IconButton(
                                tooltip: 'تصدير PDF',
                                onPressed: _monthlyRows.isEmpty ? null : _exportMonthlyPdf,
                                icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildSettingsRow(
                            mode: _modeMonthly,
                            channel: _channelMonthly,
                            recipient: _recipientMonthly,
                            onMode: (v) {
                              setState(() => _modeMonthly = v);
                              _saveSettingsMonthly();
                            },
                            onChannel: (v) {
                              setState(() => _channelMonthly = v);
                              _saveSettingsMonthly();
                            },
                            onRecipient: (v) {
                              setState(() => _recipientMonthly = v);
                              _saveSettingsMonthly();
                            },
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _messageMonthly,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'نص رسالة الإنذار الشهري',
                              alignLabelWithHint: true,
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _saveSettingsMonthly(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await _saveSettingsMonthly();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الرسالة')));
                                },
                                icon: const Icon(Icons.save),
                                label: const Text('حفظ'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: (_modeMonthly == AlertsSendMode.manual && !_sendingMonthly)
                                    ? () => _sendMonthlyAlerts(isAuto: false)
                                    : null,
                                icon: _sendingMonthly
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.send),
                                label: const Text('إرسال يدوي الآن'),
                              ),
                            ],
                          ),
                          if (_warningsMonthly.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('ملاحظات على الإرسال:',
                                style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            ..._warningsMonthly.map(
                              (w) => Text('- $w', style: TextStyle(color: Colors.red[700], fontSize: 13)),
                            ),
                          ],
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          const Text('الطلاب المشمولون بالإنذار:',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          _MonthlyTable(rows: _monthlyRows),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ConsecutiveTable extends StatelessWidget {
  final List<_ConsecutiveAlertRow> rows;

  const _ConsecutiveTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('لا توجد حالات');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('اسم الطالب')),
          DataColumn(label: Text('عدد الإنذارات')),
          DataColumn(label: Text('عدد غياباته الكلية')),
          DataColumn(label: Text('المحاضرات التي غابها')),
          DataColumn(label: Text('الامتحان الذي غابه')),
        ],
        rows: rows.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(r.student.name)),
              DataCell(Text(r.alertCount.toString())),
              DataCell(Text(r.totalAbsences.toString())),
              DataCell(Text(r.missedLectureTitles.join('، '))),
              DataCell(Text(r.missedExamTitles.join('، '))),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _MonthlyTable extends StatelessWidget {
  final List<_MonthlyAlertRow> rows;

  const _MonthlyTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const Text('لا توجد حالات');
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('اسم الطالب')),
          DataColumn(label: Text('عدد الإنذارات')),
          DataColumn(label: Text('عدد الغيابات خلال 30 يوم')),
          DataColumn(label: Text('المحاضرات')),
          DataColumn(label: Text('الامتحانات')),
        ],
        rows: rows.map((r) {
          return DataRow(
            cells: [
              DataCell(Text(r.student.name)),
              DataCell(Text(r.alertCount.toString())),
              DataCell(Text(r.absencesLast30Days.toString())),
              DataCell(Text(r.missedLectureTitles.join('، '))),
              DataCell(Text(r.missedExamTitles.join('، '))),
            ],
          );
        }).toList(),
      ),
    );
  }
}

enum _EventType { lecture, exam }

class _ClassEvent {
  final _EventType type;
  final int id;
  final String title;
  final DateTime date;

  _ClassEvent({
    required this.type,
    required this.id,
    required this.title,
    required this.date,
  });
}

class _ConsecutiveAlertRow {
  final StudentModel student;
  final int totalAbsences;
  final List<String> missedLectureTitles;
  final List<String> missedExamTitles;
  final String signature;
  final int alertCount;

  _ConsecutiveAlertRow({
    required this.student,
    required this.totalAbsences,
    required this.missedLectureTitles,
    required this.missedExamTitles,
    required this.signature,
    required this.alertCount,
  });
}

class _MonthlyAlertRow {
  final StudentModel student;
  final int absencesLast30Days;
  final List<String> missedLectureTitles;
  final List<String> missedExamTitles;
  final String signature;
  final int alertCount;

  _MonthlyAlertRow({
    required this.student,
    required this.absencesLast30Days,
    required this.missedLectureTitles,
    required this.missedExamTitles,
    required this.signature,
    required this.alertCount,
  });
}

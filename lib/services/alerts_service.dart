import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../database/database_helper.dart';
import '../models/class_model.dart';
import '../models/email_service.dart';
import '../models/student_model.dart';
import 'bot_api_service.dart';

enum AlertsSendMode { auto, manual }

enum AlertsChannel { telegram, email, both }

enum AlertsRecipient { student, parent, both }

class AlertsService {
  static const String prefsKeyConsecutive = 'alerts_consecutive_settings_v1';
  static const String prefsKeyMonthly = 'alerts_monthly_settings_v1';
  static const String prefsSentStateKey = 'alerts_sent_state_v1';

  static Future<void> runAutoIfEnabled({
    required String? workspaceId,
    required ClassModel classModel,
  }) async {
    final classId = classModel.id;
    if (classId == null) return;

    final prefs = await SharedPreferences.getInstance();

    final s1 = _decodeSettings(prefs.getString(prefsKeyConsecutive));
    final s2 = _decodeSettings(prefs.getString(prefsKeyMonthly));

    final mode1 = s1.mode ?? AlertsSendMode.manual;
    final mode2 = s2.mode ?? AlertsSendMode.manual;

    if (mode1 != AlertsSendMode.auto && mode2 != AlertsSendMode.auto) {
      return;
    }

    final dbHelper = DatabaseHelper();
    final data = await _computeAlerts(dbHelper: dbHelper, classModel: classModel);

    final sentState = await _loadSentState(prefs);

    if (mode1 == AlertsSendMode.auto && data.consecutiveRows.isNotEmpty) {
      final msg = (s1.message ?? '').trim();
      if (msg.isNotEmpty) {
        for (final r in data.consecutiveRows) {
          final sid = r.student.id;
          if (sid == null) continue;
          final key = 'c3|$classId|$sid';
          if (sentState[key] == r.signature) continue;

          await _sendTextToStudent(
            workspaceId: workspaceId,
            student: r.student,
            channel: s1.channel ?? AlertsChannel.telegram,
            recipient: s1.recipient ?? AlertsRecipient.parent,
            message: msg,
          );

          sentState[key] = r.signature;
        }
      }
    }

    if (mode2 == AlertsSendMode.auto && data.monthlyRows.isNotEmpty) {
      final msg = (s2.message ?? '').trim();
      if (msg.isNotEmpty) {
        for (final r in data.monthlyRows) {
          final sid = r.student.id;
          if (sid == null) continue;
          final key = 'm6|$classId|$sid';
          if (sentState[key] == r.signature) continue;

          await _sendTextToStudent(
            workspaceId: workspaceId,
            student: r.student,
            channel: s2.channel ?? AlertsChannel.telegram,
            recipient: s2.recipient ?? AlertsRecipient.parent,
            message: msg,
          );

          sentState[key] = r.signature;
        }
      }
    }

    await _saveSentState(prefs, sentState);
  }

  static _AlertsSettings _decodeSettings(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const _AlertsSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _AlertsSettings();
      final m = decoded.map((k, v) => MapEntry(k.toString(), v));

      AlertsSendMode? mode;
      final modeStr = m['mode']?.toString();
      if (modeStr != null) {
        mode = AlertsSendMode.values.where((e) => e.name == modeStr).cast<AlertsSendMode?>().firstWhere((e) => e != null, orElse: () => null);
      }

      AlertsChannel? channel;
      final chStr = m['channel']?.toString();
      if (chStr != null) {
        channel = AlertsChannel.values.where((e) => e.name == chStr).cast<AlertsChannel?>().firstWhere((e) => e != null, orElse: () => null);
      }

      AlertsRecipient? recipient;
      final rStr = m['recipient']?.toString();
      if (rStr != null) {
        recipient = AlertsRecipient.values.where((e) => e.name == rStr).cast<AlertsRecipient?>().firstWhere((e) => e != null, orElse: () => null);
      }

      final message = m['message']?.toString();

      return _AlertsSettings(
        mode: mode,
        channel: channel,
        recipient: recipient,
        message: message,
      );
    } catch (_) {
      return const _AlertsSettings();
    }
  }

  static Future<Map<String, String>> _loadSentState(SharedPreferences prefs) async {
    final raw = prefs.getString(prefsSentStateKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
      }
    } catch (_) {}
    return <String, String>{};
  }

  static Future<void> _saveSentState(SharedPreferences prefs, Map<String, String> state) async {
    await prefs.setString(prefsSentStateKey, jsonEncode(state));
  }

  static Future<void> _sendTextToStudent({
    required String? workspaceId,
    required StudentModel student,
    required AlertsChannel channel,
    required AlertsRecipient recipient,
    required String message,
  }) async {
    final targets = <AlertsRecipient>[];
    if (recipient == AlertsRecipient.both) {
      targets.addAll([AlertsRecipient.student, AlertsRecipient.parent]);
    } else {
      targets.add(recipient);
    }

    for (final tgt in targets) {
      if (channel == AlertsChannel.telegram || channel == AlertsChannel.both) {
        final chatId = await _getTelegramChatIdForStudent(
          workspaceId: workspaceId,
          student: student,
          recipient: tgt,
        );
        if (chatId != null) {
          await BotApiService.sendTelegramText(chatId: chatId, text: message);
        }
      }

      if (channel == AlertsChannel.email || channel == AlertsChannel.both) {
        final emails = _getEmailsForRecipient(student, tgt);
        for (final e in emails) {
          await EmailService.sendTextOnlyEmail(
            recipientEmail: e,
            subject: 'إنذار غياب',
            message: message,
          );
        }
      }
    }
  }

  static List<String> _getEmailsForRecipient(StudentModel student, AlertsRecipient recipient) {
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

  static Future<int?> _getTelegramChatIdForStudent({
    required String? workspaceId,
    required StudentModel student,
    required AlertsRecipient recipient,
  }) async {
    try {
      final studentsCol = (workspaceId != null && workspaceId.trim().isNotEmpty)
          ? FirebaseFirestore.instance.collection('workspaces').doc(workspaceId).collection('students')
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
        // Fallbacks: Firestore data may store the student id in fields like
        // local_id / student_id (sometimes numeric) and keep phone null.
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

          if (data == null && sidInt != null) {
            try {
              final qsNumeric = await studentsCol.where('id', isEqualTo: sidInt).limit(1).get();
              if (qsNumeric.docs.isNotEmpty) {
                data = qsNumeric.docs.first.data();
              }
            } catch (_) {}
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
      if (raw is int) return raw;
      return int.tryParse(raw.toString());
    } catch (_) {
      return null;
    }
  }

  static Future<_AlertsData> _computeAlerts({
    required DatabaseHelper dbHelper,
    required ClassModel classModel,
  }) async {
    final classId = classModel.id;
    if (classId == null) return const _AlertsData();

    final students = await dbHelper.getStudentsByClass(classId);
    final studentById = {for (final s in students) if (s.id != null) s.id!: s};
    final studentIds = studentById.keys.toList();

    final db = await dbHelper.database;

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

    final attendanceRows = await db.rawQuery(
      '''
      SELECT a.student_id, a.lecture_id, a.status
      FROM attendance a
      WHERE a.student_id IN (${studentIds.isEmpty ? 'NULL' : List.filled(studentIds.length, '?').join(',')})
        AND a.lecture_id IN (${lectures.isEmpty ? 'NULL' : List.filled(lectures.length, '?').join(',')})
      ''',
      [...studentIds, ...lectures.map((l) => (l['id'] is int) ? l['id'] as int : int.tryParse(l['id']?.toString() ?? '') ?? 0)],
    );

    final lectureAbsent = <int, Set<int>>{};
    final lectureAbsentTotal = <int, int>{};
    for (final r in attendanceRows) {
      final sid = (r['student_id'] is int) ? r['student_id'] as int : int.tryParse(r['student_id']?.toString() ?? '') ?? 0;
      final lid = (r['lecture_id'] is int) ? r['lecture_id'] as int : int.tryParse(r['lecture_id']?.toString() ?? '') ?? 0;
      final status = (r['status'] is num) ? (r['status'] as num).toInt() : int.tryParse(r['status']?.toString() ?? '') ?? 0;
      if (sid <= 0 || lid <= 0) continue;
      if (status == 1) {
        lectureAbsent.putIfAbsent(sid, () => <int>{}).add(lid);
        lectureAbsentTotal[sid] = (lectureAbsentTotal[sid] ?? 0) + 1;
      }
    }

    final gradeRows = await db.rawQuery(
      '''
      SELECT g.student_id, g.exam_name, g.exam_date, g.status, g.notes
      FROM grades g
      WHERE g.student_id IN (${studentIds.isEmpty ? 'NULL' : List.filled(studentIds.length, '?').join(',')})
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

    final examAbsentByTitle = <int, Set<String>>{};
    final examAbsentTotal = <int, int>{};

    for (final g in gradeRows) {
      final sid = (g['student_id'] is int) ? g['student_id'] as int : int.tryParse(g['student_id']?.toString() ?? '') ?? 0;
      if (sid <= 0) continue;
      if (!isExamAbsent(g)) continue;
      final title = g['exam_name']?.toString() ?? '';
      if (title.trim().isEmpty) continue;
      examAbsentByTitle.putIfAbsent(sid, () => <String>{}).add(title);
      examAbsentTotal[sid] = (examAbsentTotal[sid] ?? 0) + 1;
    }

    final consecutive = <_ConsecutiveAlertRow>[];
    for (final sid in studentIds) {
      final s = studentById[sid];
      if (s == null) continue;

      int streak = 0;
      final streakLectures = <String>[];
      final streakExams = <String>[];

      for (final ev in events) {
        final absent = ev.type == _EventType.lecture
            ? (lectureAbsent[sid]?.contains(ev.id) ?? false)
            : (examAbsentByTitle[sid]?.contains(ev.title) ?? false);

        if (absent) {
          streak++;
          if (ev.type == _EventType.lecture) {
            streakLectures.add(ev.title);
          } else {
            streakExams.add(ev.title);
          }
        } else {
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
        consecutive.add(
          _ConsecutiveAlertRow(
            student: s,
            signature: 'c3|${streakLectures.join(',')}|${streakExams.join(',')}',
            totalAbsences: totalAbs,
          ),
        );
      }
    }

    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 30));

    final lectureIdsInWindow = <int>[];
    for (final l in lectures) {
      final id = (l['id'] is int) ? l['id'] as int : int.tryParse(l['id']?.toString() ?? '') ?? 0;
      final dt = DateTime.tryParse(l['date']?.toString() ?? '') ?? DateTime(1970);
      if (id > 0 && !dt.isBefore(DateTime(from.year, from.month, from.day)) && !dt.isAfter(DateTime(now.year, now.month, now.day))) {
        lectureIdsInWindow.add(id);
      }
    }

    final monthly = <_MonthlyAlertRow>[];
    for (final sid in studentIds) {
      final s = studentById[sid];
      if (s == null) continue;

      int count = 0;

      final absLectIds = lectureAbsent[sid] ?? <int>{};
      for (final lid in lectureIdsInWindow) {
        if (absLectIds.contains(lid)) {
          count++;
        }
      }

      for (final g in gradeRows) {
        final gsid = (g['student_id'] is int) ? g['student_id'] as int : int.tryParse(g['student_id']?.toString() ?? '') ?? 0;
        if (gsid != sid) continue;
        if (!isExamAbsent(g)) continue;
        final dt = DateTime.tryParse(g['exam_date']?.toString() ?? '') ?? DateTime(1970);
        if (dt.isBefore(DateTime(from.year, from.month, from.day)) || dt.isAfter(DateTime(now.year, now.month, now.day))) continue;
        count++;
      }

      if (count >= 6) {
        monthly.add(
          _MonthlyAlertRow(
            student: s,
            signature: 'm6|$count|${DateTime(now.year, now.month, now.day).toIso8601String()}',
            absencesLast30Days: count,
          ),
        );
      }
    }

    consecutive.sort((a, b) => b.totalAbsences.compareTo(a.totalAbsences));
    monthly.sort((a, b) => b.absencesLast30Days.compareTo(a.absencesLast30Days));

    return _AlertsData(consecutiveRows: consecutive, monthlyRows: monthly);
  }
}

@immutable
class _AlertsSettings {
  final AlertsSendMode? mode;
  final AlertsChannel? channel;
  final AlertsRecipient? recipient;
  final String? message;

  const _AlertsSettings({
    this.mode,
    this.channel,
    this.recipient,
    this.message,
  });
}

@immutable
class _AlertsData {
  final List<_ConsecutiveAlertRow> consecutiveRows;
  final List<_MonthlyAlertRow> monthlyRows;

  const _AlertsData({
    this.consecutiveRows = const [],
    this.monthlyRows = const [],
  });
}

enum _EventType { lecture, exam }

@immutable
class _ClassEvent {
  final _EventType type;
  final int id;
  final String title;
  final DateTime date;

  const _ClassEvent({
    required this.type,
    required this.id,
    required this.title,
    required this.date,
  });
}

@immutable
class _ConsecutiveAlertRow {
  final StudentModel student;
  final int totalAbsences;
  final String signature;

  const _ConsecutiveAlertRow({
    required this.student,
    required this.totalAbsences,
    required this.signature,
  });
}

@immutable
class _MonthlyAlertRow {
  final StudentModel student;
  final int absencesLast30Days;
  final String signature;

  const _MonthlyAlertRow({
    required this.student,
    required this.absencesLast30Days,
    required this.signature,
  });
}

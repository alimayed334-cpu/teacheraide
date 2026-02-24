import 'dart:core';
import 'dart:core' as core;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../models/student_model.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../models/lecture_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/note_model.dart';
import '../../database/database_helper.dart';
import '../exports/export_files_screen.dart';
import '../../theme/app_theme.dart';
import '../../models/email_service.dart';
import '../../utils/file_attachment_helper.dart';
import 'financial_exports_helper.dart';
import '../../providers/auth_provider.dart';
import '../../models/assignment_model.dart';
import '../../models/assignment_student_model.dart';
import '../../services/bot_api_service.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({Key? key}) : super(key: key);

  @override
  _MessagingScreenState createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  final TextEditingController _messageController = TextEditingController();
  String? _selectedFile;
  String? _selectedFilePath;
  String? _selectedRecipient;
  String? _selectedMethod;
  ClassModel? _selectedClass;
  core.List<StudentModel> _students = [];
  core.List<StudentModel> _filteredStudents = [];
  Set<String> _selectedStudents = {};
  SortOption _sortOption = SortOption.none;
  final TextEditingController _searchController = TextEditingController();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final FinancialExportsHelper _financialHelper = FinancialExportsHelper();
  core.List<Map<String, dynamic>> _telegramGroups = [];
  Set<String> _selectedTelegramGroupIds = {};
  bool _telegramGroupsLoading = false;
  bool _deviceAttachmentSelected = false;
  
  // مسار الملف المُصدّر
  String? _exportedFilePath;

  bool _allDates = true;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _isDateInRange(DateTime date) {
    if (_allDates) return true;
    if (_startDate != null && date.isBefore(_startDate!)) return false;
    if (_endDate != null) {
      final endInclusive = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59, 999);
      if (date.isAfter(endInclusive)) return false;
    }

    return true;
  }

  String _telegramChatIdCacheKey({required String? workspaceId, required StudentModel student}) {
    final ws = (workspaceId ?? '').trim().isEmpty ? 'default' : workspaceId!.trim();
    final sid = student.id?.toString() ?? '';
    final recipientKey = (_selectedRecipient == 'student') ? 'student' : 'parent';
    return 'tg_chat_id_v1|$ws|$recipientKey|$sid';
  }

  Future<String?> _createCombinedSelectedStudentsFile(core.List<StudentModel> students) async {
    if (_selectedClass == null) return null;
    if (_selectedFile == null || _selectedFile == 'لا يوجد ملف') return null;
    if (students.isEmpty) return null;

    try {
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final className = _selectedClass!.name;

      switch (_selectedFile) {
        case 'معلومات الطالب':
          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                        pw.SizedBox(height: 4),
                        pw.Text('معلومات الطلاب', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('رقم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الإيميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('اسم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('رقم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('إيميل ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                        ],
                      ),
                      ...students.map((student) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.phone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.email ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.primaryGuardian?.name ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.primaryGuardian?.phone ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.primaryGuardian?.email ?? student.parentEmail ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'ملخص الحضور':
          final allLectures = await _dbHelper.getLecturesByClass(_selectedClass!.id!);
          final lectures = allLectures.where((l) => _isDateInRange(l.date)).toList();
          if (lectures.isEmpty) return null;

          final Map<int, Map<String, int>> attendanceStats = {};
          for (final s in students) {
            int present = 0, absent = 0, late = 0, expelled = 0, excused = 0;
            for (final lecture in lectures) {
              final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
                studentId: s.id!,
                lectureId: lecture.id!,
              );

              if (attendance != null) {
                switch (attendance.status) {
                  case AttendanceStatus.present:
                    present++;
                    break;
                  case AttendanceStatus.absent:
                    absent++;
                    break;
                  case AttendanceStatus.late:
                    late++;
                    break;
                  case AttendanceStatus.expelled:
                    expelled++;
                    break;
                  case AttendanceStatus.excused:
                    excused++;
                    break;
                }
              }
            }

            attendanceStats[s.id!] = {
              'present': present,
              'absent': absent,
              'late': late,
              'expelled': expelled,
              'excused': excused,
              'total': lectures.length,
            };
          }

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                        pw.SizedBox(height: 4),
                        pw.Text('ملخص الحضور', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('عدد المحاضرات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الحضور', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الغياب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('التأخر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('مجاز', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الطرد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('النسبة %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                        ],
                      ),
                      ...students.map((student) {
                        final stats = attendanceStats[student.id!]!;
                        final percentage = stats['total']! > 0
                            ? ((stats['present']! / stats['total']!) * 100).round()
                            : 0;
                        return pw.TableRow(
                          children: [
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['total']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['present']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['absent']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['late']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['excused']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${stats['expelled']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                            pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$percentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        default:
          return null;
      }

      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedFile}_selected_students.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (_) {
      return null;
    }
  }

  String _assignmentStatusLabel(String raw) {
    switch (raw.trim()) {
      case 'completed':
        return 'مكتمل';
      case 'incomplete':
        return 'غير مكتمل';
      case 'deficient':
        return 'ناقص';
      case 'excluded':
        return 'غير مشمول';
      case 'pending':
      default:
        return 'انتظار';
    }
  }

  Future<String?> _exportStudentAssignmentsForStudent(StudentModel student) async {
    if (_selectedClass == null) return null;
    if (student.id == null) return null;

    try {
      final classId = _selectedClass!.id!;

      final allAssignments = await _dbHelper.getAssignmentsByClass(classId);
      final assignments = allAssignments.where((a) => _isDateInRange(a.dueDate)).toList();
      if (assignments.isEmpty) return null;

      final statuses = await _dbHelper.getAssignmentStudentStatusesByClass(classId);
      final statusByAssignment = <int, AssignmentStudentModel>{};
      for (final s in statuses) {
        if (s.studentId == student.id && s.assignmentId != null) {
          statusByAssignment[s.assignmentId!] = s;
        }
      }

      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final className = _selectedClass!.name;

      final rows = <pw.TableRow>[
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue),
          children: [
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الواجب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('السبب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المطلوب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المنفذ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
            pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('الحالة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
          ],
        ),
      ];

      for (final a in assignments.where((x) => x.id != null)) {
        final aid = a.id!;
        final s = statusByAssignment[aid];
        final statusRaw = (s?.status ?? 'pending').toString();
        final done = s?.doneCount ?? 0;
        final required = a.requiredCount ?? 0;
        rows.add(
          pw.TableRow(
            children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(a.title, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text((a.reason ?? '-').toString(), style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(required.toString(), style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(done.toString(), style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(_assignmentStatusLabel(statusRaw), style: pw.TextStyle(font: ttfBold, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
            ],
          ),
        );
      }

      pdf.addPage(
        pw.MultiPage(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(color: PdfColors.amber100, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Column(
                  children: [
                    pw.Text(className, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                    pw.SizedBox(height: 4),
                    pw.Text('واجبات الطالب: ${student.name}', style: pw.TextStyle(fontSize: 14, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                    if (!_allDates) ...[
                      pw.SizedBox(height: 4),
                      pw.Text('من ${_startDate?.day ?? '-'} / ${_startDate?.month ?? '-'} / ${_startDate?.year ?? '-'} إلى ${_endDate?.day ?? '-'} / ${_endDate?.month ?? '-'} / ${_endDate?.year ?? '-'}', style: pw.TextStyle(fontSize: 11, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: rows),
            ];
          },
        ),
      );

      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${className}_واجبات_${student.name}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate != null && _endDate!.isBefore(_startDate!)) {
        _endDate = _startDate;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? (_startDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _endDate = picked;
      if (_startDate != null && _endDate!.isBefore(_startDate!)) {
        _startDate = _endDate;
      }
    });
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'غير محدد';
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickFileFromDevice() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: false);
      if (!mounted) return;
      if (res == null || res.files.isEmpty) return;

      final path = res.files.single.path;
      if (path == null || path.trim().isEmpty) return;

      final name = res.files.single.name;
      setState(() {
        _selectedFile = name.isNotEmpty ? name : 'ملف من الجهاز';
        _selectedFilePath = null;
        _exportedFilePath = path;
        _deviceAttachmentSelected = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم اختيار ملف من الجهاز'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر اختيار الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleSelectAllStudents() {
    setState(() {
      final ids = _students.map((s) => s.id?.toString()).whereType<String>().toList();
      final allSelected = ids.isNotEmpty && ids.every(_selectedStudents.contains);
      if (allSelected) {
        _selectedStudents.clear();
      } else {
        _selectedStudents = ids.toSet();
      }
    });
  }

  String _normalizePhoneE164(String input, {String defaultCountryCode = '+964'}) {
    final raw = input.trim();
    if (raw.isEmpty) return '';

    final hasPlus = raw.startsWith('+');
    final digitsOnly = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return '';

    if (hasPlus) {
      return '+$digitsOnly';
    }

    // Remove leading zeros
    var local = digitsOnly;
    while (local.startsWith('0')) {
      local = local.substring(1);
    }

    final ccDigits = defaultCountryCode.replaceAll('+', '');
    if (local.startsWith(ccDigits)) {
      return '+$local';
    }

    return '$defaultCountryCode$local';
  }

  String _phoneForWhatsapp(String input, {String defaultCountryCode = '+964'}) {
    final e164 = _normalizePhoneE164(input, defaultCountryCode: defaultCountryCode);
    if (e164.isEmpty) return '';
    return e164.replaceAll('+', '');
  }

  String _normalizePhoneDigitsForLookup(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0') && digits.length == 11) {
      final withoutZero = digits.substring(1);
      if (withoutZero.startsWith('7')) {
        return '964$withoutZero';
      }
    }
    return digits;
  }

  Future<ExamModel?> _resolveExamForGrade(GradeModel grade) async {
    // exam_name is not consistent across the app (sometimes title, sometimes id stored as string)
    final byId = int.tryParse(grade.examName);
    if (byId != null) {
      return _dbHelper.getExam(byId);
    }

    try {
      final db = await _dbHelper.database;
      final dateKey = grade.examDate.toIso8601String().split('T')[0];
      final maps = await db.query(
        'exams',
        where: 'title = ? AND date = ?',
        whereArgs: [grade.examName, dateKey],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ExamModel.fromMap(maps.first);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _launchExternalApp(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<String?> _uploadFileToTempSh(File file) async {
    try {
      if (!await file.exists()) return null;

      final req = http.MultipartRequest(
        'POST',
        Uri.parse('https://temp.sh/upload'),
      );

      req.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: file.path.split(Platform.pathSeparator).last,
      ));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return null;
      }

      final body = resp.body.trim();
      if (body.startsWith('http')) return body;
      return null;
    } catch (_) {
      return null;
    }
  }
  
  // متغيرات جديدة للإيميل التلقائي
  Map<String, FileInfo> _studentFiles = {}; // لكل طالب ملفه الخاص
  core.List<FileInfo> _availableAppFiles = [];
  bool _isEmailMode = false;
  bool _sendingEmails = false;
  
  // خيارات الملفات المتاحة للتصدير (نفسها من صفحة التصدير)
  final core.List<String> _availableFiles = [
    'لا يوجد ملف',
    'معلومات الطالب',
    'ملخص الحضور',
    'الحضور التفصيلي',
    'حضور الامتحانات',
    'الامتحانات',
    'الدرجة النهائية',
    'ملخص الطالب',
    'واجبات الطالب',
    'المعلومات المالية',
    'الطلاب المتأخرين بالدفع',
    'سجل الدفعات',
  ];

  @override
  void initState() {
    super.initState();
    _loadAvailableFiles();
    _searchController.addListener(_filterStudents);
    
    // Delay _loadData() to avoid setState during build error
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when returning to this screen - but avoid multiple calls
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_selectedClass != null && mounted) {
        _loadStudents();
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // إنشاء الملف مباشرة عند الاختيار
  Future<void> _createFileDirectly(String fileType) async {
    if (fileType == 'لا يوجد ملف') {
      setState(() {
        _selectedFile = 'لا يوجد ملف';
        _selectedFilePath = null;
        _exportedFilePath = null;
        _deviceAttachmentSelected = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('سيتم إرسال الرسالة بدون ملف'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    if (fileType == 'إضافة ملف من الجهاز') {
      await _pickFileFromDevice();
      return;
    }

    try {
      setState(() {
        _selectedFile = fileType;
        _selectedFilePath = null;
        _deviceAttachmentSelected = false;
      });

      final studentSpecificTypes = <String>{
        'الحضور التفصيلي',
        'حضور الامتحانات',
        'الامتحانات',
        'الدرجة النهائية',
        'ملخص الطالب',
        'واجبات الطالب',
        'البيانات المالية',
        'الطلاب المتأخرين بالدفع',
        'سجل الدفعات',
      };

      String? filePath;
      switch (fileType) {
        case 'معلومات الطالب':
          filePath = await _exportStudentInfo();
          break;
        case 'ملخص الحضور':
          filePath = await _exportAttendanceSummary();
          break;
        case 'ملاحظات الفصول':
          filePath = await _exportClassNotes();
          break;
        case 'ملخص الطالب':
        case 'الحضور التفصيلي':
        case 'حضور الامتحانات':
        case 'الامتحانات':
        case 'الدرجة النهائية':
        case 'واجبات الطالب':
        case 'البيانات المالية':
        case 'الطلاب المتأخرين بالدفع':
        case 'سجل الدفعات':
          // Student-specific exports need selecting exactly one student.
          if (studentSpecificTypes.contains(fileType)) {
            if (_selectedStudents.length != 1) {
              _showErrorDialog('يرجى اختيار طالب واحد لإنشاء هذا الملف');
              return;
            }

            final selectedIdStr = _selectedStudents.first;
            StudentModel? selectedStudent;
            try {
              selectedStudent = _students.firstWhere((s) => (s.id?.toString() ?? '') == selectedIdStr);
            } catch (_) {
              selectedStudent = null;
            }

            if (selectedStudent == null) {
              _showErrorDialog('تعذر تحديد الطالب المختار');
              return;
            }

            filePath = await _createStudentSpecificFile(selectedStudent);
            break;
          }
          break;
      }

      if (filePath != null) {
        setState(() {
          _selectedFilePath = filePath;
          _exportedFilePath = filePath;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إنشاء ملف: $fileType'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _selectedFile = null;
          _selectedFilePath = null;
          _exportedFilePath = null;
        });
      }
    } catch (e) {
      setState(() {
        _selectedFile = null;
        _selectedFilePath = null;
        _exportedFilePath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إنشاء الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // استيراد دوال التصدير من صفحة التصدير الأصلية
  // سيتم استخدام نفس الدوال بالضبط من صفحة export_files_screen.dart
  
  Future<String?> _exportAttendanceSummary() async {
    if (_selectedClass == null) return null;

    try {
      final students = await _dbHelper.getStudentsByClass(_selectedClass!.id!);
      if (students.isEmpty) return null;

      final allLectures = await _dbHelper.getLecturesByClass(_selectedClass!.id!);
      final lectures = allLectures.where((l) => _isDateInRange(l.date)).toList();
      if (lectures.isEmpty) return null;

      // حساب إحصائيات الحضور لكل طالب
      Map<int, Map<String, int>> attendanceStats = {};

      for (var student in students) {
        int present = 0, absent = 0, late = 0, expelled = 0, excused = 0;

        for (var lecture in lectures) {
          final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
            studentId: student.id!,
            lectureId: lecture.id!,
          );

          if (attendance != null) {
            switch (attendance.status) {
              case AttendanceStatus.present:
                present++;
                break;
              case AttendanceStatus.absent:
                absent++;
                break;
              case AttendanceStatus.late:
                late++;
                break;
              case AttendanceStatus.expelled:
                expelled++;
                break;
              case AttendanceStatus.excused:
                excused++;
                break;
            }
          }
        }

        attendanceStats[student.id!] = {
          'present': present,
          'absent': absent,
          'late': late,
          'expelled': expelled,
          'excused': excused,
          'total': lectures.length,
        };
      }
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final className = _selectedClass!.name;

      pdf.addPage(
        pw.MultiPage(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              // العنوان
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      className,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'ملخص الحضور',
                      style: pw.TextStyle(fontSize: 18, font: ttf),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // جدول الطلاب
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey),
                children: [
                  // رأس الجدول
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('عدد المحاضرات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الحضور', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الغياب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('التأخر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('مجاز', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الطرد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('النسبة %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  // بيانات الطلاب
                  ...students.map((student) {
                    final stats = attendanceStats[student.id!]!;
                    final percentage = stats['total']! > 0
                        ? ((stats['present']! / stats['total']!) * 100).round()
                        : 0;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['total']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['present']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['absent']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['late']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['excused']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['expelled']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$percentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ];
          },
        ),
      );

      // حفظ الملف
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${className}_ملخص_الحضور.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      return file.path;
    } catch (e) {
      print('Error exporting attendance summary: $e');
      return null;
    }
  }

  // دالة تصدير معلومات الطالب
  Future<String?> _exportStudentInfo() async {
    if (_selectedClass == null) return null;

    try {
      final students = await _dbHelper.getStudentsByClass(_selectedClass!.id!);
      if (students.isEmpty) return null;

      // تحميل الخطوط العربية
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();

      final pdf = pw.Document();
      final className = _selectedClass!.name;
      
      pdf.addPage(
        pw.MultiPage(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              // العنوان
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      className,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'معلومات الطلاب',
                      style: pw.TextStyle(fontSize: 18, font: ttf),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // جدول ملخص الحضور
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey),
                children: [
                  // رأس الجدول
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('رقم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الإيميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('رقم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('إيميل ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  // بيانات الطلاب
                  ...students.map((student) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.phone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.email ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.primaryGuardian?.name ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.primaryGuardian?.phone ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.primaryGuardian?.email ?? student.parentEmail ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ];
          },
        ),
      );

      // حفظ الملف
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${className}_معلومات_الطلاب.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      return file.path;
    } catch (e) {
      print('Error exporting attendance summary: $e');
      return null;
    }
  }

  // دالة تصدير الحضور التفصيلية (مبسطة)
  Future<String?> _exportAttendanceDetailed() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_الحضور_التفصيلي.pdf';
      final file = File('${directory.path}/$fileName');
      
      // إنشاء PDF بسيط للحضور التفصيلي
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.purple),
              child: pw.Text(
                'الحضور التفصيلي: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'تم إنشاء هذا التقرير في ${DateTime.now().toString().split(' ')[0]}',
              style: pw.TextStyle(font: ttf, fontSize: 12),
              textDirection: pw.TextDirection.rtl,
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting detailed attendance: $e');
      return null;
    }
  }

  Future<String?> _exportExamAttendance() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_حضور_الامتحانات.pdf';
      final file = File('${directory.path}/$fileName');
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.deepPurple),
              child: pw.Text(
                'حضور الامتحانات: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting exam attendance: $e');
      return null;
    }
  }

  Future<String?> _exportExams() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_الامتحانات.pdf';
      final file = File('${directory.path}/$fileName');
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.green),
              child: pw.Text(
                'تقرير الامتحانات: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting exams: $e');
      return null;
    }
  }

  Future<String?> _exportFinalGrades() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_الدرجة_النهائية.pdf';
      final file = File('${directory.path}/$fileName');
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.teal),
              child: pw.Text(
                'الدرجة النهائية: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting final grades: $e');
      return null;
    }
  }

  Future<String?> _exportStudentSummary() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_ملخص_الطالب.pdf';
      final file = File('${directory.path}/$fileName');
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.pink),
              child: pw.Text(
                'ملخص الطالب: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting student summary: $e');
      return null;
    }
  }

  Future<String?> _exportClassNotes() async {
    if (_selectedClass == null) return null;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedClass!.name}_ملاحظات_الفصل.pdf';
      final file = File('${directory.path}/$fileName');
      
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      
      pdf.addPage(pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.indigo),
              child: pw.Text(
                'ملاحظات الفصل: ${_selectedClass!.name}',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  font: ttfBold,
                  color: PdfColors.white,
                ),
                textAlign: pw.TextAlign.center,
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          ],
        ),
      ));
      
      await file.writeAsBytes(await pdf.save());
      return file.path;
    } catch (e) {
      print('Error exporting class notes: $e');
      return null;
    }
  }

  Future<void> _loadData() async {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    await classProvider.loadClasses();
    
    if (classProvider.classes.isNotEmpty && _selectedClass == null) {
      setState(() {
        _selectedClass = classProvider.classes.first;
      });
      await _loadStudents();
    }
  }

  // تحميل الملفات المتاحة من التطبيق
  Future<void> _loadAvailableFiles() async {
    try {
      final files = await FileAttachmentHelper.getAllReports();
      
      setState(() {
        _availableAppFiles = files;
      });
    } catch (e) {
      print('Error loading available files: $e');
    }
  }

  Future<void> _loadStudents() async {
    if (_selectedClass == null) return;
    
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    if (_selectedClass!.id != null) {
      await studentProvider.loadStudentsByClass(_selectedClass!.id!);
    }
    
    // Update students list
    setState(() {
      _students = studentProvider.students;
    });
    
    // Calculate statistics for each student
    for (var student in _students) {
      await _calculateStudentStatistics(student);
    }
    
    // Update filtered students after statistics are calculated
    setState(() {
      _filteredStudents = core.List.from(_students);
      _sortStudents();
    });
  }

  Future<void> _calculateStudentStatistics(StudentModel student) async {
    final dbHelper = DatabaseHelper();
    final db = await dbHelper.database;
    
    // جلب بيانات الحضور من جدول attendance - نفس الطريقة المستخدمة في صفحة الحضور
    final int? classId = _selectedClass?.id;
    final core.List<Map<String, Object?>> attendanceData;
    if (classId == null) {
      attendanceData = await db.query(
        'attendance',
        where: 'student_id = ?',
        whereArgs: [student.id],
      );
    } else {
      attendanceData = await db.rawQuery(
        '''
        SELECT a.status
        FROM attendance a
        LEFT JOIN lectures l ON a.lecture_id = l.id
        WHERE a.student_id = ?
          AND (
            (a.lecture_id IS NOT NULL AND l.class_id = ?)
            OR
            (a.lecture_id IS NULL AND EXISTS (
              SELECT 1 FROM lectures l2
              WHERE l2.class_id = ? AND date(l2.date) = a.date
            ))
          )
        ''',
        [student.id, classId, classId],
      );
    }
    
    // جلب بيانات الدرجات من جدول grades مع ربط بجدول exams - نفس الطريقة المستخدمة في صفحة الامتحانات
    final gradesData = await db.rawQuery(''' 
      SELECT g.*, e.max_score, e.title as exam_title
      FROM grades g
      LEFT JOIN exams e ON g.exam_name = e.title
      WHERE g.student_id = ?
    ''', [student.id]);
    
    // حساب إحصائيات الحضور - مطابق لصفحة الحضور
    int attendedLectures = 0;
    int absentLectures = 0;
    int excusedLectures = 0;
    int expelledLectures = 0;
    
    for (final attendance in attendanceData) {
      final status = (attendance['status'] as num?)?.toInt() ?? 0;
      if (status == AttendanceStatus.present.index || status == AttendanceStatus.late.index) {
        attendedLectures++;
      } else if (status == AttendanceStatus.absent.index) {
        absentLectures++;
      } else if (status == AttendanceStatus.excused.index) {
        excusedLectures++;
      } else if (status == AttendanceStatus.expelled.index) {
        expelledLectures++;
      }
    }
    
    // حساب إحصائيات الامتحانات والدرجات - مطابق لصفحة الامتحانات
    int attendedExams = 0;
    int absentExams = 0;
    int exemptOrPostponedExams = 0;
    int cheatingCount = 0;
    int missingCount = 0;
    double totalGrades = 0;
    int gradeCount = 0;
    double totalMaxScore = 0;
    for (final grade in gradesData) {
      final status = grade['status']?.toString();
      final notes = grade['notes']?.toString() ?? '';

      // Check status first, then fallback to notes if status is null
      String finalStatus = 'حاضر'; // default

      if (status != null && status.isNotEmpty) {
        finalStatus = status;
      } else if (notes.isNotEmpty) {
        // Check notes for status information
        if (notes.contains('غش')) {
          finalStatus = 'غش';
        } else if (notes.contains('مفقود') || notes.contains('مفقودة')) {
          finalStatus = 'مفقود';
        } else if (notes.contains('غائب')) {
          finalStatus = 'غائب';
        }
      }

      // المعفئ/المؤجل لا يدخل في المعدل ولا حاضر/غائب، لكن نُظهره كإحصائية منفصلة
      if (finalStatus == 'معفئ' || finalStatus == 'مؤجل' || finalStatus == 'معفئ او مؤجل') {
        exemptOrPostponedExams++;
        continue;
      }
      
      if (finalStatus == 'غائب') {
        absentExams++;
      } else if (finalStatus == 'حاضر') {
        attendedExams++;
        if (grade['score'] != null) {
          totalGrades += (grade['score'] as num).toDouble();
          gradeCount++;
        }
        if (grade['max_score'] != null) {
          totalMaxScore += (grade['max_score'] as num).toDouble();
        }
      } else if (finalStatus == 'غش') {
        cheatingCount++;
      } else if (finalStatus == 'مفقود') {
        missingCount++;
      }
    }
    
    final totalSessions = attendedLectures + absentLectures + excusedLectures + expelledLectures;
    final absencePercentage = totalSessions > 0
        ? ((absentLectures + expelledLectures) / totalSessions) * 100
        : 0.0;
    
    // حساب المعدل الحقيقي كنسبة مئوية - نفس طريقة صفحة الامتحانات
    double averagePercentage = 0.0;
    if (totalMaxScore > 0) {
      averagePercentage = (totalGrades / totalMaxScore) * 100;
    }
    
    // Update student statistics
    final updatedStudent = student.copyWith(
      averageGrade: averagePercentage,
      attendedLectures: attendedLectures,
      absentLectures: absentLectures,
      excusedLectures: excusedLectures,
      expelledLectures: expelledLectures,
      absencePercentage: absencePercentage,
      attendedExams: attendedExams,
      absentExams: absentExams,
      exemptOrPostponedExams: exemptOrPostponedExams,
      cheatingCount: cheatingCount,
      missingCount: missingCount,
    );
    
    // Update student in list and trigger UI update
    final index = _students.indexWhere((s) => s.id == student.id);
    if (index != -1) {
      setState(() {
        _students[index] = updatedStudent;
        // Re-filter and re-sort to ensure UI updates
        _filterStudents();
      });
    }
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStudents = _students.where((student) {
        return student.name.toLowerCase().contains(query) ||
               (student.studentId?.toLowerCase().contains(query) ?? false);
      }).toList();
      _sortStudents();
    });
  }

  void _sortStudents() {
    switch (_sortOption) {
      case SortOption.highestAverage:
        _filteredStudents.sort((a, b) => (b.averageGrade ?? 0).compareTo(a.averageGrade ?? 0));
        break;
      case SortOption.lowestAverage:
        _filteredStudents.sort((a, b) => (a.averageGrade ?? 0).compareTo(b.averageGrade ?? 0));
        break;
      case SortOption.highestAbsence:
        _filteredStudents.sort((a, b) => (b.absencePercentage ?? 0).compareTo(a.absencePercentage ?? 0));
        break;
      case SortOption.none:
        _filteredStudents.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
  }

  void _toggleStudentSelection(String studentId) {
    setState(() {
      if (_selectedStudents.contains(studentId)) {
        _selectedStudents.remove(studentId);
      } else {
        _selectedStudents.add(studentId);
      }
    });
  }

  // تحديث دالة الإرسال الرئيسية
  Future<void> _sendMessage() async {
    if (_selectedMethod == null) {
      _showErrorDialog('الرجاء اختيار طريقة الإرسال');
      return;
    }

    final isTelegramGroup = _selectedMethod == 'telegram' && _selectedRecipient == 'group';
    if (!isTelegramGroup && _selectedStudents.isEmpty) {
      _showErrorDialog('الرجاء اختيار طالب واحد على الأقل');
      return;
    }

    if (isTelegramGroup && _selectedTelegramGroupIds.isEmpty) {
      _showErrorDialog('الرجاء اختيار كروب واحد على الأقل');
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      _showErrorDialog('الرجاء كتابة الرسالة');
      return;
    }

    // إذا كانت طريقة الإيميل
    if (_selectedMethod == 'email') {
      await _sendEmails();
    } else {
      // الطرق الأخرى الحالية
      switch (_selectedMethod) {
        case 'sms':
          await _sendSMS();
          break;
        case 'whatsapp':
          await _sendWhatsApp();
          break;
        case 'telegram':
          await _sendTelegram();
          break;
      }
    }
  }

  Future<void> _ensureTelegramGroupsLoaded() async {
    if (_telegramGroupsLoading) return;
    setState(() {
      _telegramGroupsLoading = true;
    });
    try {
      final list = await BotApiService.getTelegramGroups();
      if (!mounted) return;
      setState(() {
        _telegramGroups = list;
      });
    } finally {
      if (mounted) {
        setState(() {
          _telegramGroupsLoading = false;
        });
      }
    }
  }

  void _toggleTelegramGroupSelection(String chatId) {
    setState(() {
      if (_selectedTelegramGroupIds.contains(chatId)) {
        _selectedTelegramGroupIds.remove(chatId);
      } else {
        _selectedTelegramGroupIds.add(chatId);
      }
    });
  }

  Future<int?> _getTelegramChatIdForStudent(StudentModel student) async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final ws = auth.workspaceId;

      // Local cache first (prevents intermittent false "not linked")
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getInt(_telegramChatIdCacheKey(workspaceId: ws, student: student));
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
          final qs = await studentsCol
              .where('phone', isEqualTo: phone)
              .limit(1)
              .get();
          if (qs.docs.isNotEmpty) {
            data = qs.docs.first.data();
          }
        }
      }

      if (data == null) return null;

      final field = (_selectedRecipient == 'student') ? 'telegram_student_chat_id' : 'telegram_parent_chat_id';
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
          await prefs.setInt(_telegramChatIdCacheKey(workspaceId: ws, student: student), parsed);
        } catch (_) {}
      }
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendTelegram() async {
    try {
      final messageText = _messageController.text.trim();
      final isGroup = _selectedRecipient == 'group';

      if (isGroup) {
        final groupIds = _selectedTelegramGroupIds.toList();
        for (final gid in groupIds) {
          final chatId = int.tryParse(gid);
          if (chatId == null) continue;
          await _sendTelegramToChat(chatId, messageText, isGroup: true);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الإرسال عبر تيليجرام'), backgroundColor: Colors.green),
          );
        }
        return;
      }

      int sentCount = 0;
      int totalCount = _selectedStudents.length;
      final missing = <String>[];
      for (final studentId in _selectedStudents) {
        final student = _students.firstWhere((s) => s.id.toString() == studentId);
        final chatId = await _getTelegramChatIdForStudent(student);
        if (chatId == null) {
          missing.add(student.name);
          continue;
        }

        await _sendTelegramToChat(chatId, messageText, student: student);
        sentCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم الإرسال عبر تيليجرام إلى $sentCount/$totalCount'),
            backgroundColor: sentCount > 0 ? Colors.green : Colors.red,
          ),
        );

        if (missing.isNotEmpty) {
          _showErrorDialog(
            'لم يتم الإرسال إلى بعض الطلاب لأنهم غير مربوطين بتيليجرام (${missing.length}/$totalCount):\n\n${missing.join('\n')}',
          );
        }
      }
    } catch (e) {
      _showErrorDialog('حدث خطأ أثناء الإرسال: $e');
    }
  }

  Future<void> _sendTelegramToChat(
    int chatId,
    String messageText, {
    StudentModel? student,
    bool isGroup = false,
  }) async {
    final hasFile = _selectedFile != null && _selectedFile != 'لا يوجد ملف';
    if (!hasFile) {
      await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
      return;
    }

    if (_deviceAttachmentSelected && (_exportedFilePath == null || _exportedFilePath!.trim().isEmpty)) {
      await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
      return;
    }

    File fileToSend;
    if (!isGroup && student != null && !_deviceAttachmentSelected) {
      final studentPath = await _createStudentSpecificFile(student);
      if (studentPath == null || studentPath.trim().isEmpty) {
        await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
        return;
      }
      fileToSend = File(studentPath);
    } else if (isGroup && !_deviceAttachmentSelected && _selectedStudents.isNotEmpty) {
      final selected = <StudentModel>[];
      for (final sid in _selectedStudents) {
        try {
          selected.add(_students.firstWhere((s) => (s.id?.toString() ?? '') == sid));
        } catch (_) {}
      }

      final combinedPath = await _createCombinedSelectedStudentsFile(selected);
      if (combinedPath == null || combinedPath.trim().isEmpty) {
        await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
        return;
      }
      fileToSend = File(combinedPath);
    } else {
      fileToSend = File(_exportedFilePath!);
    }

    if (!await fileToSend.exists()) {
      await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
      return;
    }

    final ok = await BotApiService.sendTelegramDocument(chatId: chatId, file: fileToSend, caption: messageText);
    if (!ok) {
      await BotApiService.sendTelegramText(chatId: chatId, text: messageText);
    }
  }

  // دالة جديدة للإرسال عبر الإيميل مع إنشاء ملف خاص لكل طالب
  Future<void> _sendEmails() async {
    setState(() => _sendingEmails = true);

    try {
      int successCount = 0;

      final auth = Provider.of<AuthProvider>(context, listen: false);
      final String? replyTo = auth.userEmail;
      int totalCount = _selectedStudents.length;

      for (final studentId in _selectedStudents) {
        final student = _students.firstWhere((s) => s.id.toString() == studentId);
        
        // إنشاء ملف خاص للطالب فقط إذا تم اختيار ملف
        String? studentFilePath;
        if (_selectedFile != null && _selectedFile != 'لا يوجد ملف') {
          try {
            studentFilePath = await _createStudentSpecificFile(student);
          } catch (e) {
            print('Error creating file for student ${student.name}: $e');
            continue;
          }
          
          if (studentFilePath == null) continue;
        }
        
        // جمع جميع الإيميلات للطالب
        final emailAddresses = [
          if (student.email?.isNotEmpty == true) student.email!,
          if (student.primaryGuardian?.email?.isNotEmpty == true) student.primaryGuardian!.email!,
          if (student.secondaryGuardian?.email?.isNotEmpty == true) student.secondaryGuardian!.email!,
        ];

        // إرسال لكل إيميل
        for (final email in emailAddresses) {
          if (studentFilePath != null) {
            // التحقق من وجود الملف وحجمه قبل الإرسال
            final file = File(studentFilePath);
            if (await file.exists() && await file.length() > 0) {
              // إرسال مع ملف مرفق
              final fileName = '${_selectedFile}_${student.name}.pdf';
              print('Sending email with attachment: $studentFilePath');
              print('File size: ${await file.length()} bytes');
              
              final success = await EmailService.sendEmailWithAttachment(
                recipientEmail: email,
                subject: '$_selectedFile - ${student.name}',
                message: _messageController.text.trim(),
                attachmentPath: studentFilePath,
                attachmentName: fileName,
                replyToEmail: replyTo,
              );
              
              if (success) {
                successCount++;
                print('Email sent successfully to $email');
              } else {
                print('Failed to send email to $email');
              }
            } else {
              print('File not accessible or empty: $studentFilePath');
              // إرسال رسالة نصية فقط بدون ملف
              final success = await EmailService.sendTextOnlyEmail(
                recipientEmail: email,
                subject: 'رسالة من ${student.name}',
                message: _messageController.text.trim(),
                replyToEmail: replyTo,
              );
              
              if (success) successCount++;
            }
          } else {
            // إرسال رسالة نصية فقط بدون ملف
            final success = await EmailService.sendTextOnlyEmail(
              recipientEmail: email,
              subject: 'رسالة من ${student.name}',
              message: _messageController.text.trim(),
              replyToEmail: replyTo,
            );
            
            if (success) successCount++;
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم إرسال الإيميل بنجاح إلى $successCount/$totalCount مستلم'),
            backgroundColor: successCount > 0 ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('حدث خطأ أثناء الإرسال: $e');
      }
    }

    setState(() => _sendingEmails = false);
  }

  // دالة إنشاء ملف خاص لطالب معين (نفس التصميم من صفحة التصدير)
  Future<String?> _createStudentSpecificFile(StudentModel student) async {
    if (_selectedFile == null || _selectedFile == 'لا يوجد ملف') return null;
    
    try {
      // Check if this is a financial file that should use the new helper
      if (_selectedFile == 'البيانات المالية' || _selectedFile == 'المعلومات المالية') {
        return await _exportFinancialDataForStudent();
      } else if (_selectedFile == 'الطلاب المتأخرين بالدفع') {
        return await _exportLatePaymentsForStudent();
      } else if (_selectedFile == 'سجل الدفعات') {
        return await _exportPaymentHistoryForStudent();
      } else if (_selectedFile == 'واجبات الطالب') {
        return await _exportStudentAssignmentsForStudent(student);
      }
      
      // For other files, use the old method
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final className = _selectedClass?.name ?? 'فصل غير معروف';

      switch (_selectedFile) {
        case 'معلومات الطالب':
          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'معلومات الطالب',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول معلومات الطالب
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(3),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('المعلومات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('البيانات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الطالب
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('اسم الطالب', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('رقم الطالب', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الهاتف', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.phone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الإيميل', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.email ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('اسم ولي الأمر', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.primaryGuardian?.name ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('رقم ولي الأمر', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.primaryGuardian?.phone ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('إيميل ولي الأمر', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.primaryGuardian?.email ?? student.parentEmail ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'ملخص الحضور':
          // تحميل بيانات الحضور للطالب
          final allLectures = await _dbHelper.getLecturesByClass(_selectedClass!.id!);
          final lectures = allLectures.where((l) => _isDateInRange(l.date)).toList();
          if (lectures.isEmpty) return null;
          int present = 0, absent = 0, late = 0, expelled = 0, excused = 0;
          
          for (var lecture in lectures) {
            final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
              studentId: student.id!,
              lectureId: lecture.id!,
            );
            
            if (attendance != null) {
              switch (attendance.status) {
                case AttendanceStatus.present:
                  present++;
                  break;
                case AttendanceStatus.absent:
                  absent++;
                  break;
                case AttendanceStatus.late:
                  late++;
                  break;
                case AttendanceStatus.expelled:
                  expelled++;
                  break;
                case AttendanceStatus.excused:
                  excused++;
                  break;
              }
            }
          }
          
          final total = lectures.length;
          final percentage = total > 0 ? ((present / total) * 100).round() : 0;

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.orange100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'ملخص الحضور',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول ملخص الحضور
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('النوع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('العدد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الحضور
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('عدد المحاضرات', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$total', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الحضور', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$present', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الغياب', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$absent', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التأخر', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$late', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الطرد', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$expelled', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('النسبة %', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$percentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'الحضور التفصيلي':
          // تحميل بيانات الحضور التفصيلي للطالب
          final allLectures = await _dbHelper.getLecturesByClass(_selectedClass!.id!);
          final lectures = allLectures.where((l) => _isDateInRange(l.date)).toList();
          if (lectures.isEmpty) return null;
          core.List<Map<String, dynamic>> attendanceDetails = [];
          
          for (var lecture in lectures) {
            final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
              studentId: student.id!,
              lectureId: lecture.id!,
            );
            
            String statusText = '-';
            if (attendance != null) {
              switch (attendance.status) {
                case AttendanceStatus.present:
                  statusText = 'حاضر';
                  break;
                case AttendanceStatus.absent:
                  statusText = 'غائب';
                  break;
                case AttendanceStatus.late:
                  statusText = 'متأخر';
                  break;
                case AttendanceStatus.excused:
                  statusText = 'مجاز';
                  break;
                case AttendanceStatus.expelled:
                  statusText = 'مطرود';
                  break;
              }
            }
            
            attendanceDetails.add({
              'date': '${lecture.date.day}/${lecture.date.month}/${lecture.date.year}',
              'lecture': lecture.title,
              'status': statusText,
            });
          }

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.purple100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'الحضور التفصيلي',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول الحضور التفصيلي
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('المحاضرة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الحالة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الحضور
                      ...attendanceDetails.map((detail) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['date'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['lecture'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['status'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'حضور الامتحانات':
          // تحميل بيانات امتحانات الطالب
          final allExams = await _dbHelper.getExamsByClass(_selectedClass!.id!);
          final exams = allExams.where((e) => _isDateInRange(e.date)).toList();
          if (exams.isEmpty) return null;
          core.List<Map<String, dynamic>> examAttendance = [];
          
          for (var exam in exams) {
            final attendance = await _dbHelper.getStudentGradeForExam(
              student.id!,
              exam.id!,
            );
            
            String statusText = '-';
            if (attendance != null) {
              switch (attendance.status) {
                case 'حاضر':
                  statusText = 'حاضر';
                  break;
                case 'غائب':
                  statusText = 'غائب';
                  break;
                case 'غش':
                  statusText = 'غش';
                  break;
                case 'مفقود':
                  statusText = 'مفقود';
                  break;
                case 'معفئ':
                case 'مؤجل':
                case 'معفئ او مؤجل':
                  statusText = 'معفئ او مؤجل';
                  break;
                default:
                  statusText = attendance.status ?? '-';
                  break;
              }
            }
            
            examAttendance.add({
              'date': '${exam.date.day}/${exam.date.month}/${exam.date.year}',
              'exam': exam.title,
              'status': statusText,
            });
          }

          if (examAttendance.isEmpty) return null;

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.deepPurple100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'حضور الامتحانات',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول حضور الامتحانات
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الامتحان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الحالة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الامتحانات
                      ...examAttendance.map((detail) {
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['date'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['exam'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(detail['status'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'الامتحانات':
          // عرض الامتحانات من جدول exams حتى لو لا توجد درجات بعد.
          final allExams = await _dbHelper.getExamsByClass(_selectedClass!.id!);
          final exams = allExams.where((e) => _isDateInRange(e.date)).toList();
          if (exams.isEmpty) return null;

          core.List<Map<String, dynamic>> examGrades = [];
          for (final exam in exams) {
            final gradeInfo = await _dbHelper.getStudentGradeForExam(student.id!, exam.id!);
            final statusText = (gradeInfo?.status?.toString().trim().isNotEmpty == true)
                ? gradeInfo!.status!.toString().trim()
                : '-';
            final isExemptOrPostponed = statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل';

            final obtained = gradeInfo?.obtainedMarks;
            final total = gradeInfo?.totalMarks ?? exam.maxScore;
            final percentage = (obtained != null && total > 0)
                ? ((obtained / total) * 100).toStringAsFixed(1)
                : '';

            examGrades.add({
              'date': '${exam.date.day}/${exam.date.month}/${exam.date.year}',
              'exam': exam.title,
              'status': isExemptOrPostponed ? 'معفئ او مؤجل' : statusText,
              'grade': (obtained == null || isExemptOrPostponed) ? '' : obtained.toStringAsFixed(1),
              'max': total.toStringAsFixed(1),
              'percentage': (obtained == null || isExemptOrPostponed) ? '' : percentage,
            });
          }

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'درجات الامتحانات',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول درجات الامتحانات
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(1),
                      3: const pw.FlexColumnWidth(1),
                      4: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الامتحان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الدرجة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('النسبة %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الحالة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الدرجات
                      ...examGrades.map((grade) {
                        final String gradeCell = (grade['grade']?.toString() ?? '').trim();
                        final String maxCell = (grade['max']?.toString() ?? '').trim();
                        final String percentageCell =
                            (grade['percentage']?.toString() ?? '').trim();
                        final String statusCell = (grade['status']?.toString() ?? '').trim();
                        final String gradeText = gradeCell.isEmpty
                            ? ''
                            : '$gradeCell/$maxCell';
                        final String percentageText = percentageCell.isEmpty
                            ? ''
                            : '$percentageCell%';
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(grade['date'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(grade['exam'], style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(gradeText, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(percentageText, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                statusCell,
                                style: pw.TextStyle(
                                  font: ttf,
                                  color: statusCell == 'معفئ او مؤجل' ? PdfColors.blue : PdfColors.black,
                                ),
                                textDirection: pw.TextDirection.rtl,
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'الدرجة النهائية':
          // حساب الدرجة النهائية للطالب
          final grades = await _dbHelper.getGradesByStudent(student.id!);
          double totalScore = 0;
          double totalMax = 0;
          int countedExams = 0;
          
          for (var grade in grades) {
            final exam = await _resolveExamForGrade(grade);
            if (exam != null && _isDateInRange(exam.date)) {
              final statusText = grade.status?.toString().trim() ?? 'حاضر';
              if (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل') {
                continue;
              }
              totalScore += grade.score;
              totalMax += exam.maxScore;
              countedExams++;
            }
          }

          if (countedExams == 0) return null;
          
          final finalPercentage = totalMax > 0 ? ((totalScore / totalMax) * 100).round() : 0;

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.teal100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'الدرجة النهائية',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول الدرجة النهائية
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('البيان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('القيمة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // بيانات الدرجة
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('مجموع الدرجات', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('${totalScore.toStringAsFixed(1)}/${totalMax.toStringAsFixed(1)}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('النسبة المئوية', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$finalPercentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('عدد الامتحانات', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$countedExams', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                    ],
                  ),
                ];
              },
            ),
          );
          break;

        case 'ملخص الطالب':
          // جمع جميع بيانات الطالب في تقرير شامل
          final allLectures = await _dbHelper.getLecturesByClass(_selectedClass!.id!);
          final lectures = allLectures.where((l) => _isDateInRange(l.date)).toList();
          final allExams = await _dbHelper.getExamsByClass(_selectedClass!.id!);
          final exams = allExams.where((e) => _isDateInRange(e.date)).toList();
          final grades = await _dbHelper.getGradesByStudent(student.id!);

          if (lectures.isEmpty && exams.isEmpty && grades.isEmpty) return null;
          
          // حساب إحصائيات الحضور
          int present = 0, absent = 0, late = 0, expelled = 0, excused = 0;
          for (var lecture in lectures) {
            final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
              studentId: student.id!,
              lectureId: lecture.id!,
            );
            if (attendance != null) {
              switch (attendance.status) {
                case AttendanceStatus.present:
                  present++;
                  break;
                case AttendanceStatus.absent:
                  absent++;
                  break;
                case AttendanceStatus.late:
                  late++;
                  break;
                case AttendanceStatus.expelled:
                  expelled++;
                  break;
                case AttendanceStatus.excused:
                  excused++;
                  break;
              }
            }
          }
          
          // حساب إحصائيات الامتحانات
          int examPresent = 0, examAbsent = 0;
          int cheatingCount = 0, missingCount = 0;
          double totalScore = 0, totalMax = 0;
          int countedExams = 0;
          
          for (var exam in exams) {
            final attendance = await _dbHelper.getStudentGradeForExam(
              student.id!,
              exam.id!,
            );
            if (attendance != null) {
              if (attendance.status == 'معفئ' || attendance.status == 'مؤجل' || attendance.status == 'معفئ او مؤجل') {
                continue;
              }
              if (attendance.status == 'حاضر') {
                examPresent++;
              } else if (attendance.status == 'غائب') {
                examAbsent++;
              } else if (attendance.status == 'غش') {
                cheatingCount++;
              } else if (attendance.status == 'مفقود') {
                missingCount++;
              }
            }
          }
          
          for (var grade in grades) {
            final exam = await _resolveExamForGrade(grade);
            if (exam != null && _isDateInRange(exam.date)) {
              final statusText = grade.status?.toString().trim() ?? 'حاضر';
              if (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل') {
                continue;
              }
              totalScore += grade.score;
              totalMax += exam.maxScore;
              countedExams++;
            }
          }
          
          final attendancePercentage = lectures.length > 0 ? ((present / lectures.length) * 100).round() : 0;
          final finalPercentage = totalMax > 0 ? ((totalScore / totalMax) * 100).round() : 0;

          pdf.addPage(
            pw.MultiPage(
              textDirection: pw.TextDirection.rtl,
              pageFormat: PdfPageFormat.a4,
              build: (pw.Context context) {
                return [
                  // العنوان
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.pink100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Text(
                          className,
                          style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'ملخص الطالب الشامل',
                          style: pw.TextStyle(fontSize: 18, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          student.name,
                          style: pw.TextStyle(fontSize: 16, font: ttf),
                          textAlign: pw.TextAlign.center,
                          textDirection: pw.TextDirection.rtl,
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // جدول ملخص شامل
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(1),
                    },
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('البيان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('القيمة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // معلومات أساسية
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('رقم الطالب', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الهاتف', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(student.phone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // إحصائيات الحضور
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('إحصائيات الحضور', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('نسبة الحضور', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$attendancePercentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // إحصائيات الامتحانات
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('إحصائيات الامتحانات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الدرجة النهائية', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('$finalPercentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                        ],
                      ),
                      // إظهار الغش فقط إذا كان موجود
                      if (cheatingCount > 0) ...[
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('حالات الغش', style: pw.TextStyle(font: ttf, color: PdfColors.red), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('$cheatingCount', style: pw.TextStyle(font: ttf, color: PdfColors.red), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                          ],
                        ),
                      ],
                      // إظهار المفقودة فقط إذا كانت موجودة
                      if (missingCount > 0) ...[
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('الأوراق المفقودة', style: pw.TextStyle(font: ttf, color: PdfColors.purple), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('$missingCount', style: pw.TextStyle(font: ttf, color: PdfColors.purple), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ];
              },
            ),
          );
          break;
      }

      // حفظ الملف
      final directory = await getApplicationDocumentsDirectory();
      final fileName = '${_selectedFile}_${student.name}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      return file.path;
    } catch (e) {
      print('Error creating student specific file: $e');
      return null;
    }
  }

  // Helper methods
  // دالة مساعدة لإنشاء صف معلومات في PDF
  pw.Widget _buildInfoRow(String label, String value, pw.Font ttf) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                font: ttf,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: ttf, fontSize: 14),
              textDirection: pw.TextDirection.rtl,
            ),
          ),
        ],
      ),
    );
  }

  // دوال الإرسال للطرق الأخرى
  Future<void> _sendSMS() async {
    if (_selectedStudents.isEmpty) {
      _showErrorDialog('الرجاء اختيار طالب واحد على الأقل');
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      _showErrorDialog('الرجاء كتابة الرسالة');
      return;
    }

    try {
      // جمع أرقام الهواتف للطلاب المحددين
      core.List<String> phoneNumbers = [];
      
      for (final studentId in _selectedStudents) {
        final student = _students.firstWhere((s) => s.id.toString() == studentId);
        String? phoneNumber;

        // تحديد رقم الهاتف بناءً على المستلم
        switch (_selectedRecipient) {
          case 'student':
            phoneNumber = student.phone;
            break;
          case 'parent':
            phoneNumber = student.primaryGuardian?.phone ?? student.secondaryGuardian?.phone ?? student.parentPhone;
            break;
          default:
            phoneNumber = student.phone;
        }

        if (phoneNumber != null && phoneNumber.isNotEmpty) {
          phoneNumbers.add(phoneNumber);
        }
      }

      if (phoneNumbers.isEmpty) {
        _showErrorDialog('لا توجد أرقام هواتف متاحة للطلاب المحددين');
        return;
      }

      // تجهيز نص الرسالة مع إضافة رابط الملف إذا كان موجوداً
      String messageText = _messageController.text.trim();

      // إذا كان هناك ملف مُصدّر، ارفعه وأنشئ رابط حقيقي ثم أضفه لنص الـ SMS
      if (_selectedFile != null &&
          _selectedFile != 'لا يوجد ملف' &&
          _exportedFilePath != null &&
          _exportedFilePath!.isNotEmpty) {
        final file = File(_exportedFilePath!);
        final url = await _uploadFileToTempSh(file);
        if (url != null && url.isNotEmpty) {
          setState(() => _selectedFilePath = url);
          messageText += '\n\n📎 رابط ملف $_selectedFile: $url';
        } else {
          setState(() => _selectedFilePath = null);
        }
      }
      
      // دمج الأرقام مع فاصلة
      final phones = phoneNumbers.join(',');

      final bool isIOS = Theme.of(context).platform == TargetPlatform.iOS;
      final encodedMessage = Uri.encodeComponent(messageText);

      // iOS prefers sms:number&body=... while Android is typically sms:number?body=...
      final smsUri = isIOS
          ? Uri.parse('sms:$phones&body=$encodedMessage')
          : Uri.parse('sms:$phones?body=$encodedMessage');

      // فتح تطبيق الرسائل مباشرة بدون معاينة
      if (await canLaunchUrl(smsUri)) {
        final ok = await _launchExternalApp(smsUri);
        if (!ok) {
          _showErrorDialog('لا يمكن فتح تطبيق الرسائل');
          return;
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.message, color: Colors.white),
                  SizedBox(width: 8),
                  Text('تم فتح تطبيق الرسائل بنجاح'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        _showErrorDialog('لا يمكن فتح تطبيق الرسائل');
      }
    } catch (e) {
      _showErrorDialog('حدث خطأ أثناء فتح تطبيق الرسائل: $e');
    }
  }

  Future<void> _sendWhatsApp() async {
    if (_selectedStudents.length > 1) {
      _showErrorDialog('طريقة الإرسال عبر واتساب تتطلب اختيار طالب واحد فقط');
      return;
    }

    if (_selectedStudents.isEmpty) {
      _showErrorDialog('الرجاء اختيار طالب واحد على الأقل');
      return;
    }

    try {
      final studentId = _selectedStudents.first;
      final student = _students.firstWhere((s) => s.id.toString() == studentId);
      String? phoneNumber;

      // تحديد رقم الهاتف بناءً على المستلم
      switch (_selectedRecipient) {
        case 'student':
          phoneNumber = student.phone;
          break;
        case 'parent':
          phoneNumber = student.primaryGuardian?.phone ?? student.secondaryGuardian?.phone ?? student.parentPhone;
          break;
      }

      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        await _sendTextToWhatsApp(phoneNumber, student.name);
      } else {
        _showErrorDialog('لا يوجد رقم هاتف لهذا الطالب');
      }
    } catch (e) {
      _showErrorDialog('حدث خطأ أثناء الإرسال: $e');
    }
  }

  // Helper methods for WhatsApp
  Future<void> _sendTextToWhatsApp(String phoneNumber, String studentName) async {
    var messageText = _messageController.text.trim();
    if (messageText.isEmpty) {
      _showErrorDialog('الرجاء كتابة الرسالة');
      return;
    }

    if (_selectedFile != null &&
        _selectedFile != 'لا يوجد ملف' &&
        _exportedFilePath != null &&
        _exportedFilePath!.trim().isNotEmpty) {
      final file = File(_exportedFilePath!);
      final url = await _uploadFileToTempSh(file);
      if (url != null && url.isNotEmpty) {
        setState(() => _selectedFilePath = url);
        messageText += '\n\n📎 رابط ملف $_selectedFile: $url';
      } else {
        setState(() => _selectedFilePath = null);
      }
    }

    final cleanedPhone = _phoneForWhatsapp(phoneNumber);
    if (cleanedPhone.isEmpty) {
      _showErrorDialog('رقم الهاتف غير صالح');
      return;
    }
    final encodedMessage = Uri.encodeComponent(messageText);

    final whatsappAppUri = Uri.parse('whatsapp://send?phone=$cleanedPhone&text=$encodedMessage');
    final whatsappWebUri = Uri.parse('https://wa.me/$cleanedPhone?text=$encodedMessage');

    if (await canLaunchUrl(whatsappAppUri)) {
      final ok = await _launchExternalApp(whatsappAppUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح تطبيق واتساب');
      }
      return;
    }

    if (await canLaunchUrl(whatsappWebUri)) {
      final ok = await _launchExternalApp(whatsappWebUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح واتساب عبر الرابط');
      }
      return;
    }

    _showErrorDialog('لا يمكن فتح واتساب على هذا الجهاز');
  }

  Future<void> _sendFileToWhatsApp(String phoneNumber, String studentName, String filePath) async {
    // For file sharing, we'll share the text and mention the file
    final fileName = '${_selectedFile}_${studentName}.pdf';
    final message = Uri.encodeComponent('${_messageController.text}\n\nملف مرفق: $fileName');
    final cleanedPhone = _phoneForWhatsapp(phoneNumber);
    final whatsappAppUri = Uri.parse('whatsapp://send?phone=$cleanedPhone&text=$message');
    final whatsappWebUri = Uri.parse('https://wa.me/$cleanedPhone?text=$message');

    if (await canLaunchUrl(whatsappAppUri)) {
      final ok = await _launchExternalApp(whatsappAppUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح تطبيق واتساب');
      }
      return;
    }

    if (await canLaunchUrl(whatsappWebUri)) {
      final ok = await _launchExternalApp(whatsappWebUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح واتساب عبر الرابط');
      }
      return;
    }

    _showErrorDialog('لا يمكن فتح واتساب على هذا الجهاز');
  }

  Future<void> _sendToWhatsApp(String phoneNumber, String studentName) async {
    // For file sharing, we'll share the text and mention the file
    final messageText = '${_messageController.text}\n\nملف مرفق: $_selectedFile';
    final cleanedPhone = _phoneForWhatsapp(phoneNumber);
    final encodedMessage = Uri.encodeComponent(messageText);

    final whatsappAppUri = Uri.parse('whatsapp://send?phone=$cleanedPhone&text=$encodedMessage');
    final whatsappWebUri = Uri.parse('https://wa.me/$cleanedPhone?text=$encodedMessage');

    if (await canLaunchUrl(whatsappAppUri)) {
      final ok = await _launchExternalApp(whatsappAppUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح تطبيق واتساب');
      }
      return;
    }

    if (await canLaunchUrl(whatsappWebUri)) {
      final ok = await _launchExternalApp(whatsappWebUri);
      if (!ok) {
        _showErrorDialog('تعذر فتح واتساب عبر الرابط');
      }
      return;
    }

    _showErrorDialog('لا يمكن فتح واتساب على هذا الجهاز');
  }

  // Error dialog helper
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خطأ'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  // دالة جديدة لعرض معاينة الرسالة
  Future<bool?> _showMessagePreviewDialog(
    String title,
    String message,
    core.List<String> recipients,
    String confirmText,
  ) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // عرض المستلمين
              if (recipients.isNotEmpty) ...[
                const Text(
                  'المستلمون:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ...recipients.map((phone) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.phone, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(phone)),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
              ],
              
              // عرض الرسالة
              const Text(
                'الرسالة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  message,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  
  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF333333),
        title: const Text('نجاح', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق', style: TextStyle(color: Color(0xFFFEC619))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF404040),
        title: const Text(
          'المراسلة',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
      ),
      body: Row(
        children: [
          // القائمة اليسرى - قائمة الطلاب
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: Column(
                children: [
                  _buildLeftHeader(),
                  Expanded(
                    child: _buildStudentsList(),
                  ),
                ],
              ),
            ),
          ),
          // الفاصل
          Container(
            width: 1,
            color: const Color(0xFFFEC619),
          ),
          // القائمة اليمنى - معلومات الإرسال
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.black,
              child: _buildRightPanel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFF333333),
      child: Column(
        children: [
          // شريط التنقل بين الفصول والبحث والفرز
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _showClassSelection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF404040),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFEC619))
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.class_, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedClass?.name ?? 'اختر الفصل',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'البحث عن طالب',
                    hintStyle: const TextStyle(color: Colors.grey),
                    prefixIcon: const Icon(Icons.search, color: Colors.white),
                    filled: true,
                    fillColor: const Color(0xFF404040),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFEC619))
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFEC619))
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFEC619))
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<SortOption>(
                icon: const Icon(Icons.sort, color: Colors.white),
                onSelected: (option) {
                  setState(() {
                    _sortOption = option;
                    _sortStudents();
                  });
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: SortOption.none,
                    child: Text('ترتيب افتراضي'),
                  ),
                  const PopupMenuItem(
                    value: SortOption.highestAverage,
                    child: Text('أعلى معدل'),
                  ),
                  const PopupMenuItem(
                    value: SortOption.lowestAverage,
                    child: Text('أقل معدل'),
                  ),
                  const PopupMenuItem(
                    value: SortOption.highestAbsence,
                    child: Text('أعلى نسبة غياب'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _students.isEmpty ? null : _toggleSelectAllStudents,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEC619),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.select_all),
                  label: Text(
                    (() {
                      final ids = _students.map((s) => s.id?.toString()).whereType<String>().toList();
                      final allSelected = ids.isNotEmpty && ids.every(_selectedStudents.contains);
                      return allSelected ? 'إلغاء تحديد الكل' : 'تحديد الكل';
                    })(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF404040),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFEC619)),
                ),
                child: Text(
                  '${_selectedStudents.length}/${_students.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredStudents.length,
      itemBuilder: (context, index) {
        final student = _filteredStudents[index];
        final isSelected = _selectedStudents.contains(student.id.toString());
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFEC619).withOpacity(0.2) : const Color(0xFF333333),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFFFEC619) : const Color(0xFFFEC619),
            ),
          ),
          child: InkWell(
            onTap: () => _toggleStudentSelection(student.id.toString()),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _buildStudentAvatar(student),
                  const SizedBox(width: 16),
                  // مربع الاختيار
                  GestureDetector(
                    onTap: () => _toggleStudentSelection(student.id.toString()),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFFFEC619) : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFEC619) : Colors.grey,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.black, size: 16)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildStudentInfo(student),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentInfo(StudentModel student) {
    Color _getAverageColor(double? avg) {
      final value = avg ?? 0.0;

      if (value < 50) {
        if (value < 30) return Colors.red.shade900;
        if (value < 40) return Colors.red.shade800;
        return Colors.red.shade700;
      }

      if (value < 60) return Colors.green.shade600;
      if (value < 70) return Colors.green.shade700;
      if (value < 80) return Colors.green.shade800;
      if (value < 90) return Colors.green.shade900;
      return Colors.green.shade900;
    }

    Color _getAttendanceColor(double attendancePercent) {
      final value = attendancePercent.clamp(0.0, 100.0);

      if (value < 50) {
        if (value < 30) return Colors.red.shade900;
        if (value < 40) return Colors.red.shade800;
        return Colors.red.shade700;
      }

      if (value < 60) return Colors.green.shade600;
      if (value < 70) return Colors.green.shade700;
      if (value < 80) return Colors.green.shade800;
      if (value < 90) return Colors.green.shade900;
      return Colors.green.shade900;
    }

    final double attendancePercent = 100 - (student.absencePercentage ?? 0);
    final Color attendanceColor = _getAttendanceColor(attendancePercent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // إحصائيات المحاضرات
        Row(
          children: [
            _buildInfoChip('المحاضرات الحاضر: ${student.attendedLectures ?? 0}',
                chipColor: Colors.green, textColor: Colors.green),
            const SizedBox(width: 8),
            _buildInfoChip('المحاضرات الغائب: ${student.absentLectures ?? 0}',
                chipColor: Colors.red, textColor: Colors.red),
          ],
        ),
        const SizedBox(height: 4),
        // حالات المحاضرات (تظهر فقط إذا وجدت)
        if ((student.expelledLectures ?? 0) > 0 || (student.excusedLectures ?? 0) > 0)
          Row(
            children: [
              if ((student.expelledLectures ?? 0) > 0)
                _buildInfoChip(
                  'المحاضرات المطرود: ${student.expelledLectures}',
                  chipColor: Colors.purple,
                  textColor: Colors.purple,
                ),
              if ((student.expelledLectures ?? 0) > 0 && (student.excusedLectures ?? 0) > 0)
                const SizedBox(width: 8),
              if ((student.excusedLectures ?? 0) > 0)
                _buildInfoChip(
                  'المحاضرات المجاز: ${student.excusedLectures}',
                  chipColor: Colors.white,
                  textColor: Colors.black,
                ),
            ],
          ),
        if ((student.expelledLectures ?? 0) > 0 || (student.excusedLectures ?? 0) > 0)
          const SizedBox(height: 4),
        // إحصائيات الامتحانات الأساسية
        Row(
          children: [
            _buildInfoChip('الامتحانات الحاضر: ${student.attendedExams ?? 0}',
                chipColor: Colors.green, textColor: Colors.green),
            const SizedBox(width: 8),
            _buildInfoChip('الامتحانات الغائب: ${student.absentExams ?? 0}',
                chipColor: Colors.red, textColor: Colors.red),
          ],
        ),
        const SizedBox(height: 4),
        // حالات الامتحانات (تظهر فقط إذا وجدت)
        if ((student.exemptOrPostponedExams ?? 0) > 0)
          Row(
            children: [
              _buildInfoChip(
                'المعفئ او مؤجل: ${student.exemptOrPostponedExams}',
                chipColor: Colors.blue,
                textColor: Colors.blue,
              ),
            ],
          ),
        if ((student.exemptOrPostponedExams ?? 0) > 0)
          const SizedBox(height: 4),
        // حالات خاصة (غش ومفقودة) - تظهر فقط إذا وجدت
        if (student.cheatingCount != null && student.cheatingCount! > 0)
          Row(
            children: [
              _buildInfoChip('حالات الغش: ${student.cheatingCount}',
                  chipColor: Colors.red, textColor: Colors.red),
              if (student.missingCount != null && student.missingCount! > 0)
                const SizedBox(width: 8),
              if (student.missingCount != null && student.missingCount! > 0)
                _buildInfoChip('الأوراق المفقودة: ${student.missingCount}',
                    chipColor: Colors.purple, textColor: Colors.purple),
            ],
          )
        else if (student.missingCount != null && student.missingCount! > 0)
          Row(
            children: [
              _buildInfoChip('الأوراق المفقودة: ${student.missingCount}',
                  chipColor: Colors.purple, textColor: Colors.purple),
            ],
          ),
        if ((student.cheatingCount != null && student.cheatingCount! > 0) || 
            (student.missingCount != null && student.missingCount! > 0))
          const SizedBox(height: 4),
        // باقي المعلومات
        Row(
          children: [
            _buildInfoChip(
              'المعدل: ${student.averageGrade?.toStringAsFixed(1) ?? 'N/A'}%',
              chipColor: _getAverageColor(student.averageGrade),
              textColor: _getAverageColor(student.averageGrade),
            ),
            const SizedBox(width: 8),
            _buildInfoChip(
              'نسبة الحضور: ${attendancePercent.toStringAsFixed(1)}%',
              chipColor: attendanceColor,
              textColor: attendanceColor,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _buildInfoChip('الهاتف: ${student.phone ?? 'لا يوجد'}',
                chipColor: Colors.white, textColor: Colors.black),
            const SizedBox(width: 8),
            _buildInfoChip('الإيميل: ${student.email ?? 'لا يوجد'}',
                chipColor: Colors.white, textColor: Colors.black),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoChip(
    String text, {
    Color? chipColor,
    Color? textColor,
  }) {
    final Color resolvedChipColor = chipColor ?? const Color(0xFFFEC619);
    final Color resolvedTextColor = textColor ?? const Color(0xFFFEC619);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: resolvedChipColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: resolvedChipColor),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: resolvedTextColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - 200, // تقليل الارتفاع لتجنب overflow
        ),
        child: IntrinsicHeight(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // خانة اختيار الملف
              _buildFileSelector(),
              const SizedBox(height: 20),
              // حاوية الإرسال لـ
              _buildRecipientSelector(),
              const SizedBox(height: 20),
              // حاوية كتابة الرسالة
              _buildMessageInput(),
              const SizedBox(height: 20),
              // خيارات طرق الإرسال
              _buildSendMethodSelector(),
              const SizedBox(height: 20),
              // زر الإرسال
              _buildSendButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC619))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              'اختر الملف',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PopupMenuButton<String>(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF333333),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFEC619)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.file_present, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedFile ?? 'اختر الملف',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                      ],
                    ),
                  ),
                  onSelected: (String fileType) {
                    _createFileDirectly(fileType);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'لا يوجد ملف',
                      child: Row(
                        children: [
                          Icon(Icons.chat_bubble_outline, color: Colors.grey),
                          const SizedBox(width: 12),
                          Text('لا يوجد ملف'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'إضافة ملف من الجهاز',
                      child: Row(
                        children: [
                          Icon(Icons.upload_file, color: Colors.lightBlue),
                          const SizedBox(width: 12),
                          Text('إضافة ملف من الجهاز'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'معلومات الطالب',
                      child: Row(
                        children: [
                          Icon(Icons.person, color: Colors.blue),
                          const SizedBox(width: 12),
                          Text('معلومات الطالب'),
                        ],
                      ),
                    ),
                PopupMenuItem(
                  value: 'ملخص الحضور',
                  child: Row(
                    children: [
                      Icon(Icons.summarize, color: Colors.orange),
                      const SizedBox(width: 12),
                      Text('ملخص الحضور'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'الحضور التفصيلي',
                  child: Row(
                    children: [
                      Icon(Icons.calendar_month, color: Colors.purple),
                      const SizedBox(width: 12),
                      Text('الحضور التفصيلي'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'حضور الامتحانات',
                  child: Row(
                    children: [
                      Icon(Icons.fact_check, color: Colors.deepPurple),
                      const SizedBox(width: 12),
                      Text('حضور الامتحانات'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'الامتحانات',
                  child: Row(
                    children: [
                      Icon(Icons.assignment, color: Colors.green),
                      const SizedBox(width: 12),
                      Text('الامتحانات'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'الدرجة النهائية',
                  child: Row(
                    children: [
                      Icon(Icons.grade, color: Colors.teal),
                      const SizedBox(width: 12),
                      Text('الدرجة النهائية'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'ملاحظات الفصول',
                  child: Row(
                    children: [
                      Icon(Icons.note_alt, color: Colors.indigo),
                      const SizedBox(width: 12),
                      Text('ملاحظات الفصول'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'ملخص الطالب',
                  child: Row(
                    children: [
                      Icon(Icons.summarize_outlined, color: Colors.pink),
                      const SizedBox(width: 12),
                      Text('ملخص الطالب'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'واجبات الطالب',
                  child: Row(
                    children: [
                      Icon(Icons.assignment_turned_in_outlined, color: Colors.lightGreen),
                      const SizedBox(width: 12),
                      Text('واجبات الطالب'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'البيانات المالية',
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: Colors.green),
                      const SizedBox(width: 12),
                      Text('البيانات المالية'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'الطلاب المتأخرين بالدفع',
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.red),
                      const SizedBox(width: 12),
                      Text('الطلاب المتأخرين بالدفع'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'سجل الدفعات',
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.amber),
                      const SizedBox(width: 12),
                      Text('سجل الدفعات'),
                    ],
                  ),
                ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFEC619)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الفترة الزمنية للملف',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _allDates,
                        onChanged: (v) {
                          setState(() {
                            _allDates = v ?? true;
                          });
                        },
                        activeColor: const Color(0xFFFEC619),
                        checkColor: Colors.black,
                        title: const Text('الكل (بدون تحديد فترة)', style: TextStyle(color: Colors.white)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _allDates ? null : _pickStartDate,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFFEC619)),
                              ),
                              child: Text('تاريخ البدء: ${_fmtDate(_startDate)}'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _allDates ? null : _pickEndDate,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Color(0xFFFEC619)),
                              ),
                              child: Text('تاريخ الانتهاء: ${_fmtDate(_endDate)}'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC619))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              'الإرسال إلى',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildRecipientOption('الطالب', 'student'),
                const SizedBox(height: 8),
                _buildRecipientOption('ولي الأمر', 'parent'),
                if (_selectedMethod == 'telegram') ...[
                  const SizedBox(height: 8),
                  _buildRecipientOption('مجموعات تيليجرام', 'group'),
                  if (_selectedRecipient == 'group') ...[
                    const SizedBox(height: 12),
                    _buildTelegramGroupsSelector(),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelegramGroupsSelector() {
    if (_telegramGroups.isEmpty && !_telegramGroupsLoading) {
      _ensureTelegramGroupsLoaded();
    }

    if (_telegramGroupsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_telegramGroups.isEmpty) {
      return const Text(
        'لا توجد كروبات مسجلة بعد',
        style: TextStyle(color: Colors.white),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF333333),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFEC619)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختر الكروب/الكروبات',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ..._telegramGroups.map((g) {
            final id = (g['chat_id'] ?? '').toString();
            final title = (g['title'] ?? '').toString();
            final checked = _selectedTelegramGroupIds.contains(id);
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: checked,
              onChanged: (v) {
                _toggleTelegramGroupSelection(id);
              },
              activeColor: const Color(0xFFFEC619),
              checkColor: Colors.black,
              title: Text(
                title.isNotEmpty ? title : id,
                style: const TextStyle(color: Colors.white),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildRecipientOption(String title, String value) {
    return RadioListTile<String>(
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      value: value,
      groupValue: _selectedRecipient,
      onChanged: (value) {
        setState(() {
          _selectedRecipient = value;
        });
      },
      activeColor: const Color(0xFFFEC619),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC619))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              'الرسالة',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _messageController,
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'اكتب رسالتك هنا...',
                hintStyle: const TextStyle(color: Colors.grey),
                filled: true,
                fillColor: const Color(0xFF333333),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFEC619)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFEC619)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFEC619)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendMethodSelector() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF404040),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC619))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF333333),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: const Text(
              'طريقة الإرسال',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildMethodOption('SMS', 'sms', Icons.message),
                const SizedBox(height: 8),
                _buildMethodOption('WhatsApp', 'whatsapp', Icons.send),
                const SizedBox(height: 8),
                _buildMethodOption('Email', 'email', Icons.email),
                const SizedBox(height: 8),
                _buildMethodOption('Telegram', 'telegram', Icons.send),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentAvatar(StudentModel student) {
    final String? photoPath = (student.photoPath ?? '').trim().isEmpty ? null : student.photoPath;
    final hasLocalPhoto = photoPath != null && File(photoPath).existsSync();

    final avatar = Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFFEC619).withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFEC619), width: 2),
      ),
      child: ClipOval(
        child: hasLocalPhoto
            ? Image.file(
                File(photoPath!),
                fit: BoxFit.cover,
              )
            : Center(
                child: Text(
                  student.name.isNotEmpty ? student.name[0] : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
      ),
    );

    if (!hasLocalPhoto) return avatar;

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) {
            return Dialog(
              backgroundColor: Colors.black,
              child: InteractiveViewer(
                child: Image.file(
                  File(photoPath!),
                  fit: BoxFit.contain,
                ),
              ),
            );
          },
        );
      },
      borderRadius: BorderRadius.circular(999),
      child: avatar,
    );
  }

  Widget _buildMethodOption(String title, String value, IconData icon) {
    final isWhatsApp = value == 'whatsapp';
    final isDisabled = (isWhatsApp && _selectedStudents.length > 1);
    
    return RadioListTile<String>(
      title: Row(
        children: [
          Icon(
            icon, 
            color: isDisabled ? Colors.grey : Colors.white, 
            size: 20
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDisabled ? Colors.grey : Colors.white,
              ),
            ),
          ),
          if (isDisabled) ...[
            const SizedBox(width: 8),
            const Icon(
              Icons.lock,
              color: Colors.grey,
              size: 16,
            ),
          ],
        ],
      ),
      value: value,
      groupValue: _selectedMethod,
      onChanged: isDisabled ? null : (value) {
        setState(() {
          _selectedMethod = value;
          if (_selectedMethod != 'telegram' && _selectedRecipient == 'group') {
            _selectedRecipient = 'student';
          }
        });
      },
      activeColor: const Color(0xFFFEC619),
    );
  }

  Widget _buildSendButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFFEC619), const Color(0xFFFEC619).withOpacity(0.8)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFEC619).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _sendMessage,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text(
            'إرسال الرسالة',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _exportFinancialDataForStudent() async {
    if (_selectedClass == null || _selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار طالب واحد على الأقل')),
      );
      return null;
    }

    // For messaging, we'll create files for each selected student individually
    final student = _students.firstWhere((s) => _selectedStudents.contains(s.id.toString()));
    
    try {
      final filePath = await _financialHelper.exportFinancialDataForStudent(
        context,
        student: student,
        studentClass: _selectedClass!,
      );
      
      if (filePath != null) {
        print('Financial export created successfully: $filePath');
        // Verify file exists and has content
        final file = File(filePath);
        if (await file.exists() && await file.length() > 0) {
          return filePath;
        } else {
          print('Error: File is empty or does not exist');
          return null;
        }
      }
      return null;
    } catch (e) {
      print('Error in financial export: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<String?> _exportLatePaymentsForStudent() async {
    if (_selectedClass == null || _selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار طالب واحد على الأقل')),
      );
      return null;
    }

    final student = _students.firstWhere((s) => _selectedStudents.contains(s.id.toString()));
    
    try {
      final filePath = await _financialHelper.exportLatePaymentsForStudent(
        context,
        student: student,
        studentClass: _selectedClass!,
      );
      
      if (filePath != null) {
        print('Late payments export created successfully: $filePath');
        // Verify file exists and has content
        final file = File(filePath);
        if (await file.exists() && await file.length() > 0) {
          return filePath;
        } else {
          print('Error: File is empty or does not exist');
          return null;
        }
      }
      return null;
    } catch (e) {
      print('Error in late payments export: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<String?> _exportPaymentHistoryForStudent() async {
    if (_selectedClass == null || _selectedStudents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار طالب واحد على الأقل')),
      );
      return null;
    }

    final student = _students.firstWhere((s) => _selectedStudents.contains(s.id.toString()));
    
    try {
      final filePath = await _financialHelper.exportPaymentHistoryForStudent(
        context,
        student: student,
        studentClass: _selectedClass!,
      );
      
      if (filePath != null) {
        print('Payment history export created successfully: $filePath');
        // Verify file exists and has content
        final file = File(filePath);
        if (await file.exists() && await file.length() > 0) {
          return filePath;
        } else {
          print('Error: File is empty or does not exist');
          return null;
        }
      }
      return null;
    } catch (e) {
      print('Error in payment history export: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
      return null;
    }
  }

  void _showClassSelection() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF404040),
        title: const Text(
          'اختر الفصل',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Consumer<ClassProvider>(
            builder: (context, classProvider, child) {
              return ListView.builder(
                shrinkWrap: true,
                itemCount: classProvider.classes.length,
                itemBuilder: (context, index) {
                  final classItem = classProvider.classes[index];
                  return ListTile(
                    title: Text(
                      classItem.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    onTap: () async {
                      setState(() {
                        _selectedClass = classItem;
                        _selectedStudents.clear();
                      });
                      await _loadStudents();
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

enum SortOption {
  none,
  highestAverage,
  lowestAverage,
  highestAbsence,
}

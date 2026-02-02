import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../database/database_helper.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/student_model.dart';
import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../providers/grade_provider.dart';
import '../../providers/student_provider.dart';
import '../../services/student_list_order_service.dart';
import '../../services/unified_student_status_service.dart';
import '../../utils/file_attachment_helper.dart';
import '../../utils/image_picker_helper.dart';
import '../email/email_sending_screen.dart';
import '../messaging/messaging_screen.dart';
import '../students/student_assignments_screen.dart';
import '../students/student_details_screen.dart';
import '../students/student_gallery_screen.dart';
import 'exam_statistics_screen.dart';

enum ExamSortType { name, attendanceRate, absenceRate, highestAverage, lowestAverage }
enum GradeStatus { present, absent, cheating, missing, exempt, postponed }

class ExamsScreen extends StatefulWidget {
  final ClassModel classModel;

  const ExamsScreen({super.key, required this.classModel});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  ExamSortType _sortType = ExamSortType.name;
  final Map<int, Map<int, double>> _studentGrades = {};
  final Map<int, Map<int, GradeStatus>> _studentStatus = {};
  final Map<int, Map<int, String>> _studentComments = {};
  final Map<int, Map<String, int>> _studentAttendanceStats = {};
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();
  String _searchQuery = '';
  List<StudentModel> _students = [];
  List<ExamModel> _exams = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Map<int, bool> _atRiskStudents = {};
  Map<int, bool> _excellentStudents = {};
  Timer? _refreshTimer;
  bool _isDeletingMode = false;
  final Set<int> _selectedStudents = <int>{};

  StreamSubscription<StudentListOrderEvent>? _orderSub;
  StreamSubscription<StudentSortModeEvent>? _sortModeSub;
  List<int> _syncedStudentOrder = const [];
  String? _syncedSortMode;

  bool _sortByLatest = false;

  @override
  void initState() {
    super.initState();
    _headerScrollController.addListener(_syncHeaderScroll);
    _contentScrollController.addListener(_syncContentScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadSortPreference();
      _loadData();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classId = widget.classModel.id;
      if (classId != null) {
        _initStudentOrderSync(classId);
        _initSortModeSync(classId);
      }
    });
  }

  Future<void> _initSortModeSync(int classId) async {
    final saved = await StudentListOrderService.instance.getSortMode(classId);
    if (!mounted) return;
    if (saved != null) {
      _applySortMode(saved.mode);
    }

    _sortModeSub?.cancel();
    _sortModeSub = StudentListOrderService.instance.sortModeChanges.listen((event) {
      if (!mounted) return;
      if (event.classId != classId) return;
      _applySortMode(event.mode);
    });
  }

  void _applySortMode(String mode) {
    final mapped = switch (mode) {
      'attendance_rate' => ExamSortType.attendanceRate,
      'absence_rate' => ExamSortType.absenceRate,
      'highest_average' => ExamSortType.highestAverage,
      'lowest_average' => ExamSortType.lowestAverage,
      _ => ExamSortType.name,
    };
    if (!mounted) return;
    setState(() {
      _sortType = mapped;
    });
  }

  @override
  void didUpdateWidget(covariant ExamsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id) {
      _orderSub?.cancel();
      _sortModeSub?.cancel();
      _syncedStudentOrder = const [];
      _syncedSortMode = null;
      final classId = widget.classModel.id;
      if (classId != null) {
        _initStudentOrderSync(classId);
        _initSortModeSync(classId);
      }
      _studentGrades.clear();
      _studentStatus.clear();
      _studentComments.clear();
      _atRiskStudents.clear();
      _excellentStudents.clear();
      _searchController.clear();
      _searchQuery = '';
      _selectedStudents.clear();
      _isDeletingMode = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadSortPreference();
          _loadData();
        }
      });
    }
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _sortByLatest = prefs.getBool('sort_by_latest') ?? false;
    });
  }

  Future<void> _setSortByLatest(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sort_by_latest', value);
    if (!mounted) return;
    setState(() {
      _sortByLatest = value;
      _exams.sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _headerScrollController.dispose();
    _contentScrollController.dispose();
    _orderSub?.cancel();
    _sortModeSub?.cancel();
    super.dispose();
  }

  Future<void> _initStudentOrderSync(int classId) async {
    final saved = await StudentListOrderService.instance.getOrder(classId);
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _syncedStudentOrder = saved.studentIds;
      });
    }

    _orderSub = StudentListOrderService.instance.changes.listen((event) {
      if (!mounted) return;
      if (event.classId != classId) return;
      setState(() {
        _syncedStudentOrder = event.studentIds;
      });
    });
  }

  Future<void> _publishCurrentStudentOrder() async {
    final classId = widget.classModel.id;
    if (classId == null) return;
    final current = Provider.of<StudentProvider>(context, listen: false).students;
    final sorted = _sortStudents(current, publish: false, applySyncedOrder: false);
    final ids = sorted.map((s) => s.id).whereType<int>().toList();
    await StudentListOrderService.instance.setOrder(classId: classId, studentIds: ids);
  }

  void _syncHeaderScroll() {
    if (_headerScrollController.hasClients &&
        _contentScrollController.hasClients) {
      if (_headerScrollController.offset != _contentScrollController.offset) {
        _contentScrollController.jumpTo(_headerScrollController.offset);
      }
    }
  }

  void _syncContentScroll() {
    if (_contentScrollController.hasClients &&
        _headerScrollController.hasClients) {
      if (_contentScrollController.offset != _headerScrollController.offset) {
        _headerScrollController.jumpTo(_contentScrollController.offset);
      }
    }
  }

  void _showEditMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'خيارات التعديل',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            // التصنيف أصبح ضمن زر (filter) أعلى الشاشة
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الطالب', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleDeleteMode();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showExamReport(ExamModel exam) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('جاري إنشاء تقرير الامتحان...'),
            ],
          ),
        ),
      );

      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document();
      final className = widget.classModel.name;

      double total = 0;
      int count = 0;
      for (final student in _students) {
        final status = _studentStatus[student.id!]?[exam.id!] ?? GradeStatus.present;
        final grade = _studentGrades[student.id!]?[exam.id!];
        if (status == GradeStatus.present && grade != null) {
          total += grade;
          count++;
        }
      }
      final avg = count > 0 ? (total / count) : 0.0;

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
                  color: PdfColors.teal,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'تقرير عن الامتحان',
                      style: pw.TextStyle(
                        font: ttfBold,
                        fontSize: 20,
                        color: PdfColors.white,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      className,
                      style: pw.TextStyle(font: ttf, fontSize: 14, color: PdfColors.white),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('البيان', style: pw.TextStyle(font: ttfBold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('القيمة', style: pw.TextStyle(font: ttfBold)),
                      ),
                    ],
                  ),
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('اسم الامتحان', style: pw.TextStyle(font: ttf)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(exam.title, style: pw.TextStyle(font: ttf)),
                    ),
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('التاريخ', style: pw.TextStyle(font: ttf)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(DateFormat('dd/MM/yyyy').format(exam.date), style: pw.TextStyle(font: ttf)),
                    ),
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('الدرجة القصوى', style: pw.TextStyle(font: ttf)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(exam.maxScore.toStringAsFixed(1), style: pw.TextStyle(font: ttf)),
                    ),
                  ]),
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('متوسط الدرجات', style: pw.TextStyle(font: ttf)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(avg.toStringAsFixed(1), style: pw.TextStyle(font: ttf)),
                    ),
                  ]),
                ],
              ),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1.5),
                  2: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم الطالب', style: pw.TextStyle(font: ttfBold, color: PdfColors.white)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الدرجة', style: pw.TextStyle(font: ttfBold, color: PdfColors.white), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الحالة', style: pw.TextStyle(font: ttfBold, color: PdfColors.white), textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  ..._students.map((student) {
                    final status = _studentStatus[student.id!]?[exam.id!] ?? GradeStatus.present;
                    final grade = _studentGrades[student.id!]?[exam.id!];
                    final statusText = _mapStatusEnumToString(status);
                    final gradeText = (status == GradeStatus.exempt || status == GradeStatus.postponed)
                        ? ''
                        : (grade?.toInt().toString() ?? '-');
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(gradeText, style: pw.TextStyle(font: ttf), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(statusText, style: pw.TextStyle(font: ttf), textAlign: pw.TextAlign.center),
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

      if (context.mounted) {
        Navigator.pop(context);
      }

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'تقرير_امتحان_${exam.title}_${DateFormat('yyyyMMdd').format(exam.date)}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء تقرير الامتحان: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleDeleteMode() {
    setState(() {
      _isDeletingMode = !_isDeletingMode;
      _selectedStudents.clear();
    });
  }

  void _toggleStudentSelection(int studentId) {
    setState(() {
      if (_selectedStudents.contains(studentId)) {
        _selectedStudents.remove(studentId);
      } else {
        _selectedStudents.add(studentId);
      }
    });
  }

  Future<void> _deleteSelectedStudents() async {
    if (_selectedStudents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تأكيد الحذف',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'هل أنت متأكد من حذف ${_selectedStudents.length} طالب؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final ids = _selectedStudents.toList();
    for (final studentId in ids) {
      await studentProvider.deleteStudent(studentId);
    }

    if (!mounted) return;
    setState(() {
      _isDeletingMode = false;
      _selectedStudents.clear();
    });

    await _loadData();
  }

  GradeStatus _mapStatusStringToEnum(String? status) {
    switch ((status ?? 'حاضر').trim()) {
      case 'غائب':
        return GradeStatus.absent;
      case 'غش':
        return GradeStatus.cheating;
      case 'مفقودة':
        return GradeStatus.missing;
      case 'معفئ':
        return GradeStatus.exempt;
      case 'مؤجل':
        return GradeStatus.exempt;
      case 'معفئ او مؤجل':
        return GradeStatus.exempt;
      case 'حاضر':
      default:
        return GradeStatus.present;
    }
  }

  String _mapStatusEnumToString(GradeStatus status) {
    switch (status) {
      case GradeStatus.absent:
        return 'غائب';
      case GradeStatus.cheating:
        return 'غش';
      case GradeStatus.missing:
        return 'مفقودة';
      case GradeStatus.exempt:
        return 'معفئ او مؤجل';
      case GradeStatus.postponed:
        return 'معفئ او مؤجل';
      case GradeStatus.present:
      default:
        return 'حاضر';
    }
  }

  String _getSortTypeName(ExamSortType type) {
    switch (type) {
      case ExamSortType.name:
        return 'اسم الطالب';
      case ExamSortType.attendanceRate:
        return 'نسبة الحضور';
      case ExamSortType.absenceRate:
        return 'نسبة الغياب';
      case ExamSortType.highestAverage:
        return 'أعلى معدل';
      case ExamSortType.lowestAverage:
        return 'أقل معدل';
    }
  }

  // دالة عرض الصورة المكبرة
  void _showImageViewer(StudentModel student) {
    if (student.photoPath != null) {
      showImageViewer(context, student.photoPath!);
    } else if (student.photo != null) {
      // عرض صورة الشبكة إذا كانت موجودة
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black54,
                ),
              ),
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      student.photo!,
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.height * 0.8,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Future<void> _loadData() async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    await Future.wait([
      studentProvider.loadStudentsByClass(widget.classModel.id!),
      examProvider.loadExamsByClass(widget.classModel.id!),
    ]);
    
    if (mounted) {
      setState(() {
        _students = studentProvider.students;
        _exams = List<ExamModel>.from(examProvider.exams)
          ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
      });
    }

    await _loadAttendanceStats();
    
    _loadGrades();
  }

  Future<void> _loadAttendanceStats() async {
    try {
      final classId = widget.classModel.id;
      if (classId == null) return;

      final db = DatabaseHelper();
      final lectures = await db.getLecturesByClass(classId);
      final lectureIds = lectures.map((l) => l.id).whereType<int>().toSet();

      final Map<int, Map<String, int>> stats = {};
      for (final student in _students) {
        final sid = student.id;
        if (sid == null) continue;

        final allAttendances = await db.getAttendanceByStudent(sid);
        final attendances = allAttendances.where((a) => lectureIds.contains(a.lectureId)).toList();

        stats[sid] = {
          'present': attendances.where((a) => a.status == AttendanceStatus.present).length,
          'absent': attendances.where((a) => a.status == AttendanceStatus.absent).length,
          'late': attendances.where((a) => a.status == AttendanceStatus.late).length,
          'expelled': attendances.where((a) => a.status == AttendanceStatus.expelled).length,
          'excused': attendances.where((a) => a.status == AttendanceStatus.excused).length,
        };
      }

      if (!mounted) return;
      setState(() {
        _studentAttendanceStats
          ..clear()
          ..addAll(stats);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _studentAttendanceStats.clear();
      });
    }
  }

  Future<void> _loadGrades() async {
    final gradeProvider = Provider.of<GradeProvider>(context, listen: false);
    
    for (final student in _students) {
      final grades = await gradeProvider.getGradesByStudent(student.id!);
      
      for (final grade in grades) {
        final exam = _exams.firstWhere(
          (e) => e.title == grade.examName,
          orElse: () => ExamModel(
            id: 0,
            title: grade.examName,
            date: grade.examDate,
            maxScore: grade.maxScore,
            classId: widget.classModel.id!,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        
        if (!_studentGrades.containsKey(student.id)) {
          _studentGrades[student.id!] = {};
          _studentStatus[student.id!] = {};
          _studentComments[student.id!] = {};
        }
        
        _studentGrades[student.id!]![exam.id!] = grade.score;
        
        _studentComments[student.id!]![exam.id!] = grade.notes ?? '';

        _studentStatus[student.id!]![exam.id!] = _mapStatusStringToEnum(grade.status);
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Color _getGradeColor(double grade, double maxScore) {
    final percentage = (grade / maxScore) * 100;
    
    if (percentage >= 95) return Colors.green[800]!;
    if (percentage >= 90) return Colors.green[700]!;
    if (percentage >= 85) return Colors.green[600]!;
    if (percentage >= 80) return Colors.lime[600]!;
    if (percentage >= 75) return Colors.lime[500]!;
    if (percentage >= 70) return Colors.yellow[600]!;
    if (percentage >= 65) return Colors.orange[600]!;
    if (percentage >= 60) return Colors.orange[700]!;
    if (percentage >= 55) return Colors.deepOrange[600]!;
    if (percentage >= 50) return Colors.red[600]!;
    return Colors.red[800]!;
  }

  Widget _buildGradeBox(StudentModel student, ExamModel exam) {
    final grade = _studentGrades[student.id!]?[exam.id!];
    final status = _studentStatus[student.id!]?[exam.id!];
    final comment = _studentComments[student.id!]?[exam.id!];
    
    String displayText;
    Color backgroundColor;
    Color textColor = Colors.white;
    
    if (status == GradeStatus.absent) {
      displayText = 'غائب';
      backgroundColor = Colors.orange[700]!;
    } else if (status == GradeStatus.cheating) {
      displayText = 'غش';
      backgroundColor = Colors.red[700]!;
    } else if (status == GradeStatus.missing) {
      displayText = 'مفقودة';
      backgroundColor = Colors.purple[700]!;
    } else if (status == GradeStatus.exempt || status == GradeStatus.postponed) {
      displayText = 'معفئ او مؤجل';
      backgroundColor = Colors.blue[700]!;
    } else if (grade != null) {
      displayText = '${grade.toInt()}/${exam.maxScore.toInt()}';
      backgroundColor = _getGradeColor(grade, exam.maxScore);
    } else {
      displayText = '-';
      backgroundColor = Colors.grey[700]!;
    }
    
    return GestureDetector(
      onTap: () => _showGradeDialog(student, exam),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 70,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  displayText,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                if (comment?.isNotEmpty == true)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.yellow[600],
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showGradeDialog(student, exam),
            child: Container(
              width: 110,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.grey.shade600,
                  width: 0.5,
                ),
              ),
              child: Center(
                child: Text(
                  comment?.isEmpty != false ? 'اكتب تعليق' : comment!,
                  style: TextStyle(
                    fontSize: 8,
                    color: comment?.isEmpty != false ? Colors.grey : Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGradeDialog(StudentModel student, ExamModel exam) {
    final gradeController = TextEditingController();
    final commentController = TextEditingController();
    GradeStatus status = GradeStatus.present;
    
    if (_studentGrades[student.id!]?.containsKey(exam.id!) == true) {
      gradeController.text = _studentGrades[student.id!]![exam.id!]!.toString();
    }
    if (_studentStatus[student.id!]?.containsKey(exam.id!) == true) {
      status = _studentStatus[student.id!]![exam.id!]!;
    }
    if (_studentComments[student.id!]?.containsKey(exam.id!) == true) {
      commentController.text = _studentComments[student.id!]![exam.id!]!;
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${student.name} - ${exam.title}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      RadioListTile<GradeStatus>(
                        title: const Text('حاضر'),
                        value: GradeStatus.present,
                        groupValue: status,
                        onChanged: (value) {
                          setDialogState(() {
                            status = value!;
                            if (status != GradeStatus.present) {
                              gradeController.text = '0';
                            }
                          });
                        },
                      ),
                      RadioListTile<GradeStatus>(
                        title: const Text('غائب'),
                        value: GradeStatus.absent,
                        groupValue: status,
                        onChanged: (value) {
                          setDialogState(() {
                            status = value!;
                            gradeController.text = '0';
                          });
                        },
                      ),
                      RadioListTile<GradeStatus>(
                        title: const Text('غش'),
                        value: GradeStatus.cheating,
                        groupValue: status,
                        onChanged: (value) {
                          setDialogState(() {
                            status = value!;
                            gradeController.text = '0';
                          });
                        },
                      ),
                      RadioListTile<GradeStatus>(
                        title: const Text('مفقودة'),
                        value: GradeStatus.missing,
                        groupValue: status,
                        onChanged: (value) {
                          setDialogState(() {
                            status = value!;
                            gradeController.text = '0';
                          });
                        },
                      ),
                      RadioListTile<GradeStatus>(
                        title: const Text('معفئ او مؤجل'),
                        value: GradeStatus.exempt,
                        groupValue: status == GradeStatus.postponed ? GradeStatus.exempt : status,
                        onChanged: (value) {
                          setDialogState(() {
                            status = value!;
                            gradeController.clear();
                          });
                        },
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                TextField(
                  controller: gradeController,
                  decoration: InputDecoration(
                    labelText: 'الدرجة',
                    hintText: 'من ${exam.maxScore}',
                    prefixIcon: const Icon(Icons.grade),
                    enabled: status == GradeStatus.present,
                  ),
                  keyboardType: TextInputType.number,
                ),
                
                const SizedBox(height: 16),
                
                TextField(
                  controller: commentController,
                  decoration: const InputDecoration(
                    labelText: 'تعليق',
                    hintText: 'ملاحظات إضافية',
                    prefixIcon: Icon(Icons.comment),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final gradeProvider = Provider.of<GradeProvider>(context, listen: false);

                double grade = 0;
                if (status == GradeStatus.present) {
                  final parsed = double.tryParse(gradeController.text.trim());
                  if (parsed == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('يرجى إدخال درجة صحيحة'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  if (parsed < 0 || parsed > exam.maxScore) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('الدرجة يجب أن تكون بين 0 و ${exam.maxScore.toInt()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  grade = parsed;
                }

                if (status == GradeStatus.exempt || status == GradeStatus.postponed) {
                  grade = 0;
                }

                final String notes = commentController.text;
                final String statusString = _mapStatusEnumToString(status);
                
                // التحقق من وجود درجة سابقة فقط لغرض رسالة النجاح
                final existingGrades = await gradeProvider.getGradesByStudent(student.id!);
                final existingGrade =
                    existingGrades.where((g) => g.examName == exam.title).firstOrNull;

                bool success = false;
                try {
                  // لا نحذف يدوياً هنا؛ الـ provider يقوم بالحذف/التحديث داخلياً
                  success = await gradeProvider.addGrade(
                    studentId: student.id!,
                    examName: exam.title,
                    score: grade,
                    maxScore: exam.maxScore,
                    examDate: exam.date,
                    notes: notes,
                    status: statusString,
                  );
                } catch (e) {
                  success = false;
                }
                
                if (success) {
                  // إعادة تحميل الدرجات لضمان التحديث الصحيح
                  await _loadGrades();
                  if (mounted) {
                    Provider.of<StudentProvider>(context, listen: false)
                        .refreshIndicators();
                  }
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        existingGrade != null 
                          ? 'تم تحديث درجة ${student.name} في ${exam.title}'
                          : 'تم حفظ درجة ${student.name} في ${exam.title}'
                      ),
                      backgroundColor: existingGrade != null ? Colors.blue : Colors.green,
                    ),
                  );
                } else {
                  final providerError = gradeProvider.error;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        providerError != null && providerError.isNotEmpty
                            ? providerError
                            : 'فشل في حفظ الدرجة',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExamDialog() {
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة امتحان جديد'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 16),
              _buildExamDatePickerTile(
                date: selectedDate,
                onTap: () async {
                  final date = await _showExamDatePicker(selectedDate);
                  if (date != null && mounted) {
                    setState(() {
                      selectedDate = date;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxScoreController,
                decoration: const InputDecoration(
                  labelText: 'الدرجة القصوى',
                  prefixIcon: Icon(Icons.grade),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                final examProvider = Provider.of<ExamProvider>(context, listen: false);
                
                final success = await examProvider.addExam(
                  title: titleController.text,
                  date: selectedDate,
                  maxScore: double.parse(maxScoreController.text),
                  classId: widget.classModel.id!,
                );
                
                if (success) {
                  if (mounted) {
                    setState(() {
                      _exams = List<ExamModel>.from(examProvider.exams)
                        ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                    });
                  }
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم إضافة امتحان: ${titleController.text}')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فشل في إضافة الامتحان')),
                  );
                }
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _showExamDatePicker(DateTime initialDate) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFEC619),
              surface: Color(0xFF2A2A2A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Widget _buildExamDatePickerTile({
    required DateTime date,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(date)}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.end,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  void _showAddExamOptions() {
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool addToAllClasses = false;
    bool addToSelectedClasses = false;
    final List<int> selectedClassIds = [];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة امتحان'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الامتحان',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 16),
                _buildExamDatePickerTile(
                  date: selectedDate,
                  onTap: () async {
                    final date = await _showExamDatePicker(selectedDate);
                    if (date != null) {
                      setDialogState(() {
                        selectedDate = date;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: maxScoreController,
                  decoration: const InputDecoration(
                    labelText: 'الدرجة القصوى',
                    prefixIcon: Icon(Icons.grade),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                const Text(
                  'إضافة الامتحان لـ:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                RadioListTile<bool>(
                  title: const Text('هذا الفصل فقط'),
                  value: false,
                  groupValue: addToAllClasses || addToSelectedClasses,
                  onChanged: (value) {
                    setDialogState(() {
                      addToAllClasses = false;
                      addToSelectedClasses = false;
                    });
                  },
                ),
                RadioListTile<bool>(
                  title: const Text('فصول محددة'),
                  value: true,
                  groupValue: addToSelectedClasses,
                  onChanged: (value) {
                    setDialogState(() {
                      addToAllClasses = false;
                      addToSelectedClasses = true;
                    });
                  },
                ),
                RadioListTile<bool>(
                  title: const Text('كل الفصول'),
                  value: true,
                  groupValue: addToAllClasses,
                  onChanged: (value) {
                    setDialogState(() {
                      addToAllClasses = true;
                      addToSelectedClasses = false;
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                  final examProvider = Provider.of<ExamProvider>(context, listen: false);
                  final classProvider = Provider.of<ClassProvider>(context, listen: false);
                  
                  if (addToAllClasses) {
                    // إضافة لكل الفصول
                    for (final classItem in classProvider.classes) {
                      await examProvider.addExam(
                        title: titleController.text,
                        date: selectedDate,
                        maxScore: double.parse(maxScoreController.text),
                        classId: classItem.id!,
                      );
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم إضافة امتحان: ${titleController.text} لكل الفصول')),
                    );
                  } else if (addToSelectedClasses) {
                    // إضافة لفصول محددة
                    Navigator.pop(context);
                    _showClassSelectionDialog(titleController.text, selectedDate, double.parse(maxScoreController.text));
                    return;
                  } else {
                    // إضافة لهذا الفصل فقط
                    await examProvider.addExam(
                      title: titleController.text,
                      date: selectedDate,
                      maxScore: double.parse(maxScoreController.text),
                      classId: widget.classModel.id!,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم إضافة امتحان: ${titleController.text}')),
                    );
                  }
                  
                  if (mounted) {
                    setState(() {
                      _exams = List<ExamModel>.from(examProvider.exams)
                        ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                    });
                  }
                  
                  Navigator.pop(context);
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showClassSelectionDialog(String examTitle, DateTime examDate, double maxScore) {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final List<int> selectedClassIds = [];
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اختر الفصول'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: ListView.builder(
              itemCount: classProvider.classes.length,
              itemBuilder: (context, index) {
                final classItem = classProvider.classes[index];
                final studentsInClass = studentProvider.students.where((s) => s.classId == classItem.id).toList();
                return CheckboxListTile(
                  title: Text(classItem.name),
                  subtitle: Text('${studentsInClass.length} طالب'),
                  value: selectedClassIds.contains(classItem.id),
                  onChanged: (value) {
                    setDialogState(() {
                      if (value == true) {
                        selectedClassIds.add(classItem.id!);
                      } else {
                        selectedClassIds.remove(classItem.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedClassIds.isNotEmpty) {
                  final examProvider = Provider.of<ExamProvider>(context, listen: false);
                  
                  for (final classId in selectedClassIds) {
                    await examProvider.addExam(
                      title: examTitle,
                      date: examDate,
                      maxScore: maxScore,
                      classId: classId,
                    );
                  }
                  
                  if (mounted) {
                    setState(() {
                      _exams = List<ExamModel>.from(examProvider.exams)
                        ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                    });
                  }
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم إضافة امتحان: $examTitle لـ ${selectedClassIds.length} فصول')),
                  );
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExamToSelectedClassesDialog(List<int> classIds) {
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة امتحان للفصول المحددة'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text('تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Color(0xFFFEC619),
                            surface: Color(0xFF2A2A2A),
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    if (mounted) {
                      setState(() {
                        selectedDate = date;
                      });
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxScoreController,
                decoration: const InputDecoration(
                  labelText: 'الدرجة القصوى',
                  prefixIcon: Icon(Icons.grade),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                final examProvider = Provider.of<ExamProvider>(context, listen: false);
                
                for (final classId in classIds) {
                  await examProvider.addExam(
                    title: titleController.text,
                    date: selectedDate,
                    maxScore: double.parse(maxScoreController.text),
                    classId: classId,
                  );
                }
                
                if (mounted) {
                  setState(() {
                    _exams = List<ExamModel>.from(examProvider.exams)
                      ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                  });
                }
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم إضافة امتحان: ${titleController.text} لـ ${classIds.length} فصول')),
                );
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showAddExamToAllClassesDialog() {
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة امتحان لكل الفصول'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان',
                  prefixIcon: Icon(Icons.title),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text('تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Color(0xFFFEC619),
                            surface: Color(0xFF2A2A2A),
                            onSurface: Colors.white,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    if (mounted) {
                      setState(() {
                        selectedDate = date;
                      });
                    }
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxScoreController,
                decoration: const InputDecoration(
                  labelText: 'الدرجة القصوى',
                  prefixIcon: Icon(Icons.grade),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                final examProvider = Provider.of<ExamProvider>(context, listen: false);
                final classProvider = Provider.of<ClassProvider>(context, listen: false);
                
                for (final classItem in classProvider.classes) {
                  await examProvider.addExam(
                    title: titleController.text,
                    date: selectedDate,
                    maxScore: double.parse(maxScoreController.text),
                    classId: classItem.id!,
                  );
                }
                
                if (mounted) {
                  setState(() {
                    _exams = List<ExamModel>.from(examProvider.exams)
                      ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                  });
                }
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم إضافة امتحان: ${titleController.text} لكل الفصول')),
                );
              }
            },
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  void _showAutoFillDialog(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ملء تلقائي - ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.grade, color: Colors.green),
              title: const Text('أعلى درجة'),
              subtitle: Text('يعطي كل الطلاب ${exam.maxScore.toInt()}'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, exam.maxScore, GradeStatus.present);
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.red),
              title: const Text('صفر'),
              subtitle: const Text('يعطي كل الطلاب صفر'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.present);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('درجة مخصصة'),
              subtitle: const Text('اختر درجة محددة لكل الطلاب'),
              onTap: () {
                Navigator.pop(context);
                _showCustomGradeDialog(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.orange),
              title: const Text('غائب'),
              subtitle: const Text('يعتبر كل الطلاب غائبين'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.absent);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: const Text('غش'),
              subtitle: const Text('يعتبر كل الطلاب غاشين'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.cheating);
              },
            ),
            ListTile(
              leading: const Icon(Icons.find_replace, color: Colors.purple),
              title: const Text('مفقودة'),
              subtitle: const Text('يعتبر كل الأوراق مفقودة'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.missing);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomGradeDialog(ExamModel exam) {
    final gradeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('درجة مخصصة - ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: gradeController,
              decoration: InputDecoration(
                labelText: 'الدرجة',
                hintText: 'من ${exam.maxScore}',
                prefixIcon: const Icon(Icons.grade),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (gradeController.text.isNotEmpty) {
                final grade = double.parse(gradeController.text);
                Navigator.pop(context);
                _autoFillGrades(exam, grade, GradeStatus.present);
              }
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  void _autoFillGrades(ExamModel exam, double grade, GradeStatus status) async {
    final gradeProvider = Provider.of<GradeProvider>(context, listen: false);
    
    for (final student in _students) {
      final String notes = '';
      final String statusString = _mapStatusEnumToString(status);
      
      await gradeProvider.addGrade(
        studentId: student.id!,
        examName: exam.title,
        score: grade,
        maxScore: exam.maxScore,
        examDate: exam.date,
        notes: notes,
        status: statusString,
      );
    }
    
    await _loadGrades();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم ملء الدرجات تلقائياً لـ ${_students.length} طالب')),
    );
  }

  void _showExamOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D), // خلفية رمادية داكنة
        title: Text(
          'خيارات الامتحان',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.description, color: Colors.teal, size: 20),
                title: const Text(
                  'تقرير عن الامتحان',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showExamReport(exam);
                },
              ),
              ListTile(
                leading: const Icon(Icons.bar_chart, color: Colors.blue, size: 20),
                title: const Text(
                  'إحصائيات الامتحان',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ExamStatisticsScreen(
                        exam: exam,
                        classModel: widget.classModel,
                        studentGrades: _studentGrades,
                        studentStatus: _studentStatus,
                        students: _students,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.star, color: Colors.amber, size: 20),
                title: const Text(
                  'أفضل الطلاب في الامتحان',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showBestStudentsInExam(exam);
                },
              ),
              ListTile(
                leading: const Icon(Icons.grade, color: Colors.purple, size: 20),
                title: const Text(
                  'علئ درجات',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _sortStudentsByExamGrade(exam);
                },
              ),
              ListTile(
                leading: const Icon(Icons.format_color_fill, color: Colors.green, size: 20),
                title: const Text(
                  'ملء تلقائي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAutoFillDialog(exam);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_calendar, color: Colors.orange, size: 20),
                title: const Text(
                  'تعديل تاريخ الامتحان',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDateDialog(exam);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red, size: 20),
                title: const Text(
                  'حذف الامتحان',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteExam(exam);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'إغلاق',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDateDialog(ExamModel exam) {
    DateTime selectedDate = exam.date;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل تاريخ الامتحان: ${exam.title}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return _buildExamDatePickerTile(
              date: selectedDate,
              onTap: () async {
                final date = await _showExamDatePicker(selectedDate);
                if (date != null) {
                  setDialogState(() {
                    selectedDate = date;
                  });
                }
              },
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final examProvider = Provider.of<ExamProvider>(context, listen: false);
              final success = await examProvider.updateExam(
                exam.copyWith(
                  date: selectedDate,
                  updatedAt: DateTime.now(),
                ),
              );
              
              if (success) {
                if (mounted) {
                  setState(() {
                    _exams = List<ExamModel>.from(examProvider.exams)
                      ..sort((a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date));
                  });
                }
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تحديث تاريخ الامتحان')),
                );
              }
            },
            child: const Text('تحديث'),
          ),
        ],
      ),
    );
  }

  // دالة إرسال إيميل للامتحان
  Future<void> _sendExamEmail(ExamModel exam) async {
    try {
      // الحصول على قائمة الطلاب الذين لديهم إيميل
      final studentsWithEmail = _students.where((student) => student.hasEmail()).toList();
      
      if (studentsWithEmail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد طلاب لديهم إيميل في هذا الفصل'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // إنشاء تقرير PDF للامتحان
      final pdfBytes = await _generateExamPDF(exam);
      
      // حفظ الملف مؤقتاً
      final fileName = 'exam_${widget.classModel.name}_${exam.title}_${DateFormat('yyyyMMdd').format(exam.date)}.pdf';
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      // الانتقال لصفحة إرسال الإيميل
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmailSendingScreen(
              attachmentPath: file.path,
              attachmentName: fileName,
              defaultSubject: 'تقرير امتحان: ${exam.title}',
              defaultMessage: '''السلام عليكم،

مرفق تقرير امتحان "${exam.title}" للفصل "${widget.classModel.name}" الذي أقيم بتاريخ ${DateFormat('dd/MM/yyyy').format(exam.date)}.

مع أطيب التحيات،
الأستاذ باقر القرغولي''',
              preselectedStudentIds: studentsWithEmail.map((s) => s.id!).toList(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // دالة إنشاء PDF للامتحان
  Future<List<int>> _generateExamPDF(ExamModel exam) async {
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'تقرير امتحان',
                    style: pw.TextStyle(
                      font: arabicFont,
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    DateFormat('dd/MM/yyyy').format(DateTime.now()),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              
              // Exam Info
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'عنوان الامتحان: ${exam.title}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الفصل: ${widget.classModel.name}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'التاريخ: ${DateFormat('dd/MM/yyyy').format(exam.date)}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الدرجة القصوى: ${exam.maxScore.toInt()}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // Results Table
              pw.Text(
                'نتائج الامتحان',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 10),
              
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FixedColumnWidth(40),
                  1: const pw.FlexColumnWidth(2),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(2),
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
                          child: pw.Text(
                            '#',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
                          child: pw.Text(
                            'اسم الطالب',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
                          child: pw.Text(
                            'الدرجة',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
                          child: pw.Text(
                            'الحالة',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
                          child: pw.Text(
                            'ملاحظات',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Students
                  ..._students.asMap().entries.map((entry) {
                    final index = entry.key;
                    final student = entry.value;
                    final grade = _studentGrades[student.id]?[exam.id] ?? 0;
                    final status = _studentStatus[student.id]?[exam.id] ?? GradeStatus.absent;
                    final comment = _studentComments[student.id]?[exam.id] ?? '';
                    
                    return pw.TableRow(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              '${index + 1}',
                              style: pw.TextStyle(font: arabicFont),
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            student.name,
                            style: pw.TextStyle(font: arabicFont),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              status == GradeStatus.present ? grade.toString() : '-',
                              style: pw.TextStyle(font: arabicFont),
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              _getGradeStatusText(status),
                              style: pw.TextStyle(
                                font: arabicFont,
                                color: _getGradeStatusColor(status),
                              ),
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            comment,
                            style: pw.TextStyle(font: arabicFont),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
              
              // Summary
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'إحصائيات الامتحان',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'إجمالي الطلاب: ${_students.length}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                    pw.Text(
                      'الحاضرون: ${_students.where((s) => _studentStatus[s.id]?[exam.id] == GradeStatus.present).length}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                    pw.Text(
                      'الغائبون: ${_students.where((s) => _studentStatus[s.id]?[exam.id] == GradeStatus.absent).length}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                    pw.Text(
                      'متوسط الدرجات: ${_calculateExamAverage(exam).toStringAsFixed(1)}',
                      style: pw.TextStyle(font: arabicFont, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return await pdf.save();
  }

  String _getGradeStatusText(GradeStatus status) {
    switch (status) {
      case GradeStatus.present:
        return 'حاضر';
      case GradeStatus.absent:
        return 'غائب';
      case GradeStatus.cheating:
        return 'غش';
      case GradeStatus.missing:
        return 'مفقودة';
      case GradeStatus.exempt:
        return 'معفئ او مؤجل';
      case GradeStatus.postponed:
        return 'معفئ او مؤجل';
    }
  }

  PdfColor _getGradeStatusColor(GradeStatus status) {
    switch (status) {
      case GradeStatus.present:
        return PdfColors.green;
      case GradeStatus.absent:
        return PdfColors.red;
      case GradeStatus.cheating:
        return PdfColors.orange;
      case GradeStatus.missing:
        return PdfColors.purple;
      case GradeStatus.exempt:
      case GradeStatus.postponed:
        return PdfColors.blue;
    }
  }

  double _calculateExamAverage(ExamModel exam) {
    final presentStudents = _students.where((s) => _studentStatus[s.id]?[exam.id] == GradeStatus.present);
    if (presentStudents.isEmpty) return 0.0;
    
    final totalGrades = presentStudents.fold<double>(0, (sum, student) {
      final grade = _studentGrades[student.id]?[exam.id] ?? 0;
      return sum + grade;
    });
    
    return totalGrades / presentStudents.length;
  }

  void _navigateToExamStatistics(ExamModel exam) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamStatisticsScreen(
          exam: exam,
          students: _students,
          studentGrades: _studentGrades,
          studentStatus: _studentStatus,
          classModel: widget.classModel,
        ),
      ),
    );
  }

  void _showBestStudentsInExam(ExamModel exam) {
    // ترتيب الطلاب حسب درجة هذا الامتحان
    final sortedStudents = List<StudentModel>.from(_students);
    sortedStudents.sort((a, b) {
      final gradeA = _studentGrades[a.id!]?[exam.id!] ?? -1;
      final gradeB = _studentGrades[b.id!]?[exam.id!] ?? -1;
      final statusA = _studentStatus[a.id!]?[exam.id!];
      final statusB = _studentStatus[b.id!]?[exam.id!];
      
      // إعطاء أولوية للطلاب الحاضرين
      if (statusA == GradeStatus.present && statusB != GradeStatus.present) {
        return -1;
      } else if (statusA != GradeStatus.present && statusB == GradeStatus.present) {
        return 1;
      }
      
      // ترتيب حسب الدرجة (من الأعلى إلى الأقل)
      return gradeB.compareTo(gradeA);
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D),
        title: Text(
          'أفضل الطلاب في ${exam.title}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 400,
          height: 500,
          child: ListView.builder(
            itemCount: sortedStudents.length,
            itemBuilder: (context, index) {
              final student = sortedStudents[index];
              final grade = _studentGrades[student.id!]?[exam.id!];
              final status = _studentStatus[student.id!]?[exam.id!];
              
              if (status != GradeStatus.present || grade == null) {
                return const SizedBox.shrink();
              }
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: index < 3 ? Colors.amber : Colors.grey[600],
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  student.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'الدرجة: ${grade.toStringAsFixed(1)}/${exam.maxScore}',
                  style: TextStyle(color: Colors.grey[300]),
                ),
                trailing: Text(
                  '${((grade / exam.maxScore) * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _sortStudentsByExamGrade(ExamModel exam) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          // ترتيب الطلاب حسب درجة هذا الامتحان المحدد
          _students.sort((a, b) {
            final gradeA = _studentGrades[a.id!]?[exam.id!] ?? -1;
            final gradeB = _studentGrades[b.id!]?[exam.id!] ?? -1;
            final statusA = _studentStatus[a.id!]?[exam.id!];
            final statusB = _studentStatus[b.id!]?[exam.id!];
            
            // إعطاء أولوية للطلاب الحاضرين
            if (statusA == GradeStatus.present && statusB != GradeStatus.present) {
              return -1;
            } else if (statusA != GradeStatus.present && statusB == GradeStatus.present) {
              return 1;
            }
            
            // ترتيب حسب الدرجة (من الأعلى إلى الأقل)
            return gradeB.compareTo(gradeA);
          });
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم ترتيب الطلاب حسب درجات ${exam.title}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _deleteExam(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الامتحان'),
        content: Text('هل أنت متأكد من حذف امتحان "${exam.title}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final examProvider = Provider.of<ExamProvider>(context, listen: false);
              final success = await examProvider.deleteExam(exam.id!);
              
              if (success) {
                if (mounted) {
                  setState(() {
                    _exams = List<ExamModel>.from(examProvider.exams)
                      ..sort((a, b) => a.date.compareTo(b.date));
                  });
                }
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حذف امتحان: ${exam.title}')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('فشل في حذف الامتحان')),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  List<StudentModel> _sortStudents(
    List<StudentModel> students, {
    bool publish = true,
    bool applySyncedOrder = true,
  }) {
    List<StudentModel> filtered = students;
    if (_searchQuery.isNotEmpty) {
      filtered = students.where((student) {
        return student.name.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    final List<StudentModel> base = List.from(filtered);

    // ملاحظة: لا نطبق ترتيب IDs المتزامن هنا لأن الترتيب يجب أن يتبع نوع الفرز المتزامن (أعلى معدل/...)

    // Otherwise, fall back to this screen's local sorting.
    switch (_sortType) {
      case ExamSortType.attendanceRate:
        base.sort((a, b) {
          final aStats = _studentAttendanceStats[a.id ?? -1] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentAttendanceStats[b.id ?? -1] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aPresent = aStats['present'] ?? 0;
          final bPresent = bStats['present'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aPresent / aTotal : 0.0;
          final bRate = bTotal > 0 ? bPresent / bTotal : 0.0;
          return bRate.compareTo(aRate);
        });
        break;

      case ExamSortType.absenceRate:
        base.sort((a, b) {
          final aStats = _studentAttendanceStats[a.id ?? -1] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentAttendanceStats[b.id ?? -1] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aAbsent = aStats['absent'] ?? 0;
          final bAbsent = bStats['absent'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aAbsent / aTotal : 0.0;
          final bRate = bTotal > 0 ? bAbsent / bTotal : 0.0;
          return bRate.compareTo(aRate);
        });
        break;

      case ExamSortType.highestAverage:
        base.sort((a, b) => _calculateStudentAverage(b.id!).compareTo(_calculateStudentAverage(a.id!)));
        break;
      case ExamSortType.lowestAverage:
        base.sort((a, b) => _calculateStudentAverage(a.id!).compareTo(_calculateStudentAverage(b.id!)));
        break;
      case ExamSortType.name:
        base.sort((a, b) => a.name.compareTo(b.name));
        break;
    }

    if (publish) {
      // publish is controlled by callers (we don't want to write prefs on every build).
    }

    return base;
  }

  double _calculateStudentAverage(int studentId) {
    if (!_studentGrades.containsKey(studentId)) return 0.0;
    
    double total = 0;
    int count = 0;
    
    for (final exam in _exams) {
      final status = _studentStatus[studentId]?[exam.id!];
      if (status == GradeStatus.exempt || status == GradeStatus.postponed) {
        continue;
      }
      final grade = _studentGrades[studentId]?[exam.id!];
      if (grade != null) {
        total += (grade / exam.maxScore) * 100;
        count++;
      }
    }
    
    return count > 0 ? total / count : 0.0;
  }

  Future<Map<String, bool>> _checkStudentStatus(StudentModel student) async {
    final status = await UnifiedStudentStatusService.checkStudentStatus(
      student,
      classId: widget.classModel.id,
    );
    return {
      'isExcellent': status['isExcellent'] ?? false,
      'isAtRisk': status['isAtRisk'] ?? false,
    };
  }

  Future<bool> _areIndicatorsHidden() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('student_status_indicators_hidden') ?? false;
  }

  bool _hasAttendanceIssues(StudentModel student) {
    // التحقق من وجود مشاكل في الحضور (غيابات أو غياب في الامتحانات)
    for (final exam in _exams) {
      final status = _studentStatus[student.id!]?[exam.id!];
      if (status == GradeStatus.absent || status == GradeStatus.missing) {
        return true;
      }
    }
    return false;
  }

  // دالة لبناء مؤشر حالة الطالب (نجمة صفراء أو نقطة حمراء)
  Widget _buildStudentStatusIndicator(StudentModel student) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        return FutureBuilder<bool>(
          key: ValueKey('hide_${studentProvider.updateCounter}'),
          future: _areIndicatorsHidden(),
          builder: (context, hiddenSnap) {
            if (hiddenSnap.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 16, height: 16);
            }

            final hidden = hiddenSnap.data ?? false;
            if (hidden) {
              return const SizedBox(width: 16, height: 16);
            }

            return FutureBuilder<Map<String, bool>>(
              key: ValueKey(studentProvider.updateCounter),
              future: _checkStudentStatus(student),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(width: 16, height: 16);
                }

                final isExcellent = snapshot.data?['isExcellent'] ?? false;
                final isAtRisk = snapshot.data?['isAtRisk'] ?? false;

                if (!isExcellent && !isAtRisk) {
                  return const SizedBox(width: 20, height: 20);
                }

                // عرض الاثنين معاً إذا كان الطالب متجاوز معايير التميز والخطر
                final children = <Widget>[];
                if (isExcellent) {
                  children.add(
                    Container(
                      padding: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.15),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.yellow.withOpacity(0.3),
                            blurRadius: 1,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Colors.yellow,
                        size: 13,
                        shadows: [
                          Shadow(
                            color: Colors.orange,
                            blurRadius: 1,
                            offset: Offset(0.5, 0.5),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (isAtRisk) {
                  if (children.isNotEmpty) {
                    children.add(const SizedBox(width: 2));
                  }
                  children.add(
                    Container(
                      width: 6,
                      height: 6,
                      margin: EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.4),
                            blurRadius: 2,
                            spreadRadius: 0.5,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                );
              },
            );
          },
        );
      },
    );
  }

  bool _hasGoodPerformance(StudentModel student) {
    // التحقق من الأداء الممتاز (معدل 85% أو أعلى)
    final average = _calculateStudentAverage(student.id!);
    return average >= 85.0;
  }

  @override
  Widget build(BuildContext context) {
    final providerStudents = context.watch<StudentProvider>().students;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF404040),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list, color: Colors.white, size: 20),
                  tooltip: 'تصنيف',
                  onSelected: (value) {
                    if (value == 'latest') {
                      _setSortByLatest(!_sortByLatest);
                      return;
                    }

                    final type = ExamSortType.values.firstWhere(
                      (t) => 'type_${t.name}' == value,
                      orElse: () => _sortType,
                    );

                    setState(() {
                      _sortType = type;
                    });

                    final classId = widget.classModel.id;
                    if (classId != null) {
                      final mode = switch (type) {
                        ExamSortType.name => 'name',
                        ExamSortType.attendanceRate => 'attendance_rate',
                        ExamSortType.absenceRate => 'absence_rate',
                        ExamSortType.highestAverage => 'highest_average',
                        ExamSortType.lowestAverage => 'lowest_average',
                      };
                      StudentListOrderService.instance.setSortMode(classId: classId, mode: mode);
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[];

                    items.add(
                      PopupMenuItem<String>(
                        value: 'latest',
                        child: Row(
                          children: [
                            Icon(
                              Icons.check,
                              size: 18,
                              color: _sortByLatest ? Colors.yellow : Colors.transparent,
                            ),
                            const SizedBox(width: 8),
                            const Text('عرض البيانات حسب الأحدث'),
                          ],
                        ),
                      ),
                    );

                    for (final type in ExamSortType.values) {
                      items.add(
                        PopupMenuItem<String>(
                          value: 'type_${type.name}',
                          child: Row(
                            children: [
                              Icon(
                                Icons.check,
                                size: 18,
                                color: _sortType == type ? Colors.yellow : Colors.transparent,
                              ),
                              const SizedBox(width: 8),
                              Text(_getSortTypeName(type)),
                            ],
                          ),
                        ),
                      );
                    }

                    return items;
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'بحث عن طالب...',
                        hintStyle: TextStyle(color: Colors.grey),
                        prefixIcon: Icon(Icons.search, size: 20, color: Colors.white),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.toLowerCase();
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: Builder(
              builder: (context) {
                final students = _sortStudents(providerStudents);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'لا يوجد طلاب',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[400],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    if (_exams.isNotEmpty)
                      Container(
                        color: const Color(0xFF2D2D2D), // رمادي داكن
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 200, // نفس العرض الجديد لمعلومات الطالب
                              height: 80,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.yellow.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.yellow,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => StudentGalleryScreen(
                                            classId: widget.classModel.id!,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.photo_library,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showEditMenu,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const MessagingScreen(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.message,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // خط فاصل رمادي
                            Container(
                              width: 3,
                              height: 80,
                              color: const Color(0xFF404040), // رمادي
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            // العناوين والتواريخ
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _headerScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _exams.asMap().entries.map((entry) {
                                    final exam = entry.value;
                                    final index = entry.key;
                                    return GestureDetector(
                                      onTap: () => _showExamOptions(exam),
                                      child: Container(
                                        width: 140,
                                        alignment: Alignment.center,
                                        margin: EdgeInsets.only(
                                          left: index == 0 ? 8 : 8,
                                          right: index == _exams.length - 1 ? 8 : 0,
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            // العنوان في الأعلى
                                            Text(
                                              exam.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            // التاريخ تحت العنوان
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blue, width: 0.5),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM/yyyy').format(exam.date),
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'الامتحان ${_exams.indexOf(exam) + 1}',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // خط فاصل أفقي رمادي بين العناوين والطلاب
                    Container(
                      height: 3,
                      color: const Color(0xFF404040),
                    ),
                    // قائمة الطلاب
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: students.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 3,
                          thickness: 3,
                          color: Color(0xFF404040),
                        ),
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final studentAverage = _calculateStudentAverage(student.id!);
                          
                          return Container(
                            color: const Color(0xFF2D2D2D), // رمادي داكن
                            // إعادة الهامش كما كان حتى تبقى الأعمدة (التواريخ/المحاضرات) مصطفّة
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 200,
                                  padding: const EdgeInsets.all(8),
                                  child: Stack(
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (_isDeletingMode) ...[
                                                GestureDetector(
                                                  onTap: () => _toggleStudentSelection(student.id!),
                                                  child: Container(
                                                    width: 22,
                                                    height: 22,
                                                    decoration: BoxDecoration(
                                                      color: Colors.transparent,
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(
                                                        color: _selectedStudents.contains(student.id!)
                                                            ? Colors.red
                                                            : Colors.grey,
                                                        width: 2,
                                                      ),
                                                    ),
                                                    child: _selectedStudents.contains(student.id!)
                                                        ? const Center(
                                                            child: Icon(
                                                              Icons.close,
                                                              color: Colors.red,
                                                              size: 16,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                              ],
                                              // دائرة الطالب
                                              GestureDetector(
                                                onTap: () {
                                                  if (student.photoPath != null || student.photo != null) {
                                                    _showImageViewer(student);
                                                  }
                                                },
                                                child: CircleAvatar(
                                                  radius: 20,
                                                  backgroundColor: Colors.white,
                                                  backgroundImage: student.photoPath != null
                                                      ? FileImage(File(student.photoPath!)) as ImageProvider
                                                      : student.photo != null
                                                          ? AssetImage(student.photo!)
                                                          : null,
                                                  child: student.photoPath == null && student.photo == null
                                                      ? Text(
                                                          student.name.isNotEmpty ? student.name[0] : '?',
                                                          style: const TextStyle(
                                                            color: Colors.black,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        )
                                                      : null,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              // النجمة أو النقطة الحمراء للطالب (أمام الاسم مباشرة)
                                              _buildStudentStatusIndicator(student),
                                              const SizedBox(width: 2),
                                              // اسم الطالب
                                              Expanded(
                                                child: GestureDetector(
                                                  onTap: () {
                                                    if (_isDeletingMode) {
                                                      _toggleStudentSelection(student.id!);
                                                      return;
                                                    }
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => StudentDetailsScreen(student: student),
                                                      ),
                                                    );
                                                  },
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        student.name,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                        ),
                                                        maxLines: 2,
                                                        overflow: TextOverflow.visible,
                                                        textAlign: TextAlign.right,
                                                      ),
                                                      if ((student.studentId ?? '').trim().isNotEmpty)
                                                        Padding(
                                                          padding: const EdgeInsets.only(top: 2),
                                                          child: Text(
                                                            'رقم: ${student.studentId}',
                                                            style: const TextStyle(
                                                              color: Colors.white70,
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 44,
                                                child: Align(
                                                  alignment: Alignment.centerRight,
                                                  child: Material(
                                                    color: Colors.yellow,
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: InkWell(
                                                      borderRadius: BorderRadius.circular(8),
                                                      onTap: () async {
                                                        await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) => StudentAssignmentsScreen(
                                                              student: student,
                                                              classModel: widget.classModel,
                                                            ),
                                                          ),
                                                        );
                                                        if (!mounted) return;
                                                        await _loadGrades();
                                                        if (!mounted) return;
                                                        setState(() {});
                                                      },
                                                      child: const SizedBox(
                                                        width: 36,
                                                        height: 36,
                                                        child: Icon(
                                                          Icons.assignment,
                                                          size: 22,
                                                          color: Colors.black,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Text(
                                                'المعدل: ${studentAverage.toInt()}%',
                                                style: TextStyle(
                                                  color: studentAverage >= 50 ? Colors.green[400] : Colors.red[400],
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 3,
                                  height: 80,
                                  color: const Color(0xFF404040),
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                Expanded(
                                  child: Stack(
                                    children: [
                                      SingleChildScrollView(
                                        controller: _contentScrollController,
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: _exams.asMap().entries.map((entry) {
                                            final index = entry.key;
                                            final exam = entry.value;
                                            return Container(
                                              width: 140,
                                              margin: EdgeInsets.only(
                                                left: index == 0 ? 8 : 8,
                                                right: index == _exams.length - 1 ? 8 : 0,
                                              ),
                                              child: _buildGradeBox(student, exam),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isDeletingMode ? _deleteSelectedStudents : _showAddExamOptions,
        backgroundColor: _isDeletingMode ? Colors.red : const Color(0xFFFFD700),
        foregroundColor: _isDeletingMode ? Colors.white : Colors.black,
        elevation: 8,
        child: Icon(_isDeletingMode ? Icons.delete : Icons.add, size: 24),
        tooltip: _isDeletingMode ? 'حذف الطلاب' : 'إضافة امتحان',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/attendance_model.dart';
import '../../models/lecture_model.dart';
import '../messaging/messaging_screen.dart';
import '../../providers/grade_provider.dart';
import '../../providers/student_provider.dart';

class AtRiskStudent {
  final StudentModel student;
  final double attendanceRate;
  final int missedLectures;
  final int missedExams;
  final double average;
  final int totalExams;

  AtRiskStudent({
    required this.student,
    required this.attendanceRate,
    required this.missedLectures,
    required this.missedExams,
    required this.average,
    required this.totalExams,
  });
}

class AtRiskStudentsScreen extends StatefulWidget {
  const AtRiskStudentsScreen({super.key});

  @override
  _AtRiskStudentsScreenState createState() => _AtRiskStudentsScreenState();
}

class _AtRiskStudentsScreenState extends State<AtRiskStudentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // معايير التقييم المنفصلة
  double _maxAveragePercentage = 60.0;
  int _minMissedExams = 2;
  int _minMissedLectures = 5;  // غيابات المحاضرات
  
  bool _averageCriteriaEnabled = true;
  bool _missedExamsCriteriaEnabled = true;
  bool _missedLecturesCriteriaEnabled = true;
  bool _featureEnabled = true;
  bool _hideIndicators = false;
  
  // الفصول
  List<ClassModel> _allClasses = [];
  List<int> _selectedClassIds = [];
  List<int> _pdfSelectedClassIds = [];
  bool _showAllClasses = true;
  bool _showAllClassesForPdf = true;
  
  // البيانات
  Map<int, List<AtRiskStudent>> _atRiskStudentsByClass = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCriteria();
    _loadData();
  }
  
  Future<void> _loadCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _maxAveragePercentage = prefs.getDouble('at_risk_max_average') ?? 60.0;
      _minMissedExams = prefs.getInt('at_risk_max_missed_exams') ??
          prefs.getInt('at_risk_min_missed_exams') ??
          2;
      _minMissedLectures = prefs.getInt('at_risk_max_missed_lectures') ??
          prefs.getInt('at_risk_min_missed_lectures') ??
          5;
      
      _averageCriteriaEnabled = prefs.getBool('at_risk_average_enabled') ?? true;
      _missedExamsCriteriaEnabled = prefs.getBool('at_risk_missed_exams_enabled') ?? true;
      _missedLecturesCriteriaEnabled = prefs.getBool('at_risk_missed_lectures_enabled') ?? true;
      _featureEnabled = prefs.getBool('at_risk_feature_enabled') ?? true;
      _hideIndicators = prefs.getBool('student_status_indicators_hidden') ?? false;
    });
  }
  
  Future<void> _saveCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('at_risk_max_average', _maxAveragePercentage);
    await prefs.setInt('at_risk_max_missed_exams', _minMissedExams);
    await prefs.setInt('at_risk_min_missed_exams', _minMissedExams);
    await prefs.setInt('at_risk_max_missed_lectures', _minMissedLectures);
    await prefs.setInt('at_risk_min_missed_lectures', _minMissedLectures);
    
    await prefs.setBool('at_risk_average_enabled', _averageCriteriaEnabled);
    await prefs.setBool('at_risk_missed_exams_enabled', _missedExamsCriteriaEnabled);
    await prefs.setBool('at_risk_missed_lectures_enabled', _missedLecturesCriteriaEnabled);
    await prefs.setBool('at_risk_feature_enabled', _featureEnabled);
    await prefs.setBool('student_status_indicators_hidden', _hideIndicators);

    if (mounted) {
      Provider.of<GradeProvider>(context, listen: false).refreshIndicators();
      Provider.of<StudentProvider>(context, listen: false).refreshIndicators();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      _allClasses = await _dbHelper.getAllClasses();
      _selectedClassIds = _allClasses.map((c) => c.id!).toList();
      _pdfSelectedClassIds = _allClasses.map((c) => c.id!).toList();
      
      await _calculateAtRiskStudents();
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _calculateAtRiskStudents() async {
    if (!mounted) return;
    
    _atRiskStudentsByClass.clear();
    
    for (final classModel in _allClasses) {
      if (!_selectedClassIds.contains(classModel.id)) continue;
      
      final classId = classModel.id!;
      final students = await _dbHelper.getStudentsByClass(classId);
      final examsInClass = await _dbHelper.getExamsByClass(classId);
      
      final atRiskStudents = <AtRiskStudent>[];
      
      for (final student in students) {
        final grades = await _dbHelper.getGradesByStudent(student.id!);
        final latestGrades = <String, GradeModel>{};

        String dateKey(DateTime d) {
          final y = d.year.toString().padLeft(4, '0');
          final m = d.month.toString().padLeft(2, '0');
          final day = d.day.toString().padLeft(2, '0');
          return '$y-$m-$day';
        }

        bool containsAny(String? value, List<String> needles) {
          if (value == null) return false;
          final v = value.toLowerCase();
          for (final n in needles) {
            if (v.contains(n.toLowerCase())) return true;
          }
          return false;
        }

        bool isExamAbsent(GradeModel g) {
          return containsAny(g.status, const ['غائب', 'غياب', 'absent']) ||
              containsAny(g.notes, const ['غائب', 'غياب', 'absent']);
        }

        bool isExamCheating(GradeModel g) {
          return containsAny(g.status, const ['غش', 'cheat']) ||
              containsAny(g.notes, const ['غش', 'cheat']);
        }

        bool isExamMissing(GradeModel g) {
          return containsAny(g.status, const ['مفقودة', 'missing']) ||
              containsAny(g.notes, const ['مفقودة', 'missing']);
        }

        bool isValidScoredExam(GradeModel g) {
          return !isExamAbsent(g) && !isExamCheating(g) && !isExamMissing(g);
        }
        
        for (final grade in grades) {
          final exam = examsInClass
              .where((e) => e.title == grade.examName && dateKey(e.date) == dateKey(grade.examDate))
              .firstOrNull;
          if (exam != null) {
            final examKey = '${grade.examName}__${dateKey(grade.examDate)}';
            final existing = latestGrades[examKey];
            if (existing == null) {
              latestGrades[examKey] = grade;
              continue;
            }

            final gStamp = grade.updatedAt.isAfter(grade.createdAt)
                ? grade.updatedAt
                : grade.createdAt;
            final eStamp = existing.updatedAt.isAfter(existing.createdAt)
                ? existing.updatedAt
                : existing.createdAt;

            if (gStamp.isAfter(eStamp)) {
              latestGrades[examKey] = grade;
            }
          }
        }
        
        final gradesList = latestGrades.values.toList();
        
        final scoredGrades = gradesList.where(isValidScoredExam).toList();
        
        final missedExams = gradesList.where(isExamAbsent).length;
        
        // حساب غيابات المحاضرات
        final allAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
        final lecturesInClass = await _dbHelper.getLecturesByClass(classId);
        final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();
        
        final attendances = allAttendances.where((a) => lectureIdsInClass.contains(a.lectureId)).toList();
        final missedLectures = attendances.where((a) => 
          a.status == AttendanceStatus.absent
        ).length;
        
        // حساب المعدل: متوسط نسب الامتحانات، مع احتساب الغائب/غش/مفقودة كنسبة 0%
        double averagePercentage = 0.0;
        if (gradesList.isNotEmpty) {
          double totalPercentage = 0.0;
          int countedExams = 0;

          for (final grade in gradesList) {
            final matchingExam = examsInClass
                .where((e) => e.title == grade.examName && dateKey(e.date) == dateKey(grade.examDate))
                .firstOrNull;

            final maxScore = grade.maxScore > 0
                ? grade.maxScore
                : (matchingExam?.maxScore ?? 0);

            if (maxScore > 0) {
              final percentage = isValidScoredExam(grade) ? (grade.score / maxScore) * 100 : 0.0;
              totalPercentage += percentage;
              countedExams++;
            }
          }

          averagePercentage = countedExams > 0 ? totalPercentage / countedExams : 0.0;
        }
        
        final totalExams = gradesList.length;
        final totalExamsWithAttendance = gradesList.length;
        
        // نسبة حضور الامتحانات = الامتحانات التي لها درجة صحيحة / إجمالي الامتحانات
        final examAttendanceRate = totalExamsWithAttendance > 0
            ? (scoredGrades.length / totalExamsWithAttendance) * 100
            : 0.0;
        
        // التحقق من المعايير المفعلة فقط
        bool isAtRisk = false;
        
        if (_averageCriteriaEnabled && averagePercentage < _maxAveragePercentage) {
          isAtRisk = true;
        }
        
        if (_missedExamsCriteriaEnabled && missedExams >= _minMissedExams) {
          isAtRisk = true;
        }
        
        if (_missedLecturesCriteriaEnabled && missedLectures >= _minMissedLectures) {
          isAtRisk = true;
        }
        
        // إذا كانت الميزة معطلة، لا يعتبر أي طالب في خطر
        if (!_featureEnabled) {
          isAtRisk = false;
        }
        // إذا لم يكن هناك أي معيار مفعّل، لا يعتبر الطالب في خطر
        else if (!_averageCriteriaEnabled && !_missedExamsCriteriaEnabled && !_missedLecturesCriteriaEnabled) {
          isAtRisk = false;
        }
        
        print('DEBUG: Student ${student.name} - avg: $averagePercentage%, missedExams: $missedExams, missedLectures: $missedLectures, isAtRisk: $isAtRisk');
        
        if (isAtRisk) {
          atRiskStudents.add(AtRiskStudent(
            student: student,
            attendanceRate: examAttendanceRate, // استخدام نسبة حضور الامتحانات
            missedLectures: missedLectures,
            missedExams: missedExams,
            average: averagePercentage,
            totalExams: totalExams,
          ));
        }
      }
      
      if (atRiskStudents.isNotEmpty) {
        _atRiskStudentsByClass[classId] = atRiskStudents;
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _exportToPDF() async {
    final totalAtRiskStudents = _atRiskStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    if (totalAtRiskStudents == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يوجد طلاب في خطر لاستخراج تقرير', style: GoogleFonts.cairo())),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        content: Row(
          children: [
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(width: 20),
            Text('جاري إنشاء تقرير PDF...', style: GoogleFonts.cairo(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      final pdf = pw.Document();
      
      // تحميل الخط العربي للـ PDF
      print('🔍 Loading NotoSansArabic font for At Risk students...');
      final arabicFontData = await rootBundle.load("assets/fonts/NotoSansArabic-Regular.ttf");
      print('✅ Font bytes loaded: ${arabicFontData.lengthInBytes}');
      
      final arabicFontBoldData = await rootBundle.load("assets/fonts/NotoSansArabic-Bold.ttf");
      print('✅ Bold font bytes loaded: ${arabicFontBoldData.lengthInBytes}');
      
      final arabicFont = pw.Font.ttf(arabicFontData);
      final arabicFontBold = pw.Font.ttf(arabicFontBoldData);
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          textDirection: pw.TextDirection.rtl,
          build: (context) => pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // العنوان الرئيسي
                pw.Text(
                  'تقرير الطلاب في خطر',
                  style: pw.TextStyle(
                    font: arabicFontBold,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue, // تغيير إلى أزرق
                  ),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 16),
                // التاريخ
                pw.Text(
                  'التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 14,
                    color: PdfColors.black, // تغيير إلى أسود
                  ),
                ),
                pw.SizedBox(height: 24),
                
                // جداول الفصول
                ..._allClasses.where((classModel) => _pdfSelectedClassIds.contains(classModel.id!)).map((classModel) {
                  final atRiskStudents = _atRiskStudentsByClass[classModel.id!] ?? [];
                  if (atRiskStudents.isEmpty) return pw.SizedBox.shrink();
                  
                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // عنوان الفصل
                      pw.Text(
                        'الفصل: ${classModel.name}',
                        style: pw.TextStyle(
                          font: arabicFontBold,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue, // تغيير إلى أزرق
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      
                      // الجدول - الأعمدة تعتمد على المعايير المفعلة
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        columnWidths: _buildTableColumnWidths(),
                        children: [
                          // رأس الجدول باللون الأزرق
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.blue),
                            children: _buildTableHeaders(arabicFontBold),
                          ),
                          // بيانات الطلاب
                          ...atRiskStudents.map((atRiskStudent) {
                            return pw.TableRow(
                              children: _buildTableRow(atRiskStudent, arabicFont),
                            );
                          }).toList(),
                        ],
                      ),
                      pw.SizedBox(height: 24),
                    ],
                  );
                }).toList(),
                
                // الإجمالي
                pw.Text(
                  'إجمالي الطلاب في خطر: ${_atRiskStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}',
                  style: pw.TextStyle(
                    font: arabicFontBold,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue, // تغيير إلى أزرق
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // حفظ الملف مباشرة في مجلد المستندات
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'الطلاب_في_خطر_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ التقرير في: ${file.path}', style: GoogleFonts.cairo()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
      
      // فتح الملف
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: fileName,
      );

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في استخراج التقرير: $e', style: GoogleFonts.cairo())),
      );
    }
  }

  // دوال الجدول الديناميكي بناءً على المعايير المفعلة
  Map<int, pw.FlexColumnWidth> _buildTableColumnWidths() {
    final columnWidths = <int, pw.FlexColumnWidth>{};
    int columnIndex = 0;
    
    // عمود اسم الطالب دائماً موجود
    columnWidths[columnIndex++] = const pw.FlexColumnWidth(3);
    
    // عمود المعدل إذا كان المعيار مفعلاً
    if (_averageCriteriaEnabled) {
      columnWidths[columnIndex++] = const pw.FlexColumnWidth(1.5);
    }
    
    // عمود عدد غيابات الامتحانات إذا كان المعيار مفعلاً
    if (_missedExamsCriteriaEnabled) {
      columnWidths[columnIndex++] = const pw.FlexColumnWidth(2);
    }
    
    // عمود غيابات المحاضرات إذا كان المعيار مفعلاً
    if (_missedLecturesCriteriaEnabled) {
      columnWidths[columnIndex++] = const pw.FlexColumnWidth(2);
    }
    
    // عمود نسبة الحضور دائماً موجود
    columnWidths[columnIndex++] = const pw.FlexColumnWidth(2);
    
    return columnWidths;
  }

  List<pw.Widget> _buildTableHeaders(pw.Font font) {
    final headers = <pw.Widget>[];
    
    // رأس اسم الطالب دائماً موجود
    headers.add(_buildHeaderCell('اسم الطالب', font));
    
    // رأس المعدل إذا كان المعيار مفعلاً
    if (_averageCriteriaEnabled) {
      headers.add(_buildHeaderCell('المعدل', font));
    }
    
    // رأس عدد غيابات الامتحانات إذا كان المعيار مفعلاً
    if (_missedExamsCriteriaEnabled) {
      headers.add(_buildHeaderCell('غيابات الامتحانات', font));
    }
    
    // رأس غيابات المحاضرات إذا كان المعيار مفعلاً
    if (_missedLecturesCriteriaEnabled) {
      headers.add(_buildHeaderCell('غيابات المحاضرات', font));
    }
    
    // رأس نسبة الحضور دائماً موجود
    headers.add(_buildHeaderCell('نسبة حضور الامتحانات', font));
    
    return headers;
  }

  List<pw.Widget> _buildTableRow(AtRiskStudent student, pw.Font font) {
    final cells = <pw.Widget>[];
    
    // اسم الطالب دائماً موجود
    cells.add(_buildDataCell(student.student.name, font));
    
    // المعدل إذا كان المعيار مفعلاً
    if (_averageCriteriaEnabled) {
      cells.add(_buildDataCell(student.average.toStringAsFixed(1), font));
    }
    
    // عدد غيابات الامتحانات إذا كان المعيار مفعلاً
    if (_missedExamsCriteriaEnabled) {
      cells.add(_buildDataCell('${student.missedExams}', font));
    }
    
    // غيابات المحاضرات إذا كان المعيار مفعلاً
    if (_missedLecturesCriteriaEnabled) {
      cells.add(_buildDataCell('${student.missedLectures}', font));
    }
    
    // نسبة الحضور دائماً موجودة
    cells.add(_buildDataCell('${student.attendanceRate.toStringAsFixed(1)}%', font));
    
    return cells;
  }

  pw.Widget _buildHeaderCell(String text, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildDataCell(String text, pw.Font font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: font,
          fontSize: 10,
          color: PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الطلاب في خطر', style: GoogleFonts.cairo()),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.blue),
            tooltip: 'تصدير PDF',
            onPressed: _atRiskStudentsByClass.isEmpty ? null : _exportToPDF,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCriteriaSection(),
                  _buildPdfClassSelectionSection(),
                  _buildStudentsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildCriteriaSection() {
    return Card(
      color: const Color(0xFF1A1A1A),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معايير الخطر',
              style: TextStyle(
                color: Colors.red,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // معيار المعدل
            _buildCriterionToggle(
              'المعدل',
              _averageCriteriaEnabled,
              (value) {
                setState(() {
                  _averageCriteriaEnabled = value;
                });
                _saveCriteria();
                _loadData();
              },
              _maxAveragePercentage,
              (newValue) {
                setState(() {
                  _maxAveragePercentage = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: true,
              isMax: true,
            ),
            
            const SizedBox(height: 12),
            
            // معيار عدد غيابات الامتحانات
            _buildCriterionToggle(
              'غيابات الامتحانات',
              _missedExamsCriteriaEnabled,
              (value) {
                setState(() {
                  _missedExamsCriteriaEnabled = value;
                });
                _saveCriteria();
                _loadData();
              },
              _minMissedExams,
              (newValue) {
                setState(() {
                  _minMissedExams = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: false,
            ),
            
            const SizedBox(height: 12),
            
            // معيار غيابات المحاضرات
            _buildCriterionToggle(
              'غيابات المحاضرات',
              _missedLecturesCriteriaEnabled,
              (value) {
                setState(() {
                  _missedLecturesCriteriaEnabled = value;
                });
                _saveCriteria();
                _loadData();
              },
              _minMissedLectures,
              (newValue) {
                setState(() {
                  _minMissedLectures = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: false,
            ),
            
            const SizedBox(height: 20),
            
            // تعطيل الميزة كلياً
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.power_settings_new,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'تعطيل الميزة كلياً',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'عند التفعيل، لن تظهر النقطة الحمراء والنجمة الصفراء بجانب أسماء الطلاب',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: !_featureEnabled,
                    onChanged: (value) {
                      setState(() {
                        _featureEnabled = !value;
                      });
                      _saveCriteria();
                      _loadData();
                    },
                    activeColor: Colors.red,
                    inactiveTrackColor: Colors.grey.withOpacity(0.3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off,
                    color: Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'عدم إظهار العلامة',
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'إخفاء النقطة الحمراء/النجمة في صفحات الحضور والامتحان مع بقاء القائمة تعمل هنا',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _hideIndicators,
                    onChanged: (value) {
                      setState(() {
                        _hideIndicators = value;
                      });
                      _saveCriteria();
                    },
                    activeColor: Colors.red,
                    inactiveTrackColor: Colors.grey.withOpacity(0.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCriterionToggle(
    String title,
    bool isEnabled,
    Function(bool) onToggle,
    dynamic value,
    Function(dynamic) onValueChanged, {
    required bool isDouble,
    bool isMax = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEnabled ? Colors.red.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled ? Colors.red.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isEnabled ? Icons.warning : Icons.warning_amber_outlined,
                color: isEnabled ? Colors.red : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: isEnabled ? Colors.red : Colors.grey,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => onToggle(!isEnabled),
                child: Icon(
                  isEnabled ? Icons.toggle_on : Icons.toggle_off,
                  color: isEnabled ? Colors.red : Colors.grey,
                  size: 48,
                ),
              ),
            ],
          ),
          if (isEnabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isMax ? 'معدل الطالب أقل أو يساوي:' : 'عدد غيابات الطالب أكبر أو يساوي:',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showCriteriaEditor(title, value, onValueChanged, isDouble, isMax),
                  child: Container(
                    width: 80,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Text(
                        isDouble ? '${value.toStringAsFixed(1)}%' : '$value',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showCriteriaEditor(String title, dynamic currentValue, Function(dynamic) onSave, bool isDouble, bool isMax) {
    final controller = TextEditingController(text: currentValue.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل $title', style: GoogleFonts.cairo()),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: title,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              final value = isDouble 
                  ? double.tryParse(controller.text) 
                  : int.tryParse(controller.text);
              
              if (value != null) {
                onSave(value);
                await _saveCriteria();
                Navigator.pop(context);
                setState(() => _isLoading = true);
                await _calculateAtRiskStudents();
                setState(() => _isLoading = false);
              }
            },
            child: Text('حفظ', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfClassSelectionSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختيار الفصول للـ PDF',
            style: TextStyle(
              color: Colors.red,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _showAllClassesForPdf = !_showAllClassesForPdf;
                      if (_showAllClassesForPdf) {
                        _pdfSelectedClassIds = _allClasses.map((c) => c.id!).toList();
                      } else {
                        _pdfSelectedClassIds.clear();
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _showAllClassesForPdf ? Colors.red.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showAllClassesForPdf ? Icons.check_box : Icons.check_box_outline_blank,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'جميع الفصول',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!_showAllClassesForPdf) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allClasses.map((classModel) {
                final isSelected = _pdfSelectedClassIds.contains(classModel.id!);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _pdfSelectedClassIds.remove(classModel.id!);
                      } else {
                        _pdfSelectedClassIds.add(classModel.id!);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.red.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(
                      classModel.name,
                      style: TextStyle(
                        color: isSelected ? Colors.red : Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentsList() {
    print('DEBUG: _buildStudentsList called');
    print('DEBUG: _averageCriteriaEnabled: $_averageCriteriaEnabled');
    print('DEBUG: _missedExamsCriteriaEnabled: $_missedExamsCriteriaEnabled');
    print('DEBUG: _missedLecturesCriteriaEnabled: $_missedLecturesCriteriaEnabled');
    print('DEBUG: _atRiskStudentsByClass: $_atRiskStudentsByClass');
    
    if (!_averageCriteriaEnabled && !_missedExamsCriteriaEnabled && !_missedLecturesCriteriaEnabled) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, color: Colors.grey, size: 64),
            SizedBox(height: 16),
            Text(
              'جميع المعايير معطلة',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'قم بتفعيل معيار واحد على الأقل لعرض الطلاب في خطر',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    final totalAtRiskStudents = _atRiskStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    print('DEBUG: totalAtRiskStudents: $totalAtRiskStudents');
    
    if (totalAtRiskStudents == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, size: 80, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'لا يوجد طلاب في خطر حالياً',
              style: TextStyle(color: Colors.red, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'حاول تفعيل المزيد من المعايير أو رفع الحدود الدنيا',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final classesForList = _showAllClassesForPdf
        ? _allClasses
        : _allClasses.where((c) => _pdfSelectedClassIds.contains(c.id)).toList();

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: classesForList.length,
      itemBuilder: (context, index) {
        final classModel = classesForList[index];
        final atRiskStudents = _atRiskStudentsByClass[classModel.id!] ?? [];
        
        if (atRiskStudents.isEmpty) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        classModel.name,
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${atRiskStudents.length} طالب',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...atRiskStudents.map((atRiskStudent) {
                return _buildStudentCard(atRiskStudent);
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentCard(AtRiskStudent atRiskStudent) {
    final student = atRiskStudent.student;
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.7),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            student.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.grey),
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'messaging',
                              child: Row(
                                children: [
                                  Icon(Icons.message, size: 18, color: Colors.amber),
                                  SizedBox(width: 6),
                                  Text('المراسلة'),
                                ],
                              ),
                            ),
                          ],
                          onSelected: (value) {
                            if (value == 'messaging') {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MessagingScreen(),
                                ),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    if (student.studentId != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          student.studentId!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_averageCriteriaEnabled)
                _buildStatCard(
                  'المعدل',
                  atRiskStudent.average.toStringAsFixed(1),
                  atRiskStudent.average < 50 ? Colors.red : Colors.orange,
                ),
              if (_missedExamsCriteriaEnabled) ...[
                if (_averageCriteriaEnabled) const SizedBox(width: 8),
                _buildStatCard(
                  'غيابات الامتحانات',
                  '${atRiskStudent.missedExams}',
                  Colors.red,
                ),
              ],
              if (_missedLecturesCriteriaEnabled) ...[
                if (_averageCriteriaEnabled || _missedExamsCriteriaEnabled) const SizedBox(width: 8),
                _buildStatCard(
                  'غيابات المحاضرات',
                  '${atRiskStudent.missedLectures}',
                  Colors.red,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

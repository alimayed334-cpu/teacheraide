import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:arabic_font/arabic_font.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/attendance_model.dart';
import '../../theme/app_theme.dart';
import '../../providers/grade_provider.dart';
import '../../providers/student_provider.dart';

// دالة مساعدة للخط العربي
TextStyle _arabicStyle({double? fontSize, FontWeight? fontWeight, Color? color}) {
  return GoogleFonts.cairo(
    fontSize: fontSize ?? 14,
    fontWeight: fontWeight ?? FontWeight.normal,
    color: color ?? Colors.white,
  );
}

class ExcellentStudent {
  final StudentModel student;
  final double attendanceRate;
  final int missedLectures;
  final int missedExams;
  final double average;
  final int totalExams;

  ExcellentStudent({
    required this.student,
    required this.attendanceRate,
    required this.missedLectures,
    required this.missedExams,
    required this.average,
    required this.totalExams,
  });
}

class ExcellentStudentsScreen extends StatefulWidget {
  const ExcellentStudentsScreen({super.key});

  @override
  State<ExcellentStudentsScreen> createState() => _ExcellentStudentsScreenState();
}

class _ExcellentStudentsScreenState extends State<ExcellentStudentsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // معايير التقييم المنفصلة
  double _minAveragePercentage = 70.0;
  int _minExamsCount = 1;
  double _minLectureAttendanceRate = 50.0;  // نسبة حضور المحاضرات
  
  bool _averageCriteriaEnabled = true;
  bool _examsCountCriteriaEnabled = true;
  bool _lectureAttendanceCriteriaEnabled = true;
  bool _featureEnabled = true;
  bool _hideIndicators = false;
  
  // الفصول
  List<ClassModel> _allClasses = [];
  List<int> _selectedClassIds = [];
  List<int> _pdfSelectedClassIds = [];
  bool _showAllClasses = true;
  bool _showAllClassesForPdf = true;
  
  // البيانات
  Map<int, List<ExcellentStudent>> _excellentStudentsByClass = {};
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
      _minAveragePercentage = prefs.getDouble('excellent_min_average') ?? 70.0;
      // توحيد المفتاح مع باقي التطبيق + توافق مع الإصدارات السابقة
      _minExamsCount = prefs.getInt('excellent_min_exams_count') ??
          prefs.getInt('excellent_min_exams') ??
          1;
      _minLectureAttendanceRate = prefs.getDouble('excellent_min_lecture_attendance') ??
          prefs.getDouble('excellent_min_exam_attendance') ??
          50.0;
      
      _averageCriteriaEnabled = prefs.getBool('excellent_average_enabled') ?? true;
      _examsCountCriteriaEnabled = prefs.getBool('excellent_exams_count_enabled') ?? true;
      _lectureAttendanceCriteriaEnabled = prefs.getBool('excellent_lecture_attendance_enabled') ??
          prefs.getBool('excellent_exam_attendance_enabled') ??
          true;
      _featureEnabled = prefs.getBool('excellent_feature_enabled') ?? true;
      _hideIndicators = prefs.getBool('student_status_indicators_hidden') ?? false;
    });
  }
  
  Future<void> _saveCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('excellent_min_average', _minAveragePercentage);
    // حفظ على المفتاح الجديد + القديم للتوافق
    await prefs.setInt('excellent_min_exams_count', _minExamsCount);
    await prefs.setInt('excellent_min_exams', _minExamsCount);
    await prefs.setDouble('excellent_min_lecture_attendance', _minLectureAttendanceRate);
    await prefs.setDouble('excellent_min_exam_attendance', _minLectureAttendanceRate);
    
    await prefs.setBool('excellent_average_enabled', _averageCriteriaEnabled);
    await prefs.setBool('excellent_exams_count_enabled', _examsCountCriteriaEnabled);
    await prefs.setBool('excellent_lecture_attendance_enabled', _lectureAttendanceCriteriaEnabled);
    await prefs.setBool('excellent_exam_attendance_enabled', _lectureAttendanceCriteriaEnabled);
    await prefs.setBool('excellent_feature_enabled', _featureEnabled);
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
      
      await _calculateExcellentStudents();
    } catch (e) {
      print('Error loading data: $e');
    } finally {
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _calculateExcellentStudents() async {
    if (!mounted) return;
    
    _excellentStudentsByClass.clear();
    
    for (final classModel in _allClasses) {
      if (!_selectedClassIds.contains(classModel.id)) continue;
      
      final classId = classModel.id!;
      final students = await _dbHelper.getStudentsByClass(classId);
      final examsInClass = await _dbHelper.getExamsByClass(classId);
      final lecturesInClass = await _dbHelper.getLecturesByClass(classId);
      
      final excellentStudents = <ExcellentStudent>[];
      
      for (final student in students) {
        final grades = await _dbHelper.getGradesByStudent(student.id!);
        final attendances = await _dbHelper.getAttendanceByStudent(student.id!);
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
        
        // إجمالي الامتحانات في الفصل لهذا الطالب (يشمل الغائب/غش/مفقودة)
        final totalExams = gradesList.length;
        // attendedExams not used anymore for lecture attendance; keep exam counting via totalExams

        // نسبة حضور المحاضرات (الحضور الحقيقي) داخل هذا الفصل فقط
        final attendancesInClass = attendances
            .where((a) => lecturesInClass.any((l) => l.id == a.lectureId))
            .toList();
        final totalLectures = attendancesInClass.length;
        final attendedLectures = attendancesInClass
            .where((a) => a.status == AttendanceStatus.present || a.status == AttendanceStatus.late)
            .length;
        final lectureAttendanceRate = totalLectures > 0
            ? (attendedLectures / totalLectures) * 100
            : 0.0;
        
        // التحقق من المعايير المفعلة فقط
        bool isExcellent = true;
        
        if (_averageCriteriaEnabled && averagePercentage < _minAveragePercentage) {
          isExcellent = false;
        }
        
        if (_examsCountCriteriaEnabled && totalExams < _minExamsCount) {
          isExcellent = false;
        }
        
        if (_lectureAttendanceCriteriaEnabled &&
            lectureAttendanceRate < _minLectureAttendanceRate) {
          isExcellent = false;
        }
        
        // إذا كانت الميزة معطلة، لا يعتبر أي طالب مميزاً
        if (!_featureEnabled) {
          isExcellent = false;
        }
        // إذا لم يكن هناك أي معيار مفعّل، لا يعتبر الطالب مميزاً
        else if (!_averageCriteriaEnabled &&
            !_examsCountCriteriaEnabled &&
            !_lectureAttendanceCriteriaEnabled) {
          isExcellent = false;
        }
        
        print('DEBUG: Student ${student.name} - avg: $averagePercentage%, exams: $totalExams, lectureAttendance: $lectureAttendanceRate%, isExcellent: $isExcellent');
        
        if (isExcellent) {
          excellentStudents.add(ExcellentStudent(
            student: student,
            attendanceRate: lectureAttendanceRate, // استخدام نسبة حضور المحاضرات
            missedLectures: 0, // غير مستخدم في الطلاب المميزون
            missedExams: missedExams,
            average: averagePercentage,
            totalExams: totalExams,
          ));
        }
      }
      
      if (excellentStudents.isNotEmpty) {
        _excellentStudentsByClass[classId] = excellentStudents;
      }
    }
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _exportToPDF() async {
    final totalExcellentStudents = _excellentStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    if (totalExcellentStudents == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد طلاب مميزون لاستخراج تقرير')),
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
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(width: 20),
            Text('جاري إنشاء تقرير PDF...', style: _arabicStyle()),
          ],
        ),
      ),
    );

    try {
      final pdf = pw.Document();
      
      // تحميل الخط العربي للـ PDF
      print('🔍 Loading NotoSansArabic font...');
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
                  'تقرير الطلاب المميزون',
                  style: pw.TextStyle(
                    font: arabicFontBold,
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber,
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
                    color: PdfColors.grey700,
                  ),
                ),
                pw.SizedBox(height: 24),
                
                // جداول الفصول
                ..._allClasses.where((classModel) => _pdfSelectedClassIds.contains(classModel.id!)).map((classModel) {
                  final excellentStudents = _excellentStudentsByClass[classModel.id!] ?? [];
                  if (excellentStudents.isEmpty) return pw.SizedBox.shrink();
                  
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
                          color: PdfColors.blue,
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
                          ...excellentStudents.map((excellentStudent) {
                            return pw.TableRow(
                              children: _buildTableRow(excellentStudent, arabicFont),
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
                  'إجمالي الطلاب المميزون: ${_excellentStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}',
                  style: pw.TextStyle(
                    font: arabicFontBold,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // حفظ الملف وفتحه مباشرة
      Navigator.pop(context);
      
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'تقرير_الطلاب_المميزون_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      // فتح الملف مباشرة
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: fileName,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حفظ التقرير بنجاح', style: GoogleFonts.cairo()),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في استخراج التقرير: $e', style: GoogleFonts.cairo()),
        ),
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
    
    // عمود عدد الامتحانات إذا كان المعيار مفعلاً
    if (_examsCountCriteriaEnabled) {
      columnWidths[columnIndex++] = const pw.FlexColumnWidth(2);
    }
    
    // عمود نسبة الحضور إذا كان المعيار مفعلاً
    if (_lectureAttendanceCriteriaEnabled) {
      columnWidths[columnIndex++] = const pw.FlexColumnWidth(2);
    }
    
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
    
    // رأس عدد الامتحانات إذا كان المعيار مفعلاً
    if (_examsCountCriteriaEnabled) {
      headers.add(_buildHeaderCell('عدد الامتحانات', font));
    }
    
    // رأس نسبة الحضور إذا كان المعيار مفعلاً
    if (_lectureAttendanceCriteriaEnabled) {
      headers.add(_buildHeaderCell('نسبة الحضور', font));
    }
    
    return headers;
  }

  List<pw.Widget> _buildTableRow(ExcellentStudent student, pw.Font font) {
    final cells = <pw.Widget>[];
    
    // اسم الطالب دائماً موجود
    cells.add(_buildDataCell(student.student.name, font));
    
    // المعدل إذا كان المعيار مفعلاً
    if (_averageCriteriaEnabled) {
      cells.add(_buildDataCell(student.average.toStringAsFixed(1), font));
    }
    
    // عدد الامتحانات إذا كان المعيار مفعلاً
    if (_examsCountCriteriaEnabled) {
      cells.add(_buildDataCell('${student.totalExams}', font));
    }
    
    // نسبة الحضور إذا كان المعيار مفعلاً
    if (_lectureAttendanceCriteriaEnabled) {
      // استخدام رمز % مباشرة
      cells.add(_buildDataCell('${student.attendanceRate.toStringAsFixed(1)}%', font));
    }
    
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
        title: const Text('الطلاب المميزون'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.amber),
            tooltip: 'تصدير PDF',
            onPressed: _excellentStudentsByClass.isEmpty ? null : _exportToPDF,
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
            Text(
              'معايير التميز',
              style: _arabicStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.amber),
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
              _minAveragePercentage,
              (newValue) {
                setState(() {
                  _minAveragePercentage = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: true,
            ),
            
            const SizedBox(height: 12),
            
            // معيار عدد الامتحانات
            _buildCriterionToggle(
              'عدد الامتحانات',
              _examsCountCriteriaEnabled,
              (value) {
                setState(() {
                  _examsCountCriteriaEnabled = value;
                });
                _saveCriteria();
                _loadData();
              },
              _minExamsCount,
              (newValue) {
                setState(() {
                  _minExamsCount = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: false,
            ),
            
            const SizedBox(height: 12),
            
            // معيار حضور الامتحانات
            _buildCriterionToggle(
              'نسبة الحضور',
              _lectureAttendanceCriteriaEnabled,
              (value) {
                setState(() {
                  _lectureAttendanceCriteriaEnabled = value;
                });
                _saveCriteria();
                _loadData();
              },
              _minLectureAttendanceRate,
              (newValue) {
                setState(() {
                  _minLectureAttendanceRate = newValue;
                });
                _saveCriteria();
                _loadData();
              },
              isDouble: true,
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
                          'عند التفعيل، لن تظهر النجمة الصفراء والنقطة الحمراء بجانب أسماء الطلاب',
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
                    activeColor: Theme.of(context).colorScheme.primary,
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
                          'إخفاء النجمة/النقطة في صفحات الحضور والامتحان مع بقاء القائمة تعمل هنا',
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
                    activeColor: Colors.amber,
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
  }) {
    // تحديد النص الصغير بناءً على عنوان المعيار
    String getLabelText() {
      if (title == 'المعدل') {
        return 'معدل الطالب أكبر أو يساوي:';
      } else if (title == 'عدد الامتحانات') {
        return 'عدد امتحانات الطالب أكبر أو يساوي:';
      } else if (title == 'نسبة الحضور') {
        return 'نسبة حضور الطالب أكبر أو يساوي:';
      }
      return 'القيمة:';
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isEnabled ? Colors.amber.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isEnabled ? Colors.amber.withOpacity(0.3) : Colors.grey.withOpacity(0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isEnabled ? Icons.check_circle : Icons.check_circle_outline,
                color: isEnabled ? Colors.amber : Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: _arabicStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
              ),
              GestureDetector(
                onTap: () => onToggle(!isEnabled),
                child: Icon(
                  isEnabled ? Icons.toggle_on : Icons.toggle_off,
                  color: isEnabled ? Colors.amber : Colors.grey,
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
                    getLabelText(),
                    style: _arabicStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showCriteriaEditor(title, value, onValueChanged, isDouble),
                  child: Container(
                    width: 80,
                    height: 30,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Center(
                      child: Text(
                        isDouble ? '${value.toStringAsFixed(1)}%' : '$value',
                        style: _arabicStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
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

  Widget _buildCriteriaItem(String title, dynamic value, Function(dynamic) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
          GestureDetector(
            onTap: () => _showCriteriaEditor(title, value, (newValue) {
              setState(() {
                if (newValue is double) {
                  _minAveragePercentage = newValue;
                } else if (newValue is int) {
                  _minExamsCount = newValue;
                }
                _saveCriteria();
                _loadData();
              });
            }, title.contains('%')),
            child: Container(
              width: 80,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  value is double ? '${value.toStringAsFixed(1)}%' : '$value',
                  style: _arabicStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCriteriaEditor(String title, dynamic currentValue, Function(dynamic) onSave, bool isDouble) {
    final controller = TextEditingController(text: currentValue.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل $title'),
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
            child: const Text('إلغاء'),
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
                await _calculateExcellentStudents();
                setState(() => _isLoading = false);
              }
            },
            child: const Text('حفظ'),
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
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Text(
              'اختيار الفصول للـ PDF',
              style: _arabicStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
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
                      color: _showAllClassesForPdf ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showAllClassesForPdf ? Icons.check_box : Icons.check_box_outline_blank,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'جميع الفصول',
                          style: _arabicStyle(color: Colors.white),
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
                      color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Text(
                      classModel.name,
                      style: _arabicStyle(
                        color: isSelected ? Colors.amber : Colors.white,
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
    print('DEBUG: _examsCountCriteriaEnabled: $_examsCountCriteriaEnabled');
    print('DEBUG: _lectureAttendanceCriteriaEnabled: $_lectureAttendanceCriteriaEnabled');
    print('DEBUG: _excellentStudentsByClass: $_excellentStudentsByClass');
    
    if (!_averageCriteriaEnabled && !_examsCountCriteriaEnabled && !_lectureAttendanceCriteriaEnabled) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, color: Colors.grey, size: 64),
            SizedBox(height: 16),
            Text(
              'جميع المعايير معطلة',
              style: _arabicStyle(color: Colors.grey, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'قم بتفعيل معيار واحد على الأقل لعرض الطلاب المميزين',
              style: _arabicStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }
    
    final totalExcellentStudents = _excellentStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    print('DEBUG: totalExcellentStudents: $totalExcellentStudents');
    
    if (totalExcellentStudents == 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, size: 80, color: Colors.amber),
            SizedBox(height: 16),
            Text(
              'لا يوجد طلاب مميزون حالياً',
              style: _arabicStyle(color: Colors.amber, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'حاول تفعيل المزيد من المعايير أو خفض الحدود الدنيا',
              style: _arabicStyle(color: Colors.grey, fontSize: 14),
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
        final excellentStudents = _excellentStudentsByClass[classModel.id!] ?? [];
        
        if (excellentStudents.isEmpty) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.amber.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        classModel.name,
                        style: _arabicStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${excellentStudents.length} طالب',
                        style: _arabicStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              ...excellentStudents.map((excellentStudent) {
                return _buildStudentCard(excellentStudent);
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStudentCard(ExcellentStudent excellentStudent) {
    final student = excellentStudent.student;
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withOpacity(0.2)),
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
                        color: Colors.yellow,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.yellow.withOpacity(0.7),
                            blurRadius: 6,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.star,
                        color: Colors.orange,
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
                    Text(
                      student.name,
                      style: _arabicStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    if (student.studentId != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          student.studentId!,
                          style: _arabicStyle(color: Colors.amber, fontSize: 12),
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
              _buildStatCard(
                'المعدل',
                excellentStudent.average.toStringAsFixed(1),
                excellentStudent.average >= 90 ? Colors.amber : Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                'عدد الامتحانات',
                '${excellentStudent.totalExams}',
                Colors.green,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                'حضور الامتحانات',
                '${excellentStudent.attendanceRate.toStringAsFixed(1)}%',
                Colors.green,
              ),
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

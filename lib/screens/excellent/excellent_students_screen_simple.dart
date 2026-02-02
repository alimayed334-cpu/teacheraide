import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/attendance_model.dart';
import '../../models/grade_model.dart';
import '../../models/exam_model.dart';
import '../../database/database_helper.dart';

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
  
  // معايير التقييم
  double _minAveragePercentage = 85.0;
  int _minExamsCount = 3;
  bool _criteriaEnabled = true;
  
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
      _minAveragePercentage = prefs.getDouble('excellent_min_average') ?? 85.0;
      _minExamsCount = prefs.getInt('excellent_min_exams') ?? 3;
      _criteriaEnabled = prefs.getBool('excellent_criteria_enabled') ?? true;
    });
  }
  
  Future<void> _saveCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('excellent_min_average', _minAveragePercentage);
    await prefs.setInt('excellent_min_exams', _minExamsCount);
    await prefs.setBool('excellent_criteria_enabled', _criteriaEnabled);
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateExcellentStudents() async {
    _excellentStudentsByClass.clear();
    
    for (final classModel in _allClasses) {
      if (!_selectedClassIds.contains(classModel.id)) continue;
      
      final classId = classModel.id!;
      final students = await _dbHelper.getStudentsByClass(classId);
      final examsInClass = await _dbHelper.getExamsByClass(classId);
      
      final excellentStudents = <ExcellentStudent>[];
      
      for (final student in students) {
        final grades = await _dbHelper.getGradesByStudent(student.id!);
        final latestGrades = <String, GradeModel>{};
        
        for (final grade in grades) {
          final exam = examsInClass.where((e) => e.title == grade.examName).firstOrNull;
          if (exam != null) {
            if (!latestGrades.containsKey(grade.examName) || 
                latestGrades[grade.examName]!.createdAt.isBefore(grade.createdAt)) {
              latestGrades[grade.examName] = grade;
            }
          }
        }
        
        final gradesList = latestGrades.values.toList();
        
        final missedExams = gradesList.where((g) => 
          g.notes?.contains('غائب') == true
        ).length;
        
        final allAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
        final lecturesInClass = await _dbHelper.getLecturesByClass(classId);
        final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();
        
        final attendances = allAttendances.where((a) => lectureIdsInClass.contains(a.lectureId)).toList();
        final missedLectures = attendances.where((a) => 
          a.status == 'absent'
        ).length;
        
        final scoredGrades = gradesList.where((g) => 
          g.notes?.contains('غائب') != true &&
          g.notes?.contains('غش') != true &&
          g.notes?.contains('مفقودة') != true
        ).toList();
        
        double averagePercentage = 0.0;
        if (scoredGrades.isNotEmpty) {
          double totalPercentage = 0.0;
          int validExamCount = 0;
          
          for (final grade in scoredGrades) {
            final matchingExam = examsInClass.where((e) => e.title == grade.examName).firstOrNull;
            
            if (matchingExam != null && matchingExam.maxScore > 0) {
              final percentage = (grade.score / matchingExam.maxScore) * 100;
              totalPercentage += percentage;
              validExamCount++;
            }
          }
          
          averagePercentage = validExamCount > 0 ? totalPercentage / validExamCount : 0.0;
        }
        
        final totalExams = scoredGrades.length;
        final attendanceRate = attendances.isNotEmpty 
            ? ((attendances.where((a) => a.status == 'present').length) / attendances.length) * 100
            : 0.0;
        
        final isExcellent = averagePercentage >= _minAveragePercentage &&
                           totalExams >= _minExamsCount &&
                           attendanceRate >= 80.0;
        
        if (isExcellent) {
          excellentStudents.add(ExcellentStudent(
            student: student,
            attendanceRate: attendanceRate,
            missedLectures: missedLectures,
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
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1A1A1A),
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(width: 20),
            Text('جاري إنشاء تقرير PDF...'),
          ],
        ),
      ),
    );

    try {
      final pdf = pw.Document();
      
      // تحميل خط عربي وإنجليزي
      pw.Font arabicFont;
      pw.Font arabicFontBold;
      pw.Font englishFont;
      pw.Font englishFontBold;
      try {
        arabicFont = await PdfGoogleFonts.cairoRegular();
        arabicFontBold = await PdfGoogleFonts.cairoBold();
        englishFont = await PdfGoogleFonts.robotoRegular();
        englishFontBold = await PdfGoogleFonts.robotoBold();
      } catch (e) {
        // استخدام الخط الافتراضي إذا فشل تحميل الخط العربي
        arabicFont = pw.Font.helvetica();
        arabicFontBold = pw.Font.helveticaBold();
        englishFont = pw.Font.helvetica();
        englishFontBold = pw.Font.helveticaBold();
      }

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
                  'الطلاب المميزون / Excellent Students',
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
                  'التاريخ / Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
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
                        'الفصل: ${classModel.name} / Class: ${classModel.name}',
                        style: pw.TextStyle(
                          font: arabicFontBold,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue,
                        ),
                      ),
                      pw.SizedBox(height: 12),
                      
                      // الجدول
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey300),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(3),
                          1: const pw.FlexColumnWidth(1.5),
                          2: const pw.FlexColumnWidth(2),
                        },
                        children: [
                          // رأس الجدول باللون الأزرق
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.blue),
                            children: [
                              _buildHeaderCell('اسم الطالب\nStudent Name', arabicFontBold, englishFontBold),
                              _buildHeaderCell('المعدل\nAverage', arabicFontBold, englishFontBold),
                              _buildHeaderCell('عدد الامتحانات\nNumber of Exams', arabicFontBold, englishFontBold),
                            ],
                          ),
                          // بيانات الطلاب
                          ...excellentStudents.map((excellentStudent) {
                            return pw.TableRow(
                              children: [
                                _buildDataCell(excellentStudent.student.name, arabicFont, englishFont),
                                _buildDataCell(excellentStudent.average.toStringAsFixed(1), arabicFont, englishFont),
                                _buildDataCell('${excellentStudent.totalExams}', arabicFont, englishFont),
                              ],
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
                  'إجمالي عدد الطلاب المميزين: ${_excellentStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}\nTotal Excellent Students: ${_excellentStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}',
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

      Navigator.pop(context);

      // فتح الملف مباشرة بدون حوار الطباعة
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'تقرير_الطلاب_المميزين_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في استخراج التقرير: $e')),
      );
    }
  }

  pw.Widget _buildHeaderCell(String text, pw.Font arabicFont, pw.Font englishFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: arabicFont,
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildDataCell(String text, pw.Font arabicFont, pw.Font englishFont) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: arabicFont,
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
      color: _criteriaEnabled ? const Color(0xFF1A1A1A) : Colors.amber.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _criteriaEnabled = !_criteriaEnabled;
                });
                _saveCriteria();
                _loadData();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _criteriaEnabled ? Colors.amber.withOpacity(0.2) : Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.star,
                      color: _criteriaEnabled ? Colors.amber : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'معايير التميز',
                        style: TextStyle(
                          color: _criteriaEnabled ? Colors.amber : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _criteriaEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: _criteriaEnabled ? Colors.amber : Colors.white,
                      size: 48,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_criteriaEnabled) ...[
              _buildCriteriaItem(
                'معدل الطالب (>=)',
                _minAveragePercentage,
                (value) => setState(() {
                  _minAveragePercentage = value;
                  _saveCriteria();
                  _loadData();
                }),
              ),
              _buildCriteriaItem(
                'عدد الامتحانات (>=)',
                _minExamsCount,
                (value) => setState(() {
                  _minExamsCount = value;
                  _saveCriteria();
                  _loadData();
                }),
              ),
            ],
          ],
        ),
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
            }),
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
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCriteriaEditor(String title, dynamic currentValue, Function(dynamic) onSave) {
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
              final value = currentValue is double 
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
          const Text(
            'اختيار الفصول للـ PDF',
            style: TextStyle(
              color: Colors.amber,
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
                      color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.amber),
                    ),
                    child: Text(
                      classModel.name,
                      style: TextStyle(
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
    if (!_criteriaEnabled) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, color: Colors.grey, size: 64),
            SizedBox(height: 16),
            Text(
              'المعايير معطلة',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'قم بتفعيل المعايير لعرض الطلاب المميزين',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    final totalExcellentStudents = _excellentStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    if (totalExcellentStudents == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.star, size: 80, color: Colors.amber),
            SizedBox(height: 16),
            Text(
              'لا يوجد طلاب مميزون حالياً',
              style: TextStyle(color: Colors.amber, fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'حاول تعديل معايير التميز',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _allClasses.length,
      itemBuilder: (context, index) {
        final classModel = _allClasses[index];
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
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
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
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
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
            children: [
              // النجمة الذهبية فوق اسم الطالب
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(top: -8, right: 8, left: 4),
                decoration: BoxDecoration(
                  color: Colors.yellow,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.yellow.withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star,
                  color: Colors.orange,
                  size: 8,
                ),
              ),
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
              if (student.studentId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    student.studentId!,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
                'نسبة الحضور',
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

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

class AtRiskStudentsScreen extends StatefulWidget {
  final ClassModel? initialClass;

  const AtRiskStudentsScreen({
    super.key,
    this.initialClass,
  });

  @override
  State<AtRiskStudentsScreen> createState() => _AtRiskStudentsScreenState();
}

class _AtRiskStudentsScreenState extends State<AtRiskStudentsScreen> with WidgetsBindingObserver {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // معايير التقييم
  int _minMissedExams = 1;
  int _minMissedLectures = 1;
  double _minAveragePercentage = 50.0;
  bool _criteriaEnabled = true; // خيار تفعيل/تعطيل المعايير
  
  // الفصول
  List<ClassModel> _allClasses = [];
  List<int> _selectedClassIds = [];
  List<int> _pdfSelectedClassIds = []; // للـ PDF
  bool _showAllClasses = true;
  bool _showAllClassesForPdf = true;
  
  // البيانات
  Map<int, List<AtRiskStudent>> _atRiskStudentsByClass = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCriteria();
    _loadData();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة تحميل البيانات عند العودة للتطبيق
      _loadData();
    }
  }
  
  
  Future<void> _loadCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _minMissedExams = prefs.getInt('at_risk_min_missed_exams') ?? 1;
      _minMissedLectures = prefs.getInt('at_risk_min_missed_lectures') ?? 1;
      _minAveragePercentage = prefs.getDouble('at_risk_min_average') ?? 50.0;
      _criteriaEnabled = prefs.getBool('at_risk_criteria_enabled') ?? true;
    });
  }
  
  Future<void> _saveCriteria() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('at_risk_min_missed_exams', _minMissedExams);
    await prefs.setInt('at_risk_min_missed_lectures', _minMissedLectures);
    await prefs.setDouble('at_risk_min_average', _minAveragePercentage);
    await prefs.setBool('at_risk_criteria_enabled', _criteriaEnabled);
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // تحميل جميع الفصول
      _allClasses = await _dbHelper.getAllClasses();
      
      // إذا كان هناك فصل محدد مسبقاً
      if (widget.initialClass != null) {
        _showAllClasses = false;
        _selectedClassIds = [widget.initialClass!.id!];
      } else {
        _showAllClasses = true;
        _selectedClassIds = _allClasses.map((c) => c.id!).toList();
        _showAllClassesForPdf = true;
        _pdfSelectedClassIds = _allClasses.map((c) => c.id!).toList();
      }
      
      await _calculateAtRiskStudents();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _calculateAtRiskStudents() async {
    _atRiskStudentsByClass.clear();
    
    // إذا كانت المعايير معطلة، نعرض قائمة فارغة
    if (!_criteriaEnabled) {
      setState(() {});
      return;
    }
    
    final classIds = _selectedClassIds.isEmpty 
        ? _allClasses.map((c) => c.id!).toList()
        : _selectedClassIds;
    
    for (final classId in classIds) {
      final students = await _dbHelper.getStudentsByClass(classId);
      final atRiskStudents = <AtRiskStudent>[];
      
      for (final student in students) {
        // حساب الامتحانات الغائبة للفصل الحالي فقط
        final allGrades = await _dbHelper.getGradesByStudent(student.id!);
        final examsInClass = await _dbHelper.getExamsByClass(classId);
        final examNamesInClass = examsInClass.map((e) => e.title).toSet();
        
        // تصفية الدرجات للفصل الحالي فقط
        final allGradesInClass = allGrades.where((g) => examNamesInClass.contains(g.examName)).toList();
        
        // أخذ آخر درجة فقط لكل امتحان (لتجنب التكرار)
        final Map<String, GradeModel> latestGrades = {};
        for (final grade in allGradesInClass) {
          final key = '${grade.examName}_${grade.studentId}';
          if (!latestGrades.containsKey(key) || 
              (grade.createdAt != null && latestGrades[key]!.createdAt != null && 
               grade.createdAt!.isAfter(latestGrades[key]!.createdAt!))) {
            latestGrades[key] = grade;
          }
        }
        
        final grades = latestGrades.values.toList();
        
        final missedExams = grades.where((g) => 
          g.notes?.contains('غائب') == true
        ).length;
        
        // حساب المحاضرات الغائبة للفصل الحالي فقط
        final allAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
        final lecturesInClass = await _dbHelper.getLecturesByClass(classId);
        final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();
        
        final attendances = allAttendances.where((a) => lectureIdsInClass.contains(a.lectureId)).toList();
        final missedLectures = attendances.where((a) => 
          a.status == AttendanceStatus.absent
        ).length;
        
        // حساب المعدل العام من امتحانات الفصل الحالي فقط - بنفس طريقة exams_screen
        final scoredGrades = grades.where((g) => 
          g.notes?.contains('غائب') != true &&
          g.notes?.contains('غش') != true &&
          g.notes?.contains('مفقودة') != true
        ).toList();
        
        double averagePercentage = 0.0;
        if (scoredGrades.isNotEmpty) {
          double totalPercentage = 0.0;
          int validExamCount = 0;
          
          for (final grade in scoredGrades) {
            // البحث عن الامتحان المطابق للحصول على الدرجة القصوى الصحيحة
            final matchingExam = examsInClass.where((e) => e.title == grade.examName).firstOrNull;
            
            if (matchingExam != null && matchingExam.maxScore > 0) {
              // حساب النسبة المئوية لهذا الامتحان بنفس طريقة exams_screen
              final percentage = (grade.score / matchingExam.maxScore) * 100;
              totalPercentage += percentage;
              validExamCount++;
            }
          }
          
          // حساب معدل النسب المئوية
          averagePercentage = validExamCount > 0 ? totalPercentage / validExamCount : 0.0;
        }
        
        // التحقق من المعايير
        final isAtRisk = missedExams >= _minMissedExams ||
                        missedLectures >= _minMissedLectures ||
                        (scoredGrades.isNotEmpty && averagePercentage < _minAveragePercentage);
        
        if (isAtRisk) {
          atRiskStudents.add(AtRiskStudent(
            student: student,
            missedExams: missedExams,
            missedLectures: missedLectures,
            averagePercentage: averagePercentage,
          ));
        }
      }
      
      if (atRiskStudents.isNotEmpty) {
        _atRiskStudentsByClass[classId] = atRiskStudents;
      }
    }
  }

  void _showClassSelector() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('اختيار الفصول'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: const Text('جميع الفصول'),
                  value: _showAllClasses,
                  onChanged: (value) {
                    setDialogState(() {
                      _showAllClasses = value ?? true;
                      if (_showAllClasses) {
                        _selectedClassIds = _allClasses.map((c) => c.id!).toList();
                      }
                    });
                  },
                ),
                const Divider(),
                if (!_showAllClasses)
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _allClasses.length,
                      itemBuilder: (context, index) {
                        final classModel = _allClasses[index];
                        final isSelected = _selectedClassIds.contains(classModel.id);
                        
                        return CheckboxListTile(
                          title: Text(classModel.name),
                          subtitle: Text(classModel.subject),
                          value: isSelected,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                _selectedClassIds.add(classModel.id!);
                              } else {
                                _selectedClassIds.remove(classModel.id);
                              }
                            });
                          },
                        );
                      },
                    ),
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
                Navigator.pop(context);
                setState(() => _isLoading = true);
                await _calculateAtRiskStudents();
                setState(() => _isLoading = false);
              },
              child: const Text('تطبيق'),
            ),
          ],
        ),
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
                await _saveCriteria(); // حفظ المعايير
                Navigator.pop(context);
                setState(() => _isLoading = true);
                await _calculateAtRiskStudents();
                setState(() => _isLoading = false);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPdf() async {
    try {
      // عرض مؤشر التحميل
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 16),
                Text('جاري إنشاء ملف PDF...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

            // جداول الفصول
            ..._allClasses.where((classModel) => _pdfSelectedClassIds.contains(classModel.id!)).map((classModel) {
              final atRiskStudents = _atRiskStudentsByClass[classModel.id!] ?? [];
              if (atRiskStudents.isEmpty) return pw.SizedBox.shrink();

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
                      3: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      // رأس الجدول باللون الأزرق
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          _buildHeaderCell('اسم الطالب\nStudent Name', arabicFontBold, englishFontBold),
                          _buildHeaderCell('المعدل\nAverage', arabicFontBold, englishFontBold),
                          _buildHeaderCell('غيابات الامتحان\nExam Absences', arabicFontBold, englishFontBold),
                          _buildHeaderCell('غيابات المحاضرات\nLecture Absences', arabicFontBold, englishFontBold),
                        ],
                      ),
                      // بيانات الطلاب
                      ...atRiskStudents.map((student) {
                        return pw.TableRow(
                          children: [
                            _buildDataCell(student.student.name, arabicFont, englishFont),
                            _buildDataCell(student.averagePercentage.toStringAsFixed(1), arabicFont, englishFont),
                            _buildDataCell(student.missedExams.toString(), arabicFont, englishFont),
                            _buildDataCell(student.missedLectures.toString(), arabicFont, englishFont),
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
              'إجمالي عدد الطلاب في خطر: ${_atRiskStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}\nTotal At Risk Students: ${_atRiskStudentsByClass.values.fold(0, (sum, students) => sum + students.length)}',
              style: pw.TextStyle(
                font: arabicFontBold,
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
          ],
        ),
      );
    },
  );

  // فتح الملف مباشرة بدون حوار الطباعة
  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: 'طلاب_في_خطر_${dateFormat.format(now)}.pdf',
  );
} catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('خطأ في تصدير PDF: $e')),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            tooltip: 'تصدير PDF',
            onPressed: _atRiskStudentsByClass.isEmpty ? null : _exportToPdf,
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
      color: _criteriaEnabled ? const Color(0xFF1A1A1A) : Colors.red.withOpacity(0.1),
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
                  color: _criteriaEnabled ? Colors.red.withOpacity(0.2) : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: _criteriaEnabled ? Colors.red : Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'معايير الخطر',
                        style: TextStyle(
                          color: _criteriaEnabled ? Colors.red : Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _criteriaEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: _criteriaEnabled ? Colors.red : Colors.white,
                      size: 48,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_criteriaEnabled) ...[
              _buildCriteriaItem(
                'عدد غيابات المحاضرات (>=)',
                _minMissedLectures,
                (value) => setState(() {
                  _minMissedLectures = value;
                  _saveCriteria();
                  _loadData();
                }),
              ),
              _buildCriteriaItem(
                'عدد غيابات الامتحانات (>=)',
                _minMissedExams,
                (value) => setState(() {
                  _minMissedExams = value;
                  _saveCriteria();
                  _loadData();
                }),
              ),
              _buildClickableCriteriaItem(
                'معدل الطالب (<)',
                _minAveragePercentage,
                (value) => setState(() {
                  _minAveragePercentage = value;
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

  Widget _buildCriteriaItem(String title, int value, Function(dynamic) onChanged) {
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
                if (newValue is int) {
                  if (title.contains('امتحانات')) {
                    _minMissedExams = newValue;
                  } else {
                    _minMissedLectures = newValue;
                  }
                }
                _saveCriteria();
                _loadData();
              });
            }),
            child: Container(
              width: 60,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  '$value',
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
    );
  }

  Widget _buildClickableCriteriaItem(String title, double value, Function(dynamic) onChanged) {
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
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  '${value.toStringAsFixed(1)}%',
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
    );
  }
  Widget _buildClassSelectionSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختيار الفصول للعرض',
            style: TextStyle(
              color: Colors.white,
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
                      _showAllClasses = !_showAllClasses;
                      if (_showAllClasses) {
                        _selectedClassIds = _allClasses.map((c) => c.id!).toList();
                      } else {
                        _selectedClassIds.clear();
                      }
                    });
                    // استدعاء بعد setState
                    _calculateAtRiskStudents();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _showAllClasses ? Colors.grey.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showAllClasses ? Icons.check_box : Icons.check_box_outline_blank,
                          color: Colors.grey,
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
          if (!_showAllClasses) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allClasses.map((classModel) {
                final isSelected = _selectedClassIds.contains(classModel.id!);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedClassIds.remove(classModel.id!);
                      } else {
                        _selectedClassIds.add(classModel.id!);
                      }
                    });
                    // استدعاء بعد setState
                    _calculateAtRiskStudents();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.grey.withOpacity(0.2) : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Text(
                      classModel.name,
                      style: TextStyle(
                        color: isSelected ? Colors.grey : Colors.white,
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
    // إذا كانت المعايير معطلة، اعرض رسالة واضحة
    if (!_criteriaEnabled) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning, color: Colors.grey, size: 64),
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
              'قم بتفعيل المعايير لعرض الطلاب في خطر',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    // إذا كانت المعايير مفعلة، تحقق من وجود طلاب في خطر
    final totalAtRiskStudents = _atRiskStudentsByClass.values
        .fold(0, (sum, students) => sum + students.length);
    
    if (totalAtRiskStudents == 0) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 64),
            SizedBox(height: 16),
            Text(
              'لا يوجد طلاب في خطر',
              style: TextStyle(
                color: Colors.green,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'جميع الطلاب في وضع جيد',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _atRiskStudentsByClass.length,
      itemBuilder: (context, index) {
        final entry = _atRiskStudentsByClass.entries.elementAt(index);
        final classId = entry.key;
        final students = entry.value;
        final classModel = _allClasses.firstWhere((c) => c.id == classId);
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
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
                        '${students.length} طالب',
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
              ...students.map((atRiskStudent) => _buildStudentCard(atRiskStudent)),
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // النقطة الحمراء صغيرة بجانب اسم الطالب
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 4),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
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
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatCard(
                'المعدل',
                atRiskStudent.averagePercentage.toStringAsFixed(1),
                atRiskStudent.averagePercentage >= 70 ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                'غياب امتحانات',
                '${atRiskStudent.missedExams}',
                Colors.red,
              ),
              const SizedBox(width: 8),
              _buildStatCard(
                'غياب محاضرات',
                '${atRiskStudent.missedLectures}',
                Colors.red,
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

class AtRiskStudent {
  final StudentModel student;
  final int missedExams;
  final int missedLectures;
  final double averagePercentage;

  AtRiskStudent({
    required this.student,
    required this.missedExams,
    required this.missedLectures,
    required this.averagePercentage,
  });
}

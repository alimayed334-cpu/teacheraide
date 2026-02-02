import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../providers/grade_provider.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/attendance_model.dart';
import '../../theme/app_theme.dart';
import '../../database/database_helper.dart';
import '../students/student_details_screen.dart';
import 'exam_statistics_screen.dart';
import 'package:intl/intl.dart';
import 'dart:io';

enum ExamSortType { highestAverage, lowestAverage, name, gender }
enum GradeStatus { present, absent, cheating, missing }

class ExamsScreen extends StatefulWidget {
  final ClassModel classModel;

  const ExamsScreen({super.key, required this.classModel});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> with WidgetsBindingObserver {
  ExamSortType _sortType = ExamSortType.name;
  final Map<int, Map<int, double>> _studentGrades = {};
  final Map<int, Map<int, GradeStatus>> _studentStatus = {};
  final Map<int, Map<int, String>> _studentComments = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<StudentModel> _students = [];
  List<ExamModel> _exams = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Map<int, bool> _atRiskStudents = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة فحص المعايير عند العودة للتطبيق
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAtRiskStudents();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ExamsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعادة تحميل البيانات عند تغيير الفصل
    if (oldWidget.classModel.id != widget.classModel.id) {
      _loadData();
    } else {
      // فحص المعايير عند العودة للصفحة
      _checkAtRiskStudents();
      // إعادة تحميل الطلاب عند العودة للصفحة
      _loadStudents();
    }
  }

  Future<void> _loadStudents() async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    await studentProvider.loadStudentsByClass(widget.classModel.id!);
    
    if (mounted) {
      setState(() {
        _students = studentProvider.students;
      });
      
      // تحميل الدرجات للطلاب الجدد
      await _loadGrades();
    }
  }

  Future<void> _loadData() async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    await Future.wait([
      studentProvider.loadStudentsByClass(widget.classModel.id!),
      examProvider.loadExamsByClass(widget.classModel.id!),
    ]);
    
    setState(() {
      _students = studentProvider.students;
      _exams = examProvider.exams;
    });
    
    await _loadGrades();
    await _checkAtRiskStudents();
  }
  
  Future<void> _checkAtRiskStudents() async {
    // تحميل المعايير من SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final int minMissedExams = prefs.getInt('at_risk_min_missed_exams') ?? 1;
    final int minMissedLectures = prefs.getInt('at_risk_min_missed_lectures') ?? 1;
    final double minAveragePercentage = prefs.getDouble('at_risk_min_average') ?? 50.0;
    final bool criteriaEnabled = prefs.getBool('at_risk_criteria_enabled') ?? true;
    
    final Map<int, bool> atRisk = {};
    
    // إذا كانت المعايير معطلة، جميع الطلاب ليسوا في خطر
    if (!criteriaEnabled) {
      for (final student in _students) {
        atRisk[student.id!] = false;
      }
      setState(() {
        _atRiskStudents = atRisk;
      });
      return;
    }
    
    // الحصول على معرفات المحاضرات في الفصل الحالي
    final lecturesInClass = await _dbHelper.getLecturesByClass(widget.classModel.id!);
    final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();
    
    for (final student in _students) {
      try {
        // حساب الامتحانات الغائبة من البيانات المحلية
        int missedExams = 0;
        if (_studentStatus.containsKey(student.id)) {
          for (final examId in _studentStatus[student.id!]!.keys) {
            if (_studentStatus[student.id!]![examId] == GradeStatus.absent) {
              missedExams++;
            }
          }
        }
        
        // الحصول على جميع الحضور ثم تصفيته للفصل الحالي فقط
        final allAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
        final attendances = allAttendances.where((a) => lectureIdsInClass.contains(a.lectureId)).toList();
        
        final missedLectures = attendances.where((a) => 
          a.status == AttendanceStatus.absent
        ).length;
        
        // حساب المعدل من البيانات المحلية (نفس منطق _calculateStudentAverage)
        final averagePercentage = _calculateStudentAverage(student.id!);
        
        // في صفحة الامتحانات: التحقق من الامتحانات الغائبة والمعدل فقط (بدون المحاضرات الغائبة)
        final isAtRisk = missedExams >= minMissedExams ||
                        (averagePercentage > 0 && averagePercentage < minAveragePercentage);
        
        atRisk[student.id!] = isAtRisk;
      } catch (e) {
        atRisk[student.id!] = false;
      }
    }
    
    setState(() {
      _atRiskStudents = atRisk;
    });
  }
  
  Future<void> _loadGrades() async {
    final gradeProvider = Provider.of<GradeProvider>(context, listen: false);
    
    for (final student in _students) {
      final grades = await gradeProvider.getGradesByStudent(student.id!);
      
      for (final grade in grades) {
        if (!_studentGrades.containsKey(student.id)) {
          _studentGrades[student.id!] = {};
          _studentStatus[student.id!] = {};
          _studentComments[student.id!] = {};
        }
        
        final exam = _exams.where((e) => e.title == grade.examName).isNotEmpty 
            ? _exams.where((e) => e.title == grade.examName).first 
            : null;
        if (exam != null) {
          _studentGrades[student.id!]![exam.id!] = grade.score;
          _studentComments[student.id!]![exam.id!] = grade.notes ?? '';
          
          // تحديد الحالة بناءً على الملاحظات فقط، بغض النظر عن الدرجة
          if (grade.notes?.contains('غائب') == true) {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.absent;
          } else if (grade.notes?.contains('غش') == true) {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.cheating;
          } else if (grade.notes?.contains('مفقودة') == true) {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.missing;
          } else {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.present;
          }
        }
      }
    }
    
    setState(() {});
  }

  double _calculateStudentAverage(int studentId) {
    if (!_studentGrades.containsKey(studentId) || _studentGrades[studentId]!.isEmpty) {
      return 0.0;
    }
    
    double totalPercentage = 0.0;
    int examCount = 0;
    
    // تحويل كل امتحان إلى نسبة مئوية ثم حساب المعدل
    for (final examId in _studentGrades[studentId]!.keys) {
      // تجاهل الدرجات للطلاب الغائبين أو الغشاشين أو الأوراق المفقودة
      final status = _studentStatus[studentId]?[examId];
      if (status == GradeStatus.absent || 
          status == GradeStatus.cheating || 
          status == GradeStatus.missing) {
        continue;
      }
      
      final grade = _studentGrades[studentId]![examId]!;
      final exam = _exams.firstWhere((e) => e.id == examId);
      
      // تحويل الدرجة إلى نسبة مئوية
      final percentage = (grade / exam.maxScore) * 100;
      totalPercentage += percentage;
      examCount++;
    }
    
    // حساب معدل النسب المئوية
    return examCount > 0 ? totalPercentage / examCount : 0.0;
  }

  Color _getGradeColor(double grade, double maxScore) {
    final percentage = (grade / maxScore) * 100;
    
    if (grade == 0) {
      return Colors.red[900]!;
    }
    
    if (percentage < 50) {
      return Colors.red[600]!;
    }
    
    if (percentage == 50) {
      return Colors.orange[600]!;
    }
    
    if (grade >= maxScore) {
      return Colors.green[900]!;
    } else if (grade >= maxScore - 5) {
      return Colors.green[800]!;
    } else if (grade >= maxScore - 10) {
      return Colors.green[700]!;
    } else if (grade >= maxScore - 15) {
      return Colors.green[600]!;
    } else if (grade >= maxScore - 20) {
      return Colors.green[500]!;
    } else if (grade >= maxScore - 25) {
      return Colors.green[400]!;
    } else {
      return Colors.green[300]!;
    }
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
            width: 110,
            height: 20,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.grey.shade600,
                width: 0.5,
              ),
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
          title: Text('درجة ${student.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('امتحان: ${exam.title}'),
                Text('الدرجة القصوى: ${exam.maxScore}'),
                const SizedBox(height: 16),
                
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
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
                if (status == GradeStatus.present && gradeController.text.isNotEmpty) {
                  grade = double.tryParse(gradeController.text) ?? 0;
                  
                  // التحقق من أن الدرجة لا تتجاوز الدرجة القصوى
                  if (grade > exam.maxScore) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('الدرجة يجب أن تكون أقل من أو تساوي الدرجة القصوى (${exam.maxScore.toInt()})'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  
                  // التحقق من أن الدرجة ليست سالبة
                  if (grade < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('الدرجة يجب أن تكون صفر أو أكثر'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }
                
                String notes = commentController.text;
                if (status == GradeStatus.absent) {
                  notes = 'غائب${notes.isNotEmpty ? ' - $notes' : ''}';
                } else if (status == GradeStatus.cheating) {
                  notes = 'غش${notes.isNotEmpty ? ' - $notes' : ''}';
                } else if (status == GradeStatus.missing) {
                  notes = 'مفقودة${notes.isNotEmpty ? ' - $notes' : ''}';
                }
                
                final success = await gradeProvider.saveGrade(
                  studentId: student.id!,
                  examName: exam.title,
                  score: grade,
                  maxScore: exam.maxScore,
                  examDate: exam.date,
                  notes: notes,
                );
                
                if (success) {
                  // تحديث البيانات المحلية أولاً
                  if (!_studentGrades.containsKey(student.id)) {
                    _studentGrades[student.id!] = {};
                    _studentStatus[student.id!] = {};
                    _studentComments[student.id!] = {};
                  }
                  _studentGrades[student.id!]![exam.id!] = grade;
                  _studentStatus[student.id!]![exam.id!] = status;
                  _studentComments[student.id!]![exam.id!] = commentController.text;
                  
                  // إغلاق الحوار
                  Navigator.pop(context);
                  
                  // إعادة فحص الطلاب في خطر وتحديث الواجهة فوراً
                  if (mounted) {
                    setState(() {});
                    await _checkAtRiskStudents();
                  }
                  
                  // عرض رسالة النجاح
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تم حفظ درجة ${student.name}')),
                    );
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('فشل في حفظ الدرجة')),
                  );
                }
              },
              child: const Text('موافق'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExamDialog() {
    showDialog(
      context: context,
      builder: (context) => _AddExamDialog(
        currentClass: widget.classModel,
        onSave: () {
          setState(() {
            _loadData();
          });
        },
      ),
    );
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    List<StudentModel> filtered = students;
    if (_searchQuery.isNotEmpty) {
      filtered = students.where((student) {
        return student.name.toLowerCase().contains(_searchQuery);
      }).toList();
    }
    
    final List<StudentModel> sorted = List.from(filtered);
    
    switch (_sortType) {
      case ExamSortType.highestAverage:
        sorted.sort((a, b) => _calculateStudentAverage(b.id!).compareTo(_calculateStudentAverage(a.id!)));
        break;
      case ExamSortType.lowestAverage:
        sorted.sort((a, b) => _calculateStudentAverage(a.id!).compareTo(_calculateStudentAverage(b.id!)));
        break;
      case ExamSortType.name:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case ExamSortType.gender:
        break;
    }
    
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
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
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                PopupMenuButton<ExamSortType>(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  tooltip: 'تصنيف',
                  onSelected: (ExamSortType type) {
                    setState(() {
                      _sortType = type;
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: ExamSortType.name,
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha),
                          SizedBox(width: 8),
                          Text('أبجدي'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ExamSortType.highestAverage,
                      child: Row(
                        children: [
                          Icon(Icons.trending_up),
                          SizedBox(width: 8),
                          Text('أعلى معدل'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ExamSortType.lowestAverage,
                      child: Row(
                        children: [
                          Icon(Icons.trending_down),
                          SizedBox(width: 8),
                          Text('أقل معدل'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
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
                final students = _sortStudents(_students);

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
                    // صف العناوين والتواريخ في الأعلى
                    if (_exams.isNotEmpty)
                      Container(
                        color: const Color(0xFF2D2D2D), // رمادي داكن
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 150,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text(
                                  'الطلاب',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // خط فاصل رمادي
                            Container(
                              width: 3,
                              height: 80,
                              color: const Color(0xFF404040), // رمادي
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            // العناوين والتواريخ - عنوان الامتحان في الأعلى
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _exams.asMap().entries.map((entry) {
                                    final exam = entry.value;
                                    return GestureDetector(
                                      onTap: () => _showExamOptions(exam),
                                      child: Container(
                                        width: 140,
                                        alignment: Alignment.center,
                                        margin: const EdgeInsets.only(left: 8),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              exam.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF404040),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM').format(exam.date),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                ),
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

                    // قائمة الطلاب
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: students.map((student) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFF404040),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // صورة الطالب
                                  Container(
                                    width: 50,
                                    height: 50,
                                    margin: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF2D2D2D),
                                        width: 2,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: Colors.white,
                                      backgroundImage: student.photo != null
                                          ? AssetImage(student.photo!)
                                          : null,
                                      child: student.photo == null
                                          ? Text(
                                              student.name.isNotEmpty ? student.name[0] : '?',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  
                                  // اسم الطالب والمعدل
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
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
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'المعدل: ${_calculateStudentAverage(student.id!).toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              color: _calculateStudentAverage(student.id!) >= 75 ? Colors.green : Colors.red,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  
                                  // مربعات الدرجات
                                  if (_exams.isNotEmpty)
                                    SizedBox(
                                      height: 80,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: _exams.length,
                                        itemBuilder: (context, examIndex) {
                                          final exam = _exams[examIndex];
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 2),
                                            child: _buildGradeBox(student, exam),
                                          );
                                        },
                                      ),
                                    ),
                                  
                                  // الإحصائيات
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _buildStudentStats(student.id!),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                                                        decoration: const BoxDecoration(
                                                          color: Colors.yellow,
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                    
                                                    // اسم الطالب في سطر واحد
                                                    Expanded(
                                                      child: Text(
                                                        student.name,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w500,
                                                          fontSize: 14,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        textAlign: TextAlign.start,
                                                      ),
                                                    ),
                                                    
                                                    // النسبة المئوية
                                                    Text(
                                                      '${studentAverage.toStringAsFixed(1)}%',
                                                      style: TextStyle(
                                                        color: studentAverage >= 50 ? Colors.green[400] : Colors.red[400],
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            
                                            // الدائرة البيضاء (الصورة الشخصية) - ملاصقة لليسار
                                            Container(
                                              margin: const EdgeInsets.only(left: 4, right: 2),
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                alignment: Alignment.center,
                                                children: [
                                                  CircleAvatar(
                                                    radius: 14,
                                                    backgroundColor: Colors.white,
                                                    backgroundImage: student.photo != null
                                                        ? AssetImage(student.photo!)
                                                        : null,
                                                    child: student.photo == null
                                                        ? Text(
                                                            student.name[0],
                                                            style: const TextStyle(
                                                              color: Colors.black,
                                                              fontWeight: FontWeight.bold,
                                                              fontSize: 12,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Container(
                                      width: 2,
                                      height: 80,
                                      color: const Color(0xFF505050),
                                      margin: const EdgeInsets.only(right: 12, left: 4),
                                    ),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: _exams.map((exam) {
                                            return Container(
                                              width: 100,
                                              alignment: Alignment.center,
                                              margin: const EdgeInsets.only(left: 8),
                                              child: _buildGradeBox(student, exam),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // خط فاصل رمادي بين الطلاب
                              if (index < students.length - 1)
                                Container(
                                  height: 3,
                                  color: const Color(0xFF404040), // رمادي
                                ),
                            ],
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
        onPressed: _showAddExamDialog,
        child: const Icon(Icons.add),
        tooltip: 'إضافة امتحان',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _showExamOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات الامتحان: ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(exam.date)}'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.analytics, color: Colors.blue),
              title: const Text('إحصائيات الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _navigateToExamStatistics(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text('أفضل الطلاب في الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _sortStudentsByExamGrade(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_fix_high, color: Colors.green),
              title: const Text('ملء تلقائي'),
              onTap: () {
                Navigator.pop(context);
                _showAutoFillOptions(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.purple),
              title: const Text('تقرير عن الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _showExamReport(exam);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: AppTheme.primaryColor),
              title: const Text('تغيير تاريخ الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _showEditExamDateDialog(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _deleteExam(exam);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteExam(ExamModel exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف امتحان "${exam.title}"؟\nسيتم حذف جميع الدرجات المتعلقة به.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final examProvider = Provider.of<ExamProvider>(context, listen: false);
      final success = await examProvider.deleteExam(exam.id!);
      
      if (success) {
        setState(() {
          _loadData();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حذف امتحان "${exam.title}"')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في حذف الامتحان')),
        );
      }
    }
  }

  Future<void> _showEditExamDateDialog(ExamModel exam) async {
    DateTime selectedDate = exam.date;
    
    final date = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (date != null && date != exam.date) {
      final examProvider = Provider.of<ExamProvider>(context, listen: false);
      final updatedExam = ExamModel(
        id: exam.id,
        title: exam.title,
        date: date,
        maxScore: exam.maxScore,
        classId: exam.classId,
        description: exam.description,
        createdAt: exam.createdAt,
        updatedAt: DateTime.now(),
      );
      final success = await examProvider.updateExam(updatedExam);
      
      if (success) {
        setState(() {
          _loadData();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث تاريخ امتحان "${exam.title}"')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل في تحديث تاريخ الامتحان')),
        );
      }
    }
  }

  void _navigateToExamStatistics(ExamModel exam) {
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
  }

  void _showTopGradesOptions(ExamModel exam) {
    // الحصول على الطلاب مع درجاتهم في هذا الامتحان
    List<MapEntry<StudentModel, double>> studentGradesList = [];
    
    for (final student in _students) {
      final grade = _studentGrades[student.id!]?[exam.id!];
      final status = _studentStatus[student.id!]?[exam.id!];
      
      if (grade != null && status == GradeStatus.present) {
        studentGradesList.add(MapEntry(student, grade));
      }
    }
    
    // ترتيب الطلاب حسب الدرجة (من الأعلى إلى الأقل)
    studentGradesList.sort((a, b) => b.value.compareTo(a.value));
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('أعلى الدرجات - ${exam.title}'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('الدرجة القصوى: ${exam.maxScore.toInt()}'),
                    Text('عدد الممتحنين: ${studentGradesList.length}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: studentGradesList.length,
                  itemBuilder: (context, index) {
                    final entry = studentGradesList[index];
                    final student = entry.key;
                    final grade = entry.value;
                    final percentage = (grade / exam.maxScore) * 100;
                    
                    // تحديد لون الترتيب
                    Color rankColor;
                    IconData rankIcon;
                    
                    if (index == 0) {
                      rankColor = Colors.amber;
                      rankIcon = Icons.emoji_events;
                    } else if (index == 1) {
                      rankColor = Colors.grey[400]!;
                      rankIcon = Icons.emoji_events;
                    } else if (index == 2) {
                      rankColor = Colors.brown[400]!;
                      rankIcon = Icons.emoji_events;
                    } else {
                      rankColor = Colors.blue;
                      rankIcon = Icons.person;
                    }
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: index < 3 ? rankColor.withOpacity(0.1) : Colors.grey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: index < 3 ? rankColor.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          // نقطة حمراء للطلاب في خطر
                          if (_atRiskStudents[student.id] == true)
                            Container(
                              margin: const EdgeInsets.only(right: 4),
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                          // صورة الطالب
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.grey.shade300,
                            backgroundImage: student.photo != null 
                                ? AssetImage(student.photo!) 
                                : null,
                            child: student.photo == null 
                                ? Text(
                                    student.name[0],
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ) 
                                : null,
                          ),
                          const SizedBox(width: 8),
                          // رقم الترتيب
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: rankColor.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: index < 3 
                                ? Icon(rankIcon, color: rankColor, size: 20)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: rankColor,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
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
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    '${percentage.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getGradeColor(grade, exam.maxScore).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _getGradeColor(grade, exam.maxScore).withOpacity(0.5),
                              ),
                            ),
                            child: Text(
                              '${grade.toInt()}/${exam.maxScore.toInt()}',
                              style: TextStyle(
                                color: _getGradeColor(grade, exam.maxScore),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
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
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _sortStudentsByExamGrade(exam);
            },
            child: const Text('ترتيب القائمة'),
          ),
        ],
      ),
    );
  }

  void _sortStudentsByExamGrade(ExamModel exam) {
    setState(() {
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
      SnackBar(content: Text('تم ترتيب الطلاب حسب درجات ${exam.title}')),
    );
  }

  void _showAutoFillOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ملء تلقائي للدرجات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('مخصص'),
              subtitle: const Text('إدخال درجة مخصصة لجميع الطلاب'),
              onTap: () {
                Navigator.pop(context);
                _showCustomGradeDialog(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.green),
              title: const Text('أعلى درجة'),
              subtitle: Text('إعطاء الدرجة القصوى (${exam.maxScore.toInt()}) لجميع الطلاب'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, exam.maxScore, GradeStatus.present);
              },
            ),
            ListTile(
              leading: const Icon(Icons.minimize, color: Colors.red),
              title: const Text('أقل درجة'),
              subtitle: const Text('إعطاء صفر لجميع الطلاب'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.present);
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline, color: Colors.purple),
              title: const Text('مفقودة'),
              subtitle: const Text('تحديد جميع الأوراق كمفقودة'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.missing);
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_off, color: Colors.orange),
              title: const Text('غياب'),
              subtitle: const Text('تحديد جميع الطلاب كغائبين'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.absent);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning, color: Colors.red),
              title: const Text('غش'),
              subtitle: const Text('تحديد جميع الطلاب كغاشين'),
              onTap: () {
                Navigator.pop(context);
                _autoFillGrades(exam, 0, GradeStatus.cheating);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  void _showCustomGradeDialog(ExamModel exam) {
    final gradeController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('درجة مخصصة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('امتحان: ${exam.title}'),
            Text('الدرجة القصوى: ${exam.maxScore.toInt()}'),
            const SizedBox(height: 16),
            TextField(
              controller: gradeController,
              decoration: InputDecoration(
                labelText: 'الدرجة المخصصة',
                hintText: 'من 0 إلى ${exam.maxScore.toInt()}',
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
              final grade = double.tryParse(gradeController.text);
              if (grade != null && grade >= 0 && grade <= exam.maxScore) {
                Navigator.pop(context);
                _autoFillGrades(exam, grade, GradeStatus.present);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('يرجى إدخال درجة صحيحة من 0 إلى ${exam.maxScore.toInt()}')),
                );
              }
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  Future<void> _autoFillGrades(ExamModel exam, double grade, GradeStatus status) async {
    final gradeProvider = Provider.of<GradeProvider>(context, listen: false);
    
    for (final student in _students) {
      String notes = '';
      if (status == GradeStatus.absent) {
        notes = 'غائب';
      } else if (status == GradeStatus.cheating) {
        notes = 'غش';
      } else if (status == GradeStatus.missing) {
        notes = 'مفقودة';
      }
      
      await gradeProvider.saveGrade(
        studentId: student.id!,
        examName: exam.title,
        score: grade,
        maxScore: exam.maxScore,
        examDate: exam.date,
        notes: notes,
      );
    }
    
    await _loadGrades();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم تطبيق الدرجات على جميع الطلاب')),
    );
  }

  // دالة تقرير الامتحان PDF
  Future<void> _showExamReport(ExamModel exam) async {
    try {
      print('Starting exam report generation for: ${exam.title}');
      print('Step 1: Loading Arabic font...');
      
      // عرض مؤشر تحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('جاري إنشاء تقرير PDF...'),
            ],
          ),
        ),
      );

      // التحقق من وجود بيانات
      if (_students.isEmpty) {
        print('No students found');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد طلاب في هذا الفصل')),
        );
        return;
      }

      print('Found ${_students.length} students');

      // الحصول على درجات الامتحان
      print('Step 2: Getting exam grades data...');
      final List<GradeModel> allGrades = [];
      for (final student in _students) {
        try {
          final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
          allGrades.addAll(studentGrades);
        } catch (e) {
          print('Error getting grades for student ${student.id}: $e');
        }
      }
      final grades = allGrades.where((g) => g.examName == exam.title).toList();
      
      print('Found ${grades.length} grade records');
      
      // حساب الإحصائيات
      int totalStudents = grades.length;
      int presentCount = grades.where((g) => !(g.notes?.contains('غائب') ?? false)).length;
      int absentCount = grades.where((g) => g.notes?.contains('غائب') ?? false).length;
      int missingCount = grades.where((g) => g.notes?.contains('مفقودة') ?? false).length;
      
      // حساب متوسط الدرجات
      double averageScore = 0.0;
      final scoredGrades = grades.where((g) => 
        !(g.notes?.contains('غائب') ?? false) &&
        !(g.notes?.contains('غش') ?? false) &&
        !(g.notes?.contains('مفقودة') ?? false)
      ).toList();
      
      if (scoredGrades.isNotEmpty) {
        double totalScore = scoredGrades.fold(0.0, (sum, grade) => sum + grade.score);
        averageScore = totalScore / scoredGrades.length;
      }

      // حساب توزيع النسب المئوية
      Map<String, int> percentageDistribution = {
        '100': 0,
        '90-99': 0,
        '80-89': 0,
        '70-79': 0,
        '60-69': 0,
        '50-59': 0,
        '40-49': 0,
        '30-39': 0,
        '20-29': 0,
        '10-19': 0,
        '0-9': 0,
      };

      for (final grade in scoredGrades) {
        final percentage = (grade.score / exam.maxScore) * 100;
        if (percentage >= 90) {
          percentageDistribution['90-99'] = (percentageDistribution['90-99'] ?? 0) + 1;
        } else if (percentage >= 80) {
          percentageDistribution['80-89'] = (percentageDistribution['80-89'] ?? 0) + 1;
        } else if (percentage >= 70) {
          percentageDistribution['70-79'] = (percentageDistribution['70-79'] ?? 0) + 1;
        } else if (percentage >= 60) {
          percentageDistribution['60-69'] = (percentageDistribution['60-69'] ?? 0) + 1;
        } else if (percentage >= 50) {
          percentageDistribution['50-59'] = (percentageDistribution['50-59'] ?? 0) + 1;
        } else if (percentage >= 40) {
          percentageDistribution['40-49'] = (percentageDistribution['40-49'] ?? 0) + 1;
        } else if (percentage >= 30) {
          percentageDistribution['30-39'] = (percentageDistribution['30-39'] ?? 0) + 1;
        } else if (percentage >= 20) {
          percentageDistribution['20-29'] = (percentageDistribution['20-29'] ?? 0) + 1;
        } else if (percentage >= 10) {
          percentageDistribution['10-19'] = (percentageDistribution['10-19'] ?? 0) + 1;
        } else {
          percentageDistribution['0-9'] = (percentageDistribution['0-9'] ?? 0) + 1;
        }
      }

      print('Step 3: Creating PDF document...');
      // إنشاء ملف PDF
      final pdf = pw.Document();
      
      // إعداد الخط العربي - استخدام خط Noto Sans Arabic TTF مع خط احتياطي للرموز
      print('Step 4: Loading Arabic font from assets...');
      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      // تحميل خط احتياطي للرموز الخاصة والرياضيات
      final symbolFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      print('Arabic font loaded successfully!');

      print('Step 5: Building PDF content...');
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // العنوان العلوي
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'تقرير امتحان',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'الفصل: ${widget.classModel.name}',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 14,
                              color: PdfColors.white,
                            ),
                          ),
                          pw.Text(
                            'الامتحان: ${exam.title}',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.grey300,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildSymbolText(
                      DateFormat('yyyy/MM/dd').format(exam.date),
                      arabicFont,
                      symbolFont,
                      fontSize: 12,
                      color: PdfColors.white,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // قسم الإحصائيات والرسم البياني
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // قائمة الإحصائيات على اليسار
                  pw.Expanded(
                    flex: 1,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'إحصائيات الامتحان',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 14,
                              color: PdfColors.blue800,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          _buildStatisticItem('متوسط الدرجات', '${averageScore.toStringAsFixed(1)}', arabicFont, PdfColors.green, symbolFont),
                          pw.SizedBox(height: 4),
                          _buildStatisticItem('عدد الطلاب الممتحنين', '$presentCount', arabicFont, PdfColors.blue, symbolFont),
                          pw.SizedBox(height: 4),
                          _buildStatisticItem('الطلاب الغائبين', '$absentCount', arabicFont, PdfColors.red, symbolFont),
                          pw.SizedBox(height: 4),
                          _buildStatisticItem('الأوراق المفقودة', '$missingCount', arabicFont, PdfColors.orange, symbolFont),
                          pw.SizedBox(height: 4),
                          _buildStatisticItem('الدرجة القصوى', '${exam.maxScore}', arabicFont, PdfColors.purple, symbolFont),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // رسم النسب المئوية على اليمين
                  pw.Expanded(
                    flex: 2,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.grey300),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'توزيع النسب المئوية',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 14,
                              color: PdfColors.blue800,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 8),
                          // رسم بياني بسيط للنسب
                          pw.Container(
                            height: 120,
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                              children: percentageDistribution.entries.map((entry) {
                                final count = entry.value;
                                final maxHeight = 100.0;
                                final height = count > 0 ? (count / scoredGrades.length) * maxHeight : 0.0;
                                
                                return pw.Column(
                                  mainAxisAlignment: pw.MainAxisAlignment.end,
                                  children: [
                                    pw.Container(
                                      width: 20,
                                      height: height,
                                      decoration: pw.BoxDecoration(
                                        color: _getPercentageColor(entry.key),
                                        borderRadius: pw.BorderRadius.circular(2),
                                      ),
                                    ),
                                    pw.SizedBox(height: 4),
                                    _buildSymbolText(
                                      entry.key,
                                      arabicFont,
                                      symbolFont,
                                      fontSize: 8,
                                      color: PdfColors.black,
                                    ),
                                    pw.Text(
                                      '$count',
                                      style: pw.TextStyle(
                                        font: arabicFont,
                                        fontSize: 8,
                                        color: PdfColors.black,
                                        fontWeight: pw.FontWeight.bold,
                                      ),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // الجدول الرئيسي
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3), // اسم الطالب
                  1: const pw.FlexColumnWidth(2), // رقم الطالب
                  2: const pw.FlexColumnWidth(1.5), // الدرجة
                  3: const pw.FlexColumnWidth(2), // الملاحظات
                },
                children: [
                  // عنوان الأعمدة
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue),
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'اسم الطالب',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'رقم الطالب',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'الدرجة',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'ملاحظات',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  // بيانات الطلاب
                  ...grades.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final grade = entry.value;
                    final student = _students.firstWhere(
                      (s) => s.id == grade.studentId,
                      orElse: () => StudentModel(
                        id: grade.studentId ?? 0,
                        name: 'طالب غير معروف',
                        classId: widget.classModel.id!,
                        studentId: 'غير معروف',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                    
                    // تحديد النص واللون للدرجة
                    String gradeText;
                    PdfColor gradeColor;
                    
                    if (grade.notes?.contains('غائب') ?? false) {
                      gradeText = 'غائب';
                      gradeColor = PdfColors.red;
                    } else if (grade.notes?.contains('غش') ?? false) {
                      gradeText = 'غش';
                      gradeColor = PdfColors.orange;
                    } else if (grade.notes?.contains('مفقودة') ?? false) {
                      gradeText = 'مفقودة';
                      gradeColor = PdfColors.purple;
                    } else {
                      // طالب حاضر، اعرض الدرجة
                      gradeText = '${grade.score}';
                      if (grade.score >= exam.maxScore * 0.8) {
                        gradeColor = PdfColors.green;
                      } else if (grade.score >= exam.maxScore * 0.6) {
                        gradeColor = PdfColors.blue;
                      } else {
                        gradeColor = PdfColors.red;
                      }
                    }
                    
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: index % 2 == 0 ? PdfColors.grey50 : PdfColors.white,
                      ),
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            student.name,
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 10,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            student.studentId ?? 'غير معروف',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 10,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            gradeText,
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 10,
                              color: gradeColor,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            grade.notes ?? '',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 9,
                              color: PdfColors.grey700,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ],
          ),
        ),
      );

      print('Step 6: Saving PDF file...');
      // إغلاق مؤشر التحميل
      Navigator.pop(context);
      
      // حفظ الملف وفتحه مباشرة
      final String fileName = 'تقرير_امتحان_${exam.title}_${DateFormat('yyyy_MM_dd').format(exam.date)}.pdf';
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      print('PDF saved to: ${file.path}');
      
      print('Step 7: Opening PDF for sharing...');
      // فتح الملف مباشرة
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: fileName,
      );

      print('Step 8: Showing success message...');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ تقرير الامتحان في: ${file.path}')),
      );
      print('✅ Exam report generated successfully!');
    } catch (e) {
      print('❌ Error in exam report: $e');
      print('Stack trace: ${StackTrace.current}');
      // إغلاق مؤشر التحميل إذا كان مفتوحاً
      try {
        Navigator.pop(context);
      } catch (_) {}
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    }
  }

  // دالة مساعدة للنصوص التي تحتوي على رموز
  pw.Widget _buildSymbolText(String text, pw.Font arabicFont, pw.Font symbolFont, {double fontSize = 12, PdfColor? color}) {
    // استبدال الرموز ببدائل نصية تدعمها الخطوط العربية
    String processedText = text
        .replaceAll('/', '-');  // استخدام شرطة عادية بدلاً من الشرطة المائلة
    
    // استخدام الخط العربي للنص المعالج
    return pw.Text(
      processedText,
      style: pw.TextStyle(
        font: arabicFont,
        fontSize: fontSize,
        color: color ?? PdfColors.black,
      ),
    );
  }

  // دالة مساعدة لبناء عنصر إحصائي
  pw.Widget _buildStatisticItem(String label, String value, pw.Font arabicFont, PdfColor color, pw.Font symbolFont) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            font: arabicFont,
            fontSize: 10,
            color: PdfColors.black,
          ),
        ),
        _buildSymbolText(
          value,
          arabicFont,
          symbolFont,
          fontSize: 10,
          color: color,
        ),
      ],
    );
  }

  // دالة مساعدة للحصول على لون النسبة المئوية
  PdfColor _getPercentageColor(String percentage) {
    switch (percentage) {
      case '100%':
        return PdfColors.green;
      case '90-99%':
        return PdfColors.lightGreen;
      case '80-89%':
        return PdfColors.lime;
      case '70-79%':
        return PdfColors.yellow;
      case '60-69%':
        return PdfColors.amber;
      case '50-59%':
        return PdfColors.orange;
      case '40-49%':
        return PdfColors.red;      // تغيير إلى أحمر (راسب)
      case '30-39%':
        return PdfColors.red;      // تغيير إلى أحمر (راسب)
      case '20-29%':
        return PdfColors.red;      // تغيير إلى أحمر (راسب)
      case '10-19%':
        return PdfColors.red;      // تغيير إلى أحمر (راسب)
      case '0-9%':
        return PdfColors.red;      // تغيير إلى أحمر (راسب)
      default:
        return PdfColors.grey;
    }
  }

  void _showAddExamDialog2() {
    showDialog(
      context: context,
      builder: (context) => _AddExamDialog(
        currentClass: widget.classModel,
        onSave: () {
          Navigator.pop(context);
          _loadGrades();
        },
      ),
    );
  }
}

class _AddExamDialog extends StatefulWidget {
  final ClassModel currentClass;
  final VoidCallback onSave;

  const _AddExamDialog({
    required this.currentClass,
    required this.onSave,
  });

  @override
  State<_AddExamDialog> createState() => _AddExamDialogState();
}

class _AddExamDialogState extends State<_AddExamDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _maxScoreController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  List<ClassModel> _selectedClasses = [];
  bool _isAllClasses = false;
  List<ClassModel> _availableClasses = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    try {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      
      // تحميل الفصول مباشرة من قاعدة البيانات
      await classProvider.loadClasses();
      
      print('📚 Loaded ${classProvider.classes.length} classes from provider');
      
      // إذا لم تحمل الفصول من Provider، حمل مباشرة من قاعدة البيانات
      if (classProvider.classes.isEmpty) {
        print('🔄 Provider empty, loading directly from database...');
        
        // استخدام DatabaseHelper مباشرة
        final dbHelper = DatabaseHelper();
        final allClasses = await dbHelper.getAllClasses();
        
        print('📚 Loaded ${allClasses.length} classes directly from database');
        
        if (mounted) {
          setState(() {
            _availableClasses = List.from(allClasses);
            
            // إذا لم توجد فصول حتى من قاعدة البيانات، أضف الفصل الحالي
            if (_availableClasses.isEmpty) {
              _availableClasses = [widget.currentClass];
            }
            
            _selectedClasses = [widget.currentClass];
            
            print('✅ Available classes: ${_availableClasses.length}');
            for (var cls in _availableClasses) {
              print('📋 Available class: ${cls.name} (ID: ${cls.id})');
            }
          });
        }
      } else {
        // استخدام الفصول من Provider
        if (mounted) {
          setState(() {
            _availableClasses = List.from(classProvider.classes);
            _selectedClasses = [widget.currentClass];
            
            print('✅ Available classes: ${_availableClasses.length}');
            for (var cls in _availableClasses) {
              print('📋 Available class: ${cls.name} (ID: ${cls.id})');
            }
          });
        }
      }
    } catch (e) {
      print('❌ Error loading classes: $e');
      if (mounted) {
        setState(() {
          _availableClasses = [widget.currentClass];
          _selectedClasses = [widget.currentClass];
        });
      }
    }
  }

  void _showClassSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحديد الفصول'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _availableClasses.length,
            itemBuilder: (context, index) {
              final classModel = _availableClasses[index];
              final isSelected = _selectedClasses.any((c) => c.id == classModel.id);
              
              return FutureBuilder<int>(
                future: _getStudentCount(classModel.id!),
                builder: (context, snapshot) {
                  final studentCount = snapshot.data ?? 0;
                  return CheckboxListTile(
                    title: Text(classModel.name),
                    subtitle: Text('${classModel.subject} - ${classModel.year}\n$studentCount طالب'),
                    isThreeLine: true,
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          if (!_selectedClasses.any((c) => c.id == classModel.id)) {
                            _selectedClasses.add(classModel);
                          }
                        } else {
                          _selectedClasses.removeWhere((c) => c.id == classModel.id);
                        }
                      });
                      Navigator.pop(context);
                      _showClassSelectionDialog();
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
            child: const Text('تم'),
          ),
        ],
      ),
    );
  }

  Future<int> _getStudentCount(int classId) async {
    try {
      final dbHelper = DatabaseHelper();
      final students = await dbHelper.getStudentsByClass(classId);
      return students.length;
    } catch (e) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة امتحان جديد'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الامتحان',
                    hintText: 'أدخل عنوان الامتحان',
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال عنوان الامتحان';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('تاريخ الامتحان'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (date != null) {
                      setState(() {
                        _selectedDate = date;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxScoreController,
                  decoration: const InputDecoration(
                    labelText: 'الدرجة القصوى',
                    hintText: 'أدخل الدرجة القصوى للامتحان',
                    prefixIcon: Icon(Icons.grade),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال الدرجة القصوى';
                    }
                    if (double.tryParse(value) == null || double.parse(value) <= 0) {
                      return 'يرجى إدخال رقم صحيح أكبر من صفر';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.class_, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    const Text(
                      'تحديد الفصول',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        title: const Text('كل الفصول'),
                        subtitle: const Text('إضافة هذا الامتحان لجميع الفصول'),
                        value: _isAllClasses,
                        onChanged: (value) {
                          setState(() {
                            _isAllClasses = value ?? false;
                            if (_isAllClasses) {
                              // تحديد جميع الفصول المتاحة
                              _selectedClasses = List.from(_availableClasses);
                              print('🔄 Selected all classes: ${_selectedClasses.length}');
                            } else {
                              // العودة للفصل الحالي فقط
                              _selectedClasses = [widget.currentClass];
                              print('🔄 Selected current class only');
                            }
                          });
                        },
                      ),
                      if (!_isAllClasses) ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.class_),
                          title: Text('الفصول المحددة (${_selectedClasses.length})'),
                          subtitle: Text(_selectedClasses.map((c) => c.name).join(', ')),
                          trailing: const Icon(Icons.edit),
                          onTap: () {
                            _showClassSelectionDialog();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () async {
            print('🔍 Form valid: ${_formKey.currentState!.validate()}');
            print('🔍 Selected classes: ${_selectedClasses.length}');
            print('🔍 Available classes: ${_availableClasses.length}');
            
            if (_formKey.currentState!.validate()) {
              // التأكد من وجود فصول محددة
              if (_selectedClasses.isEmpty && _availableClasses.isNotEmpty) {
                _selectedClasses = [widget.currentClass];
              }
              final examProvider = Provider.of<ExamProvider>(context, listen: false);
              
              bool allSuccess = true;
              
              for (final classModel in _selectedClasses) {
                final success = await examProvider.addExam(
                  title: _titleController.text,
                  date: _selectedDate,
                  maxScore: double.parse(_maxScoreController.text),
                  classId: classModel.id!,
                );
                
                if (!success) {
                  allSuccess = false;
                  break;
                }
              }
              
              if (allSuccess) {
                widget.onSave();
                Navigator.pop(context);
                
                final message = _isAllClasses 
                    ? 'تم إضافة الامتحان لجميع الفصول'
                    : 'تم إضافة الامتحان لـ ${_selectedClasses.length} فصل';
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(message)),
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
    );
  }
}

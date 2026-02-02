import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../providers/grade_provider.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../theme/app_theme.dart';
import '../../database/database_helper.dart';
import '../students/student_details_screen.dart';
import '../assignments/student_assignments_screen.dart';
import 'exam_statistics_screen.dart';
import 'package:intl/intl.dart';

enum ExamSortType { highestAverage, lowestAverage, name, gender }
enum GradeStatus { present, absent, cheating, missing }

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<StudentModel> _students = [];
  List<ExamModel> _exams = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  Map<int, bool> _atRiskStudents = {};

  @override
  void initState() {
    super.initState();
    _loadData();
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
    
    _loadGrades();
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
        
        if ((grade.notes ?? '').contains('غائب')) {
          _studentStatus[student.id!]![exam.id!] = GradeStatus.absent;
        } else if ((grade.notes ?? '').contains('غش')) {
          _studentStatus[student.id!]![exam.id!] = GradeStatus.cheating;
        } else if ((grade.notes ?? '').contains('مفقودة')) {
          _studentStatus[student.id!]![exam.id!] = GradeStatus.missing;
        } else {
          _studentStatus[student.id!]![exam.id!] = GradeStatus.present;
        }
      }
    }
    
    setState(() {});
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
            width: 140,
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
          if (comment?.isNotEmpty == true)
            Container(
              width: 140,
              height: 20,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withOpacity(0.5)),
              ),
              child: Text(
                comment!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (comment?.isEmpty != false)
            GestureDetector(
              onTap: () => _showGradeDialog(student, exam),
              child: Container(
                width: 140,
                height: 20,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey.shade600, width: 0.5),
                ),
                child: const Center(
                  child: Text(
                    'اكتب تعليق',
                    style: TextStyle(
                      fontSize: 8,
                      color: Colors.grey,
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
                    color: Colors.grey[100],
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
                  grade = double.parse(gradeController.text);
                }
                
                String notes = commentController.text;
                if (status == GradeStatus.absent) {
                  notes = 'غائب${notes.isNotEmpty ? ' - $notes' : ''}';
                } else if (status == GradeStatus.cheating) {
                  notes = 'غش${notes.isNotEmpty ? ' - $notes' : ''}';
                } else if (status == GradeStatus.missing) {
                  notes = 'مفقودة${notes.isNotEmpty ? ' - $notes' : ''}';
                }
                
                // التحقق من وجود درجة سابقة وتحديثها بدلاً من إضافة جديدة
                final existingGrades = await gradeProvider.getGradesByStudent(student.id!);
                final existingGrade = existingGrades.where((g) => g.examName == exam.title).firstOrNull;
                
                bool success;
                if (existingGrade != null) {
                  // تحديث الدرجة الموجودة - حذف القديمة وإضافة جديدة
                  await gradeProvider.deleteGrade(existingGrade.id!);
                  success = await gradeProvider.addGrade(
                    studentId: student.id!,
                    examName: exam.title,
                    score: grade,
                    maxScore: exam.maxScore,
                    examDate: exam.date,
                    notes: notes,
                  );
                } else {
                  // إضافة درجة جديدة
                  success = await gradeProvider.addGrade(
                    studentId: student.id!,
                    examName: exam.title,
                    score: grade,
                    maxScore: exam.maxScore,
                    examDate: exam.date,
                    notes: notes,
                  );
                }
                
                if (success) {
                  // إعادة تحميل الدرجات لضمان التحديث الصحيح
                  await _loadGrades();
                  
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('فشل في حفظ الدرجة'),
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
              ListTile(
                title: const Text('تاريخ الامتحان'),
                subtitle: Text(DateFormat('yyyy/MM/dd').format(selectedDate)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
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
                  setState(() {
                    _exams = examProvider.exams;
                  });
                  
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

  void _showExamOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات الامتحان: ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _deleteExam(exam);
              },
            ),
          ],
        ),
      ),
    );
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

  void _sortStudentsByExamGrade(ExamModel exam) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
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
                setState(() {
                  _exams = examProvider.exams;
                });
                
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

  double _calculateStudentAverage(int studentId) {
    if (!_studentGrades.containsKey(studentId)) return 0.0;
    
    double total = 0;
    int count = 0;
    
    for (final exam in _exams) {
      final grade = _studentGrades[studentId]?[exam.id!];
      if (grade != null) {
        total += (grade / exam.maxScore) * 100;
        count++;
      }
    }
    
    return count > 0 ? total / count : 0.0;
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

  bool _hasGoodPerformance(StudentModel student) {
    // التحقق من الأداء الممتاز (معدل 85% أو أعلى)
    final average = _calculateStudentAverage(student.id!);
    return average >= 85.0;
  }

  Widget _buildStudentStatusIndicator(StudentModel student) {
    // التحقق من وجود مشاكل في الحضور
    bool hasIssues = false;
    for (final exam in _exams) {
      final status = _studentStatus[student.id!]?[exam.id!];
      if (status == GradeStatus.absent || status == GradeStatus.missing) {
        hasIssues = true;
        break;
      }
    }

    // التحقق من الأداء الممتاز
    final average = _calculateStudentAverage(student.id!);
    bool hasGoodPerformance = average >= 85.0;

    if (hasIssues) {
      return Container(
        margin: const EdgeInsets.only(left: 4),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF2D2D2D),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 2,
              spreadRadius: 0.5,
            ),
          ],
        ),
      );
    } else if (hasGoodPerformance) {
      return Container(
        margin: const EdgeInsets.only(left: 4),
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: Colors.amber,
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF2D2D2D),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withOpacity(0.4),
              blurRadius: 2,
              spreadRadius: 0.5,
            ),
          ],
        ),
        child: const Icon(
          Icons.star,
          color: Colors.white,
          size: 6,
        ),
      );
    }

    return const SizedBox(width: 14); // مساحة فارغة للمحافظة على المحاذاة
  }

  Widget _buildStudentStats(int studentId) {
    final average = _calculateStudentAverage(studentId);
    final presentCount = _studentStatus[studentId]?.values.where((s) => s == GradeStatus.present).length ?? 0;
    final totalCount = _studentStatus[studentId]?.length ?? 0;
    final attendanceRate = totalCount > 0 ? (presentCount / totalCount * 100).round() : 0;

    return Row(
      children: [
        Text(
          'المعدل: ${average.toInt()}%',
          style: TextStyle(
            color: average >= 50 ? Colors.green[400] : Colors.red[400],
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'الحضور: $attendanceRate%',
          style: TextStyle(
            color: attendanceRate >= 80 ? Colors.green[400] : Colors.orange[400],
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final students = _sortStudents(_students);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              border: Border(bottom: BorderSide(color: Color(0xFF404040), width: 1)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'البحث عن طالب...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF404040)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF404040)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppTheme.primaryColor),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                PopupMenuButton<ExamSortType>(
                  icon: const Icon(Icons.sort, color: Colors.white),
                  onSelected: (value) {
                    setState(() {
                      _sortType = value;
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: ExamSortType.name, child: Text('ترتيب بالاسم')),
                    const PopupMenuItem(value: ExamSortType.highestAverage, child: Text('الأعلى معدلاً')),
                    const PopupMenuItem(value: ExamSortType.lowestAverage, child: Text('الأقل معدلاً')),
                  ],
                ),
              ],
            ),
          ),

          // Exam Headers
          if (_exams.isNotEmpty)
            Container(
              height: 140,
              decoration: const BoxDecoration(
                color: Color(0xFF1A1A1A),
                border: Border(bottom: BorderSide(color: Color(0xFF404040), width: 1)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(width: 150),
                    ..._exams.asMap().entries.map((entry) {
                      final exam = entry.value;
                      final index = entry.key;
                      
                      return Container(
                        width: 140,
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF404040), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              exam.title,
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('dd/MM').format(exam.date),
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'امتحان ${index + 1}',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'الدرجة: ${exam.maxScore.toInt()}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            ),

          // Students List
          if (students.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.school,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا يوجد طلاب في هذا الفصل',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: students.length,
                itemBuilder: (context, index) {
                  final student = students[index];
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        // Student Info Section
                        Container(
                          width: 150,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  // دائرة الحرف الأول
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.3),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.blue, width: 1),
                                    ),
                                    child: Center(
                                      child: Text(
                                        student.name.isNotEmpty ? student.name[0].toUpperCase() : '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // اسم الطالب والمعلومات
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
                                      child: Row(
                                        children: [
                                          // الأيقونة الصفراء (التحذيرية) - بجانب الاسم
                                          if (student.notes?.toLowerCase().contains('مخالفة') == true || 
                                              student.notes?.toLowerCase().contains('تحذير') == true)
                                            Container(
                                              margin: const EdgeInsets.only(left: 4, right: 6),
                                              width: 8,
                                              height: 8,
                                              decoration: const BoxDecoration(
                                                color: Colors.yellow,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          // النجمة أو النقطة الحمراء للطالب
                                          _buildStudentStatusIndicator(student),
                                          const SizedBox(width: 8),
                                          // اسم الطالب في سطر واحد
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  student.name.isNotEmpty ? student.name : 'اسم غير محدد',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                // إحصائيات الطالب تحت الاسم
                                                _buildStudentStats(student.id!),
                                                // أيقونة الواجبات تحت الإحصائيات وقريب من الخط الفاصل
                                                GestureDetector(
                                                  onTap: () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) => StudentAssignmentsScreen(
                                                          student: student,
                                                          classModel: widget.classModel,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  child: Container(
                                                    padding: const EdgeInsets.all(4),
                                                    margin: const EdgeInsets.only(top: 9, right: 0),
                                                    decoration: BoxDecoration(
                                                      color: Colors.yellow,
                                                      borderRadius: BorderRadius.circular(4),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.yellow.withOpacity(0.3),
                                                          blurRadius: 4,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: const Icon(
                                                      Icons.assignment,
                                                      size: 16,
                                                      color: Colors.black,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // الخط الفاصل
                        Container(
                          width: 3,
                          height: 80,
                          color: const Color(0xFF404040),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                        ),

                        // Grade Boxes
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _exams.map((exam) {
                                return Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  child: _buildGradeBox(student, exam),
                                );
                              }).toList(),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddExamDialog,
        backgroundColor: AppTheme.primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }
}

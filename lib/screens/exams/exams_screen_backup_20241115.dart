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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didUpdateWidget(ExamsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعادة تحميل البيانات عند تغيير الفصل
    if (oldWidget.classModel.id != widget.classModel.id) {
      _loadData();
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
          
          if (grade.score == 0 && grade.notes?.contains('غائب') == true) {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.absent;
          } else if (grade.score == 0 && grade.notes?.contains('غش') == true) {
            _studentStatus[student.id!]![exam.id!] = GradeStatus.cheating;
          } else if (grade.score == 0 && grade.notes?.contains('مفقودة') == true) {
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
                
                final success = await gradeProvider.addGrade(
                  studentId: student.id!,
                  examName: exam.title,
                  score: grade,
                  maxScore: exam.maxScore,
                  examDate: exam.date,
                  notes: notes,
                );
                
                if (success) {
                  setState(() {
                    if (!_studentGrades.containsKey(student.id)) {
                      _studentGrades[student.id!] = {};
                      _studentStatus[student.id!] = {};
                      _studentComments[student.id!] = {};
                    }
                    _studentGrades[student.id!]![exam.id!] = grade;
                    _studentStatus[student.id!]![exam.id!] = status;
                    _studentComments[student.id!]![exam.id!] = commentController.text;
                  });
                  
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم حفظ درجة ${student.name}')),
                  );
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
                    if (_exams.isNotEmpty)
                      Container(
                        color: const Color(0xFF2D2D2D),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
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
                            Container(
                              width: 3,
                              height: 80,
                              color: const Color(0xFF404040),
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _exams.asMap().entries.map((entry) {
                                    final exam = entry.value;
                                    final examNumber = entry.key + 1;
                                    return Container(
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
                                              fontSize: 11,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          GestureDetector(
                                            onTap: () => _showExamOptions(exam),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withOpacity(0.2),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.blue, width: 0.5),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM/yyyy').format(exam.date),
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'امتحان #$examNumber',
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.white70,
                                              fontWeight: FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // خط فاصل بين header والطلاب
                      Container(
                        height: 1,
                        color: Colors.black.withOpacity(0.3),
                      ),

                    Expanded(
                      child: ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final studentAverage = _calculateStudentAverage(student.id!);
                          
                          return Column(
                            children: [
                              Container(
                                color: const Color(0xFF2D2D2D),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 150,
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            student.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'المعدل: ${studentAverage.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              color: studentAverage >= 50 ? Colors.green[400] : Colors.red[400],
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
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
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          children: _exams.map((exam) {
                                            return Container(
                                              width: 140,
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
                                  height: 1,
                                  color: Colors.grey.shade600,
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
              title: const Text('أعلى الدرجات'),
              onTap: () {
                Navigator.pop(context);
                _showTopGradesOptions(exam);
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
      
      await gradeProvider.addGrade(
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

  void _showExamReport(ExamModel exam) {
    // سيتم تنفيذها لاحقاً
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ميزة التقرير قيد التطوير')),
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

  @override
  void dispose() {
    _titleController.dispose();
    _maxScoreController.dispose();
    super.dispose();
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

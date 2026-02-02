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
import 'package:intl/intl.dart';

enum ExamSortType { highestAverage, lowestAverage, name, gender }
enum GradeStatus { present, absent, cheating }

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
    
    final grades = _studentGrades[studentId]!.values.toList();
    final sum = grades.reduce((a, b) => a + b);
    return sum / grades.length;
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
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة امتحان جديد'),
          content: SingleChildScrollView(
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
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('تاريخ الامتحان'),
                  subtitle: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
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
                    const PopupMenuItem(
                      value: ExamSortType.name,
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha),
                          SizedBox(width: 8),
                          Text('الاسم'),
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
                                          Container(
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
                                          const SizedBox(height: 2),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.amber, width: 0.5),
                                            ),
                                            child: Text(
                                              'امتحان #$examNumber',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.amber,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            'من ${exam.maxScore.toInt()}',
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.white60,
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

                    Expanded(
                      child: ListView.builder(
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          final student = students[index];
                          final studentAverage = _calculateStudentAverage(student.id!);
                          
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(8),
                            ),
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
                                        'المعدل: ${studentAverage.toInt()}',
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
        backgroundColor: Colors.yellow[600],
        child: const Icon(
          Icons.add,
          color: Colors.black,
          size: 28,
        ),
        tooltip: 'إضافة امتحان',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

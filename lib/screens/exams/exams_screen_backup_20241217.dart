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
import '../students/student_assignments_screen.dart';
import 'exam_statistics_screen.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/unified_student_status_service.dart';

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
  Map<int, bool> _excellentStudents = {};

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
    
    if (mounted) {
      setState(() {
        _students = studentProvider.students;
        _exams = examProvider.exams;
      });
    }
    
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
                title: Text('تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
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
                
                final success = await examProvider.addExam(
                  title: titleController.text,
                  date: selectedDate,
                  maxScore: double.parse(maxScoreController.text),
                  classId: widget.classModel.id!,
                );
                
                if (success) {
                  if (mounted) {
                    setState(() {
                      _exams = examProvider.exams;
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
                ListTile(
                  title: Text('تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                  trailing: const Icon(Icons.calendar_today),
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
                      _exams = examProvider.exams;
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
                      _exams = examProvider.exams;
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
                    _exams = examProvider.exams;
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
                    _exams = examProvider.exams;
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
      String notes = '';
      if (status == GradeStatus.absent) {
        notes = 'غائب';
      } else if (status == GradeStatus.cheating) {
        notes = 'غش';
      } else if (status == GradeStatus.missing) {
        notes = 'مفقودة';
      }
      
      // التحقق من وجود درجة سابقة وتحديثها
      final existingGrades = await gradeProvider.getGradesByStudent(student.id!);
      final existingGrade = existingGrades.where((g) => g.examName == exam.title).firstOrNull;
      
      if (existingGrade != null) {
        await gradeProvider.deleteGrade(existingGrade.id!);
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
        content: ListTile(
          title: Text('تاريخ الامتحان: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
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
              selectedDate = date;
            }
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
                    _exams = examProvider.exams;
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
                    _exams = examProvider.exams;
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

  Future<Map<String, bool>> _checkStudentStatus(StudentModel student) async {
    final status = await UnifiedStudentStatusService.checkStudentStatus(student);
    return {
      'isExcellent': status['isExcellent'] ?? false,
      'isAtRisk': status['isAtRisk'] ?? false,
    };
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
    return FutureBuilder<Map<String, bool>>(
      future: _checkStudentStatus(student),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 20, height: 20);
        }
        
        final isExcellent = snapshot.data?['isExcellent'] ?? false;
        final isAtRisk = snapshot.data?['isAtRisk'] ?? false;
        
        if (isExcellent) {
          // نجمة صفراء مصغرة مع تأثيرات بصرية
          return Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Colors.yellow.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.yellow.withOpacity(0.3),
                  blurRadius: 3,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: const Icon(
              Icons.star,
              color: Colors.yellow,
              size: 15,
              shadows: [
                Shadow(
                  color: Colors.orange,
                  blurRadius: 1,
                  offset: Offset(0.5, 0.5),
                ),
              ],
            ),
          );
        } else if (isAtRisk) {
          // نقطة حمراء مصغرة مع تأثيرات بصرية
          return Container(
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 2,
                  spreadRadius: 0.5,
                ),
              ],
            ),
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          );
        } else {
          return const SizedBox(width: 20, height: 20);
        }
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
                // أيقونة التصنيف
                PopupMenuButton<ExamSortType>(
                  icon: const Icon(Icons.sort, color: Colors.white, size: 20),
                  tooltip: 'تصنيف',
                  onSelected: (ExamSortType sortType) {
                    setState(() {
                      _sortType = sortType;
                    });
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem(
                      value: ExamSortType.name,
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha, color: Colors.white),
                          SizedBox(width: 8),
                          Text('اسم الطالب'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ExamSortType.highestAverage,
                      child: Row(
                        children: [
                          Icon(Icons.trending_up, color: Colors.green),
                          SizedBox(width: 8),
                          Text('أعلى معدل'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ExamSortType.lowestAverage,
                      child: Row(
                        children: [
                          Icon(Icons.trending_down, color: Colors.red),
                          SizedBox(width: 8),
                          Text('أقل معدل'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: ExamSortType.gender,
                      child: Row(
                        children: [
                          Icon(Icons.people, color: Colors.blue),
                          SizedBox(width: 8),
                          Text('الجنس'),
                        ],
                      ),
                    ),
                  ],
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
                        color: const Color(0xFF2D2D2D), // رمادي داكن
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 200, // نفس العرض الجديد لمعلومات الطالب
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
                            // العناوين والتواريخ
                            Expanded(
                              child: SingleChildScrollView(
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
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 200,
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: [
                                          // دائرة الطالب
                                          CircleAvatar(
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
                                                      fontSize: 18,
                                                    ),
                                                  ) 
                                                : null,
                                          ),
                                          const SizedBox(width: 12),
                                          // النجمة أو النقطة الحمراء للطالب
                                          _buildStudentStatusIndicator(student),
                                          const SizedBox(width: 8),
                                          // اسم الطالب
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
                                              child: Text(
                                                student.name,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 14,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                textAlign: TextAlign.right,
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
                                          const SizedBox(width: 8),
                                          // أيقونة الواجبات أمام المعدل
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
                                              decoration: BoxDecoration(
                                                color: Colors.yellow,
                                                borderRadius: BorderRadius.circular(4),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.yellow.withOpacity(0.3),
                                                    blurRadius: 2,
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
        onPressed: _showAddExamOptions,
        backgroundColor: const Color(0xFFFFD700), // لون أصفر مثل الثيم
        foregroundColor: Colors.black,
        elevation: 8,
        child: const Icon(Icons.add, size: 24),
        tooltip: 'إضافة امتحان',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

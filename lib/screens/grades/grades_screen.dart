import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/grade_provider.dart';
import '../../providers/student_provider.dart';
import '../../theme/app_theme.dart';

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الدرجات'),
      ),
      body: Consumer<StudentProvider>(
        builder: (context, studentProvider, child) {
          if (studentProvider.students.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.grade,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد طلاب',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'قم بإضافة طلاب أولاً لإدارة درجاتهم',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: studentProvider.students.length,
            itemBuilder: (context, index) {
              final student = studentProvider.students[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryColor,
                    child: Text(
                      student.name[0],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(student.name),
                  subtitle: const Text('اضغط لإدارة الدرجات'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => StudentGradesScreen(student: student),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class StudentGradesScreen extends StatelessWidget {
  final dynamic student;

  const StudentGradesScreen({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('درجات ${student.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              _showAddGradeDialog(context);
            },
          ),
        ],
      ),
      body: Consumer<GradeProvider>(
        builder: (context, gradeProvider, child) {
          // Load grades for this student
          if (gradeProvider.currentStudentId != student.id) {
            gradeProvider.loadGradesByStudent(student.id);
          }

          if (gradeProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (gradeProvider.grades.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.grade,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد درجات',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اضغط على + لإضافة درجة جديدة',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: gradeProvider.grades.length,
            itemBuilder: (context, index) {
              final grade = gradeProvider.grades[index];
              return Card(
                child: ListTile(
                  title: Text(grade.examName),
                  subtitle: Text(
                    '${grade.examDate.day}/${grade.examDate.month}/${grade.examDate.year}',
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${grade.score.toInt()}/${grade.maxScore.toInt()}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${grade.percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: _getGradeColor(grade.percentage),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getGradeColor(double percentage) {
    if (percentage >= 90) return AppTheme.successColor;
    if (percentage >= 70) return Colors.blue;
    if (percentage >= 60) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  void _showAddGradeDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final examNameController = TextEditingController();
    final scoreController = TextEditingController();
    final maxScoreController = TextEditingController(text: '100');
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة درجة جديدة'),
        content: SizedBox(
          width: double.maxFinite,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: examNameController,
                    decoration: const InputDecoration(
                      labelText: 'اسم الاختبار',
                      hintText: 'مثال: اختبار الفصل الأول',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال اسم الاختبار';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: scoreController,
                    decoration: const InputDecoration(
                      labelText: 'الدرجة المحصلة',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال الدرجة';
                      }
                      final score = double.tryParse(value);
                      if (score == null) {
                        return 'الرجاء إدخال رقم صحيح';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: maxScoreController,
                    decoration: const InputDecoration(
                      labelText: 'الدرجة الكاملة',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'الرجاء إدخال الدرجة الكاملة';
                      }
                      final maxScore = double.tryParse(value);
                      if (maxScore == null || maxScore <= 0) {
                        return 'الرجاء إدخال رقم صحيح أكبر من صفر';
                      }
                      return null;
                    },
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
              if (formKey.currentState!.validate()) {
                final gradeProvider = Provider.of<GradeProvider>(context, listen: false);
                final success = await gradeProvider.addGrade(
                  studentId: student.id,
                  examName: examNameController.text.trim(),
                  score: double.parse(scoreController.text.trim()),
                  maxScore: double.parse(maxScoreController.text.trim()),
                  examDate: selectedDate,
                );

                if (success && context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم إضافة الدرجة بنجاح')),
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
}

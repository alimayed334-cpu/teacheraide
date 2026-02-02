import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../models/hive_exam.dart';
import '../models/hive_student.dart';
import '../services/hive_service.dart';

class HiveExamsScreen extends StatefulWidget {
  const HiveExamsScreen({super.key});

  @override
  State<HiveExamsScreen> createState() => _HiveExamsScreenState();
}

class _HiveExamsScreenState extends State<HiveExamsScreen> {
  String? _selectedSubject;
  String? _selectedStudentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الامتحانات - Hive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'تصفية',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط الفلاتر النشطة
          if (_selectedSubject != null || _selectedStudentId != null)
            Container(
              padding: const EdgeInsets.all(8),
              color: Colors.blue.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Text('الفلاتر النشطة: '),
                  if (_selectedSubject != null)
                    Chip(
                      label: Text(_selectedSubject!),
                      onDeleted: () => setState(() => _selectedSubject = null),
                    ),
                  if (_selectedStudentId != null)
                    Chip(
                      label: Text(_getStudentName(_selectedStudentId!)),
                      onDeleted: () => setState(() => _selectedStudentId = null),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _selectedSubject = null;
                      _selectedStudentId = null;
                    }),
                    child: const Text('مسح الكل'),
                  ),
                ],
              ),
            ),
          
          // قائمة الامتحانات
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: HiveService.examsBox.listenable(),
              builder: (context, Box<HiveExam> box, _) {
                List<HiveExam> exams = _getFilteredExams();

                if (exams.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.assignment_outlined,
                          size: 80,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedSubject != null || _selectedStudentId != null
                              ? 'لا توجد امتحانات تطابق الفلاتر'
                              : 'لا توجد امتحانات',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // تجميع الامتحانات حسب المادة
                final examsBySubject = <String, List<HiveExam>>{};
                for (var exam in exams) {
                  examsBySubject.putIfAbsent(exam.subject, () => []).add(exam);
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: examsBySubject.length,
                  itemBuilder: (context, index) {
                    final subject = examsBySubject.keys.elementAt(index);
                    final subjectExams = examsBySubject[subject]!;
                    
                    // حساب معدل المادة
                    double totalPercentage = 0;
                    for (var exam in subjectExams) {
                      totalPercentage += exam.percentage;
                    }
                    final average = totalPercentage / subjectExams.length;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: average >= 50 ? Colors.green : Colors.red,
                          child: Text(
                            '${average.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        title: Text(
                          subject,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('${subjectExams.length} امتحان'),
                        children: subjectExams.map((exam) {
                          return _buildExamListTile(exam);
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<HiveExam> _getFilteredExams() {
    List<HiveExam> exams = HiveService.getAllExams();

    if (_selectedSubject != null) {
      exams = exams.where((exam) => exam.subject == _selectedSubject).toList();
    }

    if (_selectedStudentId != null) {
      exams = exams.where((exam) => exam.studentId == _selectedStudentId).toList();
    }

    exams.sort((a, b) => b.date.compareTo(a.date));
    return exams;
  }

  Widget _buildExamListTile(HiveExam exam) {
    final student = HiveService.getStudent(exam.studentId);
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: exam.isPassed ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
        child: Icon(
          exam.isPassed ? Icons.check : Icons.close,
          color: exam.isPassed ? Colors.green : Colors.red,
        ),
      ),
      title: Text(student?.name ?? 'طالب محذوف'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('الدرجة: ${exam.score}/${exam.maxScore} (${exam.percentage.toStringAsFixed(1)}%)'),
          Text('التقدير: ${exam.grade}'),
          Text('التاريخ: ${dateFormat.format(exam.date)}'),
          if (exam.examType != null) Text('النوع: ${exam.examType}'),
        ],
      ),
      trailing: Text(
        '${exam.percentage.toStringAsFixed(0)}%',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: exam.isPassed ? Colors.green : Colors.red,
        ),
      ),
      onTap: () {
        if (student != null) {
          _showExamDetails(exam, student);
        }
      },
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final subjects = _getAllSubjects();
          final students = HiveService.getAllStudents();

          return AlertDialog(
            title: const Text('تصفية الامتحانات'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'المادة:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSubject,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'اختر المادة',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ...subjects.map((subject) {
                        return DropdownMenuItem(value: subject, child: Text(subject));
                      }),
                    ],
                    onChanged: (value) {
                      setDialogState(() => _selectedSubject = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'الطالب:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStudentId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'اختر الطالب',
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('الكل')),
                      ...students.map((student) {
                        return DropdownMenuItem(
                          value: student.id,
                          child: Text(student.name),
                        );
                      }),
                    ],
                    onChanged: (value) {
                      setDialogState(() => _selectedStudentId = value);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedSubject = null;
                    _selectedStudentId = null;
                  });
                  Navigator.pop(context);
                },
                child: const Text('مسح الفلاتر'),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                },
                child: const Text('تطبيق'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showExamDetails(HiveExam exam, HiveStudent student) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(exam.subject),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('الطالب', student.name),
              _buildDetailRow('الدرجة', '${exam.score}/${exam.maxScore}'),
              _buildDetailRow('النسبة المئوية', '${exam.percentage.toStringAsFixed(1)}%'),
              _buildDetailRow('التقدير', exam.grade),
              _buildDetailRow('الحالة', exam.isPassed ? 'ناجح ✓' : 'راسب ✗'),
              _buildDetailRow('التاريخ', dateFormat.format(exam.date)),
              if (exam.examType != null)
                _buildDetailRow('نوع الامتحان', exam.examType!),
              if (exam.notes != null && exam.notes!.isNotEmpty)
                _buildDetailRow('ملاحظات', exam.notes!),
            ],
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  List<String> _getAllSubjects() {
    final exams = HiveService.getAllExams();
    final subjects = <String>{};
    for (var exam in exams) {
      subjects.add(exam.subject);
    }
    return subjects.toList()..sort();
  }

  String _getStudentName(String studentId) {
    final student = HiveService.getStudent(studentId);
    return student?.name ?? 'غير معروف';
  }
}

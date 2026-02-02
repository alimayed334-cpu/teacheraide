import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/hive_student.dart';
import '../models/hive_exam.dart';
import '../services/hive_service.dart';

class HiveStudentDetailsScreen extends StatefulWidget {
  final String studentId;

  const HiveStudentDetailsScreen({
    super.key,
    required this.studentId,
  });

  @override
  State<HiveStudentDetailsScreen> createState() => _HiveStudentDetailsScreenState();
}

class _HiveStudentDetailsScreenState extends State<HiveStudentDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: HiveService.studentsBox.listenable(),
      builder: (context, Box<HiveStudent> box, _) {
        final student = HiveService.getStudent(widget.studentId);

        if (student == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('تفاصيل الطالب')),
            body: const Center(child: Text('الطالب غير موجود')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(student.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () => _showAddExamDialog(student),
                tooltip: 'إضافة امتحان',
              ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // معلومات الطالب
                _buildStudentInfoCard(student),
                
                // الإحصائيات
                _buildStatisticsCard(student),
                
                // قائمة الامتحانات
                _buildExamsSection(student),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentInfoCard(HiveStudent student) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: Theme.of(context).primaryColor,
                  child: Text(
                    student.name.isNotEmpty ? student.name[0] : '؟',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'الصف: ${student.grade}',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.cake, 'العمر', '${student.age} سنة'),
            if (student.phoneNumber != null)
              _buildInfoRow(Icons.phone, 'الهاتف', student.phoneNumber!),
            if (student.parentPhone != null)
              _buildInfoRow(Icons.contact_phone, 'هاتف ولي الأمر', student.parentPhone!),
            if (student.address != null)
              _buildInfoRow(Icons.location_on, 'العنوان', student.address!),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsCard(HiveStudent student) {
    final examsCount = HiveService.getStudentExamsCount(student.id);
    final average = HiveService.getStudentAverage(student.id);
    final exams = HiveService.getExamsByStudentId(student.id);
    
    // حساب عدد الامتحانات الناجحة والراسبة
    int passedCount = 0;
    int failedCount = 0;
    for (var exam in exams) {
      if (exam.isPassed) {
        passedCount++;
      } else {
        failedCount++;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 الإحصائيات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('الامتحانات', examsCount.toString(), Colors.blue),
                _buildStatColumn('المعدل', '${average.toStringAsFixed(1)}%', 
                  average >= 50 ? Colors.green : Colors.red),
                _buildStatColumn('نجح', passedCount.toString(), Colors.green),
                _buildStatColumn('رسب', failedCount.toString(), Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildExamsSection(HiveStudent student) {
    return ValueListenableBuilder(
      valueListenable: HiveService.examsBox.listenable(),
      builder: (context, Box<HiveExam> box, _) {
        final exams = HiveService.getExamsByStudentId(student.id);

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '📝 الامتحانات',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    onPressed: () => _showAddExamDialog(student),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (exams.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'لا توجد امتحانات\nاضغط + لإضافة امتحان',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: exams.length,
                  itemBuilder: (context, index) {
                    final exam = exams[index];
                    return _buildExamCard(exam, student);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExamCard(HiveExam exam, HiveStudent student) {
    final dateFormat = DateFormat('yyyy/MM/dd', 'ar');
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: exam.isPassed ? Colors.green : Colors.red,
          child: Text(
            '${exam.percentage.toStringAsFixed(0)}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(
          exam.subject,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الدرجة: ${exam.score}/${exam.maxScore}'),
            Text('التقدير: ${exam.grade}'),
            Text('التاريخ: ${dateFormat.format(exam.date)}'),
            if (exam.examType != null) Text('النوع: ${exam.examType}'),
            if (exam.notes != null && exam.notes!.isNotEmpty)
              Text('ملاحظات: ${exam.notes}', 
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit),
                  SizedBox(width: 8),
                  Text('تعديل'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  SizedBox(width: 8),
                  Text('حذف', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              _showAddExamDialog(student, exam: exam);
            } else if (value == 'delete') {
              _confirmDeleteExam(exam);
            }
          },
        ),
      ),
    );
  }

  void _showAddExamDialog(HiveStudent student, {HiveExam? exam}) {
    final isEdit = exam != null;
    final subjectController = TextEditingController(text: exam?.subject ?? '');
    final scoreController = TextEditingController(text: exam?.score.toString() ?? '');
    final maxScoreController = TextEditingController(text: exam?.maxScore.toString() ?? '100');
    final notesController = TextEditingController(text: exam?.notes ?? '');
    DateTime selectedDate = exam?.date ?? DateTime.now();
    String? selectedExamType = exam?.examType;

    final examTypes = ['شهري', 'نصفي', 'نهائي', 'مفاجئ', 'أخرى'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'تعديل امتحان' : 'إضافة امتحان جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(
                    labelText: 'المادة *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: scoreController,
                        decoration: const InputDecoration(
                          labelText: 'الدرجة *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: maxScoreController,
                        decoration: const InputDecoration(
                          labelText: 'من *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedExamType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الامتحان',
                    border: OutlineInputBorder(),
                  ),
                  items: examTypes.map((type) {
                    return DropdownMenuItem(value: type, child: Text(type));
                  }).toList(),
                  onChanged: (value) {
                    setDialogState(() => selectedExamType = value);
                  },
                ),
                const SizedBox(height: 12),
                ListTile(
                  title: const Text('تاريخ الامتحان'),
                  subtitle: Text(DateFormat('yyyy/MM/dd').format(selectedDate)),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
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
                if (subjectController.text.isEmpty ||
                    scoreController.text.isEmpty ||
                    maxScoreController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء الحقول المطلوبة')),
                  );
                  return;
                }

                final newExam = HiveExam(
                  id: exam?.id ?? const Uuid().v4(),
                  studentId: student.id,
                  subject: subjectController.text,
                  score: double.parse(scoreController.text),
                  maxScore: double.parse(maxScoreController.text),
                  date: selectedDate,
                  examType: selectedExamType,
                  notes: notesController.text.isEmpty ? null : notesController.text,
                  createdAt: exam?.createdAt ?? DateTime.now(),
                  updatedAt: isEdit ? DateTime.now() : null,
                );

                if (isEdit) {
                  await HiveService.updateExam(newExam);
                } else {
                  await HiveService.addExam(newExam);
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? 'تم تحديث الامتحان بنجاح' : 'تم إضافة الامتحان بنجاح'),
                    ),
                  );
                }
              },
              child: Text(isEdit ? 'تحديث' : 'حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteExam(HiveExam exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف امتحان "${exam.subject}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await HiveService.deleteExam(exam.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الامتحان بنجاح')),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

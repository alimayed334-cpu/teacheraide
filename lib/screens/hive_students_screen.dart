import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import '../models/hive_student.dart';
import '../services/hive_service.dart';
import 'hive_student_details_screen.dart';

class HiveStudentsScreen extends StatefulWidget {
  const HiveStudentsScreen({super.key});

  @override
  State<HiveStudentsScreen> createState() => _HiveStudentsScreenState();
}

class _HiveStudentsScreenState extends State<HiveStudentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الطلاب - Hive'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _exportStudentsJson,
            tooltip: 'تصدير الطلاب (JSON)',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: _showStatistics,
            tooltip: 'الإحصائيات',
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'ابحث عن طالب...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          
          // قائمة الطلاب
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: HiveService.studentsBox.listenable(),
              builder: (context, Box<HiveStudent> box, _) {
                List<HiveStudent> students = _searchQuery.isEmpty
                    ? box.values.toList()
                    : HiveService.searchStudents(_searchQuery);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty ? Icons.person_add : Icons.search_off,
                          size: 80,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'لا يوجد طلاب\nاضغط + لإضافة طالب جديد'
                              : 'لا توجد نتائج للبحث',
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

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    final examsCount = HiveService.getStudentExamsCount(student.id);
                    final average = HiveService.getStudentAverage(student.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            student.name.isNotEmpty ? student.name[0] : '؟',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          student.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('العمر: ${student.age} | الصف: ${student.grade}'),
                            if (examsCount > 0)
                              Text(
                                'الامتحانات: $examsCount | المعدل: ${average.toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: average >= 50 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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
                              _showAddEditDialog(student: student);
                            } else if (value == 'delete') {
                              _confirmDelete(student);
                            }
                          },
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => HiveStudentDetailsScreen(
                                studentId: student.id,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة طالب'),
      ),
    );
  }

  void _showAddEditDialog({HiveStudent? student}) {
    final isEdit = student != null;
    final nameController = TextEditingController(text: student?.name ?? '');
    final ageController = TextEditingController(text: student?.age.toString() ?? '');
    final gradeController = TextEditingController(text: student?.grade ?? '');
    final phoneController = TextEditingController(text: student?.phoneNumber ?? '');
    final parentPhoneController = TextEditingController(text: student?.parentPhone ?? '');
    final addressController = TextEditingController(text: student?.address ?? '');
    String selectedRole = student != null ? 'student' : 'student'; // default to student

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? 'تعديل طالب' : 'إضافة شخص جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'النوع *',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text('طالب')),
                    DropdownMenuItem(value: 'parent', child: Text('ولي أمر')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => selectedRole = value);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'الاسم *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (selectedRole == 'student') ...[
                  TextField(
                    controller: ageController,
                    decoration: const InputDecoration(
                      labelText: 'العمر *',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: gradeController,
                    decoration: const InputDecoration(
                      labelText: 'الصف *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف *',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                if (selectedRole == 'student')
                  TextField(
                    controller: parentPhoneController,
                    decoration: const InputDecoration(
                      labelText: 'هاتف ولي الأمر',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'العنوان',
                    border: OutlineInputBorder(),
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
                if (nameController.text.isEmpty ||
                    phoneController.text.isEmpty ||
                    (selectedRole == 'student' && (ageController.text.isEmpty || gradeController.text.isEmpty))) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى ملء الحقول المطلوبة')),
                  );
                  return;
                }

                final personId = student?.id ?? const Uuid().v4();

                // If student, also save to Hive
                if (selectedRole == 'student') {
                  final newStudent = HiveStudent(
                    id: personId,
                    name: nameController.text,
                    age: int.parse(ageController.text),
                    grade: gradeController.text,
                    phoneNumber: phoneController.text.isEmpty ? null : phoneController.text,
                    parentPhone: parentPhoneController.text.isEmpty ? null : parentPhoneController.text,
                    address: addressController.text.isEmpty ? null : addressController.text,
                    createdAt: student?.createdAt ?? DateTime.now(),
                    updatedAt: isEdit ? DateTime.now() : null,
                    examIds: student?.examIds ?? [],
                  );

                  if (isEdit) {
                    await HiveService.updateStudent(newStudent);
                  } else {
                    await HiveService.addStudent(newStudent);
                  }
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEdit ? 'تم تحديث البيانات بنجاح' : 'تمت الإضافة بنجاح'),
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

  void _confirmDelete(HiveStudent student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الطالب "${student.name}"؟\nسيتم حذف جميع امتحاناته أيضاً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await HiveService.deleteStudent(student.id);
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حذف الطالب بنجاح')),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  void _showStatistics() {
    final studentsCount = HiveService.getStudentsCount();
    final examsCount = HiveService.getExamsCount();
    final topStudents = HiveService.getTopStudents(limit: 5);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 الإحصائيات'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatItem('عدد الطلاب', studentsCount.toString()),
              _buildStatItem('عدد الامتحانات', examsCount.toString()),
              const Divider(height: 24),
              const Text(
                '🏆 أفضل 5 طلاب:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (topStudents.isEmpty)
                const Text('لا توجد بيانات كافية')
              else
                ...topStudents.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final student = data['student'] as HiveStudent;
                  final average = data['average'] as double;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text('${index + 1}'),
                    ),
                    title: Text(student.name),
                    trailing: Text(
                      '${average.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  );
                }),
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

  Widget _buildStatItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportStudentsJson() async {
    try {
      final students = HiveService.getAllStudents();
      final payload = {
        'exportedAt': DateTime.now().toIso8601String(),
        'count': students.length,
        'students': students.map((s) => s.toMap()).toList(),
      };

      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'students_export.json';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(jsonEncode(payload), encoding: utf8);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم تصدير ${students.length} طالب إلى: ${file.path}')),
      );

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'ملف تصدير الطلاب',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل تصدير الطلاب: $e')),
      );
    }
  }
}

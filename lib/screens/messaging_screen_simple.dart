import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/student_model.dart';
import '../models/class_model.dart';
import '../providers/student_provider.dart';
import '../providers/class_provider.dart';

class MessagingScreenSimple extends StatefulWidget {
  const MessagingScreenSimple({super.key});

  @override
  State<MessagingScreenSimple> createState() => _MessagingScreenSimpleState();
}

class _MessagingScreenSimpleState extends State<MessagingScreenSimple> {
  int? selectedClassId;
  String selectedFile = 'no_file';
  String messageText = '';
  List<String> selectedMethods = [];
  Set<int> selectedStudents = {};
  final TextEditingController messageController = TextEditingController();

  final List<Map<String, String>> availableFiles = [
    {'id': 'no_file', 'name': 'لا يوجد ملف', 'icon': '🚫'},
    {'id': 'student_info', 'name': 'معلومات الطالب', 'icon': '👤'},
    {'id': 'attendance_summary', 'name': 'ملخص الحضور', 'icon': '📊'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      if (classProvider.classes.isNotEmpty && selectedClassId == null) {
        setState(() {
          selectedClassId = classProvider.classes.first.id;
        });
      }
    });
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'المراسلة',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // اختيار الفصل
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: Consumer<ClassProvider>(
                builder: (context, classProvider, child) {
                  return DropdownButton<String>(
                    value: selectedClassId?.toString(),
                    hint: const Text('اختر الفصل', style: TextStyle(color: Colors.grey)),
                    dropdownColor: const Color(0xFF3D3D3D),
                    style: const TextStyle(color: Colors.white),
                    isExpanded: true,
                    items: classProvider.classes.map((ClassModel classModel) {
                      return DropdownMenuItem<String>(
                        value: classModel.id.toString(),
                        child: Text(classModel.name),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedClassId = int.parse(newValue!);
                        selectedStudents.clear();
                      });
                    },
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // قائمة الطلاب
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1),
                ),
                child: Consumer<StudentProvider>(
                  builder: (context, studentProvider, child) {
                    final students = selectedClassId != null
                        ? studentProvider.students
                            .where((s) => s.classId == selectedClassId)
                            .toList()
                        : <StudentModel>[];
                    
                    return ListView.builder(
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        final isSelected = selectedStudents.contains(student.id);
                        
                        return Card(
                          color: const Color(0xFF3D3D3D),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: CheckboxListTile(
                            title: Text(
                              student.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              student.email ?? 'لا يوجد بريد',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  if (student.id != null) {
                                    selectedStudents.add(student.id!);
                                  }
                                } else {
                                  if (student.id != null) {
                                    selectedStudents.remove(student.id!);
                                  }
                                }
                              });
                            },
                            activeColor: const Color(0xFFFFD700),
                            checkColor: Colors.black,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // قسم الرسالة
            Expanded(
              flex: 1,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // اختيار الملف
                    const Text(
                      'اختيار الملف',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedFile,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey[600]!),
                        ),
                      ),
                      dropdownColor: Colors.grey[800],
                      style: const TextStyle(color: Colors.white),
                      items: availableFiles.map((file) {
                        return DropdownMenuItem<String>(
                          value: file['id'],
                          child: Row(
                            children: [
                              Text(
                                file['icon']!,
                                style: const TextStyle(fontSize: 20),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file['name']!,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedFile = newValue!;
                        });
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // مربع الرسالة
                    const Text(
                      'الرسالة',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: messageController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك هنا...',
                        hintStyle: const TextStyle(color: Colors.grey),
                        filled: true,
                        fillColor: Colors.grey[800],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFFFFD700)),
                        ),
                      ),
                      onChanged: (value) {
                        messageText = value;
                      },
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // خيارات الإرسال
                    const Text(
                      'طرق الإرسال',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildMethodOption('SMS', 'sms'),
                        _buildMethodOption('EMAIL', 'email'),
                        _buildMethodOption('WHATSAPP', 'whatsapp'),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // زر الإرسال
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedStudents.isNotEmpty && 
                                 selectedMethods.isNotEmpty && 
                                 messageText.isNotEmpty
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم إرسال الرسالة بنجاح'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'إرسال',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodOption(String title, String value) {
    final isSelected = selectedMethods.contains(value);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedMethods.remove(value);
          } else {
            selectedMethods.add(value);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : Colors.grey[700],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFFDAA520) : Colors.grey,
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

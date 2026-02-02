import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import '../models/student_model.dart';
import '../models/class_model.dart';
import '../providers/student_provider.dart';
import '../providers/class_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/exam_provider.dart';
import '../database/database_helper.dart';
import '../models/attendance_model.dart';
import '../models/exam_model.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  int? selectedClassId;
  String selectedSortOption = 'معدل';
  String selectedFile = 'no_file';
  String messageText = '';
  List<String> selectedMethods = [];
  String selectedRecipient = 'طالب';
  Set<int> selectedStudents = {};
  String? selectedFilePath;
  final TextEditingController messageController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  final List<Map<String, String>> availableFiles = [
    {'id': 'no_file', 'name': 'لا يوجد ملف', 'icon': '🚫'},
    {'id': 'student_info', 'name': 'معلومات الطالب', 'icon': '👤'},
    {'id': 'attendance_summary', 'name': 'ملخص الحضور', 'icon': '📊'},
    {'id': 'detailed_attendance', 'name': 'الحضور التفصيلي', 'icon': '📋'},
    {'id': 'exam_attendance', 'name': 'حضور الامتحانات', 'icon': '📝'},
    {'id': 'exams', 'name': 'الامتحانات', 'icon': '🎯'},
    {'id': 'final_grade', 'name': 'الدرجة النهائية', 'icon': '🏆'},
    {'id': 'student_summary', 'name': 'ملخص الطالب', 'icon': '📄'},
    {'id': 'detailed_statistics', 'name': 'احصائيات الطالب التفصيلية', 'icon': '📈'},
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
    searchController.dispose();
    super.dispose();
  }

  Future<Uint8List?> _generatePDFBytes(String fileType, StudentModel student) async {
    if (fileType == 'no_file') {
      return null;
    }

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.cairoRegular();
    final fontBold = await PdfGoogleFonts.cairoBold();

    switch (fileType) {
      case 'student_info':
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Header(
                      level: 0,
                      text: 'معلومات الطالب',
                      textStyle: pw.TextStyle(font: fontBold, fontSize: 24),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text('الاسم: ${student.name}', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.SizedBox(height: 10),
                    pw.Text('البريد الإلكتروني: ${student.email}', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.SizedBox(height: 10),
                    pw.Text('رقم الهاتف: ${student.phone}', style: pw.TextStyle(font: font, fontSize: 16)),
                  ],
                ),
              );
            },
          ),
        );
        break;
      
      case 'attendance_summary':
        final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
        final attendances = attendanceProvider.attendances
            .where((a) => a.studentId == student.id)
            .toList();
        
        final present = attendances.where((a) => a.status == 'present').length;
        final absent = attendances.where((a) => a.status == 'absent').length;
        final late = attendances.where((a) => a.status == 'late').length;
        
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Header(
                      level: 0,
                      text: 'ملخص الحضور',
                      textStyle: pw.TextStyle(font: fontBold, fontSize: 24),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Text('الطالب: ${student.name}', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.SizedBox(height: 20),
                    pw.Text('إجمالي المحاضرات: ${attendances.length}', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.Text('عدد الحضور: $present', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.Text('عدد الغياب: $absent', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.Text('عدد التأخير: $late', style: pw.TextStyle(font: font, fontSize: 16)),
                    pw.SizedBox(height: 20),
                    pw.Text('نسبة الحضور: ${attendances.isEmpty ? 0 : ((present / attendances.length) * 100).toStringAsFixed(1)}%', 
                        style: pw.TextStyle(font: font, fontSize: 16)),
                  ],
                ),
              );
            },
          ),
        );
        break;
        
      default:
        return null;
    }
    
    return await pdf.save();
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
            Consumer<ClassProvider>(
              builder: (context, classProvider, child) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D3D3D),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFFD700), width: 1),
                  ),
                  child: DropdownButton<String>(
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
                  ),
                );
              },
            ),
            
            const SizedBox(height: 16),
            
            // قائمة الطلاب
            Expanded(
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
                        color: const Color(0xFF2D2D2D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: isSelected ? const Color(0xFFFFD700) : Colors.grey,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: ListTile(
                          title: Text(
                            student.name,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            student.email,
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Checkbox(
                            value: isSelected,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  selectedStudents.add(student.id);
                                } else {
                                  selectedStudents.remove(student.id);
                                }
                              });
                            },
                            activeColor: const Color(0xFFFFD700),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // قسم الرسالة
            Container(
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
                    maxLines: 3,
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

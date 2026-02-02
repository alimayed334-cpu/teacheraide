import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/student_model.dart';
import '../models/class_model.dart';
import '../providers/student_provider.dart';
import '../providers/class_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/exam_provider.dart';
import '../database/database_helper.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  int? selectedClassId;
  String selectedFile = 'no_file';
  String messageText = '';
  String selectedRecipient = 'طالب';
  String selectedMethod = 'sms';
  List<String> selectedMethods = [];
  Set<int> selectedStudents = {};
  final TextEditingController messageController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  String selectedSortOption = 'معدل';

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
      body: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.of(context).size.height - 
                       MediaQuery.of(context).padding.top - 
                       kToolbarHeight,
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // القسم الأيسر - قائمة الطلاب
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1),
                    ),
                    child: Column(
                      children: [
                        // شريط التحكم في الفصول والبحث
                        _buildControlBar(),
                        const SizedBox(height: 16),
                        // قائمة الطلاب
                        Expanded(child: _buildStudentsList()),
                      ],
                    ),
                  ),
                ),
                // القسم الأيمن - قائمة الإدخال
                Expanded(
                  flex: 1,
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D2D2D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFD700), width: 1),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildFileSelector(),
                          const SizedBox(height: 16),
                          _buildRecipientSelector(),
                          const SizedBox(height: 16),
                          _buildMessageInput(),
                          const SizedBox(height: 16),
                          _buildSendMethodSelector(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // شريط التحكم في الفصول والبحث
  Widget _buildControlBar() {
    return Column(
      children: [
        // اختيار الفصل
        Consumer<ClassProvider>(
          builder: (context, classProvider, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                underline: const SizedBox(),
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
        const SizedBox(height: 12),
        // شريط البحث والفرز
        Row(
          children: [
            // حقل البحث
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D3D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1),
                ),
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'البحث عن طالب...',
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.search, color: Color(0xFFDAA520)),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // قائمة الفرز
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: DropdownButton<String>(
                value: selectedSortOption,
                dropdownColor: const Color(0xFF3D3D3D),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'معدل', child: Text('معدل')),
                  DropdownMenuItem(value: 'أعلى معدل', child: Text('أعلى معدل')),
                  DropdownMenuItem(value: 'أقل معدل', child: Text('أقل معدل')),
                  DropdownMenuItem(value: 'أعلى غياب', child: Text('أعلى غياب')),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    selectedSortOption = newValue!;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  // قائمة الطلاب
  Widget _buildStudentsList() {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        final students = getFilteredStudents();
        
        return ListView.builder(
          itemCount: students.length,
          itemBuilder: (context, index) {
            final student = students[index];
            final isSelected = selectedStudents.contains(student.id ?? 0);
            
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFD700) : Colors.grey,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  // دائرة بأول حرف من اسم الطالب
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        student.name.isNotEmpty ? student.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // معلومات الطالب
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // معلومات الطالب الحقيقية من قاعدة البيانات
                        FutureBuilder(
                          future: _getStudentInfo(student.id!),
                          builder: (context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
                            if (snapshot.hasData) {
                              final info = snapshot.data!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'المعدل: ${info['average']}',
                                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                                  ),
                                  Text(
                                    'الحضور: ${info['presentLectures']}/${info['totalLectures']}',
                                    style: const TextStyle(color: Colors.green, fontSize: 12),
                                  ),
                                  Text(
                                    'الغياب: ${info['absentLectures']} محاضرة',
                                    style: const TextStyle(color: Colors.red, fontSize: 12),
                                  ),
                                  Text(
                                    'الامتحانات: ${info['presentExams']}/${info['totalExams']}',
                                    style: const TextStyle(color: Colors.purple, fontSize: 12),
                                  ),
                                  Text(
                                    'الهاتف: ${info['phone']}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                                  ),
                                ],
                              );
                            }
                            return const Text(
                              'جاري تحميل المعلومات...',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // مربع الاختيار
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected && student.id != null) {
                          selectedStudents.remove(student.id!);
                        } else if (student.id != null) {
                          selectedStudents.add(student.id!);
                        }
                      });
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? const Color(0xFFFFD700) : Colors.grey,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: isSelected ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.transparent,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, size: 16, color: Color(0xFFFFD700))
                          : null,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // اختيار الملف
  Widget _buildFileSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختيار الملف',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: selectedFile,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
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
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                selectedFile = newValue ?? 'no_file';
              });
            },
          ),
        ],
      ),
    );
  }

  // اختيار المستلم
  Widget _buildRecipientSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإرسال إلى',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildRecipientOption('الطالب', 'طالب'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildRecipientOption('ولي الأمر 1', 'ولي الأمر 1'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildRecipientOption('ولي الأمر 2', 'ولي الأمر 2'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientOption(String title, String value) {
    final isSelected = selectedRecipient == value;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRecipient = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? const Color(0xFFFFD700) : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  // مربع الرسالة
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الرسالة',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
              ),
              hintText: 'اكتب رسالتك هنا...',
              hintStyle: const TextStyle(color: Colors.grey),
            ),
            onChanged: (value) {
              setState(() {
                messageText = value;
              });
            },
          ),
        ],
      ),
    );
  }

  // اختيار طريقة الإرسال
  Widget _buildSendMethodSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'طريقة الإرسال',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMethodOption('SMS', 'sms', Icons.message),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMethodOption('WhatsApp', 'whatsapp', Icons.message),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMethodOption('Email', 'email', Icons.email),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMethodOption(String title, String value, IconData icon) {
    final isSelected = selectedMethod == value;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedMethod = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFFFD700) : Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFD700) : Colors.white,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // دوال مساعدة
  List<StudentModel> getFilteredStudents() {
    final studentProvider = Provider.of<StudentProvider>(context);
    final students = selectedClassId != null
        ? studentProvider.students.where((s) => s.classId == selectedClassId).toList()
        : <StudentModel>[];

    // تطبيق البحث
    if (searchController.text.isNotEmpty) {
      students.retainWhere((student) =>
          student.name.toLowerCase().contains(searchController.text.toLowerCase()));
    }

    // تطبيق الفرز
    switch (selectedSortOption) {
      case 'أعلى معدل':
        // سيتم تنفيذها بعد إضافة دالة getStudentAverage
        break;
      case 'أقل معدل':
        // سيتم تنفيذها بعد إضافة دالة getStudentAverage
        break;
      case 'أعلى غياب':
        // سيتم تنفيذها بعد إضافة دالة getAttendanceStats
        break;
      default:
        students.sort((a, b) => a.name.compareTo(b.name));
    }

    return students;
  }

  Future<Map<String, dynamic>> _getStudentInfo(int studentId) async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    try {
      // جلب معدل الطالب
      final average = await studentProvider.getStudentAverage(studentId);
      
      // جلب إحصائيات الحضور
      final attendanceStats = await studentProvider.getStudentAttendanceStats(studentId);
      
      // جلب معلومات الطالب
      final students = studentProvider.students.where((s) => s.id == studentId).toList();
      final student = students.isNotEmpty ? students.first : null;
      
      return {
        'average': average.toStringAsFixed(1),
        'presentLectures': attendanceStats['present'] ?? 0,
        'absentLectures': attendanceStats['absent'] ?? 0,
        'totalLectures': (attendanceStats['present'] ?? 0) + (attendanceStats['absent'] ?? 0),
        'presentExams': attendanceStats['presentExams'] ?? 0,
        'absentExams': attendanceStats['absentExams'] ?? 0,
        'totalExams': (attendanceStats['presentExams'] ?? 0) + (attendanceStats['absentExams'] ?? 0),
        'phone': student?.phone ?? student?.parentPhone ?? 'لا يوجد',
        'email': student?.email ?? 'لا يوجد',
      };
    } catch (e) {
      return {
        'average': '0.0',
        'presentLectures': 0,
        'absentLectures': 0,
        'totalLectures': 0,
        'presentExams': 0,
        'absentExams': 0,
        'totalExams': 0,
        'phone': 'لا يوجد',
        'email': 'لا يوجد',
      };
    }
  }

  void _sendMessage() {
    // هنا سيتم تنفيذ منطق الإرسال
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('جاري إرسال الرسالة...'),
        backgroundColor: Color(0xFFFFD700),
      ),
    );
  }
}

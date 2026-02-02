import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/student_note_model.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../database/database_helper.dart';
import '../../widgets/student_status_indicator.dart';
import '../students/student_attendance_screen.dart';
import '../students/student_assignments_screen.dart';
import '../students/student_attendance_pdf.dart';
import '../../models/attendance_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../utils/date_filter_helper.dart';

class StudentNotesMainScreen extends StatefulWidget {
  final StudentModel? student;
  final ClassModel? classModel;

  const StudentNotesMainScreen({
    super.key,
    this.student,
    this.classModel,
  });

  @override
  State<StudentNotesMainScreen> createState() => _StudentNotesMainScreenState();
}

class _StudentNotesMainScreenState extends State<StudentNotesMainScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<StudentModel> _students = [];
  List<StudentNoteModel> _studentNotes = [];
  List<ClassModel> _classes = [];
  ClassModel? _selectedClass;
  bool _isLoading = true;

  // إحصائيات الملاحظات
  int _goodNotesCount = 0;
  int _badNotesCount = 0;
  int _normalNotesCount = 0;
  
  // متغيرات التاريخ والتصفية
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedFilter = 'كل الفترة';

  @override
  void initState() {
    super.initState();
    // استخدام البيانات الممررة إذا كانت متوفرة
    if (widget.student != null) {
      _students = [widget.student!];
    }
    if (widget.classModel != null) {
      _selectedClass = widget.classModel;
      _classes = [widget.classModel!];
    }
    _loadDateFilter();
    _loadData();
  }

  Future<void> _loadDateFilter() async {
    final filterData = await DateFilterHelper.getDateFilter();
    setState(() {
      // التأكد من أن الفلتر المدخل من القائمة الصحيحة
      String filter = filterData['filter'] ?? 'كل الفترة';
      if (filter == 'التواريخ: الكل') {
        filter = 'كل الفترة';
      }
      _selectedFilter = filter;
      _startDate = filterData['startDate'];
      _endDate = filterData['endDate'];
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // إذا كانت البيانات ممررة من صفحة سابقة، استخدمها مباشرة
      if (widget.student != null && widget.classModel != null) {
        _students = [widget.student!];
        _selectedClass = widget.classModel;
        _classes = [widget.classModel!];
      } else {
        // تحميل الفصول
        final classProvider = Provider.of<ClassProvider>(context, listen: false);
        await classProvider.loadClasses();
        _classes = classProvider.classes;
        
        if (_classes.isNotEmpty && _selectedClass == null) {
          _selectedClass = _classes.first;
        }
        
        // تحميل الطلاب
        final studentProvider = Provider.of<StudentProvider>(context, listen: false);
        if (_selectedClass != null) {
          await studentProvider.loadStudentsByClass(_selectedClass!.id!);
          _students = studentProvider.students;
        }
      }

      // تحميل الملاحظات
      await _loadStudentNotes();
      _calculateStatistics();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadStudentNotes() async {
    if (_selectedClass == null || _students.isEmpty) return;
    
    setState(() => _isLoading = true);
    
    try {
      final studentNotes = <StudentNoteModel>[];
      
      for (final student in _students) {
        final notes = await _dbHelper.getStudentNotesByStudent(student.id!);
        studentNotes.addAll(notes);
      }
      
      // Filter notes using DateFilterHelper
      final filteredNotes = DateFilterHelper.filterNotes(
        studentNotes, 
        _selectedFilter, 
        _startDate, 
        _endDate, 
        (note) => note.date
      );
      
      setState(() {
        _studentNotes = filteredNotes;
        _isLoading = false;
      });
      
    } catch (e) {
      print('Error loading student notes: $e');
      setState(() {
        _isLoading = false;
        _studentNotes = [];
      });
    }
  }

  void _calculateStatistics() {
    _goodNotesCount = _studentNotes.where((note) => note.noteType == StudentNoteType.good).length;
    _badNotesCount = _studentNotes.where((note) => note.noteType == StudentNoteType.bad).length;
    _normalNotesCount = _studentNotes.where((note) => note.noteType == StudentNoteType.normal).length;
  }

  // تجميع الملاحظات حسب التاريخ
  Map<String, List<StudentNoteModel>> get _groupedNotes {
    final Map<String, List<StudentNoteModel>> grouped = {};
    
    for (final note in _studentNotes) {
      final dateKey = DateFormat('yyyy-MM-dd').format(note.date);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(note);
    }
    
    // ترتيب التواريخ من الأحدث إلى الأقدم
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));
    
    final Map<String, List<StudentNoteModel>> sortedGrouped = {};
    for (final key in sortedKeys) {
      sortedGrouped[key] = grouped[key]!;
    }
    
    return sortedGrouped;
  }

  Widget _buildDateGroup(String dateKey, List<StudentNoteModel> notes, StudentModel student) {
    final date = DateTime.parse(dateKey);
    final formattedDate = DateFormat('EEEE, d MMMM yyyy', 'ar').format(date);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس التاريخ
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.yellow.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.grey.withOpacity(0.3)),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.yellow, size: 20),
                const SizedBox(width: 8),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    color: Colors.yellow,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${notes.length} ملاحظة',
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // الملاحظات في هذا التاريخ
          ...notes.map((note) => _buildNoteItemInGroup(note, student)).toList(),
        ],
      ),
    );
  }

  Widget _buildNoteItemInGroup(StudentNoteModel note, StudentModel student) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getNoteTypeColor(note.noteType),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getNoteTypeColor(note.noteType).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // محتوى الملاحظة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.note,
                  style: TextStyle(
                    color: note.noteType == StudentNoteType.normal ? Colors.black : Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _getNoteTypeText(note.noteType),
                      style: TextStyle(
                        fontSize: 12,
                        color: note.noteType == StudentNoteType.normal ? Colors.black87 : Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (note.studentId != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '• ${_getStudentName(note.studentId!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: note.noteType == StudentNoteType.normal ? Colors.black54 : Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          // قائمة الخيارات
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditNoteDialog(note, student);
                  break;
                case 'edit_date':
                  _showEditDateDialog(note, student);
                  break;
                case 'delete':
                  _confirmDeleteNote(note);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text('تعديل الملاحظة'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit_date',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text('تعديل التاريخ'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Text('حذف الملاحظة'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: _selectedClass != null 
          ? Text('ملاحظات طلاب ${_selectedClass!.name}')
          : const Text('ملاحظات الطلاب'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst); // Go to student details page
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: () => _exportToPDF(),
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadData,
            child: Column(
              children: [
                // معلومات الطالب والفصل
                if (_students.isNotEmpty) _buildStudentClassInfo(),
                
                // حاوية الإحصائيات
                _buildStatisticsContainer(),
                
                // قائمة الملاحظات
                Expanded(
                  child: _studentNotes.isEmpty 
                    ? const Center(
                        child: Text(
                          'لا توجد ملاحظات',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _groupedNotes.keys.length,
                        itemBuilder: (context, index) {
                          final date = _groupedNotes.keys.elementAt(index);
                          final notes = _groupedNotes[date]!;
                          return _buildDateGroup(date, notes, _students.firstWhere((s) => s.id == notes.first.studentId));
                        },
                      ),
                ),
              ],
            ),
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.yellow,
        child: const Icon(Icons.add, color: Colors.black),
        onPressed: () {
          if (_students.isNotEmpty) {
            _showAddNoteOptions(_students.first);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('لا يوجد طلاب في هذا الفصل'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        },
      ),
      // Bottom navigation
      bottomNavigationBar: Container(
        height: 63,
        color: const Color(0xFF1A1A1A), // Blackish gray
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem('الحضور', Icons.event_available, false),
            _buildNavItem('الامتحانات', Icons.quiz, false),
            _buildNavItem('الملاحظات', Icons.note, true),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (title == 'الحضور') {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentAttendanceScreen(
                student: _students.isNotEmpty ? _students.first : widget.student ?? StudentModel(id: 1, classId: 1, name: 'طالب', createdAt: DateTime.now(), updatedAt: DateTime.now()),
                classModel: _selectedClass ?? widget.classModel ?? ClassModel(id: 1, name: 'فصل', subject: 'مادة', year: '2024', createdAt: DateTime.now(), updatedAt: DateTime.now()),
              ),
            ),
          );
        } else if (title == 'الامتحانات') {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentAssignmentsScreen(
                student: _students.isNotEmpty ? _students.first : widget.student ?? StudentModel(id: 1, classId: 1, name: 'طالب', createdAt: DateTime.now(), updatedAt: DateTime.now()),
                classModel: _selectedClass ?? widget.classModel ?? ClassModel(id: 1, name: 'فصل', subject: 'مادة', year: '2024', createdAt: DateTime.now(), updatedAt: DateTime.now()),
              ),
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.yellow.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? Colors.black : Colors.grey[400],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                color: isActive ? Colors.black : Colors.grey[400],
                fontSize: 12,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentClassInfo() {
    if (_students.isEmpty) return const SizedBox.shrink();
    
    final student = _students.first;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اسم الطالب',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  student.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اسم الفصل',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _selectedClass?.name ?? 'غير محدد',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'التصفية',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.yellow.withOpacity(0.5)),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedFilter,
                    underline: const SizedBox(),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(
                      color: Colors.yellow,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'كل الفترة', child: Text('كل الفترة')),
                      DropdownMenuItem(value: 'اليوم', child: Text('اليوم')),
                      DropdownMenuItem(value: 'آخر أسبوع', child: Text('آخر أسبوع')),
                      DropdownMenuItem(value: 'آخر شهر', child: Text('آخر شهر')),
                      DropdownMenuItem(value: 'تاريخ محدد', child: Text('تاريخ محدد')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _handleFilterChange(value);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatisticsContainer() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.yellow.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellow.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إحصائيات الملاحظات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.yellow,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('جيدة', _goodNotesCount, Colors.green),
              _buildStatItem('سيئة', _badNotesCount, Colors.red),
              _buildStatItem('عادية', _normalNotesCount, Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Center(
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard(StudentNoteModel note) {
    final student = _students.firstWhere((s) => s.id == note.studentId);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _getNoteTypeColor(note.noteType),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getNoteTypeColor(note.noteType).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // رأس البطاقة
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // نوع الملاحظة
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getNoteTypeText(note.noteType),
                    style: TextStyle(
                      color: note.noteType == StudentNoteType.normal ? Colors.black87 : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                // التاريخ
                Text(
                  DateFormat('d MMMM yyyy', 'ar').format(note.date),
                  style: TextStyle(
                    color: note.noteType == StudentNoteType.normal ? Colors.black87 : Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                // قائمة الخيارات
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert, 
                    color: note.noteType == StudentNoteType.normal ? Colors.black87 : Colors.white,
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showEditNoteDialog(note, student);
                        break;
                      case 'edit_date':
                        _showEditDateDialog(note, student);
                        break;
                      case 'delete':
                        _confirmDeleteNote(note);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: Colors.blue, size: 16),
                          SizedBox(width: 8),
                          Text('تعديل الملاحظة'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'edit_date',
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: Colors.orange, size: 16),
                          SizedBox(width: 8),
                          Text('تعديل التاريخ'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red, size: 16),
                          SizedBox(width: 8),
                          Text('حذف الملاحظة'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // محتوى الملاحظة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.note,
                  style: TextStyle(
                    color: note.noteType == StudentNoteType.normal ? Colors.black : Colors.white,
                    fontSize: 14,
                  ),
                ),
                if (note.studentId != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'الطالب: ${_getStudentName(note.studentId!)}',
                    style: TextStyle(
                      color: note.noteType == StudentNoteType.normal ? Colors.black54 : Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(StudentModel student, List<StudentNoteModel> notes) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // معلومات الطالب
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.1),
                  child: Text(
                    student.name.isNotEmpty ? student.name[0] : 'S',
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            student.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          StudentStatusIndicator(student: student),
                        ],
                      ),
                      if (_selectedClass != null)
                        Text(
                          'الفصل: ${_selectedClass!.name}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
                // زر الإضافة الأصفر
                Container(
                  decoration: BoxDecoration(
                    color: Colors.yellow,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.yellow.withOpacity(0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.black),
                    onPressed: () => _showAddNoteOptions(student),
                    tooltip: 'إضافة ملاحظة',
                  ),
                ),
              ],
            ),
          ),
          
          // عرض الملاحظات
          if (notes.isNotEmpty) ...[
            const Divider(height: 1),
            ...notes.map((note) => _buildNoteItem(note, student)).toList(),
          ],
        ],
      ),
    );
  }

  Widget _buildNoteItem(StudentNoteModel note, StudentModel student) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getNoteColor(note.noteType).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _getNoteColor(note.noteType).withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // لون الملاحظة
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: _getNoteColor(note.noteType),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          
          // محتوى الملاحظة
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.note,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd/MM/yyyy').format(note.date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getNoteColor(note.noteType).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        note.noteType.displayName,
                        style: TextStyle(
                          fontSize: 10,
                          color: _getNoteColor(note.noteType),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // قائمة الخيارات
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditNoteDialog(note, student);
                  break;
                case 'delete':
                  _confirmDeleteNote(note);
                  break;
                case 'edit_date':
                  _showEditDateDialog(note, student);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit, color: Colors.blue, size: 16),
                    SizedBox(width: 8),
                    Text('تعديل الملاحظة'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit_date',
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.orange, size: 16),
                    SizedBox(width: 8),
                    Text('تعديل التاريخ'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: Colors.red, size: 16),
                    SizedBox(width: 8),
                    Text('حذف الملاحظة'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getNoteColor(StudentNoteType type) {
    switch (type) {
      case StudentNoteType.good:
        return Colors.green;
      case StudentNoteType.bad:
        return Colors.red;
      case StudentNoteType.normal:
        return Colors.white;
    }
  }

  Color _getNoteTypeColor(StudentNoteType type) {
    switch (type) {
      case StudentNoteType.good:
        return Colors.green;
      case StudentNoteType.bad:
        return Colors.red;
      case StudentNoteType.normal:
        return Colors.white;
    }
  }

  String _getNoteTypeText(StudentNoteType type) {
    return type.displayName;
  }

  String _getStudentName(int studentId) {
    final student = _students.firstWhere(
      (s) => s.id == studentId,
      orElse: () => StudentModel(id: 1, classId: 1, name: 'طالب', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    );
    return student.name;
  }

  String _getDateRangeText() {
    if (_startDate == null && _endDate == null) {
      return 'كل الفترة';
    } else if (_startDate != null && _endDate == null) {
      return 'من ${DateFormat('d/M').format(_startDate!)}';
    } else if (_startDate == null && _endDate != null) {
      return 'حتى ${DateFormat('d/M').format(_endDate!)}';
    } else {
      return '${DateFormat('d/M').format(_startDate!)} - ${DateFormat('d/M').format(_endDate!)}';
    }
  }

  void _handleFilterChange(String filter) async {
    setState(() {
      _selectedFilter = filter;
      _startDate = null;
      _endDate = null;
    });

    // Save filter to shared storage
    await DateFilterHelper.saveDateFilter(filter, null, null);

    final now = DateTime.now();
    
    switch (filter) {
      case 'اليوم':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = _startDate!.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
        break;
      case 'آخر أسبوع':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        break;
      case 'آخر شهر':
        _startDate = DateTime(now.year, now.month - 1, now.day);
        _endDate = now;
        break;
      case 'تاريخ محدد':
        await _showCustomDateRangeDialog();
        return;
      case 'كل الفترة':
      default:
        // لا تغيير، ابقى null
        break;
    }
    
    await _loadStudentNotes();
    _calculateStatistics();
  }

  Future<void> _showCustomDateRangeDialog() async {
    DateTime? startDate = _startDate;
    DateTime? endDate = _endDate;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: const Text(
            'تحديد فترة زمنية',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // تاريخ البدء
              ListTile(
                title: const Text(
                  'تاريخ البدء',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  startDate != null 
                      ? DateFormat('yyyy/MM/dd').format(startDate!)
                      : 'اختر تاريخ البدء',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.yellow),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: Colors.yellow,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    setDialogState(() => startDate = date);
                  }
                },
              ),
              
              // تاريخ النهاية
              ListTile(
                title: const Text(
                  'تاريخ النهاية',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  endDate != null 
                      ? DateFormat('yyyy/MM/dd').format(endDate!)
                      : 'اختر تاريخ النهاية',
                  style: const TextStyle(color: Colors.grey),
                ),
                trailing: const Icon(Icons.calendar_today, color: Colors.yellow),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: endDate ?? DateTime.now(),
                    firstDate: startDate ?? DateTime(2020),
                    lastDate: DateTime(2030),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: Colors.yellow,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (date != null) {
                    setDialogState(() => endDate = date);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (startDate != null && endDate != null) {
                  // Save the custom date range to shared storage
                  await DateFilterHelper.saveDateFilter('تاريخ محدد', startDate, endDate);
                  
                  setState(() {
                    _startDate = startDate;
                    _endDate = endDate;
                    _selectedFilter = 'تاريخ محدد';
                  });
                  Navigator.pop(context);
                  _loadStudentNotes();
                  _calculateStatistics();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
              ),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNoteOptions(StudentModel student) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'اختر نوع الملاحظة',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...StudentNoteType.values.map((type) {
              return ListTile(
                leading: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _getNoteColor(type),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                title: Text(type.displayName),
                onTap: () {
                  Navigator.pop(context);
                  _showAddNoteDialog(student, type);
                },
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  void _showAddNoteDialog(StudentModel student, StudentNoteType noteType) {
    final noteController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('إضافة ملاحظة ${noteType.displayName} لـ ${student.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'الملاحظة',
                  hintText: 'اكتب ملاحظتك هنا...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              ListTile(
                title: Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setDialogState(() => selectedDate = date);
                  }
                },
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
                if (noteController.text.trim().isNotEmpty) {
                  _saveStudentNote(student, noteController.text.trim(), noteType, selectedDate);
                  Navigator.pop(context);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveStudentNote(
    StudentModel student,
    String noteText,
    StudentNoteType noteType,
    DateTime selectedDate,
  ) async {
    try {
      final newNote = StudentNoteModel(
        id: null,
        studentId: student.id!,
        classId: _selectedClass?.id ?? 1,
        note: noteText,
        noteType: noteType,
        date: selectedDate,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      
      await _dbHelper.insertStudentNote(newNote);
      await _loadStudentNotes();
      _calculateStatistics();
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إضافة الملاحظة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('هناك خطأ في إضافة ملاحظة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showEditNoteDialog(StudentNoteModel note, StudentModel student) {
    final noteController = TextEditingController(text: note.note);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل ملاحظة لـ ${student.name}'),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            labelText: 'الملاحظة',
            hintText: 'اكتب ملاحظتك هنا...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.trim().isNotEmpty) {
                _updateStudentNote(note, noteController.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showEditDateDialog(StudentNoteModel note, StudentModel student) {
    DateTime selectedDate = note.date;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل تاريخ الملاحظة لـ ${student.name}'),
        content: ListTile(
          title: Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
          trailing: const Icon(Icons.calendar_today),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (date != null) {
              Navigator.pop(context);
              _updateNoteDate(note, date);
            }
          },
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

  Future<void> _updateStudentNote(StudentNoteModel note, String newNote) async {
    try {
      final updatedNote = note.copyWith(
        note: newNote,
        updatedAt: DateTime.now(),
      );
      
      await _dbHelper.updateStudentNote(updatedNote);
      await _loadStudentNotes();
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث الملاحظة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث الملاحظة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateNoteDate(StudentNoteModel note, DateTime newDate) async {
    try {
      final updatedNote = note.copyWith(
        date: newDate,
        updatedAt: DateTime.now(),
      );
      
      await _dbHelper.updateStudentNote(updatedNote);
      await _loadStudentNotes();
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث تاريخ الملاحظة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحديث تاريخ الملاحظة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteNote(StudentNoteModel note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('هل أنت متأكد من حذف هذه الملاحظة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await _deleteNote(note);
    }
  }

  Future<void> _deleteNote(StudentNoteModel note) async {
    try {
      await _dbHelper.deleteStudentNote(note.id!);
      await _loadStudentNotes();
      _calculateStatistics();
      setState(() {});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الملاحظة'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف الملاحظة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportToPDF() async {
    if (_students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يوجد طلاب للتصدير'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final student = _students.first;
    final classModel = _selectedClass;
    
    await StudentReportPDF.generatePDF(
      context: context,
      student: student,
      classModel: classModel,
      reportType: 'notes',
    );
  }
}

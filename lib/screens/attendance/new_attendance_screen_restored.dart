import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/lecture_model.dart';
import '../../models/attendance_model.dart';
import '../../models/note_model.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../database/database_helper.dart';
import '../students/add_student_screen.dart';
import '../students/student_details_screen.dart';
import '../students/student_assignments_screen.dart';
import '../notes/class_notes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SortType { alphabetical, attendanceRate, absenceRate, gender }

class NewAttendanceScreen extends StatefulWidget {
  final ClassModel classModel;
  final VoidCallback? onStudentAdded;

  const NewAttendanceScreen({
    super.key,
    required this.classModel,
    this.onStudentAdded,
  });

  @override
  State<NewAttendanceScreen> createState() => _NewAttendanceScreenState();
}

class _NewAttendanceScreenState extends State<NewAttendanceScreen> with WidgetsBindingObserver {
  SortType _sortType = SortType.alphabetical;
  List<LectureModel> _lectures = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<StudentModel> _students = [];
  final DatabaseHelper _dbHelper = DatabaseHelper();
  // خريطة لحفظ حالة الحضور: studentId -> {date: status}
  Map<int, Map<String, AttendanceStatus>> _attendanceStatus = {};
  // خريطة لحفظ التعليقات: studentId -> {date: comment}
  Map<int, Map<String, String>> _studentComments = {};
  // خريطة لحفظ ملاحظات المحاضرات: lectureId -> notes
  Map<int, String> _lectureNotes = {};
  // خريطة لتخزين إحصائيات الحضور للفرز
  Map<int, Map<String, int>> _studentStats = {};
  bool _isLoadingStats = false;
  // خريطة لتخزين حالة الطلاب في خطر
  Map<int, bool> _atRiskStudents = {};
  // متحكمات التمرير المشتركة
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    // ربط التمرير بين العناوين والمحتوى
    _headerScrollController.addListener(_syncHeaderScroll);
    _contentScrollController.addListener(_syncContentScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة فحص المعايير عند العودة للتطبيق
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkAtRiskStudents();
      });
    }
  }

  void _syncHeaderScroll() {
    if (_headerScrollController.hasClients && _contentScrollController.hasClients) {
      if (_headerScrollController.offset != _contentScrollController.offset) {
        _contentScrollController.jumpTo(_headerScrollController.offset);
      }
    }
  }

  void _syncContentScroll() {
    if (_contentScrollController.hasClients && _headerScrollController.hasClients) {
      if (_contentScrollController.offset != _headerScrollController.offset) {
        _headerScrollController.jumpTo(_contentScrollController.offset);
      }
    }
  }

  // دالة مساعدة لتحديث واجهة المستخدم
  void _updateAttendance() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headerScrollController.dispose();
    _contentScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(NewAttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.classModel.id != widget.classModel.id) {
      _loadData();
    } else {
      _checkAtRiskStudents();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    
    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.loadStudentsByClass(widget.classModel.id!);
      
      final lectures = await _dbHelper.getLecturesByClass(widget.classModel.id!);
      
      if (!mounted) return;
      setState(() {
        _students = studentProvider.students;
        _lectures = lectures;
      });
      
      await _loadAllAttendanceStatuses();
      await _loadStudentStats();
      await _checkAtRiskStudents();
      
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ في تحميل البيانات: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _loadAllAttendanceStatuses() async {
    if (!mounted) return;
    try {
      for (final lecture in _lectures) {
        for (final student in _students) {
          final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
            studentId: student.id!,
            lectureId: lecture.id!,
          );
          if (attendance != null) {
            final dateKey = DateFormat('yyyy-MM-dd').format(lecture.date);
            _attendanceStatus[student.id!] = {
              dateKey: attendance.status,
            };
          }
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading attendance statuses: $e');
    }
  }

  Future<void> _loadStudentStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    try {
      for (final student in _students) {
        final stats = {'total': 0, 'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
        _studentStats[student.id!] = stats;
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading student stats: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _checkAtRiskStudents() async {
    if (!mounted) return;
    try {
      for (final student in _students) {
        final stats = _studentStats[student.id!];
        if (stats != null) {
          final totalLectures = stats['total'] ?? 0;
          final absences = stats['absent'] ?? 0;
          final absenceRate = totalLectures > 0 ? (absences / totalLectures) * 100 : 0;
          
          _atRiskStudents[student.id!] = absenceRate > 25; // At risk if >25% absence
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error checking at-risk students: $e');
    }
  }

  Widget _buildSymbolText(String text, {Color? color, double size = 16}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? Colors.grey,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          text.isNotEmpty ? text[0] : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green;
      case AttendanceStatus.absent:
        return Colors.red;
      case AttendanceStatus.late:
        return Colors.orange;
      case AttendanceStatus.expelled:
        return Colors.purple;
    }
  }

  String _getStatusText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'ح';
      case AttendanceStatus.absent:
        return 'غ';
      case AttendanceStatus.late:
        return 'ت';
      case AttendanceStatus.expelled:
        return 'ط';
    }
  }

  void _showSortOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ترتيب حسب'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSortChip('أبجدي', SortType.alphabetical),
            _buildSortChip('نسبة الحضور', SortType.attendanceRate),
            _buildSortChip('نسبة الغياب', SortType.absenceRate),
            _buildSortChip('الجنس', SortType.gender),
          ],
        ),
      ),
    );
  }

  Widget _buildSortChip(String label, SortType type) {
    return FilterChip(
      label: Text(label),
      selected: _sortType == type,
      onSelected: (selected) {
        setState(() {
          _sortType = type;
        });
        Navigator.pop(context);
      },
    );
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_add),
            title: const Text('إضافة طالب'),
            onTap: () {
              Navigator.pop(context);
              _showAddStudentDialog();
            },
          ),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('إضافة محاضرة'),
            onTap: () {
              Navigator.pop(context);
              _showAddLectureDialog();
            },
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddStudentScreen(
          selectedClass: widget.classModel,
        ),
      ),
    );
  }

  void _showAddLectureDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة محاضرة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'عنوان المحاضرة'),
              controller: TextEditingController(),
            ),
            const SizedBox(height: 16),
            ListTile(
              title: const Text('تاريخ المحاضرة'),
              subtitle: Text(DateFormat('yyyy-MM-dd').format(DateTime.now())),
              trailing: const Icon(Icons.calendar_today),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إضافة'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'بحث عن طالب...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  Widget _buildLecturesHeader() {
    return Container(
      height: 60,
      decoration: const BoxDecoration(
        color: Colors.blue,
        boxShadow: [BoxShadow(blurRadius: 4)],
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        controller: _headerScrollController,
        itemCount: _lectures.length,
        itemBuilder: (context, index) {
          final lecture = _lectures[index];
          return Container(
            width: 80,
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat('dd/MM').format(lecture.date),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Text(
                  lecture.title,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStudentsList() {
    final filteredStudents = _students.where((student) {
      return student.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    
    final sortedStudents = _sortStudents(filteredStudents);
    
    return ListView.builder(
      controller: _contentScrollController,
      itemCount: sortedStudents.length,
      itemBuilder: (context, index) {
        final student = sortedStudents[index];
        return ListTile(
          leading: CircleAvatar(
            child: Text(student.name.isNotEmpty ? student.name[0] : '?'),
          ),
          title: Text(student.name),
          subtitle: Text(student.phone ?? ''),
          trailing: _buildStudentStats(student.id!),
        );
      },
    );
  }

  Widget _buildStudentStats(int studentId) {
    final stats = _studentStats[studentId];
    if (stats == null) return const SizedBox();
    
    final total = stats['total'] ?? 0;
    final present = stats['present'] ?? 0;
    final percentage = total > 0 ? (present / total * 100).round() : 0;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: percentage >= 75 ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$percentage%',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    switch (_sortType) {
      case SortType.alphabetical:
        return students..sort((a, b) => a.name.compareTo(b.name));
      case SortType.attendanceRate:
        return students..sort((a, b) {
          final statsA = _studentStats[a.id!];
          final statsB = _studentStats[b.id!];
          final rateA = statsA != null ? (statsA['present'] ?? 0) / (statsA['total'] ?? 1) : 0;
          final rateB = statsB != null ? (statsB['present'] ?? 0) / (statsB['total'] ?? 1) : 0;
          return rateB.compareTo(rateA);
        });
      case SortType.absenceRate:
        return students..sort((a, b) {
          final statsA = _studentStats[a.id!];
          final statsB = _studentStats[b.id!];
          final rateA = statsA != null ? (statsA['absent'] ?? 0) / (statsA['total'] ?? 1) : 0;
          final rateB = statsB != null ? (statsB['absent'] ?? 0) / (statsB['total'] ?? 1) : 0;
          return rateB.compareTo(rateA);
        });
      case SortType.gender:
        return students..sort((a, b) => (a.studentId ?? '').compareTo(b.studentId ?? ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('حضور ${widget.classModel.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildLecturesHeader(),
          Expanded(
            child: _buildStudentsList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }
}

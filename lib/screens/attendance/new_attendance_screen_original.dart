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
    // إعادة تحميل البيانات عند تغيير الفصل
    if (oldWidget.classModel.id != widget.classModel.id) {
      _loadData();
    } else {
      // فحص المعايير عند العودة للصفحة
      _checkAtRiskStudents();
    }
  }

  Future<void> _loadData() async {
    // تحميل الطلاب من Provider
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    await studentProvider.loadStudentsByClass(widget.classModel.id!);
    
    // تحميل المحاضرات الخاصة بهذا الفصل فقط
    final lectures = await _dbHelper.getLecturesByClass(widget.classModel.id!);
    
    setState(() {
      _students = studentProvider.students; // ✅ استخدام الطلاب من Provider
      _lectures = lectures;
    });
    
    // تحميل جميع حالات الحضور من قاعدة البيانات
    await _loadAllAttendanceStatuses();
    
    // حساب إحصائيات الحضور للفرز
    await _loadStudentStats();
    
    // فحص الطلاب في خطر
    await _checkAtRiskStudents();
  }

  Future<void> _loadAllAttendanceStatuses() async {
    _attendanceStatus.clear();
    
    for (final student in _students) {
      try {
        final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
        if (!_attendanceStatus.containsKey(student.id!)) {
          _attendanceStatus[student.id!] = {};
        }
        
        for (final attendance in attendances) {
          final dateKey = DateFormat('yyyy-MM-dd').format(attendance.date);
          _attendanceStatus[student.id!]![dateKey] = attendance.status;
        }
      } catch (e) {
        debugPrint('Error loading attendance for student ${student.id}: $e');
      }
    }
  }

  Future<void> _loadStudentStats() async {
    if (!mounted) return;
    setState(() => _isLoadingStats = true);
    
    try {
      for (final student in _students) {
        final stats = await _dbHelper.getStudentAttendanceStats(student.id!);
        _studentStats[student.id!] = stats;
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error loading student stats: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingStats = false);
      }
    }
  }

  Future<void> _checkAtRiskStudents() async {
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
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error checking at-risk students: $e');
    }
  }

  Color _getAttendanceColor(AttendanceStatus status) {
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

  IconData _getAttendanceIcon(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle;
      case AttendanceStatus.absent:
        return Icons.cancel;
      case AttendanceStatus.late:
        return Icons.access_time;
      case AttendanceStatus.expelled:
        return Icons.not_interested;
    }
  }

  String _getAttendanceText(AttendanceStatus status) {
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

  void _showAttendanceOptions(StudentModel student, LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حضور ${student.name} - ${lecture.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAttendanceOption(student, lecture, AttendanceStatus.present),
            _buildAttendanceOption(student, lecture, AttendanceStatus.absent),
            _buildAttendanceOption(student, lecture, AttendanceStatus.late),
            _buildAttendanceOption(student, lecture, AttendanceStatus.expelled),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceOption(StudentModel student, LectureModel lecture, AttendanceStatus status) {
    final dateKey = DateFormat('yyyy-MM-dd').format(lecture.date);
    final currentStatus = _attendanceStatus[student.id!]?[dateKey] ?? AttendanceStatus.present;
    
    return ListTile(
      leading: Icon(_getAttendanceIcon(status), color: _getAttendanceColor(status)),
      title: Text(_getAttendanceText(status)),
      trailing: currentStatus == status ? const Icon(Icons.check, color: Colors.green) : null,
      onTap: () async {
        // تحديث الحالة في قاعدة البيانات
        await _saveAttendanceStatus(student, lecture, status);
        Navigator.pop(context);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم تحديث الحضور: ${student.name}')),
          );
        }
      },
    );
  }

  Future<void> _saveAttendanceStatus(StudentModel student, LectureModel lecture, AttendanceStatus status) async {
    try {
      final dateKey = DateFormat('yyyy-MM-dd').format(lecture.date);
      
      // تحديث الحالة في الذاكرة
      if (!_attendanceStatus.containsKey(student.id!)) {
        _attendanceStatus[student.id!] = {};
      }
      _attendanceStatus[student.id!]![dateKey] = status;
      
      // تحديث الحالة في قاعدة البيانات
      final attendance = AttendanceModel(
        studentId: student.id!,
        lectureId: lecture.id,
        date: lecture.date,
        status: status,
        notes: '',
        createdAt: DateTime.now(),
      );
      
      await _dbHelper.insertOrUpdateAttendance(attendance);
      
      // تحديث الإحصائيات
      await _loadStudentStats();
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error saving attendance status: $e');
    }
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

  Widget _buildAttendanceBox(StudentModel student, LectureModel lecture) {
    final dateKey = DateFormat('yyyy-MM-dd').format(lecture.date);
    final status = _attendanceStatus[student.id!]?[dateKey] ?? AttendanceStatus.present;
    
    return GestureDetector(
      onTap: () => _showAttendanceOptions(student, lecture),
      child: Container(
        width: 110,
        height: 70,
        decoration: BoxDecoration(
          color: _getAttendanceColor(status),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
          boxShadow: [
            BoxShadow(
              color: _getAttendanceColor(status).withOpacity(0.4),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getAttendanceIcon(status),
              size: 22,
              color: Colors.white,
            ),
            const SizedBox(height: 4),
            Text(
              _getAttendanceText(status),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // شريط التصنيف والبحث في الأعلى
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D), // أسود داكن
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF404040), // خط فاصل رمادي
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                // أيقونة التصنيف
                PopupMenuButton<SortType>(
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  tooltip: 'تصنيف',
                  onSelected: (SortType type) {
                    setState(() {
                      _sortType = type;
                    });
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: SortType.alphabetical,
                      child: Row(
                        children: [
                          Icon(Icons.sort_by_alpha),
                          SizedBox(width: 8),
                          Text('أبجدي'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: SortType.attendanceRate,
                      child: Row(
                        children: [
                          Icon(Icons.trending_up),
                          SizedBox(width: 8),
                          Text('نسبة الحضور'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: SortType.absenceRate,
                      child: Row(
                        children: [
                          Icon(Icons.trending_down),
                          SizedBox(width: 8),
                          Text('نسبة الغياب'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: SortType.gender,
                      child: Row(
                        children: [
                          Icon(Icons.wc),
                          SizedBox(width: 8),
                          Text('الجنس'),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                // شريط البحث
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
          
          // رؤوس المحاضرات
          Container(
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(
                bottom: BorderSide(
                  color: Color(0xFF404040),
                  width: 1,
                ),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              controller: _headerScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _lectures.length,
              itemBuilder: (context, index) {
                final lecture = _lectures[index];
                return Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('dd/MM').format(lecture.date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lecture.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          // قائمة الطلاب
          Expanded(
            child: Container(
              color: const Color(0xFF0D0D0D),
              child: ListView.builder(
                controller: _contentScrollController,
                itemCount: _students.length,
                itemBuilder: (context, index) {
                  final student = _students[index];
                  
                  // فلترة حسب البحث
                  if (_searchQuery.isNotEmpty && 
                      !student.name.toLowerCase().contains(_searchQuery)) {
                    return const SizedBox.shrink();
                  }
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF404040),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // صورة الطالب
                        Container(
                          width: 50,
                          height: 50,
                          margin: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF2D2D2D),
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
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
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        
                        // اسم الطالب
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  student.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                                if (student.phone != null)
                                  Text(
                                    student.phone!,
                                    style: const TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        
                        // مربعات الحضور
                        SizedBox(
                          height: 80,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _lectures.length,
                            itemBuilder: (context, lectureIndex) {
                              final lecture = _lectures[lectureIndex];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 2),
                                child: _buildAttendanceBox(student, lecture),
                              );
                            },
                          ),
                        ),
                        
                        // الإحصائيات
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: _buildStudentStats(student.id!),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

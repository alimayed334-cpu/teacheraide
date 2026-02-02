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
          final lecture = _lectures.where((l) => l.id == attendance.lectureId).firstOrNull;
          if (lecture != null) {
            final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
            _attendanceStatus[student.id!]![lectureKey] = attendance.status;
          }
        }
      } catch (e) {
        print('Error loading attendance for student ${student.id}: $e');
      }
    }
  }

  Future<void> _loadStudentStats() async {
    setState(() {
      _isLoadingStats = true;
    });
    
    final Map<int, Map<String, int>> stats = {};
    
    for (final student in _students) {
      try {
        final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
        stats[student.id!] = {
          'present': attendances.where((a) => a.status == AttendanceStatus.present).length,
          'absent': attendances.where((a) => a.status == AttendanceStatus.absent).length,
          'late': attendances.where((a) => a.status == AttendanceStatus.late).length,
          'expelled': attendances.where((a) => a.status == AttendanceStatus.expelled).length,
        };
      } catch (e) {
        stats[student.id!] = {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
      }
    }
    
    setState(() {
      _studentStats = stats;
      _isLoadingStats = false;
    });
    
    // تحميل حالة الطلاب في خطر
    await _checkAtRiskStudents();
  }

  Future<void> _checkAtRiskStudents() async {
    // تحميل المعايير من SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final int minMissedLectures = prefs.getInt('at_risk_min_missed_lectures') ?? 1;
    final double minAveragePercentage = prefs.getDouble('at_risk_min_average') ?? 50.0;
    final bool criteriaEnabled = prefs.getBool('at_risk_criteria_enabled') ?? true;
    
    final Map<int, bool> atRisk = {};
    
    // إذا كانت المعايير معطلة، جميع الطلاب ليسوا في خطر
    if (!criteriaEnabled) {
      for (final student in _students) {
        atRisk[student.id!] = false;
      }
      setState(() {
        _atRiskStudents = atRisk;
      });
      return;
    }
    
    // الحصول على معرفات المحاضرات في الفصل الحالي
    final lecturesInClass = await _dbHelper.getLecturesByClass(widget.classModel.id!);
    final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();
    
    // الحصول على امتحانات الفصل الحالي
    final examsInClass = await _dbHelper.getExamsByClass(widget.classModel.id!);
    final examNamesInClass = examsInClass.map((e) => e.title).toSet();
    
    for (final student in _students) {
      try {
        // حساب المحاضرات الغائبة للفصل الحالي فقط
        final allAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
        final attendances = allAttendances.where((a) => lectureIdsInClass.contains(a.lectureId)).toList();
        final missedLectures = attendances.where((a) => 
          a.status == AttendanceStatus.absent
        ).length;
        
        // حساب المعدل العام من امتحانات الفصل الحالي فقط
        final allGrades = await _dbHelper.getGradesByStudent(student.id!);
        final grades = allGrades.where((g) => examNamesInClass.contains(g.examName)).toList();
        
        final scoredGrades = grades.where((g) => 
          g.notes?.contains('غائب') != true &&
          g.notes?.contains('غش') != true &&
          g.notes?.contains('مفقودة') != true
        ).toList();
        
        double averagePercentage = 0.0;
        if (scoredGrades.isNotEmpty) {
          double totalPercentage = 0.0;
          int validExamCount = 0;
          
          for (final grade in scoredGrades) {
            // البحث عن الامتحان المطابق للحصول على الدرجة القصوى الصحيحة
            final matchingExam = examsInClass.where((e) => e.title == grade.examName).firstOrNull;
            
            if (matchingExam != null && matchingExam.maxScore > 0) {
              final percentage = (grade.score / matchingExam.maxScore) * 100;
              totalPercentage += percentage;
              validExamCount++;
            }
          }
          
          averagePercentage = validExamCount > 0 ? totalPercentage / validExamCount : 0.0;
        }
        
        // في صفحة الحضور: التحقق من المحاضرات الغائبة فقط
        final isAtRisk = missedLectures >= minMissedLectures;
        
        atRisk[student.id!] = isAtRisk;
      } catch (e) {
        atRisk[student.id!] = false;
      }
    }
    
    setState(() {
      _atRiskStudents = atRisk;
    });
  }

  void _saveComment(int studentId, String dateKey, String comment) {
    setState(() {
      if (!_studentComments.containsKey(studentId)) {
        _studentComments[studentId] = {};
      }
      _studentComments[studentId]![dateKey] = comment;
    });
  }

  void _showCommentDialog(int studentId, String dateKey, String currentComment) {
    final commentController = TextEditingController(text: currentComment);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إضافة تعليق'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            hintText: 'اكتب تعليقك هنا...',
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
              _saveComment(studentId, dateKey, commentController.text);
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showLectureOptions(LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات المحاضرة: ${lecture.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(lecture.date)}'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.note_add, color: Colors.blue),
              title: const Text('ملاحظة سريعة'),
              onTap: () {
                Navigator.pop(context);
                _showLectureNotesDialog(lecture);
              },
            ),
            ListTile(
              leading: const Icon(Icons.book, color: Colors.green),
              title: const Text('صفحة الملاحظات'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ClassNotesScreen(classModel: widget.classModel),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.assessment, color: Colors.blue),
              title: const Text('تقرير الحضور'),
              onTap: () {
                Navigator.pop(context);
                _showAttendanceReport(lecture);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.green),
              title: const Text('الحضور التلقائي'),
              onTap: () {
                Navigator.pop(context);
                _showAutoAttendanceOptions(lecture);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('تغيير تاريخ المحاضرة'),
              onTap: () {
                Navigator.pop(context);
                _showEditLectureDateDialog(lecture);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف المحاضرة'),
              onTap: () {
                Navigator.pop(context);
                _deleteLecture(lecture);
              },
            ),
          ],
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

  Future<void> _deleteLecture(LectureModel lecture) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف محاضرة "${lecture.title}"؟\nسيتم حذف جميع سجلات الحضور المتعلقة بها.'),
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
      try {
        // حذف سجلات الحضور المرتبطة بالمحاضرة باستخدام lecture_id
        final db = await _dbHelper.database;
        await db.delete(
          'attendance',
          where: 'lecture_id = ?',
          whereArgs: [lecture.id!],
        );
        
        // حذف المحاضرة
        await _dbHelper.deleteLecture(lecture.id!);
        
        // تحديث الواجهة
        setState(() {
          _lectures.remove(lecture);
        });
        
        // تحديث الإحصائيات
        await _loadStudentStats();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حذف محاضرة: ${lecture.title}')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في حذف المحاضرة: $e')),
          );
        }
      }
    }
  }

  Future<void> _addNewLectureWithDefaultAttendance(LectureModel newLecture) async {
    try {
      // إضافة المحاضرة الجديدة
      final id = await _dbHelper.insertLecture(newLecture);
      final savedLecture = newLecture.copyWith(id: id);
      
      // إضافة جميع الطلاب كحاضرين تلقائياً للمحاضرة الجديدة
      for (final student in _students) {
        final attendance = AttendanceModel(
          studentId: student.id!,
          lectureId: savedLecture.id, // Include lecture ID
          date: savedLecture.date,
          status: AttendanceStatus.present,
          notes: '',
          createdAt: DateTime.now(),
        );
        
        await _dbHelper.insertAttendance(attendance);
        
        // تحديث الحالة في الذاكرة باستخدام معرف المحاضرة الفريد
        final lectureKey = '${savedLecture.id}_${DateFormat('yyyy-MM-dd').format(savedLecture.date)}';
        if (!_attendanceStatus.containsKey(student.id!)) {
          _attendanceStatus[student.id!] = {};
        }
        _attendanceStatus[student.id!]![lectureKey] = AttendanceStatus.present;
      }
      
      // تحديث الإحصائيات بعد إضافة الحضور التلقائي
      await _loadStudentStats();
      
      setState(() {
        _lectures.add(savedLecture);
        _lectures.sort((a, b) => a.date.compareTo(b.date));
      });
      
      // التمرير التلقائي للمحاضرة الجديدة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_headerScrollController.hasClients && _lectures.isNotEmpty) {
          // حساب موقع المحاضرة الجديدة (آخر محاضرة)
          final scrollPosition = (_lectures.length - 1) * 148.0; // 140 عرض + 8 مسافة
          _headerScrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إضافة محاضرة: ${savedLecture.title} مع حضور تلقائي لجميع الطلاب')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إضافة المحاضرة: $e')),
        );
      }
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add, color: Colors.blue),
              title: const Text('إضافة طالب'),
              onTap: () {
                Navigator.pop(context);
                _showAddStudentDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.event, color: Colors.green),
              title: const Text('إضافة محاضرة'),
              onTap: () {
                Navigator.pop(context);
                _showAddLectureDialog();
              },
            ),
          ],
        ),
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
    ).then((result) {
      if (result == true) {
        _loadData(); // إعادة تحميل البيانات عند إضافة طالب جديد
        if (widget.onStudentAdded != null) {
          widget.onStudentAdded!();
        }
      }
    });
  }

  void _showAddLectureDialog() {
    final titleController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة محاضرة جديدة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان المحاضرة',
                  hintText: 'مثال: محاضرة 1',
                  border: OutlineInputBorder(),
                ),
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
                    setDialogState(() {
                      selectedDate = date;
                    });
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
              onPressed: () async {
                if (titleController.text.isNotEmpty) {
                  try {
                    // حفظ المحاضرة في قاعدة البيانات مع ربطها بالفصل
                    final newLecture = LectureModel(
                      classId: widget.classModel.id!,
                      title: titleController.text,
                      date: selectedDate,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    
                    // إغلاق الـ dialog أولاً
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    
                    // استخدام الدالة الجديدة التي تضيف حضور تلقائي
                    await _addNewLectureWithDefaultAttendance(newLecture);
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ في إضافة المحاضرة: $e')),
                      );
                    }
                  }
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('ترتيب حسب', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.sort_by_alpha),
              title: const Text('الترتيب الأبجدي'),
              selected: _sortType == SortType.alphabetical,
              onTap: () {
                setState(() => _sortType = SortType.alphabetical);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.trending_up),
              title: const Text('نسبة الحضور'),
              selected: _sortType == SortType.attendanceRate,
              onTap: () {
                setState(() => _sortType = SortType.attendanceRate);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.trending_down),
              title: const Text('نسبة الغياب'),
              selected: _sortType == SortType.absenceRate,
              onTap: () {
                setState(() => _sortType = SortType.absenceRate);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.wc),
              title: const Text('الجنس'),
              selected: _sortType == SortType.gender,
              onTap: () {
                setState(() => _sortType = SortType.gender);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  // حساب عدد الحضور للطالب
  Future<int> _getAttendanceCount(StudentModel student) async {
    final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
    return attendances.where((a) => a.status == AttendanceStatus.present).length;
  }

  // حساب عدد الغياب للطالب
  Future<int> _getAbsenceCount(StudentModel student) async {
    final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
    return attendances.where((a) => a.status == AttendanceStatus.absent).length;
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    // تطبيق البحث أولاً
    List<StudentModel> filtered = students;
    if (_searchQuery.isNotEmpty) {
      filtered = students.where((student) {
        return student.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }
    
    // ثم الترتيب
    final List<StudentModel> sorted = List.from(filtered);
    
    switch (_sortType) {
      case SortType.alphabetical:
        // ترتيب أبجدي
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
        
      case SortType.attendanceRate:
        // ترتيب تنازلي حسب نسبة الحضور (الأعلى أولاً)
        sorted.sort((a, b) {
          final aStats = _studentStats[a.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          
          final aPresent = aStats['present'] ?? 0;
          final bPresent = bStats['present'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) + (aStats['absent'] ?? 0) + (aStats['late'] ?? 0) + (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) + (bStats['absent'] ?? 0) + (bStats['late'] ?? 0) + (bStats['expelled'] ?? 0);
          
          final aRate = aTotal > 0 ? aPresent / aTotal : 0;
          final bRate = bTotal > 0 ? bPresent / bTotal : 0;
          
          // ترتيب تنازلي (الأعلى أولاً)
          return bRate.compareTo(aRate);
        });
        break;
        
      case SortType.absenceRate:
        // ترتيب تنازلي حسب نسبة الغياب (الأعلى أولاً)
        sorted.sort((a, b) {
          final aStats = _studentStats[a.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          
          final aAbsent = aStats['absent'] ?? 0;
          final bAbsent = bStats['absent'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) + (aStats['absent'] ?? 0) + (aStats['late'] ?? 0) + (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) + (bStats['absent'] ?? 0) + (bStats['late'] ?? 0) + (bStats['expelled'] ?? 0);
          
          final aRate = aTotal > 0 ? aAbsent / aTotal : 0;
          final bRate = bTotal > 0 ? bAbsent / bTotal : 0;
          
          // ترتيب تنازلي (الأعلى غياباً أولاً)
          return bRate.compareTo(aRate);
        });
        break;
        
      case SortType.gender:
        // ترتيب حسب الجنس (الذكور أولاً) ثم الأبجدية
        sorted.sort((a, b) {
          // يمكن تعديل هذا الجزء حسب حقل الجنس إذا كان موجوداً في النموذج
          return a.name.compareTo(b.name);
        });
        break;
    }
    
    return sorted;
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
        return Icons.block;
    }
  }

  Color _getAttendanceColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green;
      case AttendanceStatus.absent:
        return Colors.red;
      case AttendanceStatus.late:
        return Colors.yellow[700]!;
      case AttendanceStatus.expelled:
        return Colors.purple;
    }
  }

  String _getAttendanceText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'مطرود';
    }
  }

  void _showEditLectureDateDialog(LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تعديل تاريخ: ${lecture.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('التاريخ الحالي: ${DateFormat('dd/MM/yyyy').format(lecture.date)}'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: const Text('اختر تاريخ جديد'),
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: lecture.date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null && context.mounted) {
                  // تحديث المحاضرة في قاعدة البيانات
                  final updatedLecture = lecture.copyWith(
                    date: date,
                    updatedAt: DateTime.now(),
                  );
                  await _dbHelper.updateLecture(updatedLecture);
                  
                  setState(() {
                    final index = _lectures.indexOf(lecture);
                    _lectures[index] = updatedLecture;
                    _lectures.sort((a, b) => a.date.compareTo(b.date));
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث التاريخ')),
                  );
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
        ],
      ),
    );
  }

  Widget _buildAttendanceBox(StudentModel student, LectureModel lecture, AttendanceStatus currentStatus) {
    // الحصول على الحالة المحفوظة باستخدام معرف المحاضرة الفريد
    final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
    final status = _attendanceStatus[student.id!]?[lectureKey] ?? currentStatus;
    final comment = _studentComments[student.id!]?[lectureKey] ?? '';
    
    return GestureDetector(
      onTap: () => _showAttendanceOptions(student, lecture),
      child: Column(
        children: [
          // مربع الحضور الكبير
          Container(
            width: 110,
            height: 70,
            decoration: BoxDecoration(
              color: _getAttendanceColor(status),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _getAttendanceColor(status).withValues(alpha: 0.4),
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
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // خط للتعليق تحت المربع
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showCommentDialog(student.id!, lectureKey, comment),
            child: Container(
              width: 110,
              height: 20,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.grey.shade600, width: 0.5),
              ),
              child: Center(
                child: Text(
                  comment.isEmpty ? 'اكتب تعليق' : comment,
                  style: TextStyle(
                    fontSize: 8,
                    color: comment.isEmpty ? Colors.grey : Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAttendanceOptions(StudentModel student, LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تحديد حالة الحضور - ${student.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAttendanceOption(student, lecture, AttendanceStatus.present, '✅ حاضر', Colors.green),
            _buildAttendanceOption(student, lecture, AttendanceStatus.late, '⏰ متأخر', Colors.orange),
            _buildAttendanceOption(student, lecture, AttendanceStatus.expelled, '🚫 مطرود', Colors.purple),
            _buildAttendanceOption(student, lecture, AttendanceStatus.absent, '❌ غائب', Colors.red),
          ],
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

  Widget _buildAttendanceOption(StudentModel student, LectureModel lecture, AttendanceStatus status, String text, Color color) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            text.split(' ')[0], // Emoji only
            style: const TextStyle(fontSize: 20),
          ),
        ),
      ),
      title: Text(text.split(' ')[1]), // Text only
      onTap: () {
        Navigator.pop(context);
        _saveAttendanceStatus(student, lecture, status);
      },
    );
  }

  Future<void> _saveAttendanceStatus(StudentModel student, LectureModel lecture, AttendanceStatus status) async {
    try {
      // البحث عن سجل الحضور الحالي لهذا الطالب في هذه المحاضرة
      final existingAttendance = await _dbHelper.getAttendanceByStudentAndLecture(
        studentId: student.id!,
        lectureId: lecture.id!,
      );

      if (existingAttendance != null) {
        // تحديث سجل الحضور الموجود
        await _dbHelper.updateAttendance(
          existingAttendance.copyWith(
            status: status,
            date: lecture.date,
          ),
        );
      } else {
        // إنشاء سجل حضور جديد
        await _dbHelper.insertAttendance(AttendanceModel(
          studentId: student.id!,
          lectureId: lecture.id!, // Include lecture ID
          date: lecture.date,
          status: status,
          notes: '',
          createdAt: DateTime.now(),
        ));
      }

      // تحديث الحالة في الذاكرة فوراً باستخدام معرف المحاضرة الفريد
      if (mounted) {
        setState(() {
          final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
          if (!_attendanceStatus.containsKey(student.id!)) {
            _attendanceStatus[student.id!] = {};
          }
          _attendanceStatus[student.id!]![lectureKey] = status;
        });
        
        // تحديث الإحصائيات فوراً بعد تغيير الحالة
        await _updateSingleStudentStats(student.id!);
        
        // إعادة فحص الطلاب في خطر فوراً
        await _checkAtRiskStudents();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ حالة الحضور: $e')),
        );
      }
    }
  }

  Future<void> _updateSingleStudentStats(int studentId) async {
    try {
      final attendanceRecords = await _dbHelper.getAttendanceByStudent(studentId);
      
      int presentCount = 0;
      int absentCount = 0;
      int lateCount = 0;
      int expelledCount = 0;
      
      for (final record in attendanceRecords) {
        switch (record.status) {
          case AttendanceStatus.present:
            presentCount++;
            break;
          case AttendanceStatus.absent:
            absentCount++;
            break;
          case AttendanceStatus.late:
            lateCount++;
            break;
          case AttendanceStatus.expelled:
            expelledCount++;
            break;
        }
      }
      
      setState(() {
        _studentStats[studentId] = {
          'present': presentCount,
          'absent': absentCount,
          'late': lateCount,
          'expelled': expelledCount,
        };
      });
    } catch (e) {
      debugPrint('خطأ في تحديث إحصائيات الطالب: $e');
    }
  }

  Widget _buildSortChip(String label, SortType type) {
    final isSelected = _sortType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _sortType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStudentStats(int studentId) {
    final stats = _studentStats[studentId] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
    final presentCount = stats['present'] ?? 0;
    final absentCount = stats['absent'] ?? 0;
    final lateCount = stats['late'] ?? 0;
    final expelledCount = stats['expelled'] ?? 0;
    final totalLectures = presentCount + absentCount + lateCount + expelledCount;
    
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        // إحصائيات الحضور
        if (presentCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'حاضر $presentCount',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // إحصائيات الغياب
        if (absentCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'غائب $absentCount',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // إحصائيات التأخير
        if (lateCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'متأخر $lateCount',
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // إحصائيات الطرد
        if (expelledCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'مطرود $expelledCount',
              style: const TextStyle(
                color: Colors.purple,
                fontSize: 8,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        // نسبة الحضور الإجمالية
        if (totalLectures > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '%${((presentCount / totalLectures) * 100).toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
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
          
        // قائمة الطلاب والمحاضرات
        Expanded(
            child: Builder(
              builder: (context) {
                final students = _sortStudents(_students);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'لا يوجد طلاب في هذا الفصل',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    // صف العناوين والتواريخ في الأعلى
                    if (_lectures.isNotEmpty)
                      Container(
                        color: const Color(0xFF2D2D2D), // رمادي داكن
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 150,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2D2D2D),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text(
                                  'الطلاب',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            // خط فاصل رمادي
                            Container(
                              width: 3,
                              height: 80,
                              color: const Color(0xFF404040), // رمادي
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            // العناوين والتواريخ
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _headerScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _lectures.asMap().entries.map((entry) {
                                    final lecture = entry.value;
                                    final index = entry.key;
                                    return GestureDetector(
                                      onTap: () => _showLectureOptions(lecture),
                                      child: Container(
                                        width: 140,
                                        alignment: Alignment.center,
                                        margin: EdgeInsets.only(
                                          left: 8, // مسافة ثابتة ومتساوية بين جميع المربعات
                                          right: 0,
                                        ),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              lecture.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: Colors.blue, width: 0.5),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM/yyyy').format(lecture.date),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'محاضرة ${_lectures.indexOf(lecture) + 1}',
                                              style: const TextStyle(
                                                fontSize: 8,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // خط فاصل أفقي رمادي بين العناوين والطلاب
                    Container(
                      height: 3,
                      color: const Color(0xFF404040), // رمادي
                    ),
                    // قائمة الطلاب
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: students.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 3,
                          thickness: 3,
                          color: Color(0xFF404040),
                        ),
                        itemBuilder: (context, index) {
                          final student = students[index];
                          return Container(
                            color: const Color(0xFF2D2D2D), // رمادي داكن
                            // إعادة الهامش كما كان حتى تبقى الأعمدة (التواريخ/المحاضرات) مصطفّة
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                // معلومات الطالب في اليمين - خلفية داكنة
                                Container(
                                  width: 150,
                                  // إعادة الحواف المتساوية كما كانت حتى لا يتحرك محتوى المحاضرات
                                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2D2D2D),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // دائرة الطالب مع النقطة الحمراء
                                      Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 20,
                                            backgroundColor: Colors.white,
                                            backgroundImage: student.photo != null 
                                                ? AssetImage(student.photo!) 
                                                : null,
                                            child: student.photo == null 
                                                ? Text(
                                                    student.name[0],
                                                    style: const TextStyle(
                                                      color: Colors.black,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ) 
                                                : null,
                                          ),
                                          // نقطة حمراء للطلاب في خطر - على يسار الصورة
                                          if (_atRiskStudents[student.id] == true)
                                            Positioned(
                                              right: -10,
                                              top: -2,
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration: BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: const Color(0xFF2D2D2D),
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      // صف الطالب مع الصورة والأيقونة الصفراء
                                      Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // الصورة الشخصية مع الإطار
                                          Container(
                                            width: 40,
                                            height: 40,
                                            margin: const EdgeInsets.only(left: 4, right: 8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: const Color(0xFF2D2D2D),
                                                width: 2,
                                              ),
                                            ),
                                            child: CircleAvatar(
                                              radius: 16,
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
                                        ],
                                      ),
                                      
                                      // اسم الطالب والمعلومات
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => StudentDetailsScreen(student: student),
                                              ),
                                            );
                                          },
                                          child: Row(
                                            children: [
                                              // الأيقونة الصفراء (التحذيرية) - بجانب الاسم
                                              if (student.notes?.toLowerCase().contains('مخالفة') == true || 
                                                  student.notes?.toLowerCase().contains('تحذير') == true)
                                                Container(
                                                  margin: const EdgeInsets.only(left: 4, right: 6),
                                                  width: 8,
                                                  height: 8,
                                                  decoration: const BoxDecoration(
                                                    color: Colors.yellow,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                              // اسم الطالب في سطر واحد
                                              Expanded(
                                                child: Text(
                                                  student.name,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                    fontSize: 14,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // إحصائيات الطالب
                                      _buildStudentStats(student.id!),
                                            ],
                                          ),
                                        ),
                                      ),
                                      
                                      // زر الواجبات
                                      GestureDetector(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) => StudentAssignmentsScreen(
                                                student: student,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.amber,
                                            borderRadius: BorderRadius.circular(4),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.amber.withValues(alpha: 0.3),
                                                blurRadius: 2,
                                                offset: const Offset(0, 1),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.assignment,
                                            color: Colors.black,
                                            size: 16,
                                          ),
                                          padding: const EdgeInsets.all(4),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                // خط فاصل
                                Container(
                                  width: 3,
                                  height: 80,
                                  color: const Color(0xFF404040), // رمادي
                                  // تقليل الفراغ بين معلومات الطالب والخط الفاصل
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                // المحاضرات أفقياً - محاذاة مباشرة تحت التواريخ
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _contentScrollController,
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: _lectures.asMap().entries.map((entry) {
                                        final lecture = entry.value;
                                        final index = entry.key;
                                        // الحصول على الحالة المحفوظة باستخدام معرف المحاضرة الفريد
                                        final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
                                        final status = _attendanceStatus[student.id!]?[lectureKey] ?? AttendanceStatus.present;
                                        
                                        // مسافة متساوية بين جميع المربعات
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            left: 8, // مسافة ثابتة ومتساوية
                                            right: 0,
                                          ),
                                          child: Container(
                                            width: 140, // نفس عرض التاريخ في الأعلى
                                            child: _buildAttendanceBox(student, lecture, status),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }

  String _getSortTypeName() {
    switch (_sortType) {
      case SortType.alphabetical:
        return 'أبجدي';
      case SortType.attendanceRate:
        return 'نسبة الحضور';
      case SortType.absenceRate:
        return 'نسبة الغياب';
      case SortType.gender:
        return 'الجنس';
    }
  }

  // دالة عرض ملاحظات المحاضرة
  void _showLectureNotesDialog(LectureModel lecture) {
    final notesController = TextEditingController();
    notesController.text = _lectureNotes[lecture.id!] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ملاحظات المحاضرة: ${lecture.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(lecture.date)}'),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات المحاضرة',
                  hintText: 'اكتب ملاحظاتك حول هذه المحاضرة...',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
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
              try {
                // حفظ الملاحظة في قاعدة البيانات
                await _saveLectureNote(lecture.id!, notesController.text);
                
                setState(() {
                  _lectureNotes[lecture.id!] = notesController.text;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حفظ ملاحظات المحاضرة بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('خطأ في حفظ الملاحظة: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // دالة حفظ ملاحظة المحاضرة في قاعدة البيانات
  Future<void> _saveLectureNote(int lectureId, String noteContent) async {
    try {
      // البحث عن ملاحظة موجودة
      final existingNote = await _dbHelper.getNote('lecture', lectureId);
      
      if (noteContent.trim().isEmpty) {
        // حذف الملاحظة إذا كانت فارغة
        if (existingNote != null) {
          await _dbHelper.deleteNote(existingNote.id!);
        }
      } else {
        if (existingNote != null) {
          // تحديث الملاحظة الموجودة
          final updatedNote = existingNote.copyWith(
            content: noteContent.trim(),
            updatedAt: DateTime.now(),
          );
          await _dbHelper.updateNote(updatedNote);
        } else {
          // إضافة ملاحظة جديدة
          final newNote = NoteModel(
            classId: widget.classModel.id!,
            itemType: 'lecture',
            itemId: lectureId,
            content: noteContent.trim(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          );
          await _dbHelper.insertNote(newNote);
        }
      }
    } catch (e) {
      throw Exception('فشل في حفظ الملاحظة: $e');
    }
  }

  
  // دالة الحضور التلقائي
  void _showAutoAttendanceOptions(LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الحضور التلقائي: ${lecture.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('اختر حالة الحضور لجميع الطلاب:'),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('جميع الطلاب حاضرين'),
              onTap: () {
                _setAllStudentsAttendance(lecture, AttendanceStatus.present);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('جميع الطلاب غائبين'),
              onTap: () {
                _setAllStudentsAttendance(lecture, AttendanceStatus.absent);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('جميع الطلاب متأخرين'),
              onTap: () {
                _setAllStudentsAttendance(lecture, AttendanceStatus.late);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              title: const Text('جميع الطلاب مطرودين'),
              onTap: () {
                _setAllStudentsAttendance(lecture, AttendanceStatus.expelled);
                Navigator.pop(context);
              },
            ),
          ],
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

  // دالة تطبيق حالة الحضور على جميع الطلاب
  Future<void> _setAllStudentsAttendance(LectureModel lecture, AttendanceStatus status) async {
    final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
    
    for (final student in _students) {
      // تحديث الحالة في الذاكرة
      if (!_attendanceStatus.containsKey(student.id!)) {
        _attendanceStatus[student.id!] = {};
      }
      _attendanceStatus[student.id!]![lectureKey] = status;
      
      // حفظ في قاعدة البيانات
      await _dbHelper.insertAttendance(
        AttendanceModel(
          id: null,
          studentId: student.id!,
          lectureId: lecture.id!,
          status: status,
          date: lecture.date,
        ),
      );
    }
    
    _updateAttendance();
    
    String statusText = '';
    switch (status) {
      case AttendanceStatus.present:
        statusText = 'حاضرين';
        break;
      case AttendanceStatus.absent:
        statusText = 'غائبين';
        break;
      case AttendanceStatus.late:
        statusText = 'متأخرين';
        break;
      case AttendanceStatus.expelled:
        statusText = 'مطرودين';
        break;
    }
    
    // إظهار رسالة نجاح
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين حالة الحضور لجميع الطلاب إلى: $statusText'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // دالة تقرير الحضور PDF
  Future<void> _showAttendanceReport(LectureModel lecture) async {
    try {
        print('Starting attendance report generation for: ${lecture.title}');
        print('Step 1: Loading Arabic font...');
        
        // عرض مؤشر تحميل
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('جاري إنشاء تقرير PDF...'),
              ],
            ),
          ),
        );

        // التحقق من وجود بيانات
        if (_students.isEmpty) {
          print('No students found');
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد طلاب في هذا الفصل')),
          );
          return;
        }

        print('Found ${_students.length} students');

        // الحصول على بيانات الحضور للمحاضرة
        print('Step 2: Getting attendance data...');
        final List<AttendanceModel> allAttendances = [];
        for (final student in _students) {
          try {
            final studentAttendances = await _dbHelper.getAttendanceByStudent(student.id!);
            allAttendances.addAll(studentAttendances);
          } catch (e) {
            print('Error getting attendance for student ${student.id}: $e');
          }
        }
        final attendances = allAttendances.where((a) => a.lectureId == lecture.id).toList();
        
        // حساب عدد كل حالة
        int presentCount = attendances.where((a) => a.status == AttendanceStatus.present).length;
        int absentCount = attendances.where((a) => a.status == AttendanceStatus.absent).length;
        int lateCount = attendances.where((a) => a.status == AttendanceStatus.late).length;
        int expelledCount = attendances.where((a) => a.status == AttendanceStatus.expelled).length;

        print('Step 3: Creating PDF document...');
        // إنشاء ملف PDF
        final pdf = pw.Document();
        
        // إعداد الخط العربي - استخدام خط Noto Sans Arabic TTF مع خط احتياطي للرموز
        print('Step 4: Loading Arabic font from assets...');
        final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
        // تحميل خط احتياطي للرموز الخاصة والرياضيات
        final symbolFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
        print('Arabic font loaded successfully!');

        print('Step 5: Building PDF content...');
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            textDirection: pw.TextDirection.rtl,
            build: (pw.Context context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // العنوان العلوي
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'تقرير الحضور',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              ),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'الفصل: ${widget.classModel.name}',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 14,
                                color: PdfColors.white,
                              ),
                            ),
                            pw.Text(
                              'المحاضرة: ${lecture.title}',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: PdfColors.grey300,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildSymbolText(
                        DateFormat('yyyy/MM/dd').format(lecture.date),
                        arabicFont,
                        symbolFont,
                        fontSize: 12,
                        color: PdfColors.white,
                      ),
                    ],
                  ),
                ),
                
                pw.SizedBox(height: 20),
                
                // جدول حالات الحضور
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey50,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1), // حاضر
                      1: const pw.FlexColumnWidth(1), // غائب
                      2: const pw.FlexColumnWidth(1), // متأخر
                      3: const pw.FlexColumnWidth(1), // مطرود
                    },
                    children: [
                      // عنوان الأعمدة
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blue),
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'حاضر',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'غائب',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'متأخر',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              'مطرود',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: PdfColors.white,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                      // بيانات الإحصائيات
                      pw.TableRow(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '$presentCount',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 16,
                                color: PdfColors.green,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '$absentCount',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 16,
                                color: PdfColors.red,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '$lateCount',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 16,
                                color: PdfColors.orange,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              '$expelledCount',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 16,
                                color: PdfColors.purple,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                pw.SizedBox(height: 20),
                
                // الجدول الرئيسي
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3), // اسم الطالب
                    1: const pw.FlexColumnWidth(2), // رقم الطالب
                    2: const pw.FlexColumnWidth(1.5), // الحالة
                    3: const pw.FlexColumnWidth(2), // الملاحظات
                  },
                  children: [
                    // عنوان الأعمدة
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue),
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'اسم الطالب',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'رقم الطالب',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'الحالة',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            'ملاحظات',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    // بيانات الطلاب
                    ...attendances.asMap().entries.map((entry) {
                      final index = entry.key + 1;
                      final attendance = entry.value;
                      final student = _students.firstWhere(
                        (s) => s.id == attendance.studentId,
                        orElse: () => StudentModel(
                          id: attendance.studentId ?? 0,
                          name: 'طالب غير معروف',
                          classId: widget.classModel.id!,
                          studentId: 'غير معروف',
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ),
                      );
                      
                      final statusText = attendance.statusText;
                      final statusColor = attendance.status == AttendanceStatus.present ? PdfColors.green :
                                         attendance.status == AttendanceStatus.absent ? PdfColors.red :
                                         attendance.status == AttendanceStatus.late ? PdfColors.orange :
                                         PdfColors.purple;
                      
                      // الحصول على ملاحظات المحاضرة لهذا الطالب
                      final lectureNotes = _lectureNotes[lecture.id] ?? '';
                      final studentNotes = ''; // يمكن إضافة ملاحظات خاصة بالطالب لاحقاً
                      
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: index % 2 == 0 ? PdfColors.grey50 : PdfColors.white,
                        ),
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              student.name,
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 10,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              student.studentId ?? 'غير معروف',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 10,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              statusText,
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 10,
                                color: statusColor,
                                fontWeight: pw.FontWeight.bold,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text(
                              studentNotes.isNotEmpty ? studentNotes : lectureNotes,
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 9,
                                color: PdfColors.grey700,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          ),
        );

        print('Step 6: Saving PDF file...');
        // إغلاق مؤشر التحميل
        Navigator.pop(context);
        
        // حفظ الملف وفتحه مباشرة
        final String fileName = 'تقرير_حضور_${lecture.title}_${DateFormat('yyyy_MM_dd').format(lecture.date)}.pdf';
        final directory = await getApplicationDocumentsDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(await pdf.save());
        
        print('PDF saved to: ${file.path}');
        
        print('Step 7: Opening PDF for sharing...');
        // فتح الملف مباشرة
        await Printing.sharePdf(
          bytes: await pdf.save(),
          filename: fileName,
        );

        print('Step 8: Showing success message...');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم حفظ تقرير الحضور في: ${file.path}')),
        );
        print('✅ Attendance report generated successfully!');
      } catch (e) {
        print('❌ Error in attendance report: $e');
        print('Stack trace: ${StackTrace.current}');
        // إغلاق مؤشر التحميل إذا كان مفتوحاً
        try {
          Navigator.pop(context);
        } catch (_) {}
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e')),
        );
      }
  }

  // دالة مساعدة للنصوص التي تحتوي على رموز
  pw.Widget _buildSymbolText(String text, pw.Font arabicFont, pw.Font symbolFont, {double fontSize = 12, PdfColor? color}) {
    // استبدال الرموز ببدائل نصية تدعمها الخطوط العربية
    String processedText = text
        .replaceAll('/', '-');  // استخدام شرطة عادية بدلاً من الشرطة المائلة
    
    // استخدام الخط العربي للنص المعالج
    return pw.Text(
      processedText,
      style: pw.TextStyle(
        font: arabicFont,
        fontSize: fontSize,
        color: color ?? PdfColors.black,
      ),
    );
  }
}

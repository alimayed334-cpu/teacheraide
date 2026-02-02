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
          final lecture = _lectures.where((l) => l.id == attendance.lectureId).firstOrNull;
          if (lecture != null) {
            final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
            _attendanceStatus[student.id!]![lectureKey] = attendance.status;
          }
        }
      } catch (e) {
        debugPrint('Error loading attendance for student ${student.id}: $e');
      }
    }
  }

  Future<void> _loadStudentStats() async {
    if (!mounted) return;
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
    
    if (mounted) {
      setState(() {
        _studentStats = stats;
        _isLoadingStats = false;
      });
    }
    
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
      if (mounted) {
        setState(() {
          _atRiskStudents = atRisk;
        });
      }
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
    
    if (mounted) {
      setState(() {
        _atRiskStudents = atRisk;
      });
    }
  }

  void _saveComment(int studentId, String dateKey, String comment) {
    if (!mounted) return;
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
        if (mounted) {
          setState(() {
            _lectures.remove(lecture);
          });
        }
        
        // تحديث الإحصائيات
        await _loadStudentStats();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حذف محاضرة: ${lecture.title}')),
          );
        }
      } catch (e) {
        if (mounted) {
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
      final savedLecture = newLecture.copyWith(id: id, updatedAt: DateTime.now());
      
      // إضافة جميع الطلاب كحاضرين تلقائياً للمحاضرة الجديدة
      for (final student in _students) {
        final attendance = AttendanceModel(
          studentId: student.id!,
          lectureId: savedLecture.id,
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
      
      if (mounted) {
        setState(() {
          _lectures.add(savedLecture);
          _lectures.sort((a, b) => a.date.compareTo(b.date));
        });
      }
      
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
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إضافة محاضرة: ${savedLecture.title} مع حضور تلقائي لجميع الطلاب')),
        );
      }
    } catch (e) {
      if (mounted) {
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
                    if (mounted) {
                      Navigator.pop(context);
                    }
                    
                    // استخدام الدالة الجديدة التي تضيف حضور تلقائي
                    await _addNewLectureWithDefaultAttendance(newLecture);
                  } catch (e) {
                    if (mounted) {
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
        return Colors.orange;
      case AttendanceStatus.expelled:
        return Colors.purple;
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
                if (date != null && mounted) {
                  // تحديث المحاضرة في قاعدة البيانات
                  final updatedLecture = lecture.copyWith(
                    date: date,
                    updatedAt: DateTime.now(),
                  );
                  await _dbHelper.updateLecture(updatedLecture);
                  
                  if (mounted) {
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

  Widget _buildAttendanceBox(StudentModel student, LectureModel lecture) {
    // الحصول على الحالة المحفوظة باستخدام معرف المحاضرة الفريد
    final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
    final status = _attendanceStatus[student.id!]?[lectureKey] ?? AttendanceStatus.present;
    
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
    final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
    final currentStatus = _attendanceStatus[student.id!]?[lectureKey] ?? AttendanceStatus.present;
    
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
      final lectureKey = '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
      
      // تحديث الحالة في الذاكرة
      if (!_attendanceStatus.containsKey(student.id!)) {
        _attendanceStatus[student.id!] = {};
      }
      _attendanceStatus[student.id!]![lectureKey] = status;
      
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

  void _showLectureNotesDialog(LectureModel lecture) {
    final notesController = TextEditingController(text: _lectureNotes[lecture.id] ?? '');
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ملاحظات المحاضرة: ${lecture.title}'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظاتك هنا...',
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
              if (mounted) {
                setState(() {
                  _lectureNotes[lecture.id!] = notesController.text;
                });
              }
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showAutoAttendanceOptions(LectureModel lecture) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حضور تلقائي: ${lecture.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: const Text('جميع الحاضرين'),
              onTap: () {
                Navigator.pop(context);
                _setAllAttendance(lecture, AttendanceStatus.present);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.red),
              title: const Text('جميع الغائبين'),
              onTap: () {
                Navigator.pop(context);
                _setAllAttendance(lecture, AttendanceStatus.absent);
              },
            ),
            ListTile(
              leading: const Icon(Icons.access_time, color: Colors.orange),
              title: const Text('جميع المتأخرين'),
              onTap: () {
                Navigator.pop(context);
                _setAllAttendance(lecture, AttendanceStatus.late);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAllAttendance(LectureModel lecture, AttendanceStatus status) async {
    try {
      for (final student in _students) {
        await _saveAttendanceStatus(student, lecture, status);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تحديث جميع الطلاب: ${_getAttendanceText(status)}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث الحضور: $e')),
        );
      }
    }
  }

  void _showAttendanceReport(LectureModel lecture) {
    // Placeholder for attendance report functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ميزة تقرير الحضور قيد التطوير')),
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
                                        margin: const EdgeInsets.only(left: 8),
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
                                                color: const Color(0xFF404040),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                DateFormat('dd/MM').format(lecture.date),
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                ),
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
                    
                    // قائمة الطلاب
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _contentScrollController,
                        child: Column(
                          children: students.map((student) {
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
                                  if (_lectures.isNotEmpty)
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
                          }).toList(),
                        ),
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
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildStudentStats(int studentId) {
    final stats = _studentStats[studentId];
    if (stats == null) return const SizedBox();
    
    final total = (stats['present'] ?? 0) + (stats['absent'] ?? 0) + (stats['late'] ?? 0) + (stats['expelled'] ?? 0);
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
}

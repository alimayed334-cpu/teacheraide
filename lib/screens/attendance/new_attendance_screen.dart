import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
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
import '../students/student_gallery_screen.dart';
import '../../utils/image_picker_helper.dart';
import '../students/student_assignments_screen.dart';
import '../notes/class_notes_screen.dart';
import '../email/email_sending_screen.dart';
import '../messaging/messaging_screen.dart';
import '../../services/unified_student_status_service.dart';
import '../../utils/file_attachment_helper.dart';
import '../../services/student_list_order_service.dart';
import '../../services/latest_view_mode_service.dart';

enum SortType { alphabetical, attendanceRate, absenceRate, highestAverage, lowestAverage }

class NewAttendanceScreen extends StatefulWidget {
  final ClassModel classModel;
  final VoidCallback? onStudentAdded;
  final VoidCallback? onDataChanged;

  const NewAttendanceScreen({
    super.key,
    required this.classModel,
    this.onStudentAdded,
    this.onDataChanged,
  });

  @override
  State<NewAttendanceScreen> createState() => _NewAttendanceScreenState();
}

class _NewAttendanceScreenState extends State<NewAttendanceScreen>
    with WidgetsBindingObserver {
  //=== متغيرات التحكم ===
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();
  final Set<int> _selectedStudents = <int>{};
  String _searchQuery = '';
  bool _sortByLatest = false;

  final Map<int, ScrollController> _rowScrollControllers = {};
  bool _isSyncingHorizontalScroll = false;
  double _sharedHorizontalOffset = 0.0;

  StreamSubscription<bool>? _latestViewModeSub;

  //=== متغيرات الحالة ===
  List<LectureModel> _lectures = [];
  SortType _sortType = SortType.alphabetical;
  bool _isLoadingStats = false;
  bool _isDeletingMode = false;
  final Map<int, Map<String, int>> _lectureStats = {};
  final Map<int, String> _lectureNotes = {};
  // حالة الحضور: studentId -> {lectureKey: status}
  final Map<int, Map<String, AttendanceStatus>> _attendanceStatus = {};
  // ملاحظات الطلاب: studentId -> {lectureKey: comment}
  final Map<int, Map<String, String>> _studentComments = {};
  // إحصائيات الحضور: studentId -> {total: x, present: y, ...}
  Map<int, Map<String, int>> _studentStats = {};
  Map<int, double> _studentGradeAverages = {};
  // حالة الطلاب في خطر: studentId -> isAtRisk
  Map<int, bool> _atRiskStudents = {};

  StreamSubscription<StudentListOrderEvent>? _orderSub;
  StreamSubscription<StudentSortModeEvent>? _sortModeSub;
  List<int> _syncedStudentOrder = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _headerScrollController.addListener(_syncHeaderScroll);

    _loadSortPreference().then((_) {
      if (!mounted) return;
      _loadData();
      _loadComments();
      _checkAtRiskStudents();
    });

    _latestViewModeSub = LatestViewModeService.instance.changes.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _sortByLatest = enabled;
        _lectures.sort(
          (a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
        );
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classId = widget.classModel.id;
      if (classId != null) {
        _initStudentOrderSync(classId);
        _initSortModeSync(classId);
      }
    });

    // إضافة مستمع لتغييرات التركيز
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupFocusListener();
    });
  }

  Future<void> _initSortModeSync(int classId) async {
    final saved = await StudentListOrderService.instance.getSortMode(classId);
    if (!mounted) return;
    if (saved != null) {
      _applySortMode(saved.mode);
    }

    _sortModeSub?.cancel();
    _sortModeSub = StudentListOrderService.instance.sortModeChanges.listen((event) {
      if (!mounted) return;
      if (event.classId != classId) return;
      _applySortMode(event.mode);
    });
  }

  void _applySortMode(String mode) {
    final mapped = switch (mode) {
      'attendance_rate' => SortType.attendanceRate,
      'absence_rate' => SortType.absenceRate,
      'highest_average' => SortType.highestAverage,
      'lowest_average' => SortType.lowestAverage,
      _ => SortType.alphabetical,
    };

    if (!mounted) return;
    setState(() {
      _sortType = mapped;
    });

    if (mapped == SortType.highestAverage || mapped == SortType.lowestAverage) {
      _loadStudentGradeAverages();
    }
  }

  Future<void> _loadStudentGradeAverages() async {
    final students = Provider.of<StudentProvider>(context, listen: false).students;
    if (students.isEmpty) {
      if (!mounted) return;
      setState(() {
        _studentGradeAverages = {};
      });
      return;
    }

    final futures = <Future<void>>[];
    final map = <int, double>{};
    for (final s in students) {
      final sid = s.id;
      if (sid == null) continue;
      futures.add(() async {
        final avg = await _dbHelper.getStudentAverage(sid);
        map[sid] = avg;
      }());
    }

    await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      _studentGradeAverages = map;
    });
  }

  void _setupFocusListener() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // تحديث التعليقات عند العودة للصفحة
        _refreshCommentsOnResume();
      }
    });
  }

  Future<void> _loadSortPreference() async {
    final enabled = await LatestViewModeService.instance.getValue();
    if (!mounted) return;
    setState(() {
      _sortByLatest = enabled;
    });
  }

  Future<void> _setSortByLatest(bool value) async {
    await LatestViewModeService.instance.setValue(value);
    if (!mounted) return;
    setState(() {
      _sortByLatest = value;
      _lectures.sort(
        (a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
      );
    });
  }

  void _refreshCommentsOnResume() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _loadComments();
      }
    });
  }

  @override
  void dispose() {
    _latestViewModeSub?.cancel();
    _searchController.dispose();
    _headerScrollController.dispose();
    _contentScrollController.dispose();
    _orderSub?.cancel();
    _sortModeSub?.cancel();
    for (final c in _rowScrollControllers.values) {
      c.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // دالة عرض الصورة المكبرة
  void _showImageViewer(StudentModel student) {
    if (student.photoPath != null) {
      showImageViewer(context, student.photoPath!);
    } else if (student.photo != null) {
      // عرض صورة الشبكة إذا كانت موجودة
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.black54,
                ),
              ),
              Center(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      student.photo!,
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: MediaQuery.of(context).size.height * 0.8,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // إعادة فحص المعايير عند العودة للتطبيق
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshData(); // تحديث جميع البيانات
        _loadComments();
      });
    }
  }

  @override
  void didUpdateWidget(NewAttendanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعادة تحميل البيانات عند تغيير الفصل
    if (oldWidget.classModel.id != widget.classModel.id) {
      _orderSub?.cancel();
      _sortModeSub?.cancel();
      _syncedStudentOrder = const [];
      final classId = widget.classModel.id;
      if (classId != null) {
        _initStudentOrderSync(classId);
        _initSortModeSync(classId);
      }
      _loadData();
    } else {
      // تحديث جميع البيانات عند العودة للصفحة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshData();
        _loadComments();
      });
    }
  }

  Future<void> _initStudentOrderSync(int classId) async {
    final saved = await StudentListOrderService.instance.getOrder(classId);
    if (!mounted) return;
    if (saved != null) {
      setState(() {
        _syncedStudentOrder = saved.studentIds;
      });
    }

    _orderSub = StudentListOrderService.instance.changes.listen((event) {
      if (!mounted) return;
      if (event.classId != classId) return;
      setState(() {
        _syncedStudentOrder = event.studentIds;
      });
    });
  }

  Future<void> _publishCurrentStudentOrder() async {
    final classId = widget.classModel.id;
    if (classId == null) return;
    final students = Provider.of<StudentProvider>(context, listen: false).students;
    final sorted = _sortStudents(students, publish: false, applySyncedOrder: false);
    final ids = sorted.map((s) => s.id).whereType<int>().toList();
    await StudentListOrderService.instance.setOrder(classId: classId, studentIds: ids);
  }

  // دالة لتحديث البيانات عند العودة من صفحات أخرى
  Future<void> _refreshData() async {
    await _loadData();
    await _checkAtRiskStudents();
    await _loadStudentStats();
  }

  void _syncHeaderScroll() {
    if (_isSyncingHorizontalScroll) return;
    if (!_headerScrollController.hasClients) return;

    _sharedHorizontalOffset = _headerScrollController.offset;
    _isSyncingHorizontalScroll = true;
    for (final c in _rowScrollControllers.values) {
      if (!c.hasClients) continue;
      if (c.offset == _sharedHorizontalOffset) continue;
      c.jumpTo(_sharedHorizontalOffset);
    }
    _isSyncingHorizontalScroll = false;
  }

  void _syncContentScroll() {
    // لم يعد مستخدماً بعد تحويل السحب الأفقي إلى ScrollController لكل صف.
  }

  void _onRowHorizontalScroll(int studentId) {
    if (_isSyncingHorizontalScroll) return;
    final controller = _rowScrollControllers[studentId];
    if (controller == null || !controller.hasClients) return;

    _sharedHorizontalOffset = controller.offset;
    _isSyncingHorizontalScroll = true;

    if (_headerScrollController.hasClients &&
        _headerScrollController.offset != _sharedHorizontalOffset) {
      _headerScrollController.jumpTo(_sharedHorizontalOffset);
    }

    for (final entry in _rowScrollControllers.entries) {
      if (entry.key == studentId) continue;
      final c = entry.value;
      if (!c.hasClients) continue;
      if (c.offset == _sharedHorizontalOffset) continue;
      c.jumpTo(_sharedHorizontalOffset);
    }

    _isSyncingHorizontalScroll = false;
  }

  Future<void> _loadData() async {
    // تحميل الطلاب من Provider
    final studentProvider =
        Provider.of<StudentProvider>(context, listen: false);
    await studentProvider.loadStudentsByClass(widget.classModel.id!);

    // تحميل المحاضرات الخاصة بهذا الفصل فقط
    final lectures = await _dbHelper.getLecturesByClass(widget.classModel.id!);

    setState(() {
      // لا نخزن الطلاب محلياً، سنستخدمهم مباشرة من Provider
      _lectures = List<LectureModel>.from(lectures)
        ..sort(
          (a, b) => _sortByLatest
              ? b.date.compareTo(a.date)
              : a.date.compareTo(b.date),
        );
    });

    // تحميل جميع حالات الحضور من قاعدة البيانات
    await _loadAllAttendanceStatuses();

    // ضمان وجود سجلات حضور لكل طالب ولكل محاضرة (مهم بعد إضافة طالب جديد)
    await _ensureAttendanceRecordsForAllStudentsAndLectures();

    // حساب إحصائيات الحضور للفرز
    await _loadStudentStats();

    // فحص الطلاب في خطر
    await _checkAtRiskStudents();
  }

  Future<void> _loadAllAttendanceStatuses() async {
    _attendanceStatus.clear();

    for (final student
        in Provider.of<StudentProvider>(context, listen: false).students) {
      try {
        final attendances =
            await _dbHelper.getAttendancesByStudent(student.id!);
        if (!_attendanceStatus.containsKey(student.id!)) {
          _attendanceStatus[student.id!] = {};
        }

        for (final attendance in attendances) {
          final lecture =
              _lectures.where((l) => l.id == attendance.lectureId).firstOrNull;
          if (lecture != null) {
            final lectureKey =
                '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
            _attendanceStatus[student.id!]![lectureKey] = attendance.status;
          }
        }
      } catch (e) {
        debugPrint('Error loading attendance for student ${student.id}: $e');
      }
    }
  }

  Future<void> _ensureAttendanceRecordsForAllStudentsAndLectures() async {
    final students = Provider.of<StudentProvider>(context, listen: false).students;
    if (students.isEmpty || _lectures.isEmpty) return;

    for (final student in students) {
      final studentId = student.id;
      if (studentId == null) continue;

      _attendanceStatus[studentId] ??= {};

      for (final lecture in _lectures) {
        final lectureId = lecture.id;
        if (lectureId == null) continue;

        final lectureKey = '${lectureId}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';

        // إذا كان لدينا حالة محملة بالفعل، لا نلمسها
        if (_attendanceStatus[studentId]!.containsKey(lectureKey)) {
          continue;
        }

        try {
          final existing = await _dbHelper.getAttendanceByStudentAndLecture(
            studentId: studentId,
            lectureId: lectureId,
          );

          if (existing != null) {
            _attendanceStatus[studentId]![lectureKey] = existing.status;
            continue;
          }

          await _dbHelper.insertAttendance(
            AttendanceModel(
              studentId: studentId,
              lectureId: lectureId,
              date: lecture.date,
              status: AttendanceStatus.present,
              notes: '',
              createdAt: DateTime.now(),
            ),
          );

          _attendanceStatus[studentId]![lectureKey] = AttendanceStatus.present;
        } catch (e) {
          debugPrint('Error ensuring attendance for student $studentId lecture $lectureId: $e');
        }
      }
    }
  }

  Future<void> _loadStudentStats() async {
    setState(() {
      _isLoadingStats = true;
    });

    final Map<int, Map<String, int>> stats = {};

    for (final student
        in Provider.of<StudentProvider>(context, listen: false).students) {
      try {
        final attendances =
            await _dbHelper.getAttendancesByStudent(student.id!);
        stats[student.id!] = {
          'present': attendances
              .where((a) => a.status == AttendanceStatus.present)
              .length,
          'absent': attendances
              .where((a) => a.status == AttendanceStatus.absent)
              .length,
          'late': attendances
              .where((a) => a.status == AttendanceStatus.late)
              .length,
          'expelled': attendances
              .where((a) => a.status == AttendanceStatus.expelled)
              .length,
          'excused': attendances
              .where((a) => a.status == AttendanceStatus.excused)
              .length,
        };
      } catch (e) {
        stats[student.id!] = {
          'present': 0,
          'absent': 0,
          'late': 0,
          'expelled': 0,
          'excused': 0,
        };
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
    if (!mounted) return;
    // تحميل المعايير من SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final int minMissedLectures =
        prefs.getInt('at_risk_min_missed_lectures') ?? 1;
    final double minAveragePercentage =
        prefs.getDouble('at_risk_min_average') ?? 50.0;

    // المعايير الجديدة للتعطيل
    final bool featureEnabled =
        prefs.getBool('at_risk_feature_enabled') ?? true;
    final bool averageCriteriaEnabled =
        prefs.getBool('at_risk_average_enabled') ?? true;
    final bool missedExamsCriteriaEnabled =
        prefs.getBool('at_risk_missed_exams_enabled') ?? true;
    final bool missedLecturesCriteriaEnabled =
        prefs.getBool('at_risk_missed_lectures_enabled') ?? true;

    final Map<int, bool> atRisk = {};

    // الطريقة الأولى: التعطيل الكلي اليدوي
    if (!featureEnabled) {
      for (final student
          in Provider.of<StudentProvider>(context, listen: false).students) {
        atRisk[student.id!] = false;
      }
      if (!mounted) return;
      setState(() {
        _atRiskStudents = atRisk;
      });
      return;
    }

    // الطريقة الثانية: التعطيل التلقائي إذا جميع المعايير معطلة
    if (!averageCriteriaEnabled &&
        !missedExamsCriteriaEnabled &&
        !missedLecturesCriteriaEnabled) {
      for (final student
          in Provider.of<StudentProvider>(context, listen: false).students) {
        atRisk[student.id!] = false;
      }
      if (!mounted) return;
      setState(() {
        _atRiskStudents = atRisk;
      });
      return;
    }

    // الحصول على معرفات المحاضرات في الفصل الحالي
    final lecturesInClass =
        await _dbHelper.getLecturesByClass(widget.classModel.id!);
    final lectureIdsInClass = lecturesInClass.map((l) => l.id).toSet();

    // الحصول على امتحانات الفصل الحالي
    final examsInClass = await _dbHelper.getExamsByClass(widget.classModel.id!);
    final examNamesInClass = examsInClass.map((e) => e.title).toSet();

    for (final student
        in Provider.of<StudentProvider>(context, listen: false).students) {
      if (!mounted) return;
      try {
        // حساب المحاضرات الغائبة للفصل الحالي فقط
        final allAttendances =
            await _dbHelper.getAttendanceByStudent(student.id!);
        if (!mounted) return;
        final attendances = allAttendances
            .where((a) => lectureIdsInClass.contains(a.lectureId))
            .toList();
        final missedLectures = attendances
            .where((a) => a.status == AttendanceStatus.absent)
            .length;

        // حساب المعدل العام من امتحانات الفصل الحالي فقط
        final allGrades = await _dbHelper.getGradesByStudent(student.id!);
        if (!mounted) return;
        final grades = allGrades
            .where((g) => examNamesInClass.contains(g.examName))
            .toList();

        final scoredGrades = grades
            .where((g) =>
                g.notes?.contains('غائب') != true &&
                g.notes?.contains('غش') != true &&
                g.notes?.contains('مفقودة') != true)
            .toList();

        double averagePercentage = 0.0;
        if (scoredGrades.isNotEmpty) {
          double totalPercentage = 0.0;
          int validExamCount = 0;

          for (final grade in scoredGrades) {
            // البحث عن الامتحان المطابق للحصول على الدرجة القصوى الصحيحة
            final matchingExam = examsInClass
                .where((e) => e.title == grade.examName)
                .firstOrNull;

            if (matchingExam != null && matchingExam.maxScore > 0) {
              final percentage = (grade.score / matchingExam.maxScore) * 100;
              totalPercentage += percentage;
              validExamCount++;
            }
          }

          averagePercentage =
              validExamCount > 0 ? totalPercentage / validExamCount : 0.0;
        }

        // التحقق من المعايير المفعلة فقط
        bool isAtRisk = false;

        // معيار المحاضرات الغائبة
        if (missedLecturesCriteriaEnabled &&
            missedLectures >= minMissedLectures) {
          isAtRisk = true;
        }

        // معيار المعدل المنخفض
        if (averageCriteriaEnabled &&
            averagePercentage < minAveragePercentage) {
          isAtRisk = true;
        }

        // معيار الامتحانات الفائتة (يمكن إضافته لاحقاً)
        // if (missedExamsCriteriaEnabled && missedExams >= minMissedExams) {
        //   isAtRisk = true;
        // }

        atRisk[student.id!] = isAtRisk;
      } catch (e) {
        atRisk[student.id!] = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _atRiskStudents = atRisk;
    });
  }

  void _saveComment(int studentId, String dateKey, String comment) async {
    // حفظ في الذاكرة
    setState(() {
      if (!_studentComments.containsKey(studentId)) {
        _studentComments[studentId] = {};
      }
      _studentComments[studentId]![dateKey] = comment;
    });

    // حفظ في قاعدة البيانات
    try {
      final dbHelper = DatabaseHelper();
      // البحث عن سجل الحضور المطابق وتحديثه
      final attendances = await dbHelper.getAttendanceByStudent(studentId);
      for (var attendance in attendances) {
        final attendanceDateKey =
            DateFormat('yyyy-MM-dd').format(attendance.date);
        if (dateKey.contains(attendanceDateKey)) {
          await dbHelper.updateAttendance(attendance.copyWith(notes: comment));
          print(
              'Updated attendance in database: ${attendance.notes} -> $comment');

          // Use the correct key format: lectureId_studentId_date
          final finalKey = '${attendance.lectureId}_$studentId$dateKey';

          // حفظ في SharedPreferences
          try {
            final prefs = await SharedPreferences.getInstance();
            final commentsKey = 'student_comments_${widget.classModel.id}';
            final Map<String, String> allComments = Map<String, String>.from(
                prefs.getString(commentsKey) != null
                    ? Map<String, String>.fromEntries(
                        prefs.getString(commentsKey)!.split(',').map((e) {
                        final parts = e.split(':');
                        if (parts.length >= 2) {
                          return MapEntry(parts[0], parts.sublist(1).join(':'));
                        }
                        return MapEntry(parts[0], '');
                      }))
                    : {});
            allComments[finalKey] = comment;
            await prefs.setString(
                commentsKey,
                allComments.entries
                    .map((e) => '${e.key}:${e.value}')
                    .join(','));
            print('Saved to SharedPreferences: $finalKey -> $comment');
          } catch (e) {
            print('Error saving comment to SharedPreferences: $e');
          }

          // مزامنة مع جدول الملاحظات الرئيسي
          await _syncCommentToNotes(attendance.lectureId, comment);
          break;
        }
      }
    } catch (e) {
      print('Error saving comment: $e');
    }
  }

  // دالة مزامنة التعليقات مع جدول الملاحظات الرئيسي
  Future<void> _syncCommentToNotes(int? lectureId, String comment) async {
    if (lectureId == null) return;

    try {
      final dbHelper = DatabaseHelper();
      // البحث عن ملاحظة موجودة للمحاضرة
      final existingNote = await dbHelper.getNote('lecture', lectureId);

      if (existingNote != null) {
        // تحديث الملاحظة الموجودة
        final updatedNote = existingNote.copyWith(
          content: comment,
          updatedAt: DateTime.now(),
        );
        await dbHelper.updateNote(updatedNote);
        print('✅ Synced comment to notes table (updated): lecture_$lectureId');
      } else if (comment.isNotEmpty) {
        // إضافة ملاحظة جديدة إذا كان التعليق ليس فارغاً
        final newNote = NoteModel(
          classId: widget.classModel.id!,
          itemType: 'lecture',
          itemId: lectureId,
          content: comment,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await dbHelper.insertNote(newNote);
        print('✅ Synced comment to notes table (created): lecture_$lectureId');
      }
    } catch (e) {
      print('❌ Error syncing comment to notes: $e');
    }
  }

  Future<void> _loadComments() async {
    try {
      // تحميل من قاعدة البيانات أولاً
      final dbHelper = DatabaseHelper();
      final students =
          Provider.of<StudentProvider>(context, listen: false).students;

      setState(() {
        _studentComments.clear();
      });

      for (final student in students) {
        final attendances = await dbHelper.getAttendanceByStudent(student.id!);
        for (final attendance in attendances) {
          if (attendance.notes != null && attendance.notes!.isNotEmpty) {
            final dateKey = DateFormat('yyyy-MM-dd').format(attendance.date);
            setState(() {
              if (!_studentComments.containsKey(student.id!)) {
                _studentComments[student.id!] = {};
              }
              _studentComments[student.id!]![
                  '${attendance.lectureId}_$dateKey'] = attendance.notes!;
            });
          }
        }
      }

      // تحميل من SharedPreferences كنسخة احتياطية
      try {
        final prefs = await SharedPreferences.getInstance();
        final commentsKey = 'student_comments_${widget.classModel.id}';
        final commentsString = prefs.getString(commentsKey);

        if (commentsString != null) {
          final Map<String, String> allComments =
              Map<String, String>.fromEntries(
                  commentsString.split(',').map((e) {
            final parts = e.split(':');
            if (parts.length >= 2) {
              return MapEntry(parts[0], parts.sublist(1).join(':'));
            }
            return MapEntry(parts[0], '');
          }));

          setState(() {
            for (final entry in allComments.entries) {
              final parts = entry.key.split('_');
              if (parts.length >= 3) {
                // New format: lectureId_studentId_date
                final studentId = int.tryParse(parts[1]);
                final dateKey = parts.sublist(2).join('_');
                if (studentId != null) {
                  if (!_studentComments.containsKey(studentId)) {
                    _studentComments[studentId] = {};
                  }
                  _studentComments[studentId]![dateKey] = entry.value;
                }
              } else if (parts.length >= 2) {
                // Old format: studentId_date (for backward compatibility)
                final studentId = int.tryParse(parts[0]);
                final dateKey = parts.sublist(1).join('_');
                if (studentId != null) {
                  if (!_studentComments.containsKey(studentId)) {
                    _studentComments[studentId] = {};
                  }
                  _studentComments[studentId]![dateKey] = entry.value;
                }
              }
            }
          });
        }
      } catch (e) {
        print('Error loading SharedPreferences comments: $e');
      }
    } catch (e) {
      print('Error loading comments: $e');
    }
  }

  // إضافة method لتحديث التعليقات من الخارج
  void refreshComments() {
    _loadComments();
  }

  void _showCommentDialog(
      int studentId, String dateKey, String currentComment) {
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
                    builder: (context) =>
                        ClassNotesScreen(classModel: widget.classModel),
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
        content: Text(
            'هل تريد حذف محاضرة "${lecture.title}"؟\nسيتم حذف جميع سجلات الحضور المتعلقة بها.'),
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

        widget.onDataChanged?.call();

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

  Future<void> _addNewLectureWithDefaultAttendance(
      LectureModel newLecture) async {
    try {
      // إضافة المحاضرة الجديدة
      final id = await _dbHelper.insertLecture(newLecture);
      final savedLecture = newLecture.copyWith(id: id);

      // ضمان تحميل طلاب هذا الفصل قبل إنشاء سجلات الحضور الافتراضية
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.loadStudentsByClass(widget.classModel.id!);

      // إضافة جميع الطلاب كحاضرين تلقائياً للمحاضرة الجديدة
      for (final student
          in studentProvider.students) {
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
        final lectureKey =
            '${savedLecture.id}_${DateFormat('yyyy-MM-dd').format(savedLecture.date)}';
        if (!_attendanceStatus.containsKey(student.id!)) {
          _attendanceStatus[student.id!] = {};
        }
        _attendanceStatus[student.id!]![lectureKey] = AttendanceStatus.present;
      }

      // تحديث الإحصائيات بعد إضافة الحضور التلقائي
      await _loadStudentStats();

      widget.onDataChanged?.call();

      setState(() {
        _lectures.add(savedLecture);
        _lectures.sort(
          (a, b) => _sortByLatest
              ? b.date.compareTo(a.date)
              : a.date.compareTo(b.date),
        );
      });

      // التمرير التلقائي للمحاضرة الجديدة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_headerScrollController.hasClients && _lectures.isNotEmpty) {
          final newLectureIndex =
              _lectures.indexWhere((l) => l.id == savedLecture.id);
          if (newLectureIndex < 0) return;

          final scrollPosition = newLectureIndex * 148.0; // 140 عرض + 8 مسافة
          _headerScrollController.animateTo(
            scrollPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'تم إضافة محاضرة: ${savedLecture.title} مع حضور تلقائي لجميع الطلاب')),
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
                title: Text(
                    'التاريخ: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
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
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('تصنيف', style: TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.filter_list, color: Colors.white),
              onTap: () {},
            ),
            const Divider(height: 1, color: Color(0xFF404040)),
            ListTile(
              leading: Icon(
                Icons.sort,
                color: _sortByLatest ? Colors.yellow : Colors.grey,
              ),
              title: Text(
                'عرض البيانات حسب الأحدث',
                style: TextStyle(
                  color: _sortByLatest ? Colors.yellow : Colors.white,
                ),
              ),
              trailing: _sortByLatest
                  ? const Icon(Icons.check, color: Colors.yellow)
                  : null,
              onTap: () {
                Navigator.pop(context);
                _setSortByLatest(!_sortByLatest);
              },
            ),
            const Divider(height: 1, color: Color(0xFF404040)),
            ...SortType.values.map(
              (type) => ListTile(
                leading: Icon(_getSortTypeIcon(type), color: Colors.white),
                title: Text(
                  _getSortTypeNameForType(type),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: _sortType == type
                    ? const Icon(Icons.check, color: Colors.yellow)
                    : null,
                onTap: () {
                  setState(() {
                    _sortType = type;
                  });
                  Navigator.pop(context);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // حساب عدد الحضور للطالب
  Future<int> _getAttendanceCount(StudentModel student) async {
    final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
    return attendances
        .where((a) => a.status == AttendanceStatus.present)
        .length;
  }

  // حساب عدد الغياب للطالب
  Future<int> _getAbsenceCount(StudentModel student) async {
    final attendances = await _dbHelper.getAttendancesByStudent(student.id!);
    return attendances.where((a) => a.status == AttendanceStatus.absent).length;
  }

  List<StudentModel> _sortStudents(
    List<StudentModel> students, {
    bool publish = true,
    bool applySyncedOrder = true,
  }) {
    // تطبيق البحث أولاً
    List<StudentModel> filtered = students;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      final qDigits = q.replaceAll(RegExp(r'[^0-9]'), '');

      filtered = students.where((student) {
        final nameMatch = student.name.toLowerCase().contains(q);

        final idMatch = qDigits.isNotEmpty && (
            (student.id?.toString().contains(qDigits) ?? false) ||
            ((student.studentId ?? '').contains(qDigits))
          );

        return nameMatch || idMatch;
      }).toList();
    }

    // الترتيب المتزامن (من أي شاشة) يصبح هو الترتيب الحاكم.
    final List<StudentModel> base = List.from(filtered);

    // ثم الترتيب المحلي (فقط إذا لا يوجد ترتيب متزامن)
    switch (_sortType) {
      case SortType.alphabetical:
        // ترتيب أبجدي
        base.sort((a, b) => a.name.compareTo(b.name));
        break;

      case SortType.attendanceRate:
        // ترتيب تنازلي حسب نسبة الحضور (الأعلى أولاً)
        base.sort((a, b) {
          final aStats = _studentStats[a.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aPresent = aStats['present'] ?? 0;
          final bPresent = bStats['present'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aPresent / aTotal : 0;
          final bRate = bTotal > 0 ? bPresent / bTotal : 0;

          // ترتيب تنازلي (الأعلى أولاً)
          return bRate.compareTo(aRate);
        });
        break;

      case SortType.absenceRate:
        // ترتيب تنازلي حسب نسبة الغياب (الأعلى أولاً)
        base.sort((a, b) {
          final aStats = _studentStats[a.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aAbsent = aStats['absent'] ?? 0;
          final bAbsent = bStats['absent'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aAbsent / aTotal : 0;
          final bRate = bTotal > 0 ? bAbsent / bTotal : 0;

          // ترتيب تنازلي (الأعلى غياباً أولاً)
          return bRate.compareTo(aRate);
        });
        break;

      case SortType.highestAverage:
        base.sort((a, b) {
          final aAvg = _studentGradeAverages[a.id ?? -1] ?? 0.0;
          final bAvg = _studentGradeAverages[b.id ?? -1] ?? 0.0;
          return bAvg.compareTo(aAvg);
        });
        break;

      case SortType.lowestAverage:
        base.sort((a, b) {
          final aAvg = _studentGradeAverages[a.id ?? -1] ?? 0.0;
          final bAvg = _studentGradeAverages[b.id ?? -1] ?? 0.0;
          return aAvg.compareTo(bAvg);
        });
        break;
    }

    if (publish) {
      // publish is controlled by callers (we don't want to write prefs on every build).
    }

    return base;
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
      case AttendanceStatus.excused:
        return Icons.assignment_turned_in;
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
      case AttendanceStatus.excused:
        return Colors.white;
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
      case AttendanceStatus.excused:
        return 'مجاز';
    }
  }

  Future<void> _updateAttendanceDates(
      LectureModel oldLecture, LectureModel newLecture) async {
    try {
      // الحصول على جميع سجلات الحضور للمحاضرة القديمة
      final attendances =
          await _dbHelper.getAttendancesByLectureId(oldLecture.id!);

      // تحديث تاريخ كل سجل حضور
      for (final attendance in attendances) {
        final updatedAttendance = attendance.copyWith(
          date: newLecture.date,
        );
        await _dbHelper.updateAttendance(updatedAttendance);
      }

      // تحديث الحالة في الذاكرة
      for (final student
          in Provider.of<StudentProvider>(context, listen: false).students) {
        if (_attendanceStatus.containsKey(student.id!)) {
          final oldLectureKey =
              '${oldLecture.id}_${DateFormat('yyyy-MM-dd').format(oldLecture.date)}';
          final newLectureKey =
              '${newLecture.id}_${DateFormat('yyyy-MM-dd').format(newLecture.date)}';

          if (_attendanceStatus[student.id!]!.containsKey(oldLectureKey)) {
            _attendanceStatus[student.id!]![newLectureKey] =
                _attendanceStatus[student.id!]![oldLectureKey]!;
            _attendanceStatus[student.id!]!.remove(oldLectureKey);
          }

          // تحديث التعليقات أيضاً
          if (_studentComments.containsKey(student.id!)) {
            if (_studentComments[student.id!]!.containsKey(oldLectureKey)) {
              _studentComments[student.id!]![newLectureKey] =
                  _studentComments[student.id!]![oldLectureKey]!;
              _studentComments[student.id!]!.remove(oldLectureKey);
            }
          }
        }
      }
    } catch (e) {
      print('Error updating attendance dates: $e');
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
            Text(
                'التاريخ الحالي: ${DateFormat('dd/MM/yyyy').format(lecture.date)}'),
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

                  // تحديث جميع سجلات الحضور المتعلقة بهذه المحاضرة
                  await _updateAttendanceDates(lecture, updatedLecture);

                  // إعادة تحميل البيانات لتحديث التقويم
                  setState(() {
                    _loadData();
                  });

                  setState(() {
                    final index = _lectures.indexOf(lecture);
                    _lectures[index] = updatedLecture;
                    _lectures.sort(
                      (a, b) => _sortByLatest
                          ? b.date.compareTo(a.date)
                          : a.date.compareTo(b.date),
                    );
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تحديث المحاضرة')),
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

  Widget _buildAttendanceBox(StudentModel student, LectureModel lecture,
      AttendanceStatus currentStatus) {
    // الحصول على الحالة المحفوظة باستخدام معرف المحاضرة الفريد
    final lectureKey =
        '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
    // تعريف المتغير status بشكل صحيح
    final AttendanceStatus status =
        _attendanceStatus[student.id!]?[lectureKey] ?? currentStatus;
    final comment = _studentComments[student.id!]?[lectureKey] ?? '';

    final Color boxColor =
        status == AttendanceStatus.excused ? Colors.white : _getAttendanceColor(status);
    final Color contentColor =
        status == AttendanceStatus.excused ? Colors.black : Colors.white;
    final Color borderColor = status == AttendanceStatus.excused
        ? Colors.grey.withOpacity(0.6)
        : Colors.white.withOpacity(0.3);

    return GestureDetector(
      onTap: () => _showAttendanceOptions(student, lecture),
      child: Column(
        children: [
          // مربع الحضور الكبير
          Container(
            width: 110,
            height: 70,
            decoration: BoxDecoration(
              color: boxColor,
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: borderColor, width: 1),
              boxShadow: [
                BoxShadow(
                  color: boxColor.withOpacity(0.4),
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
                  color: contentColor,
                ),
                const SizedBox(height: 4),
                Text(
                  _getAttendanceText(status),
                  style: TextStyle(
                    color: contentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // عرض التعليق إذا وجد مع إمكانية التعديل
          if (comment.isNotEmpty)
            GestureDetector(
              onTap: () => _showCommentDialog(student.id!, lectureKey, comment),
              child: Container(
                width: 110,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.withOpacity(0.5)),
                ),
                child: Text(
                  comment,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          // مربع إضافة تعليق فقط
          if (comment.isEmpty)
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
                child: const Center(
                  child: Text(
                    'اكتب تعليق',
                    style: TextStyle(
                      fontSize: 8,
                      color: Colors.grey,
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
            _buildAttendanceOption(student, lecture, AttendanceStatus.present,
                '✅ حاضر', Colors.green),
            _buildAttendanceOption(student, lecture, AttendanceStatus.late,
                '⏰ متأخر', Colors.orange),
            _buildAttendanceOption(student, lecture, AttendanceStatus.excused,
                '🟦 مجاز', Colors.blue),
            _buildAttendanceOption(student, lecture, AttendanceStatus.expelled,
                '🚫 مطرود', Colors.purple),
            _buildAttendanceOption(student, lecture, AttendanceStatus.absent,
                '❌ غائب', Colors.red),
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

  Widget _buildAttendanceOption(StudentModel student, LectureModel lecture,
      AttendanceStatus status, String text, Color color) {
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

  Future<void> _saveAttendanceStatus(StudentModel student, LectureModel lecture,
      AttendanceStatus status) async {
    try {
      // البحث عن سجل الحضور الحالي لهذا الطالب في هذه المحاضرة
      final existingAttendance =
          await _dbHelper.getAttendanceByStudentAndLecture(
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
          final lectureKey =
              '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
          if (!_attendanceStatus.containsKey(student.id!)) {
            _attendanceStatus[student.id!] = {};
          }
          _attendanceStatus[student.id!]![lectureKey] = status;
        });

        // تحديث الإحصائيات فوراً بعد تغيير الحالة
        await _updateSingleStudentStats(student.id!);

        // إعادة فحص الطلاب في خطر فوراً
        await _checkAtRiskStudents();

        widget.onDataChanged?.call();
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
      final attendanceRecords =
          await _dbHelper.getAttendanceByStudent(studentId);

      int presentCount = 0;
      int absentCount = 0;
      int lateCount = 0;
      int expelledCount = 0;
      int excusedCount = 0;

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
          case AttendanceStatus.excused:
            excusedCount++;
            break;
        }
      }

      setState(() {
        _studentStats[studentId] = {
          'present': presentCount,
          'absent': absentCount,
          'late': lateCount,
          'expelled': expelledCount,
          'excused': excusedCount,
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
        _publishCurrentStudentOrder();
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
    final stats = _studentStats[studentId] ??
        {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0, 'excused': 0};
    final presentCount = stats['present'] ?? 0;
    final absentCount = stats['absent'] ?? 0;
    final lateCount = stats['late'] ?? 0;
    final expelledCount = stats['expelled'] ?? 0;
    final excusedCount = stats['excused'] ?? 0;
    final totalLectures =
        presentCount + absentCount + lateCount + expelledCount + excusedCount;

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

        if (excusedCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'مجاز $excusedCount',
              style: const TextStyle(
                color: Colors.blue,
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
                PopupMenuButton<String>(
                  icon: const Icon(Icons.filter_list, color: Colors.white, size: 20),
                  tooltip: 'تصنيف',
                  onSelected: (value) {
                    if (value == 'latest') {
                      _setSortByLatest(!_sortByLatest);
                      return;
                    }

                    final type = SortType.values.firstWhere(
                      (t) => 'type_${t.name}' == value,
                      orElse: () => _sortType,
                    );

                    setState(() {
                      _sortType = type;
                    });
                    final classId = widget.classModel.id;
                    if (classId != null) {
                      final mode = switch (type) {
                        SortType.attendanceRate => 'attendance_rate',
                        SortType.absenceRate => 'absence_rate',
                        SortType.highestAverage => 'highest_average',
                        SortType.lowestAverage => 'lowest_average',
                        SortType.alphabetical => 'name',
                      };
                      StudentListOrderService.instance.setSortMode(classId: classId, mode: mode);
                    }
                    if (type == SortType.highestAverage || type == SortType.lowestAverage) {
                      _loadStudentGradeAverages();
                    }
                  },
                  itemBuilder: (context) {
                    final items = <PopupMenuEntry<String>>[];

                    items.add(
                      PopupMenuItem<String>(
                        value: 'latest',
                        child: Row(
                          children: [
                            Icon(
                              Icons.check,
                              size: 18,
                              color: _sortByLatest ? Colors.yellow : Colors.transparent,
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.schedule, size: 18),
                            const SizedBox(width: 8),
                            const Text('عرض المحاضرات والامتحانات حسب الأحدث'),
                          ],
                        ),
                      ),
                    );

                    for (final type in SortType.values) {
                      items.add(
                        PopupMenuItem<String>(
                          value: 'type_${type.name}',
                          child: Row(
                            children: [
                              Icon(
                                Icons.check,
                                size: 18,
                                color: _sortType == type ? Colors.yellow : Colors.transparent,
                              ),
                              const SizedBox(width: 8),
                              Icon(_getSortTypeIcon(type), size: 18),
                              const SizedBox(width: 8),
                              Text(_getSortTypeNameForType(type)),
                            ],
                          ),
                        ),
                      );
                    }

                    return items;
                  },
                ),
                const SizedBox(width: 12),
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
                        hintText: 'بحث بالاسم أو الرقم...',
                        hintStyle: TextStyle(color: Colors.grey),
                        prefixIcon:
                            Icon(Icons.search, size: 20, color: Colors.white),
                        border: InputBorder.none,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
            child: Consumer<StudentProvider>(
              builder: (context, studentProvider, child) {
                final students = _sortStudents(studentProvider.students);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline,
                            size: 80, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'لا يوجد طلاب في هذا الفصل',
                          style:
                              TextStyle(fontSize: 18, color: Colors.grey[600]),
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
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 8),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 200,
                              height: 80,
                              decoration: BoxDecoration(
                                color: Colors.yellow.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.yellow,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  // أيقونة المراسلة
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              StudentGalleryScreen(
                                                  classId:
                                                      widget.classModel.id!),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.photo_library,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  // أيقونة التعديل
                                  GestureDetector(
                                    onTap: _showEditMenu,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  // أيقونة الترتيب
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const MessagingScreen(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.message,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // خط فاصل رمادي
                            Container(
                              width: 3,
                              height: 80,
                              color: const Color(0xFF404040), // رمادي
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            // العناوين - المحاضرة والتاريخ في عمود واحد
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _headerScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children:
                                      _lectures.asMap().entries.map((entry) {
                                    final lecture = entry.value;
                                    final index = entry.key;
                                    return GestureDetector(
                                      onTap: () => _showLectureOptions(lecture),
                                      child: Container(
                                        width: 140,
                                        alignment: Alignment.center,
                                        margin: EdgeInsets.only(
                                          left:
                                              8, // مسافة ثابتة ومتساوية بين جميع المربعات
                                          right: 0,
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            // العنوان في الأعلى
                                            Text(
                                              lecture.title,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            // التاريخ تحت العنوان
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
                                                  fontSize: 12,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'المحاضرة ${_lectures.indexOf(lecture) + 1}',
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
                          final rowController = _rowScrollControllers.putIfAbsent(
                            student.id!,
                            () {
                              final c = ScrollController(initialScrollOffset: _sharedHorizontalOffset);
                              c.addListener(() => _onRowHorizontalScroll(student.id!));
                              return c;
                            },
                          );
                          return Column(
                            children: [
                              // المحتوى الرئيسي
                              Container(
                                color: const Color(0xFF2D2D2D), // رمادي داكن
                                // إعادة الهامش كما كان حتى تبقى الأعمدة (التواريخ/المحاضرات) مصطفّة
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 8),
                                child: Row(
                                  children: [
                                    // معلومات الطالب في اليمين - خلفية داكنة
                                    Container(
                                      width:
                                          200, // زيادة العرض لإظهار الاسم بشكل أفضل
                                      padding:
                                          const EdgeInsets.fromLTRB(8, 12, 8, 12),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (_isDeletingMode) ...[
                                            GestureDetector(
                                              onTap: () => _toggleStudentSelection(
                                                student.id!,
                                              ),
                                              child: Container(
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  color: Colors.transparent,
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                    color: _selectedStudents
                                                            .contains(student.id!)
                                                        ? Colors.red
                                                        : Colors.grey,
                                                    width: 2,
                                                  ),
                                                ),
                                                child: _selectedStudents
                                                        .contains(student.id!)
                                                    ? const Center(
                                                        child: Icon(
                                                          Icons.close,
                                                          color: Colors.red,
                                                          size: 16,
                                                        ),
                                                      )
                                                    : null,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                          ],
                                          // دائرة الطالب مع النقطة الحمراء
                                          Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.center,
                                            children: [
                                              GestureDetector(
                                                onTap: () {
                                                  if (student.photoPath != null ||
                                                      student.photo != null) {
                                                    _showImageViewer(student);
                                                  }
                                                },
                                                child: CircleAvatar(
                                                  radius: 20,
                                                  backgroundColor: Colors.white,
                                                  backgroundImage: student
                                                              .photoPath !=
                                                          null
                                                      ? FileImage(File(
                                                          student.photoPath!))
                                                      as ImageProvider
                                                      : student.photo != null
                                                          ? AssetImage(
                                                              student.photo!)
                                                          : null,
                                                  child: student.photoPath ==
                                                              null &&
                                                      student.photo == null
                                                  ? Text(
                                                      student.name.isNotEmpty
                                                          ? student.name[0]
                                                          : '?',
                                                      style: const TextStyle(
                                                        color: Colors.black,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize:
                                                            18, // زيادة حجم الحرف الأول
                                                      ),
                                                    )
                                                  : null,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(width: 2),
                                          // اسم الطالب والمعلومات
                                          Expanded(
                                            child: GestureDetector(
                                              onTap: () {
                                                if (_isDeletingMode) {
                                                  _toggleStudentSelection(student.id!);
                                                  return;
                                                }

                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        StudentDetailsScreen(
                                                            student: student),
                                                  ),
                                                ).then((_) {
                                                  // تحديث التعليقات عند العودة من صفحة تفاصيل الطالب
                                                  _loadComments();
                                                });
                                              },
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  // الأيقونة الصفراء (التحذيرية) - بجانب الاسم
                                                  if (student.notes
                                                              ?.toLowerCase()
                                                              .contains('مخالفة') ==
                                                          true ||
                                                      student.notes
                                                              ?.toLowerCase()
                                                              .contains('تحذير') ==
                                                          true)
                                                    Container(
                                                      margin: const EdgeInsets.only(
                                                          left: 4, right: 6),
                                                      width: 8,
                                                      height: 8,
                                                      decoration:
                                                          const BoxDecoration(
                                                        color: Colors.yellow,
                                                        shape: BoxShape.circle,
                                                      ),
                                                    ),
                                                  // النجمة أو النقطة الحمراء للطالب (أمام الاسم مباشرة)
                                                  _buildStudentStatusIndicator(student),
                                                  const SizedBox(width: 4),
                                                  // اسم الطالب في سطر واحد
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          student.name.isNotEmpty
                                                              ? student.name
                                                              : 'اسم غير محدد',
                                                          style: const TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            fontSize:
                                                                14, // تقليل حجم الخط ليطابق الامتحانات
                                                            fontFamily:
                                                                '', // إضافة خط عربي
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.visible,
                                                          textAlign: TextAlign
                                                              .right, // محاذاة لليمين
                                                        ),
                                                        if ((student.studentId ?? '').trim().isNotEmpty)
                                                          Padding(
                                                            padding: const EdgeInsets.only(top: 2),
                                                            child: Text(
                                                              'رقم: ${student.studentId}',
                                                              style: const TextStyle(
                                                                color: Colors.white70,
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w500,
                                                              ),
                                                            ),
                                                          ),
                                                        // إحصائيات الطالب تحت الاسم
                                                        const SizedBox(height: 4),
                                                        _buildStudentStats(
                                                            student.id!),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  SizedBox(
                                                    width: 44,
                                                    child: Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Material(
                                                        color: Colors.yellow,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                        child: InkWell(
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          onTap: () async {
                                                            await Navigator
                                                                .push(
                                                              context,
                                                              MaterialPageRoute(
                                                                builder:
                                                                    (context) =>
                                                                        StudentAssignmentsScreen(
                                                                  student:
                                                                      student,
                                                                  classModel: widget
                                                                      .classModel,
                                                                ),
                                                              ),
                                                            );
                                                            if (!mounted)
                                                              return;
                                                            await _refreshData();
                                                            _loadComments();
                                                            if (!mounted)
                                                              return;
                                                            Provider.of<StudentProvider>(
                                                                    context,
                                                                    listen:
                                                                        false)
                                                                .refreshIndicators();
                                                          },
                                                          child: const SizedBox(
                                                            width: 36,
                                                            height: 36,
                                                            child: Icon(
                                                              Icons.assignment,
                                                              size: 22,
                                                              color:
                                                                  Colors.black,
                                                            ),
                                                          ),
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
                                    // الخط الفاصل
                                    Container(
                                      width: 3,
                                      height: 80,
                                      color: const Color(0xFF404040),
                                      margin:
                                          const EdgeInsets.symmetric(horizontal: 8),
                                    ),

                                    // مربعات الحضور
                                    Expanded(
                                      child: SingleChildScrollView(
                                        controller: rowController,
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: _lectures
                                              .asMap()
                                              .entries
                                              .map((entry) {
                                            final lecture = entry.value;
                                            final index = entry.key;
                                            final lectureKey =
                                                '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
                                            final status =
                                                _attendanceStatus[student.id!]
                                                        ?[lectureKey] ??
                                                    AttendanceStatus.present;

                                            return Padding(
                                              padding:
                                                  const EdgeInsets.only(left: 8),
                                              child: SizedBox(
                                                width: 140,
                                                child: _buildAttendanceBox(
                                                    student, lecture, status),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
      bottomNavigationBar: _isDeletingMode
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E1E),
                border: Border(
                  top: BorderSide(color: Color(0xFF404040), width: 2),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _toggleDeleteMode,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.grey),
                          foregroundColor: Colors.grey,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedStudents.isEmpty
                            ? null
                            : _deleteSelectedStudents,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          'حذف (${_selectedStudents.length})',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }

  // عرض رسالة
  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // عرض قائمة التعديل
  void _showEditMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'خيارات التعديل',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الطالب',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _toggleDeleteMode();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // تفعيل/إلغاء وضع الحذف
  void _toggleDeleteMode() {
    setState(() {
      _isDeletingMode = !_isDeletingMode;
      _selectedStudents.clear();
    });
  }

  // تبديل الترتيب
  void _toggleSortOrder() {
    _setSortByLatest(!_sortByLatest);
  }

  // اختيار/إلغاء اختيار طالب
  void _toggleStudentSelection(int studentId) {
    setState(() {
      if (_selectedStudents.contains(studentId)) {
        _selectedStudents.remove(studentId);
      } else {
        _selectedStudents.add(studentId);
      }
    });
  }

  // حذف الطلاب المحددين
  Future<void> _deleteSelectedStudents() async {
    if (_selectedStudents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'تأكيد الحذف',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'هل أنت متأكد من حذف ${_selectedStudents.length} طالب؟',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final studentProvider =
            Provider.of<StudentProvider>(context, listen: false);
        final ids = _selectedStudents.toList();
        for (final studentId in ids) {
          await studentProvider.deleteStudent(studentId);
        }

        setState(() {
          _isDeletingMode = false;
          _selectedStudents.clear();
        });

        _showSnackBar('تم حذف الطلاب بنجاح', Colors.green);
      } catch (e) {
        _showSnackBar('حدث خطأ أثناء الحذف', Colors.red);
      }
    }
  }

  // الحصول على الطلاب المرتبين
  List<StudentModel> _getSortedStudents(List<StudentModel> students) {
    // تطبيق البحث أولاً
    List<StudentModel> filtered = students;
    if (_searchQuery.isNotEmpty) {
      filtered = students.where((student) {
        return student.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // الترتيب المتزامن (من أي شاشة) يصبح هو الترتيب الحاكم.
    final List<StudentModel> base = List.from(filtered);

    // ثم الترتيب المحلي (فقط إذا لا يوجد ترتيب متزامن)
    switch (_sortType) {
      case SortType.alphabetical:
        // ترتيب أبجدي
        base.sort((a, b) => a.name.compareTo(b.name));
        break;

      case SortType.attendanceRate:
        // ترتيب تنازلي حسب نسبة الحضور (الأعلى أولاً)
        base.sort((a, b) {
          final aStats = _studentStats[a.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aPresent = aStats['present'] ?? 0;
          final bPresent = bStats['present'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aPresent / aTotal : 0;
          final bRate = bTotal > 0 ? bPresent / bTotal : 0;

          // ترتيب تنازلي (الأعلى أولاً)
          return bRate.compareTo(aRate);
        });
        break;

      case SortType.absenceRate:
        // ترتيب تنازلي حسب نسبة الغياب (الأعلى أولاً)
        base.sort((a, b) {
          final aStats = _studentStats[a.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
          final bStats = _studentStats[b.id!] ??
              {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};

          final aAbsent = aStats['absent'] ?? 0;
          final bAbsent = bStats['absent'] ?? 0;
          final aTotal = (aStats['present'] ?? 0) +
              (aStats['absent'] ?? 0) +
              (aStats['late'] ?? 0) +
              (aStats['expelled'] ?? 0);
          final bTotal = (bStats['present'] ?? 0) +
              (bStats['absent'] ?? 0) +
              (bStats['late'] ?? 0) +
              (bStats['expelled'] ?? 0);

          final aRate = aTotal > 0 ? aAbsent / aTotal : 0;
          final bRate = bTotal > 0 ? bAbsent / bTotal : 0;

          // ترتيب تنازلي (الأعلى غياباً أولاً)
          return bRate.compareTo(aRate);
        });
        break;

      case SortType.highestAverage:
        base.sort((a, b) {
          final aAvg = _studentGradeAverages[a.id ?? -1] ?? 0.0;
          final bAvg = _studentGradeAverages[b.id ?? -1] ?? 0.0;
          return bAvg.compareTo(aAvg);
        });
        break;

      case SortType.lowestAverage:
        base.sort((a, b) {
          final aAvg = _studentGradeAverages[a.id ?? -1] ?? 0.0;
          final bAvg = _studentGradeAverages[b.id ?? -1] ?? 0.0;
          return aAvg.compareTo(bAvg);
        });
        break;
    }

    return base;
  }

  String _getSortTypeName() {
    switch (_sortType) {
      case SortType.alphabetical:
        return 'أبجدي';
      case SortType.attendanceRate:
        return 'نسبة الحضور';
      case SortType.absenceRate:
        return 'نسبة الغياب';
      case SortType.highestAverage:
        return 'أعلى معدل';
      case SortType.lowestAverage:
        return 'أقل معدل';
    }
  }

  String _getSortTypeNameForType(SortType type) {
    switch (type) {
      case SortType.alphabetical:
        return 'أبجدي';
      case SortType.attendanceRate:
        return 'أعلى حضور';
      case SortType.absenceRate:
        return 'أعلى غياب';
      case SortType.highestAverage:
        return 'أعلى معدل';
      case SortType.lowestAverage:
        return 'أقل معدل';
    }
  }

  IconData _getSortTypeIcon(SortType type) {
    switch (type) {
      case SortType.alphabetical:
        return Icons.sort_by_alpha;
      case SortType.attendanceRate:
        return Icons.trending_up;
      case SortType.absenceRate:
        return Icons.trending_down;
      case SortType.highestAverage:
        return Icons.trending_up;
      case SortType.lowestAverage:
        return Icons.trending_down;
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

  // دالة إرسال إيميل للمحاضرة
  Future<void> _sendLectureEmail(LectureModel lecture) async {
    try {
      // الحصول على قائمة الطلاب الذين لديهم إيميل
      final students =
          await Provider.of<StudentProvider>(context, listen: false)
              .getStudentsByClass(widget.classModel.id!);
      final studentsWithEmail =
          students.where((student) => student.hasEmail()).toList();

      if (studentsWithEmail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يوجد طلاب لديهم إيميل في هذا الفصل')),
          );
        }
        return;
      }

      // إنشاء تقرير PDF للمحاضرة
      final pdfBytes = await _generateLecturePDF(lecture);

      // حفظ الملف مؤقتاً
      final fileName =
          'lecture_${widget.classModel.name}_${lecture.title}_${DateFormat('yyyyMMdd').format(lecture.date)}.pdf';
      final appDir = await getApplicationDocumentsDirectory();
      final file = File('${appDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      // الانتقال لصفحة إرسال الإيميل
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmailSendingScreen(
              attachmentPath: file.path,
              attachmentName: fileName,
              defaultSubject: 'تقرير محاضرة: ${lecture.title}',
              defaultMessage: '''السلام عليكم،

مرفق تقرير محاضرة "${lecture.title}" للفصل "${widget.classModel.name}" التي أقيمت بتاريخ ${DateFormat('dd/MM/yyyy').format(lecture.date)}.

مع أطيب التحيات،
الأستاذ باقر القرغولي''',
              preselectedStudentIds:
                  studentsWithEmail.map((s) => s.id!).toList(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // دالة إنشاء PDF للمحاضرة
  Future<List<int>> _generateLecturePDF(LectureModel lecture) async {
    final pdf = pw.Document();

    final students = Provider.of<StudentProvider>(context, listen: false).students;

    // إعداد الخط العربي - استخدام خط Noto Sans Arabic TTF مع خط احتياطي للرموز
    final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
    // تحميل خط احتياطي للرموز الخاصة والرياضيات
    final symbolFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context pdfContext) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // العنوان العلوي
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue,
                borderRadius:
                    const pw.BorderRadius.all(pw.Radius.circular(8)),
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
                          'حضور ${widget.classModel.name}',
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
                border:
                    pw.TableBorder.all(color: PdfColors.grey300, width: 1),
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
                        child: pw.Center(
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
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
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
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
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
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Center(
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
                      ),
                    ],
                  ),
                  // Students
                  ...students
                      .asMap()
                      .entries
                      .map((entry) {
                    final index = entry.key;
                    final student = entry.value;
                    final lectureKey =
                        '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';
                    final status =
                        _attendanceStatus[student.id!]?[lectureKey] ??
                            AttendanceStatus.absent;
                    final comment = _studentComments[student.id!]?[lectureKey] ?? '';

                    return pw.TableRow(
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              _getAttendanceStatusText(status),
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                                color: _getAttendanceStatusColor(status),
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              student.name,
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Center(
                            child: pw.Text(
                              comment,
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                              ),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return await pdf.save();
  }

  String _getAttendanceStatusText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'مطرود';
      case AttendanceStatus.excused:
        return 'مجاز';
    }
  }

  PdfColor _getAttendanceStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return PdfColors.green;
      case AttendanceStatus.absent:
        return PdfColors.red;
      case AttendanceStatus.late:
        return PdfColors.orange;
      case AttendanceStatus.expelled:
        return PdfColors.purple;
      case AttendanceStatus.excused:
        return PdfColors.blue;
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
              title: const Text('جميع الطلاب مجازين'),
              onTap: () {
                _setAllStudentsAttendance(lecture, AttendanceStatus.excused);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: Colors.purple,
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
  Future<void> _setAllStudentsAttendance(
      LectureModel lecture, AttendanceStatus status) async {
    final lectureKey =
        '${lecture.id}_${DateFormat('yyyy-MM-dd').format(lecture.date)}';

    for (final student
        in Provider.of<StudentProvider>(context, listen: false).students) {
      // تحديث الحالة في الذاكرة
      if (!_attendanceStatus.containsKey(student.id!)) {
        _attendanceStatus[student.id!] = {};
      }
      _attendanceStatus[student.id!]![lectureKey] = status;

      // حفظ في قاعدة البيانات
      await _dbHelper.insertAttendance(
        AttendanceModel(
          studentId: student.id!,
          lectureId: lecture.id!, // Include lecture ID
          date: lecture.date,
          status: status,
          notes: '',
          createdAt: DateTime.now(),
        ),
      );
    }

    setState(() {});

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
      case AttendanceStatus.excused:
        statusText = 'مجازين';
        break;
      case AttendanceStatus.expelled:
        statusText = 'مطرودين';
        break;
    }

    // إظهار رسالة
    _showSnackBar(
        'تم تعيين حالة الحضور لجميع الطلاب إلى: $statusText', Colors.blue);
  }

  // دالة تقرير الحضور PDF
  Future<void> _showAttendanceReport(LectureModel lecture) async {
    try {
      debugPrint('Starting attendance report generation for: ${lecture.title}');

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
      final students =
          Provider.of<StudentProvider>(context, listen: false).students;
      if (students.isEmpty) {
        debugPrint('No students found');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد طلاب في هذا الفصل')),
        );
        return;
      }

      debugPrint('Found ${students.length} students');

      // الحصول على بيانات الحضور للمحاضرة
      final List<AttendanceModel> allAttendances = [];
      for (final student in students) {
        if (!mounted) return;
        try {
          final studentAttendances =
              await _dbHelper.getAttendanceByStudent(student.id!);
          allAttendances.addAll(studentAttendances);
        } catch (e) {
          debugPrint('Error getting attendance for student ${student.id}: $e');
        }
      }
      final attendances =
          allAttendances.where((a) => a.lectureId == lecture.id).toList();

      // حساب عدد كل حالة
      int presentCount =
          attendances.where((a) => a.status == AttendanceStatus.present).length;
      int absentCount =
          attendances.where((a) => a.status == AttendanceStatus.absent).length;
      int lateCount =
          attendances.where((a) => a.status == AttendanceStatus.late).length;
      int expelledCount = attendances
          .where((a) => a.status == AttendanceStatus.expelled)
          .length;
      int excusedCount = attendances
          .where((a) => a.status == AttendanceStatus.excused)
          .length;

      // إنشاء ملف PDF
      final pdf = pw.Document();

      // إعداد الخط العربي - استخدام خط Noto Sans Arabic TTF مع خط احتياطي للرموز
      final arabicFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      // تحميل خط احتياطي للرموز الخاصة والرياضيات
      final symbolFont = pw.Font.ttf(
          await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context pdfContext) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // العنوان العلوي
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
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
                            'حضور ${widget.classModel.name}',
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
                  border:
                      pw.TableBorder.all(color: PdfColors.grey300, width: 1),
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
                  ...attendances.map((attendance) {
                    final student = students.firstWhere(
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
                    final statusColor =
                        attendance.status == AttendanceStatus.present
                            ? PdfColors.green
                            : attendance.status == AttendanceStatus.absent
                                ? PdfColors.red
                                : attendance.status == AttendanceStatus.late
                                    ? PdfColors.orange
                                    : PdfColors.purple;

                    // الحصول على ملاحظات المحاضرة لهذا الطالب
                    final lectureNotes = _lectureNotes[lecture.id] ?? '';
                    final studentNotes =
                        ''; // يمكن إضافة ملاحظات خاصة بالطالب لاحقاً

                    return pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: PdfColors.grey50,
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
                            studentNotes.isNotEmpty
                                ? studentNotes
                                : lectureNotes,
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

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      // حفظ الملف وفتحه مباشرة
      final String fileName =
          'تقرير_حضور_${lecture.title}_${DateFormat('yyyy_MM_dd').format(lecture.date)}.pdf';
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      debugPrint('PDF saved to: ${file.path}');

      // فتح الملف مباشرة
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: fileName,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ تقرير الحضور في: ${file.path}')),
      );
      debugPrint('✅ Attendance report generated successfully!');
    } catch (e) {
      debugPrint('❌ Error in attendance report: $e');
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
  pw.Widget _buildSymbolText(
      String text, pw.Font arabicFont, pw.Font symbolFont,
      {double fontSize = 12, PdfColor? color}) {
    // استبدال الرموز ببدائل نصية تدعمها الخطوط العربية
    String processedText =
        text.replaceAll('/', '-'); // استخدام شرطة عادية بدلاً من الشرطة المائلة

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

  // دالة حفظ سجل الحضور في قاعدة البيانات
  Future<void> _saveAttendanceToDatabase({
    required int studentId,
    required LectureModel lecture,
    required AttendanceStatus status,
  }) async {
    try {
      // البحث عن سجل الحضور الحالي
      final existingAttendance =
          await _dbHelper.getAttendanceByStudentAndLecture(
        studentId: studentId,
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
          studentId: studentId,
          lectureId: lecture.id!, // Include lecture ID
          date: lecture.date,
          status: status,
          notes: '',
          createdAt: DateTime.now(),
        ));
      }

      if (mounted) {
        Provider.of<StudentProvider>(context, listen: false).refreshIndicators();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ الحضور: $e')),
        );
      }
      rethrow;
    }
  }

  // دالة تحديث حالة الحضور
  Future<void> _updateAttendance(
      int studentId, String lectureKey, AttendanceStatus status) async {
    if (!mounted) return;

    setState(() {
      _attendanceStatus[studentId] ??= {};
      _attendanceStatus[studentId]![lectureKey] = status;
    });

    // حفظ التغييرات في قاعدة البيانات
    try {
      // تحليل lectureKey للحصول على lectureId و date
      final parts = lectureKey.split('_');
      if (parts.length >= 2) {
        final lectureId = int.tryParse(parts[0]);
        final dateString = lectureKey.substring(parts[0].length + 1);

        if (lectureId != null) {
          // البحث عن المحاضرة المناسبة
          final lecture = _lectures.firstWhere(
            (l) =>
                l.id == lectureId &&
                DateFormat('yyyy-MM-dd').format(l.date) == dateString,
            orElse: () => LectureModel(
              id: 0,
              classId: widget.classModel.id!,
              date: DateTime.now(),
              title: 'محاضرة جديدة',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

          // تحديث أو إضافة سجل الحضور
          await _saveAttendanceToDatabase(
            studentId: studentId,
            lecture: lecture,
            status: status,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء حفظ حالة الحضور: $e')),
        );
      }
    }
  }

  // دالة للتحقق من حالة الطالب
  Future<Map<String, bool>> _checkStudentStatus(StudentModel student) async {
    final status =
        await UnifiedStudentStatusService.checkStudentStatus(
      student,
      classId: widget.classModel.id,
    );
    return {
      'isExcellent': status['isExcellent'] ?? false,
      'isAtRisk': status['isAtRisk'] ?? false,
    };
  }

  Future<bool> _areIndicatorsHidden() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('student_status_indicators_hidden') ?? false;
  }

  // دالة لبناء مؤشر حالة الطالب (نجمة صفراء ونقطة حمراء ويمكن أن يظهران معاً)
  Widget _buildStudentStatusIndicator(StudentModel student) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        return FutureBuilder<bool>(
          key: ValueKey('hide_${studentProvider.updateCounter}'),
          future: _areIndicatorsHidden(),
          builder: (context, hiddenSnap) {
            if (hiddenSnap.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 16, height: 16);
            }

            final hidden = hiddenSnap.data ?? false;
            if (hidden) {
              return const SizedBox(width: 16, height: 16);
            }

            return FutureBuilder<Map<String, bool>>(
              key: ValueKey(studentProvider.updateCounter),
              future: _checkStudentStatus(student),
              builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(width: 16, height: 16);
            }

            final isExcellent = snapshot.data?['isExcellent'] ?? false;
            final isAtRisk = snapshot.data?['isAtRisk'] ?? false;

            if (!isExcellent && !isAtRisk) {
              return const SizedBox(width: 16, height: 16);
            }

            final children = <Widget>[];
            if (isExcellent) {
              children.add(
                Container(
                  padding: const EdgeInsets.all(1),
                  decoration: BoxDecoration(
                    color: Colors.yellow.withOpacity(0.15),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.yellow.withOpacity(0.3),
                        blurRadius: 1,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.star,
                    color: Colors.yellow,
                    size: 13,
                    shadows: [
                      Shadow(
                        color: Colors.orange,
                        blurRadius: 1,
                        offset: Offset(0.5, 0.5),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (isAtRisk) {
              if (children.isNotEmpty) {
                children.add(const SizedBox(width: 2));
              }
              children.add(
                Container(
                  width: 6,
                  height: 6,
                  margin: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 2,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              );
            }

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: children,
            );
              },
            );
          },
        );
      },
    );
  }

  // دالة للتحقق إذا كانت أي معيار للطلاب في خطر مفعلاً
  Future<bool> _isAnyRiskCriteriaEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final featureEnabled =
        prefs.getBool('unified_student_status_at_risk_feature_enabled') ?? true;
    if (!featureEnabled) return false;

    final averageEnabled =
        prefs.getBool('unified_student_status_at_risk_average_enabled') ?? true;
    final missedExamsEnabled =
        prefs.getBool('unified_student_status_at_risk_missed_exams_enabled') ??
            true;
    final missedLecturesEnabled = prefs.getBool(
            'unified_student_status_at_risk_missed_lectures_enabled') ??
        true;

    return averageEnabled || missedExamsEnabled || missedLecturesEnabled;
  }
}

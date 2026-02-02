import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/note_model.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../providers/exam_provider.dart';
import '../../providers/grade_provider.dart';
import '../../database/database_helper.dart';
import '../students/add_student_screen.dart';
import '../students/student_details_screen.dart';
import '../students/student_gallery_screen.dart';
import '../notes/class_notes_screen.dart';
import '../messaging/messaging_screen.dart';
import 'exam_statistics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/latest_view_mode_service.dart';

enum SortType { alphabetical, highestGrade, lowestGrade, gender }
enum GradeStatus { present, absent, cheating, missing }

class NewExamsScreen extends StatefulWidget {
  final ClassModel classModel;
  final VoidCallback? onStudentAdded;

  const NewExamsScreen({
    super.key,
    required this.classModel,
    this.onStudentAdded,
  });

  @override
  State<NewExamsScreen> createState() => _NewExamsScreenState();
}

class _NewExamsScreenState extends State<NewExamsScreen> with WidgetsBindingObserver {
  //=== متغيرات التحكم ===
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();
  
  //=== متغيرات الحالة ===
  // إعدادات التصفية والترتيب
  SortType _sortType = SortType.alphabetical;
  String _searchQuery = '';
  bool _isLoadingStats = false;
  bool _sortByLatest = false;

  StreamSubscription<bool>? _latestViewModeSub;
  
  //=== قوائم البيانات ===
  List<ExamModel> _exams = [];
  List<StudentModel> _students = [];
  
  //=== خرائط تخزين البيانات ===
  // درجات الطلاب: studentId -> {examKey: grade}
  final Map<int, Map<String, double>> _studentGrades = {};
  // حالة الطلاب: studentId -> {examKey: status}
  final Map<int, Map<String, GradeStatus>> _studentStatus = {};
  // التعليقات: studentId -> {examKey: comment}
  final Map<int, Map<String, String>> _studentComments = {};
  // ملاحظات الامتحانات: examId -> notes
  final Map<int, String> _examNotes = {};
  // إحصائيات الدرجات: studentId -> {total: x, average: y, ...}
  Map<int, Map<String, double>> _studentStats = {};
  // حالة الطلاب في خطر: studentId -> isAtRisk
  Map<int, bool> _atRiskStudents = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLatestViewModePreference().then((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    });
    _headerScrollController.addListener(_syncHeaderScroll);
    _contentScrollController.addListener(_syncContentScroll);

    _latestViewModeSub = LatestViewModeService.instance.changes.listen((enabled) {
      if (!mounted) return;
      setState(() {
        _sortByLatest = enabled;
        _exams.sort(
          (a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
        );
      });
    });
  }

  Future<void> _loadLatestViewModePreference() async {
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
      _exams.sort(
        (a, b) => _sortByLatest ? b.date.compareTo(a.date) : a.date.compareTo(b.date),
      );
    });
  }

  @override
  void dispose() {
    _latestViewModeSub?.cancel();
    _searchController.dispose();
    _headerScrollController.dispose();
    _contentScrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  void didUpdateWidget(NewExamsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // إعادة تحميل البيانات عند تغيير الفصل
    if (oldWidget.classModel.id != widget.classModel.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadData();
        }
      });
    } else {
      // فحص المعايير عند العودة للصفحة
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _checkAtRiskStudents();
        }
      });
    }
  }

  void _showSortTypeMenu() {
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
                'عرض المحاضرات والامتحانات حسب الأحدث',
                style: TextStyle(
                  color: _sortByLatest ? Colors.yellow : Colors.white,
                ),
              ),
              trailing: Switch(
                value: _sortByLatest,
                onChanged: (value) {
                  Navigator.pop(context);
                  _setSortByLatest(value);
                },
              ),
              activeColor: Colors.yellow,
            ),
            const Divider(height: 1, color: Color(0xFF404040)),
            ...SortType.values.map(
              (type) => ListTile(
                title: Text(
                  _getSortTypeName(type),
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

  Future<void> _loadData() async {
    // تحميل الطلاب من Provider
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    await Future.wait([
      studentProvider.loadStudentsByClass(widget.classModel.id!),
      examProvider.loadExamsByClass(widget.classModel.id!),
    ]);
    
    setState(() {
      _students = studentProvider.students;
      _exams = List<ExamModel>.from(examProvider.exams)
        ..sort(
          (a, b) => _sortByLatest
              ? b.date.compareTo(a.date)
              : a.date.compareTo(b.date),
        );
    });
    
    // تحميل جميع الدرجات من قاعدة البيانات
    await _loadAllGrades();
    
    // حساب إحصائيات الدرجات للفرز
    await _loadStudentStats();
    
    // فحص الطلاب في خطر
    await _checkAtRiskStudents();
  }

  Future<GradeModel?> _getGradeByStudentAndExam(ExamModel exam, int studentId) async {
    final db = await _dbHelper.database;
    final dateKey = DateFormat('yyyy-MM-dd').format(exam.date);
    final maps = await db.query(
      'grades',
      where: 'student_id = ? AND exam_name = ? AND exam_date = ?',
      whereArgs: [studentId, exam.title, dateKey],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return GradeModel.fromMap(maps.first);
  }

  String _getSortTypeName(SortType type) {
    switch (type) {
      case SortType.alphabetical:
        return 'أبجدي';
      case SortType.highestGrade:
        return 'أعلى درجة';
      case SortType.lowestGrade:
        return 'أقل درجة';
      case SortType.gender:
        return 'الجنس';
    }
  }

  Future<void> _loadAllGrades() async {
    _studentGrades.clear();
    _studentStatus.clear();
    
    for (final student in _students) {
      try {
        final grades = await _dbHelper.getGradesByStudent(student.id!);
        if (!_studentGrades.containsKey(student.id!)) {
          _studentGrades[student.id!] = {};
          _studentStatus[student.id!] = {};
        }
        
        for (final grade in grades) {
          final exam = _exams.where((e) => e.title == grade.examName).firstOrNull;
          if (exam != null) {
            final examKey = '${exam.id}_${DateFormat('yyyy-MM-dd').format(exam.date)}';
            _studentGrades[student.id!]![examKey] = grade.score;
            
            // تحديد الحالة
            if (grade.score == 0 && grade.notes?.contains('غائب') == true) {
              _studentStatus[student.id!]![examKey] = GradeStatus.absent;
            } else if (grade.score == 0 && grade.notes?.contains('غش') == true) {
              _studentStatus[student.id!]![examKey] = GradeStatus.cheating;
            } else if (grade.score == 0 && grade.notes?.contains('مفقودة') == true) {
              _studentStatus[student.id!]![examKey] = GradeStatus.missing;
            } else {
              _studentStatus[student.id!]![examKey] = GradeStatus.present;
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading grades for student ${student.id}: $e');
      }
    }
  }

  Future<void> _loadStudentStats() async {
    setState(() {
      _isLoadingStats = true;
    });
    
    final Map<int, Map<String, double>> stats = {};
    
    for (final student in _students) {
      try {
        final grades = await _dbHelper.getGradesByStudent(student.id!);
        double totalScore = 0;
        int validGrades = 0;
        
        for (final grade in grades) {
          final exam = _exams.where((e) => e.title == grade.examName).firstOrNull;
          if (exam != null && exam.maxScore > 0) {
            totalScore += (grade.score / exam.maxScore) * 100;
            validGrades++;
          }
        }
        
        stats[student.id!] = {
          'average': validGrades > 0 ? totalScore / validGrades : 0.0,
          'total': totalScore,
          'count': validGrades.toDouble(),
        };
      } catch (e) {
        stats[student.id!] = {'average': 0.0, 'total': 0.0, 'count': 0.0};
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
    
    for (final student in _students) {
      try {
        // حساب المعدل العام من امتحانات الفصل الحالي فقط
        final allGrades = await _dbHelper.getGradesByStudent(student.id!);
        final grades = allGrades.where((g) => _exams.any((e) => e.title == g.examName)).toList();
        
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
            final matchingExam = _exams.where((e) => e.title == grade.examName).firstOrNull;
            
            if (matchingExam != null && matchingExam.maxScore > 0) {
              final percentage = (grade.score / matchingExam.maxScore) * 100;
              totalPercentage += percentage;
              validExamCount++;
            }
          }
          
          averagePercentage = validExamCount > 0 ? totalPercentage / validExamCount : 0.0;
        }
        
        final isAtRisk = averagePercentage < minAveragePercentage;
        atRisk[student.id!] = isAtRisk;
      } catch (e) {
        atRisk[student.id!] = false;
      }
    }
    
    setState(() {
      _atRiskStudents = atRisk;
    });
  }

  void _saveComment(int studentId, String examKey, String comment) {
    setState(() {
      if (!_studentComments.containsKey(studentId)) {
        _studentComments[studentId] = {};
      }
      _studentComments[studentId]![examKey] = comment;
    });
  }

  void _showCommentDialog(int studentId, String examKey, String currentComment) {
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
              _saveComment(studentId, examKey, commentController.text);
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showExamOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('خيارات الامتحان: ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(exam.date)}'),
            Text('الدرجة القصوى: ${exam.maxScore}'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.note_add, color: Colors.blue),
              title: const Text('ملاحظة سريعة'),
              onTap: () {
                Navigator.pop(context);
                _showExamNotesDialog(exam);
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
              title: const Text('تقرير الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _showExamReport(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.green),
              title: const Text('الدرجات التلقائية'),
              onTap: () {
                Navigator.pop(context);
                _showAutoGradeOptions(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('تعديل الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _showEditExamDialog(exam);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('حذف الامتحان'),
              onTap: () {
                Navigator.pop(context);
                _deleteExam(exam);
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

  Future<void> _deleteExam(ExamModel exam) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف امتحان "${exam.title}"؟\nسيتم حذف جميع الدرجات المتعلقة به.'),
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
        // حذف الدرجات المرتبطة بالامتحان
        final db = await _dbHelper.database;
        await db.delete(
          'grades',
          where: 'exam_name = ?',
          whereArgs: [exam.title],
        );
        
        // حذف الامتحان
        await _dbHelper.deleteExam(exam.id!);
        
        // تحديث الواجهة
        setState(() {
          _exams.remove(exam);
        });
        
        // تحديث الإحصائيات
        await _loadStudentStats();
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تم حذف امتحان: ${exam.title}')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ في حذف الامتحان: $e')),
          );
        }
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
              leading: const Icon(Icons.assignment, color: Colors.green),
              title: const Text('إضافة امتحان'),
              onTap: () {
                Navigator.pop(context);
                _showAddExamDialog();
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

  void _showAddExamDialog() {
    final titleController = TextEditingController();
    final maxScoreController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة امتحان جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان',
                  hintText: 'مثال: امتحان الفصل الأول',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الدرجة القصوى',
                  hintText: 'مثال: 100',
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
                if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                  try {
                    final maxScore = double.tryParse(maxScoreController.text);
                    if (maxScore != null && maxScore > 0) {
                      final newExam = ExamModel(
                        classId: widget.classModel.id!,
                        title: titleController.text,
                        date: selectedDate,
                        maxScore: maxScore,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      );
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                      
                      await _dbHelper.insertExam(newExam);
                      await _loadData();
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم إضافة امتحان: ${newExam.title}')),
                        );
                      }
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('الرجاء إدخال درجة قصوى صحيحة')),
                        );
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('خطأ في إضافة الامتحان: $e')),
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

  List<StudentModel> _sortStudents(List<StudentModel> students) {
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
    
    // ثم الترتيب
    final List<StudentModel> sorted = List.from(filtered);
    
    switch (_sortType) {
      case SortType.alphabetical:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
      case SortType.highestGrade:
        sorted.sort((a, b) {
          final aStats = _studentStats[a.id!] ?? {'average': 0.0};
          final bStats = _studentStats[b.id!] ?? {'average': 0.0};
          return bStats['average']!.compareTo(aStats['average']!);
        });
        break;
      case SortType.lowestGrade:
        sorted.sort((a, b) {
          final aStats = _studentStats[a.id!] ?? {'average': 0.0};
          final bStats = _studentStats[b.id!] ?? {'average': 0.0};
          return aStats['average']!.compareTo(bStats['average']!);
        });
        break;
      case SortType.gender:
        sorted.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    
    return sorted;
  }

  IconData _getGradeIcon(GradeStatus status) {
    switch (status) {
      case GradeStatus.present:
        return Icons.check_circle;
      case GradeStatus.absent:
        return Icons.cancel;
      case GradeStatus.cheating:
        return Icons.warning;
      case GradeStatus.missing:
        return Icons.help_outline;
    }
  }

  Color _getGradeColor(GradeStatus status) {
    switch (status) {
      case GradeStatus.present:
        return Colors.green;
      case GradeStatus.absent:
        return Colors.red;
      case GradeStatus.cheating:
        return Colors.orange;
      case GradeStatus.missing:
        return Colors.purple;
    }
  }

  String _getGradeText(GradeStatus status) {
    switch (status) {
      case GradeStatus.present:
        return 'حاضر';
      case GradeStatus.absent:
        return 'غائب';
      case GradeStatus.cheating:
        return 'غش';
      case GradeStatus.missing:
        return 'مفقودة';
    }
  }

  Widget _buildGradeBox(StudentModel student, ExamModel exam, double? currentGrade) {
    // الحصول على الدرجة المحفوظة باستخدام معرف الامتحان الفريد
    final examKey = '${exam.id}_${DateFormat('yyyy-MM-dd').format(exam.date)}';
    final grade = _studentGrades[student.id!]?[examKey] ?? currentGrade ?? 0.0;
    final status = _studentStatus[student.id!]?[examKey] ?? GradeStatus.present;
    final comment = _studentComments[student.id!]?[examKey] ?? '';
    
    return GestureDetector(
      onTap: () => _showGradeOptions(student, exam),
      child: Column(
        children: [
          // مربع الدرجة الكبير
          Container(
            width: 110,
            height: 70,
            decoration: BoxDecoration(
              color: _getGradeColor(status),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
              boxShadow: [
                BoxShadow(
                  color: _getGradeColor(status).withOpacity(0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (status == GradeStatus.present)
                  Text(
                    grade.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  Icon(
                    _getGradeIcon(status),
                    size: 22,
                    color: Colors.white,
                  ),
                const SizedBox(height: 4),
                Text(
                  _getGradeText(status),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // خط للتعليق تحت المربع
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showCommentDialog(student.id!, examKey, comment),
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

  void _showGradeOptions(StudentModel student, ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تحديد درجة الطالب - ${student.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'الدرجة (من ${exam.maxScore})',
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final grade = double.tryParse(value);
                if (grade != null && grade >= 0 && grade <= exam.maxScore) {
                  _saveGradeStatus(student, exam, grade, GradeStatus.present);
                }
              },
            ),
            const SizedBox(height: 16),
            _buildGradeOption(student, exam, GradeStatus.absent, '❌ غائب', Colors.red),
            _buildGradeOption(student, exam, GradeStatus.cheating, '⚠️ غش', Colors.orange),
            _buildGradeOption(student, exam, GradeStatus.missing, '❓ مفقودة', Colors.purple),
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

  Widget _buildGradeOption(StudentModel student, ExamModel exam, GradeStatus status, String text, Color color) {
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
        _saveGradeStatus(student, exam, 0.0, status);
      },
    );
  }

  Future<void> _saveGradeStatus(StudentModel student, ExamModel exam, double grade, GradeStatus status) async {
    try {
      // البحث عن درجة موجودة
      final existingGrade =
          await _getGradeByStudentAndExam(exam, student.id!);

      String notes = '';
      if (status == GradeStatus.absent) {
        notes = 'غائب';
      } else if (status == GradeStatus.cheating) {
        notes = 'غش';
      } else if (status == GradeStatus.missing) {
        notes = 'مفقودة';
      }

      if (existingGrade != null) {
        // تحديث الدرجة الموجودة
        await _dbHelper.updateGrade(
          existingGrade.copyWith(
            score: grade,
            notes: notes,
            maxScore: exam.maxScore,
            examDate: exam.date,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        // إنشاء درجة جديدة
        await _dbHelper.insertGrade(GradeModel(
          studentId: student.id!,
          examName: exam.title,
          score: grade,
          maxScore: exam.maxScore,
          examDate: exam.date,
          notes: notes,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }

      // تحديث الحالة في الذاكرة فوراً
      if (mounted) {
        setState(() {
          final examKey = '${exam.id}_${DateFormat('yyyy-MM-dd').format(exam.date)}';
          if (!_studentGrades.containsKey(student.id!)) {
            _studentGrades[student.id!] = {};
            _studentStatus[student.id!] = {};
          }
          _studentGrades[student.id!]![examKey] = grade;
          _studentStatus[student.id!]![examKey] = status;
        });
        
        // تحديث الإحصائيات فوراً
        await _updateSingleStudentStats(student.id!);
        
        // إعادة فحص الطلاب في خطر فوراً
        await _checkAtRiskStudents();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الدرجة: $e')),
        );
      }
    }
  }

  Future<void> _updateSingleStudentStats(int studentId) async {
    try {
      final gradeRecords = await _dbHelper.getGradesByStudent(studentId);
      double totalScore = 0;
      int validGrades = 0;
      
      for (final record in gradeRecords) {
        final exam = _exams.where((e) => e.title == record.examName).firstOrNull;
        if (exam != null && exam.maxScore > 0) {
          totalScore += (record.score / exam.maxScore) * 100;
          validGrades++;
        }
      }
      
      setState(() {
        _studentStats[studentId] = {
          'average': validGrades > 0 ? totalScore / validGrades : 0.0,
          'total': totalScore,
          'count': validGrades.toDouble(),
        };
      });
    } catch (e) {
      debugPrint('خطأ في تحديث إحصائيات الطالب: $e');
    }
  }

  Widget _buildStudentStats(int studentId) {
    final stats = _studentStats[studentId] ?? {'average': 0.0, 'total': 0.0, 'count': 0.0};
    final average = stats['average'] ?? 0.0;
    final count = (stats['count'] ?? 0.0).toInt();
    
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        // المعدل
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '%${average.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        // عدد الامتحانات
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$count امتحان',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 8,
                fontWeight: FontWeight.w500,
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
                    value: SortType.highestGrade,
                    child: Row(
                      children: [
                        Icon(Icons.trending_up),
                        SizedBox(width: 8),
                        Text('أعلى درجة'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: SortType.lowestGrade,
                    child: Row(
                      children: [
                        Icon(Icons.trending_down),
                        SizedBox(width: 8),
                        Text('أقل درجة'),
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
                      hintText: 'بحث بالاسم أو الرقم...',
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
          
        // قائمة الطلاب والامتحانات
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
                    if (_exams.isNotEmpty)
                      Container(
                        color: const Color(0xFF2D2D2D), // رمادي داكن
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            // مساحة فارغة لمحاذاة الأسماء
                            Container(
                              width: 150,
                              decoration: BoxDecoration(
                                color: Colors.yellow.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.yellow,
                                  width: 1,
                                ),
                              ),
                              height: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              StudentGalleryScreen(classId: widget.classModel.id!),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.photo_library,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _showSortTypeMenu,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.yellow,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const MessagingScreen(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.yellow.withValues(alpha: 0.2),
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
                            // العناوين والتواريخ
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _headerScrollController,
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _exams.asMap().entries.map((entry) {
                                    final exam = entry.value;
                                    final index = entry.key;
                                    return GestureDetector(
                                      onTap: () => _showExamOptions(exam),
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
                                              exam.title,
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
                                                DateFormat('dd/MM/yyyy').format(exam.date),
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.blue,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '/${exam.maxScore}',
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
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            child: Row(
                              children: [
                                // معلومات الطالب في اليمين - خلفية داكنة
                                Container(
                                  width: 150,
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
                                      const SizedBox(width: 8),
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
                                // خط فاصل
                                Container(
                                  width: 3,
                                  height: 80,
                                  color: const Color(0xFF404040), // رمادي
                                  margin: const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                // الامتحانات أفقياً - محاذاة مباشرة تحت التواريخ
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _contentScrollController,
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: _exams.asMap().entries.map((entry) {
                                        final exam = entry.value;
                                        final index = entry.key;
                                        // الحصول على الدرجة المحفوظة باستخدام معرف الامتحان الفريد
                                        final examKey = '${exam.id}_${DateFormat('yyyy-MM-dd').format(exam.date)}';
                                        final grade = _studentGrades[student.id!]?[examKey];
                                        
                                        // مسافة متساوية بين جميع المربعات
                                        return Padding(
                                          padding: EdgeInsets.only(
                                            left: 8, // مسافة ثابتة ومتساوية
                                            right: 0,
                                          ),
                                          child: Container(
                                            width: 140, // نفس عرض التاريخ في الأعلى
                                            child: _buildGradeBox(student, exam, grade),
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

  // دالة عرض ملاحظات الامتحان
  void _showExamNotesDialog(ExamModel exam) {
    final notesController = TextEditingController();
    notesController.text = _examNotes[exam.id!] ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('ملاحظات الامتحان: ${exam.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('التاريخ: ${DateFormat('dd/MM/yyyy').format(exam.date)}'),
              Text('الدرجة القصوى: ${exam.maxScore}'),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات الامتحان',
                  hintText: 'اكتب ملاحظاتك حول هذا الامتحان...',
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
                await _saveExamNote(exam.id!, notesController.text);
                
                setState(() {
                  _examNotes[exam.id!] = notesController.text;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حفظ ملاحظات الامتحان بنجاح'),
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

  // دالة حفظ ملاحظة الامتحان في قاعدة البيانات
  Future<void> _saveExamNote(int examId, String noteContent) async {
    try {
      // البحث عن ملاحظة موجودة
      final existingNote = await _dbHelper.getNote('exam', examId);
      
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
            itemType: 'exam',
            itemId: examId,
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

  // دالة الدرجات التلقائية
  void _showAutoGradeOptions(ExamModel exam) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('الدرجات التلقائية: ${exam.title}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('اختر درجة لجميع الطلاب:'),
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
              title: Text('الدرجة القصوى (${exam.maxScore})'),
              onTap: () {
                _setAllStudentsGrades(exam, exam.maxScore, GradeStatus.present);
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
              title: const Text('صفر'),
              onTap: () {
                _setAllStudentsGrades(exam, 0.0, GradeStatus.present);
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
                _setAllStudentsGrades(exam, 0.0, GradeStatus.absent);
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
              title: const Text('جميع الطلاب غاشين'),
              onTap: () {
                _setAllStudentsGrades(exam, 0.0, GradeStatus.cheating);
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
              title: const Text('جميع الأوراق مفقودة'),
              onTap: () {
                _setAllStudentsGrades(exam, 0.0, GradeStatus.missing);
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

  // دالة تطبيق درجة على جميع الطلاب
  Future<void> _setAllStudentsGrades(ExamModel exam, double grade, GradeStatus status) async {
    final examKey = '${exam.id}_${DateFormat('yyyy-MM-dd').format(exam.date)}';
    
    for (final student in _students) {
      // تحديث الدرجة في الذاكرة
      if (!_studentGrades.containsKey(student.id!)) {
        _studentGrades[student.id!] = {};
        _studentStatus[student.id!] = {};
      }
      _studentGrades[student.id!]![examKey] = grade;
      _studentStatus[student.id!]![examKey] = status;
      
      // حفظ في قاعدة البيانات
      String notes = '';
      if (status == GradeStatus.absent) {
        notes = 'غائب';
      } else if (status == GradeStatus.cheating) {
        notes = 'غش';
      } else if (status == GradeStatus.missing) {
        notes = 'مفقودة';
      }
      
      await _dbHelper.insertGrade(GradeModel(
        studentId: student.id!,
        examName: exam.title,
        score: grade,
        maxScore: exam.maxScore,
        examDate: exam.date,
        notes: notes,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
    
    setState(() {});
    
    String statusText = '';
    if (status == GradeStatus.present) {
      statusText = 'الدرجة ${grade.toStringAsFixed(1)}';
    } else if (status == GradeStatus.absent) {
      statusText = 'غائبين';
    } else if (status == GradeStatus.cheating) {
      statusText = 'غاشين';
    } else if (status == GradeStatus.missing) {
      statusText = 'مفقودة';
    }
    
    // إظهار رسالة نجاح
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تعيين $statusText لجميع الطلاب'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // دالة تعديل الامتحان
  void _showEditExamDialog(ExamModel exam) {
    final titleController = TextEditingController(text: exam.title);
    final maxScoreController = TextEditingController(text: exam.maxScore.toString());
    DateTime selectedDate = exam.date;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل الامتحان'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(
                  labelText: 'عنوان الامتحان',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: maxScoreController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'الدرجة القصوى',
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
                if (titleController.text.isNotEmpty && maxScoreController.text.isNotEmpty) {
                  try {
                    final maxScore = double.tryParse(maxScoreController.text);
                    if (maxScore != null && maxScore > 0) {
                      final updatedExam = exam.copyWith(
                        title: titleController.text,
                        date: selectedDate,
                        maxScore: maxScore,
                        updatedAt: DateTime.now(),
                      );
                      
                      await _dbHelper.updateExam(updatedExam);
                      
                      setState(() {
                        final index = _exams.indexOf(exam);
                        _exams[index] = updatedExam;
                        _exams.sort(
                          (a, b) => _sortByLatest
                              ? b.date.compareTo(a.date)
                              : a.date.compareTo(b.date),
                        );
                      });
                      
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم تحديث الامتحان')),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الرجاء إدخال درجة قصوى صحيحة')),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ في تحديث الامتحان: $e')),
                    );
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  // دالة تقرير الامتحان PDF
  Future<void> _showExamReport(ExamModel exam) async {
    try {
      debugPrint('Starting exam report generation for: ${exam.title}');
      
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
        debugPrint('No students found');
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد طلاب في هذا الفصل')),
        );
        return;
      }

      debugPrint('Found ${_students.length} students');

      // الحصول على بيانات الدرجات للامتحان
      final List<GradeModel> allGrades = [];
      for (final student in _students) {
        try {
          final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
          allGrades.addAll(studentGrades.where((g) => g.examName == exam.title));
        } catch (e) {
          debugPrint('Error getting grades for student ${student.id}: $e');
        }
      }
      
      // حساب عدد كل حالة
      int presentCount = allGrades.where((g) => g.score > 0).length;
      int absentCount = allGrades.where((g) => g.notes?.contains('غائب') == true).length;
      int cheatingCount = allGrades.where((g) => g.notes?.contains('غش') == true).length;
      int missingCount = allGrades.where((g) => g.notes?.contains('مفقودة') == true).length;
      
      // حساب المعدل
      double averageScore = 0.0;
      final scoredGrades = allGrades.where((g) => g.score > 0).toList();
      if (scoredGrades.isNotEmpty) {
        averageScore = scoredGrades.map((g) => g.score).reduce((a, b) => a + b) / scoredGrades.length;
      }

      // إنشاء ملف PDF
      final pdf = pw.Document();
      
      // إعداد الخط العربي
      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));

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
                            'تقرير الامتحان',
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
                            'الامتحان: ${exam.title}',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.grey300,
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.Column(
                      children: [
                        pw.Text(
                          DateFormat('yyyy/MM/dd').format(exam.date),
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.Text(
                          'الدرجة القصوى: ${exam.maxScore}',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // جدول حالات الامتحان
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
                    2: const pw.FlexColumnWidth(1), // غش
                    3: const pw.FlexColumnWidth(1), // مفقودة
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
                            'غش',
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
                            'مفقودة',
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
                            '$cheatingCount',
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
                            '$missingCount',
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
                  2: const pw.FlexColumnWidth(1.5), // الدرجة
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
                          'الدرجة',
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
                  ...allGrades.map((grade) {
                    final student = _students.firstWhere(
                      (s) => s.id == grade.studentId,
                      orElse: () => StudentModel(
                        id: grade.studentId ?? 0,
                        name: 'طالب غير معروف',
                        classId: widget.classModel.id!,
                        studentId: 'غير معروف',
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    );
                    
                    final gradeText = grade.score > 0 ? grade.score.toStringAsFixed(1) : '0';
                    final gradeColor = grade.score > 0 ? PdfColors.black :
                                       grade.notes?.contains('غائب') == true ? PdfColors.red :
                                       grade.notes?.contains('غش') == true ? PdfColors.orange :
                                       PdfColors.purple;
                    
                    // الحصول على ملاحظات الامتحان
                    final examNotes = _examNotes[exam.id] ?? '';
                    final studentNotes = ''; // يمكن إضافة ملاحظات خاصة بالطالب لاحقاً
                    
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
                            '$gradeText/${exam.maxScore}',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 10,
                              color: gradeColor,
                              fontWeight: pw.FontWeight.bold,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(
                            studentNotes.isNotEmpty ? studentNotes : examNotes,
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
      final String fileName = 'تقرير_امتحان_${exam.title}_${DateFormat('yyyy_MM_dd').format(exam.date)}.pdf';
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
        SnackBar(content: Text('تم حفظ تقرير الامتحان في: ${file.path}')),
      );
      debugPrint('✅ Exam report generated successfully!');
    } catch (e) {
      debugPrint('❌ Error in exam report: $e');
      // إغلاق مؤشر التحميل إذا كان مفتوحاً
      try {
        Navigator.pop(context);
      } catch (_) {}
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: $e')),
      );
    }
  }
}

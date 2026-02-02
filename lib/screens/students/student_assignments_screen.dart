import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/exam_provider.dart';
import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/attendance_model.dart';
import '../../database/database_helper.dart';
import '../../theme/app_theme.dart';
import 'student_attendance_screen.dart';
import '../notes/student_notes_main_screen.dart';
import 'student_attendance_pdf.dart';
import '../../utils/date_filter_helper.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  final StudentModel student;
  final ClassModel? classModel;

  const StudentAssignmentsScreen({
    super.key,
    required this.student,
    this.classModel,
  });

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  List<ExamModel> _studentExams = [];
  bool _isLoading = true;
  String _selectedDateFilter = 'التواريخ: الكل';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _className;
  ClassModel? _classModel;

  @override
  void initState() {
    super.initState();
    _loadDateFilter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudentExams();
      _loadClassName();
    });
  }

  Future<void> _loadDateFilter() async {
    final filterData = await DateFilterHelper.getDateFilter();
    setState(() {
      _selectedDateFilter = filterData['filter'];
      _startDate = filterData['startDate'];
      _endDate = filterData['endDate'];
    });
  }

  Future<void> _loadClassName() async {
    try {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      await classProvider.loadClasses();
      
      if (!mounted) return;
      
      final classModel = classProvider.classes.firstWhere(
        (c) => c.id == widget.student.classId,
        orElse: () => classProvider.classes.first,
      );
      
      setState(() {
        _className = classModel.name;
        _classModel = classModel;
      });
    } catch (e) {
      print('Error loading class name: $e');
      setState(() {
        _className = 'غير معروف';
        _classModel = null;
      });
    }
  }

  Future<void> _loadStudentExams() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final examProvider = Provider.of<ExamProvider>(context, listen: false);
      await examProvider.loadExamsByClass(widget.student.classId);
      
      if (!mounted) return;
      setState(() {
        _studentExams = examProvider.exams;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل الامتحانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<GradeInfo?> _getStudentGradeForExam(ExamModel exam) async {
    final dbHelper = DatabaseHelper();
    return await dbHelper.getStudentGradeForExam(widget.student.id!, exam.id!);
  }

  Future<double> _calculateOverallGrade() async {
    final filteredExams = _getFilteredExams();
    if (filteredExams.isEmpty) return 0.0;
    
    double totalObtained = 0;
    double totalPossible = 0;
    
    for (final exam in filteredExams) {
      final grade = await _getStudentGradeForExam(exam);
      
      if (grade != null && _shouldCountInAverage(grade.status ?? 'حاضر')) {
        totalObtained += _getScoreBasedOnStatus(grade, grade.status ?? 'حاضر');
        totalPossible += grade.totalMarks;
      }
    }
    
    return totalPossible > 0 ? (totalObtained / totalPossible) * 100 : 0.0;
  }

  Future<Map<String, int>> _getGradeDistribution() async {
    final filteredExams = _getFilteredExams();
    final distribution = {
      'أقل من 50%': 0,
      '50-60%': 0,
      '60-75%': 0,
      '85-99%': 0,
      '100%': 0,
    };

    for (final exam in filteredExams) {
      final grade = await _getStudentGradeForExam(exam);
      
      if (grade != null && _shouldCountInAverage(grade.status ?? 'حاضر')) {
        final percentage = (grade.obtainedMarks / grade.totalMarks) * 100;
        if (percentage < 50) {
          distribution['أقل من 50%'] = (distribution['أقل من 50%'] ?? 0) + 1;
        } else if (percentage >= 50 && percentage < 60) {
          distribution['50-60%'] = (distribution['50-60%'] ?? 0) + 1;
        } else if (percentage >= 60 && percentage < 75) {
          distribution['60-75%'] = (distribution['60-75%'] ?? 0) + 1;
        } else if (percentage >= 85 && percentage < 100) {
          distribution['85-99%'] = (distribution['85-99%'] ?? 0) + 1;
        } else if (percentage >= 99.5) { // For 100%
          distribution['100%'] = (distribution['100%'] ?? 0) + 1;
        }
      }
    }
    
    return distribution;
  }

  String _getDisplayText(GradeInfo? grade, String status) {
    // If status is not 'حاضر', show the status name instead of grade
    if (status != 'حاضر') {
      return status;
    }
    // For 'حاضر' status, show the grade
    return '${grade?.obtainedMarks.toStringAsFixed(1) ?? '0'}/${grade?.totalMarks.toStringAsFixed(1) ?? '0'}';
  }

  double _getScoreBasedOnStatus(GradeInfo grade, String status) {
    if (status == 'حاضر') {
      return grade.obtainedMarks;
    } else {
      // All statuses except 'مفقودة' count as 0
      return 0.0;
    }
  }

  bool _shouldCountInAverage(String status) {
    // Only 'حاضر' counts in average, 'مفقودة' doesn't count at all
    return status == 'حاضر';
  }

  String _formatDate(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  List<ExamModel> _getFilteredExams() {
    return DateFilterHelper.filterExams(
      _studentExams, 
      _selectedDateFilter, 
      _startDate, 
      _endDate, 
      (exam) => exam.date
    );
  }

  void _applyDateFilter() {
    _loadStudentExams();
  }

  void _showCustomDateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'اختر التاريخ',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'من تاريخ',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _startDate != null ? _formatDate(_startDate!) : 'اختر',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _startDate = date;
                  });
                }
              },
            ),
            ListTile(
              title: const Text(
                'إلى تاريخ',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _endDate != null ? _formatDate(_endDate!) : 'اختر',
                style: const TextStyle(color: Colors.white70),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? DateTime.now(),
                  firstDate: _startDate ?? DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() {
                    _endDate = date;
                  });
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () async {
              if (_startDate != null && _endDate != null) {
                // Save the custom date range to shared storage
                await DateFilterHelper.saveDateFilter('تاريخ محدد', _startDate, _endDate);
                
                setState(() {
                  _selectedDateFilter = 'تاريخ محدد';
                });
                _applyDateFilter();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellow,
              foregroundColor: Colors.black,
            ),
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(String option) {
    final isSelected = _selectedDateFilter == option;
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        
        // Save the filter to shared storage
        await DateFilterHelper.saveDateFilter(option, null, null);
        
        setState(() {
          _selectedDateFilter = option;
          _startDate = null;
          _endDate = null;
        });
        
        if (option == 'تاريخ محدد') {
          _showCustomDateDialog();
        } else {
          _applyDateFilter();
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          option,
          style: TextStyle(
            color: isSelected ? Colors.amber : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'فلترة حسب التاريخ',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFilterOption('التواريخ: الكل'),
            _buildFilterOption('اليوم'),
            _buildFilterOption('آخر أسبوع'),
            _buildFilterOption('آخر شهر'),
            _buildFilterOption('تاريخ محدد'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212), // Dark mode background
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E), // Dark gray
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.popUntil(context, (route) => route.isFirst); // Go to student details page
          },
        ),
        title: const Text(
          'الامتحانات',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _exportToPDF,
            child: const Text(
              'PDF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Student info card with yellow border
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.amber,
                width: 2.0,
              ),
            ),
            child: Column(
              children: [
                // Name and class row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.student.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _className ?? 'الصف الأول',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Date and average row
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _showDateFilterDialog,
                      child: Text(
                        _selectedDateFilter,
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FutureBuilder<double>(
                      future: _calculateOverallGrade(),
                      builder: (context, snapshot) {
                        final grade = snapshot.data ?? 0.0;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            grade > 0 ? 'المعدل: ${grade.toStringAsFixed(1)}%' : 'المعدل: —',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        // Grade distribution boxes
                        FutureBuilder<Map<String, int>>(
                          future: _getGradeDistribution(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            } else if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white));
                            } else {
                              final distribution = snapshot.data ?? {};
                              return _buildGradeDistributionBoxes(distribution);
                            }
                          },
                        ),
                        const SizedBox(height: 20),
                        // Exams list
                        _buildExamList(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      // Bottom navigation
      bottomNavigationBar: Container(
        height: 63,
        color: const Color(0xFF1A1A1A), // Blackish gray
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem('الحضور', Icons.event_available, false),
            _buildNavItem('الامتحانات', Icons.quiz, true),
            _buildNavItem('الملاحظات', Icons.note, false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (title == 'الحضور') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentAttendanceScreen(
                student: widget.student,
                classModel: widget.classModel ?? _getClassModel(),
              ),
            ),
          ).then((_) {
            // تحديث البيانات عند العودة من صفحة الحضور
            _loadStudentExams();
          });
        } else if (title == 'الملاحظات') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentNotesMainScreen(
                student: widget.student,
                classModel: widget.classModel ?? _getClassModel(),
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

  Widget _buildGradeDistributionBoxes(Map<String, int> distribution) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'توزيع الدرجات',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildGradeColumn('أقل من 50%', Colors.red.shade900, distribution['أقل من 50%'] ?? 0),
              _buildGradeColumn('50-60%', Colors.orange, distribution['50-60%'] ?? 0),
              _buildGradeColumn('60-75%', Colors.amber, distribution['60-75%'] ?? 0),
              _buildGradeColumn('85-99%', Colors.green, distribution['85-99%'] ?? 0),
              _buildGradeColumn('100%', Colors.green.shade900, distribution['100%'] ?? 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGradeColumn(String label, Color color, int count) {
    // Calculate dynamic height based on count
    final maxHeight = 80.0;
    final height = count > 0 ? (count / 5) * maxHeight : 0.0; // Assuming max 5 exams
    
    return Column(
      children: [
        // Column bar - only show if there are exams
        if (count > 0)
          Container(
            width: 40,
            height: height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
          )
        else
          const SizedBox(height: 4), // Small space when no column
        const SizedBox(height: 8),
        // Label box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 4),
        // Count
        Text(
          '$count',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildExamList() {
    final filteredExams = _getFilteredExams();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...filteredExams.map((exam) => _buildExamCard(exam)).toList(),
      ],
    );
  }

  Widget _buildExamCard(ExamModel exam) {
    return FutureBuilder<GradeInfo?>(
      future: _getStudentGradeForExam(exam),
      builder: (context, snapshot) {
        final grade = snapshot.data;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.amber.withValues(alpha: 0.3),
              width: 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date at top
              Text(
                _formatDate(exam.date),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              // Exam name and score
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      exam.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: GestureDetector(
                      onTap: () => _editScoreDirectly(exam, grade),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.5),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _getDisplayText(grade, grade?.status ?? 'حاضر'),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Show comment if exists, otherwise show add comment
              if (grade?.comment != null && grade!.comment!.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'التعليق:',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _addComment(exam, grade),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.amber,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        grade.comment!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                    ),
                    ],
                  ),
                )
              else
                GestureDetector(
                  onTap: () => _addComment(exam, grade ?? GradeInfo(obtainedMarks: 0, totalMarks: exam.maxScore)),
                  child: const Text(
                    'إضافة تعليق',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showScoreOptions(ExamModel exam, GradeInfo? grade) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          'خيارات الدرجة - ${exam.title}',
          style: const TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'تعديل الدرجة',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _editScoreDirectly(exam, grade);
              },
            ),
            ListTile(
              title: const Text(
                'إضافة تعليق',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _addComment(exam, grade!);
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

  void _addComment(ExamModel exam, GradeInfo grade) {
    final TextEditingController commentController = TextEditingController(
      text: grade.comment ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          'إضافة تعليق - ${exam.title}',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            labelText: 'التعليق',
            labelStyle: TextStyle(color: Colors.white70),
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
            onPressed: () async {
              Navigator.pop(context);
              
              try {
                final dbHelper = DatabaseHelper();
                final String currentStatus = (grade.status ?? 'حاضر');

                final updatedRows = await dbHelper.updateGradeWithStatus(
                  widget.student.id!,
                  exam.title,
                  grade.obtainedMarks,
                  grade.totalMarks,
                  exam.date,
                  commentController.text,
                  currentStatus,
                );

                if (updatedRows == 0) {
                  await dbHelper.insertGradeWithStatus(
                    widget.student.id!,
                    exam.title,
                    grade.obtainedMarks,
                    grade.totalMarks,
                    exam.date,
                    commentController.text,
                    currentStatus,
                  );
                }
                
                // Refresh data and sync with main screens
                _loadStudentExams();
                _notifyMainScreenUpdate();
                
                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حفظ التعليق بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('خطأ في حفظ التعليق: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton(String status, Color color, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Text(
          status,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _editScoreDirectly(ExamModel exam, GradeInfo? grade) {
    final TextEditingController scoreController = TextEditingController(
      text: grade?.obtainedMarks.toStringAsFixed(1) ?? '',
    );
    String selectedStatus = grade?.status ?? 'حاضر';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF2A2A2A),
          title: Text(
            'تعديل الدرجة - ${exam.title}',
            style: const TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: scoreController,
                decoration: InputDecoration(
                  labelText: 'الدرجة',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: const OutlineInputBorder(),
                  suffixText: '/${exam.maxScore}',
                  suffixStyle: const TextStyle(color: Colors.white70),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Text(
                'الحالة:',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildStatusButton('حاضر', Colors.green, selectedStatus == 'حاضر', () {
                    setState(() {
                      selectedStatus = 'حاضر';
                    });
                  }),
                  _buildStatusButton('غائب', Colors.red, selectedStatus == 'غائب', () {
                    setState(() {
                      selectedStatus = 'غائب';
                    });
                  }),
                  _buildStatusButton('متأخر', Colors.orange, selectedStatus == 'متأخر', () {
                    setState(() {
                      selectedStatus = 'متأخر';
                    });
                  }),
                  _buildStatusButton('غش', Colors.redAccent, selectedStatus == 'غش', () {
                    setState(() {
                      selectedStatus = 'غش';
                    });
                  }),
                  _buildStatusButton('مفقودة', Colors.brown, selectedStatus == 'مفقودة', () {
                    setState(() {
                      selectedStatus = 'مفقودة';
                    });
                  }),
                ],
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
                Navigator.pop(context);
                
                try {
                  final dbHelper = DatabaseHelper();
                  final newScore = double.tryParse(scoreController.text) ?? 0.0;
                  
                  if (grade != null) {
                    await dbHelper.updateGradeWithStatus(
                      widget.student.id!,
                      exam.title,
                      newScore,
                      exam.maxScore,
                      exam.date,
                      grade.comment ?? '',
                      selectedStatus,
                    );
                  } else {
                    await dbHelper.insertGradeWithStatus(
                      widget.student.id!,
                      exam.title,
                      newScore,
                      exam.maxScore,
                      exam.date,
                      '',
                      selectedStatus,
                    );
                  }
                  
                  // Refresh data and sync with main screens
                  _loadStudentExams();
                  _notifyMainScreenUpdate();
                  
                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم حفظ الدرجة بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ في حفظ الدرجة: $e'),
                        backgroundColor: Colors.red,
                      ),
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'حاضر':
        return Colors.green;
      case 'غائب':
        return Colors.red;
      case 'متأخر':
        return Colors.orange;
      case 'مطرود':
        return Colors.purple;
      case 'مفقودة':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  void _notifyMainScreenUpdate() {
    // Notify providers to refresh data in main screens
    if (mounted) {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final examProvider = Provider.of<ExamProvider>(context, listen: false);
      
      // Trigger refresh in main screens
      studentProvider.notifyListeners();
      examProvider.notifyListeners();
    }
  }

  void _exportToPDF() async {
    await StudentReportPDF.generatePDF(
      context: context,
      student: widget.student,
      classModel: widget.classModel,
      reportType: 'exams',
    );
  }

  pw.Widget _buildAttendanceBar(String label, int count, PdfColor color, pw.Font fontBold) {
    return pw.Column(
      children: [
        pw.Container(
          width: 60,
          height: 80,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 12,
            font: fontBold,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
        pw.Text(
          '$count',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            font: fontBold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildGradeDistributionChart(Map<String, double> grades, List<ExamModel> exams, pw.Font fontBold) {
    if (grades.isEmpty) {
      return pw.Text(
        'لا توجد درجات متاحة',
        style: pw.TextStyle(font: fontBold),
        textDirection: pw.TextDirection.rtl,
      );
    }

    return pw.Container(
      height: 150,
      child: pw.Column(
        children: [
          // Grade ranges
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: [
              _buildGradeRangeColumn('ممتاز', 90, 100, PdfColors.green, grades, fontBold),
              _buildGradeRangeColumn('جيد جداً', 80, 89, PdfColors.blue, grades, fontBold),
              _buildGradeRangeColumn('جيد', 70, 79, PdfColors.orange, grades, fontBold),
              _buildGradeRangeColumn('مقبول', 60, 69, PdfColors.red, grades, fontBold),
              _buildGradeRangeColumn('ضعيف', 0, 59, PdfColors.purple, grades, fontBold),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildGradeRangeColumn(String label, int minGrade, int maxGrade, PdfColor color, Map<String, double> grades, pw.Font fontBold) {
    final count = grades.values.where((grade) {
      final percentage = grade > 0 ? (grade / 100 * 100) : 0.0;
      return percentage >= minGrade && percentage <= maxGrade;
    }).length;

    return pw.Column(
      children: [
        pw.Container(
          width: 40,
          height: 60.0 * (count / grades.length), // Scale based on count
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            font: fontBold,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
        pw.Text(
          '$count',
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            font: fontBold,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildAttendanceRecordTable(List<AttendanceModel> attendances, pw.Font fontBold, pw.Font fontRegular) {
    // Group attendances by month
    final Map<String, List<AttendanceModel>> monthlyAttendances = {};
    final List<String> monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    
    for (final attendance in attendances) {
      final month = monthNames[attendance.date.month - 1];
      if (!monthlyAttendances.containsKey(month)) {
        monthlyAttendances[month] = [];
      }
      monthlyAttendances[month]!.add(attendance);
    }

    // Take only first 3 months
    final selectedMonths = monthlyAttendances.keys.take(3).toList();
    
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        children: [
          // Header row with month names
          pw.Container(
            color: PdfColors.blue,
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: selectedMonths.map((month) => pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    month,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      font: fontBold,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              )).toList(),
            ),
          ),
          // Days row
          pw.Container(
            color: PdfColors.grey700,
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: selectedMonths.map((month) => pw.Expanded(
                child: pw.Center(
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: monthlyAttendances[month]?.map((attendance) => pw.Container(
                      width: 20,
                      child: pw.Center(
                        child: pw.Text(
                          attendance.date.day.toString(),
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            font: fontRegular,
                          ),
                        ),
                      ),
                    )).toList() ?? [],
                  ),
                ),
              )).toList(),
            ),
          ),
          // Status row
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.all(8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: selectedMonths.map((month) => pw.Expanded(
                child: pw.Center(
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                    children: monthlyAttendances[month]?.map((attendance) {
                      String status;
                      PdfColor color;
                      
                      switch (attendance.status) {
                        case AttendanceStatus.present:
                          status = 'P';
                          color = PdfColors.green;
                          break;
                        case AttendanceStatus.absent:
                          status = 'U';
                          color = PdfColors.orange;
                          break;
                        case AttendanceStatus.late:
                          status = 'T';
                          color = PdfColors.orange;
                          break;
                        case AttendanceStatus.excused:
                          status = 'EX';
                          color = PdfColors.blue;
                          break;
                        case AttendanceStatus.expelled:
                          status = 'E';
                          color = PdfColors.grey;
                          break;
                        default:
                          status = 'E';
                          color = PdfColors.grey;
                      }
                      
                      return pw.Container(
                        width: 20,
                        height: 20,
                        decoration: pw.BoxDecoration(
                          color: color,
                          borderRadius: pw.BorderRadius.circular(2),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            status,
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                              font: fontBold,
                            ),
                          ),
                        ),
                      );
                    }).toList() ?? [],
                  ),
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildBar(String label, int value, int total, PdfColor color, pw.Font fontBold) {
    final percentage = total > 0 ? (value / total) : 0.0;
    return pw.Column(
      children: [
        pw.Container(
          width: 40,
          height: 60 * percentage,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            font: fontBold,
          ),
        ),
      ],
    );
  }

  ClassModel _getClassModel() {
    return _classModel ?? ClassModel(
      id: widget.student.classId,
      name: _className ?? 'غير معروف',
      subject: 'عام',
      year: '2024',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }
}

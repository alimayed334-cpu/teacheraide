import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/student_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../database/database_helper.dart';
import '../../providers/student_provider.dart';
import '../../providers/exam_provider.dart';

class GradeInfo {
  final double obtainedMarks;
  final double totalMarks;
  final String? comment;
  final String? status;

  GradeInfo({
    required this.obtainedMarks,
    required this.totalMarks,
    this.comment,
    this.status,
  });
}

class StudentAssignmentsScreen extends StatefulWidget {
  final StudentModel student;

  const StudentAssignmentsScreen({
    super.key,
    required this.student,
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudentExams();
    });
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
      '75-85%': 0,
      '85% فأعلى': 0,
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
        } else if (percentage >= 75 && percentage < 85) {
          distribution['75-85%'] = (distribution['75-85%'] ?? 0) + 1;
        } else {
          distribution['85% فأعلى'] = (distribution['85% فأعلى'] ?? 0) + 1;
        }
      }
    }
    
    return distribution;
  }

  String _getDisplayText(GradeInfo? grade, String status) {
    if (status == 'حاضر') {
      return '${grade?.obtainedMarks.toStringAsFixed(1) ?? '0'}/${grade?.totalMarks.toStringAsFixed(1) ?? '0'}';
    } else if (status == 'مفقودة') {
      return 'مفقودة';
    } else {
      return status;
    }
  }

  double _getScoreBasedOnStatus(GradeInfo grade, String status) {
    if (status == 'حاضر') {
      return grade.obtainedMarks;
    } else {
      return 0.0;
    }
  }

  bool _shouldCountInAverage(String status) {
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
    if (_selectedDateFilter == 'التواريخ: الكل') {
      return _studentExams;
    } else if (_selectedDateFilter == 'اليوم') {
      final today = DateTime.now();
      return _studentExams.where((exam) {
        return exam.date.year == today.year &&
               exam.date.month == today.month &&
               exam.date.day == today.day;
      }).toList();
    } else if (_selectedDateFilter == 'آخر أسبوع') {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      return _studentExams.where((exam) => exam.date.isAfter(weekAgo)).toList();
    } else if (_selectedDateFilter == 'آخر شهر') {
      final monthAgo = DateTime.now().subtract(const Duration(days: 30));
      return _studentExams.where((exam) => exam.date.isAfter(monthAgo)).toList();
    } else if (_selectedDateFilter == 'تاريخ محدد' && _startDate != null && _endDate != null) {
      return _studentExams.where((exam) {
        return exam.date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
               exam.date.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }
    return _studentExams;
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
                  lastDate: DateTime(2025),
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
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2025),
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
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedDateFilter = 'تاريخ محدد';
              });
              _applyDateFilter();
              Navigator.pop(context);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(String option) {
    return ListTile(
      title: Text(
        option,
        style: const TextStyle(color: Colors.white),
      ),
      onTap: () {
        Navigator.pop(context);
        
        if (option == 'تاريخ محدد') {
          _showCustomDateDialog();
        } else {
          setState(() {
            _selectedDateFilter = option;
          });
          _applyDateFilter();
        }
      },
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedDateFilter = 'تاريخ محدد';
              });
              _applyDateFilter();
            },
            child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
          ),
        ],
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
          onPressed: () => Navigator.pop(context),
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
          IconButton(
            icon: const Icon(Icons.message, color: Colors.white),
            onPressed: () {
              // Message functionality
            },
          ),
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
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // Settings functionality
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Student info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF1E1E1E),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.student.name,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'الصف الأول', // Will be dynamic based on class
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FutureBuilder<double>(
                      future: _calculateOverallGrade(),
                      builder: (context, snapshot) {
                        final grade = snapshot.data ?? 0.0;
                        return Text(
                          grade > 0 ? 'المعدل: ${grade.toStringAsFixed(1)}%' : 'المعدل: —',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: _showDateFilterDialog,
                      child: Text(
                        _selectedDateFilter,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Chart section
                        FutureBuilder<Map<String, int>>(
                          future: _getGradeDistribution(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator(color: Colors.white));
                            } else if (snapshot.hasError) {
                              return Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white));
                            } else {
                              final distribution = snapshot.data ?? {};
                              return _buildGradeChart(distribution);
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
        height: 60,
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
        // Navigation logic
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? const Color(0xFFFFD700) : Colors.grey[600],
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: isActive ? const Color(0xFFFFD700) : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeChart(Map<String, int> distribution) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A), // Dark gray box
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Chart with vertical scale
          SizedBox(
            height: 200,
            child: Row(
              children: [
                // Vertical scale
                SizedBox(
                  width: 40,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('100%', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('50%', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Text('0%', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Chart bars
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildChartBar('أقل من 50%', Colors.red, distribution['أقل من 50%'] ?? 0),
                      _buildChartBar('50-60%', Colors.orange, distribution['50-60%'] ?? 0),
                      _buildChartBar('60-75%', const Color(0xFFCDDC39), distribution['60-75%'] ?? 0), // Yellowish green
                      _buildChartBar('75-85%', const Color(0xFF8BC34A), distribution['75-85%'] ?? 0), // Light green
                      _buildChartBar('85% فأعلى', const Color(0xFF4CAF50), distribution['85% فأعلى'] ?? 0), // Dark green
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Color boxes with numbers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildColorBox('أقل من 50%', Colors.red, distribution['أقل من 50%'] ?? 0),
              _buildColorBox('50-60%', Colors.orange, distribution['50-60%'] ?? 0),
              _buildColorBox('60-75%', const Color(0xFFCDDC39), distribution['60-75%'] ?? 0),
              _buildColorBox('75-85%', const Color(0xFF8BC34A), distribution['75-85%'] ?? 0),
              _buildColorBox('85% فأعلى', const Color(0xFF4CAF50), distribution['85% فأعلى'] ?? 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartBar(String label, Color color, int count) {
    final maxHeight = 150.0;
    final height = count > 0 ? (count / 5) * maxHeight : 0.0; // Assuming max 5 exams
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 30,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildColorBox(String label, Color color, int count) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
            color: const Color(0xFF2A2A2A), // Dark gray card
            borderRadius: BorderRadius.circular(12),
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
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showScoreOptions(exam, grade),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A4A4A), // Light gray box
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getDisplayText(grade, grade?.status ?? 'حاضر'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Add comment text
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
                _editScore(exam, grade);
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
          textDirection: TextDirection.rtl,
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
                final updatedGrade = GradeModel(
                  id: 0,
                  studentId: widget.student.id!,
                  examName: exam.title,
                  score: grade.obtainedMarks,
                  maxScore: grade.totalMarks,
                  examDate: exam.date,
                  notes: commentController.text,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                await dbHelper.updateGradeByStudentAndExam(
                  widget.student.id!,
                  exam.title,
                  updatedGrade,
                );
                
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

  void _editScore(ExamModel exam, GradeInfo? grade) {
    final TextEditingController scoreController = TextEditingController(
      text: grade?.obtainedMarks.toStringAsFixed(1) ?? '',
    );
    String selectedStatus = grade?.status ?? 'حاضر';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 16),
            const Text(
              'الحالة:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
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
                _buildStatusButton('مطرود', Colors.purple, selectedStatus == 'مطرود', () {
                  setState(() {
                    selectedStatus = 'مطرود';
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
                  final updatedGrade = GradeModel(
                    id: 0,
                    studentId: widget.student.id!,
                    examName: exam.title,
                    score: newScore,
                    maxScore: exam.maxScore,
                    examDate: exam.date,
                    notes: grade.comment ?? '',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  await dbHelper.updateGradeByStudentAndExam(
                    widget.student.id!,
                    exam.title,
                    updatedGrade,
                  );
                } else {
                  final newGrade = GradeModel(
                    id: 0,
                    studentId: widget.student.id!,
                    examName: exam.title,
                    score: newScore,
                    maxScore: exam.maxScore,
                    examDate: exam.date,
                    notes: '',
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  await dbHelper.insertGrade(newGrade);
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
    );
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

  void _exportToPDF() {
    // TODO: Implement PDF export functionality
    if (mounted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تصدير PDF قيد التطوير'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }
}

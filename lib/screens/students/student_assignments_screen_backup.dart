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
  String _selectedDateFilter = 'الكل';
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
      if (mounted) {
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
      '100%': 0,
      '≥85%': 0,
      '50-84%': 0,
      '<50%': 0,
    };

    for (final exam in filteredExams) {
      final grade = await _getStudentGradeForExam(exam);
      
      if (grade != null && _shouldCountInAverage(grade.status ?? 'حاضر')) {
        final percentage = (grade.obtainedMarks / grade.totalMarks) * 100;
        if (percentage >= 100) {
          distribution['100%'] = (distribution['100%'] ?? 0) + 1;
        } else if (percentage >= 85) {
          distribution['≥85%'] = (distribution['≥85%'] ?? 0) + 1;
        } else if (percentage >= 50) {
          distribution['50-84%'] = (distribution['50-84%'] ?? 0) + 1;
        } else {
          distribution['<50%'] = (distribution['<50%'] ?? 0) + 1;
        }
      }
    }
    
    return distribution;
  }

  String _getDisplayText(GradeInfo? grade, String status) {
    if (status == 'حاضر') {
      return '${grade?.obtainedMarks.toStringAsFixed(1) ?? '0'}/${grade?.totalMarks.toStringAsFixed(1) ?? '0'}';
    } else if (status == 'مفقود') {
      return 'مفقود';
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
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<ExamModel> _getFilteredExams() {
    if (_selectedDateFilter == 'الكل') {
      return _studentExams;
    }
    
    final now = DateTime.now();
    DateTime? startDate;
    DateTime? endDate;
    
    switch (_selectedDateFilter) {
      case 'اليوم':
        startDate = DateTime(now.year, now.month, now.day);
        endDate = startDate?.add(const Duration(days: 1));
        break;
      case 'آخر أسبوع':
        startDate = now.subtract(const Duration(days: 7));
        endDate = now;
        break;
      case 'آخر شهر':
        startDate = now.subtract(const Duration(days: 30));
        endDate = now;
        break;
      case 'تاريخ محدد':
        startDate = _startDate;
        endDate = _endDate;
        break;
    }
    
    if (startDate == null || endDate == null) {
      return _studentExams;
    }
    
    return _studentExams.where((exam) {
      final examDate = exam.date;
      return examDate.isAfter(startDate!.subtract(const Duration(days: 1))) &&
             examDate.isBefore(endDate!.add(const Duration(days: 1)));
    }).toList();
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
            _buildFilterOption('الكل'),
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
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text('واجبات الطالب: ${widget.student.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showDateFilterDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStudentInfoSection(),
                  const SizedBox(height: 20),
                  FutureBuilder<double>(
                    future: _calculateOverallGrade(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else {
                        final overallGrade = snapshot.data ?? 0.0;
                        return _buildGradeSummary(overallGrade);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  FutureBuilder<Map<String, int>>(
                    future: _getGradeDistribution(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const CircularProgressIndicator();
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      } else {
                        final distribution = snapshot.data ?? {};
                        return _buildGradeChart(distribution);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildExamList(),
                ],
              ),
            ),
    );
  }

  Widget _buildStudentInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'معلومات الطالب',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'الاسم: ${widget.student.name}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            'الرقم: ${widget.student.id}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            'الفصل: ${widget.student.classId}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeSummary(double overallGrade) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مجموع الدرجات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${overallGrade.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: overallGrade >= 85 ? Colors.green : 
                     overallGrade >= 50 ? Colors.orange : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeChart(Map<String, int> distribution) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'توزيع الدرجات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          ...distribution.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      entry.key,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: entry.value > 0 ? entry.value / _getFilteredExams().length : 0,
                      backgroundColor: Colors.grey[600],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        entry.key == '100%' ? Colors.green :
                        entry.key == '≥85%' ? Colors.blue :
                        entry.key == '50-84%' ? Colors.orange : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildExamList() {
    final filteredExams = _getFilteredExams();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الامتحانات (${filteredExams.length})',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        ...filteredExams.map((exam) => _buildExamCard(exam)).toList(),
      ],
    );
  }

  Widget _buildExamCard(ExamModel exam) {
    return FutureBuilder<GradeInfo?>(
      future: _getStudentGradeForExam(exam),
      builder: (context, snapshot) {
        final grade = snapshot.data;
        final percentage = grade != null ? (grade.obtainedMarks / grade.totalMarks) * 100 : 0.0;
        final color = percentage >= 85 ? Colors.green : 
                      percentage >= 50 ? Colors.orange : Colors.red;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exam.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          _formatDate(exam.date),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showScoreOptions(exam, grade),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        _getDisplayText(grade, grade?.status ?? 'حاضر'),
                        style: TextStyle(
                          color: color,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
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
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حفظ التعليق بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
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
                _buildStatusButton('غش', Colors.purple, selectedStatus == 'غش', () {
                  setState(() {
                    selectedStatus = 'غش';
                  });
                }),
                _buildStatusButton('مفقود', Colors.brown, selectedStatus == 'مفقود', () {
                  setState(() {
                    selectedStatus = 'مفقود';
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
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم حفظ الدرجة بنجاح'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
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
}

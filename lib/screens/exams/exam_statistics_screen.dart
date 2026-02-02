import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/exam_model.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../providers/exam_provider.dart';
import '../../theme/app_theme.dart';
import 'exams_screen.dart';
import 'package:intl/intl.dart';

class ExamStatisticsScreen extends StatefulWidget {
  final ExamModel exam;
  final ClassModel classModel;
  final Map<int, Map<int, double>> studentGrades;
  final Map<int, Map<int, GradeStatus>> studentStatus;
  final List<StudentModel> students;

  const ExamStatisticsScreen({
    super.key,
    required this.exam,
    required this.classModel,
    required this.studentGrades,
    required this.studentStatus,
    required this.students,
  });

  @override
  State<ExamStatisticsScreen> createState() => _ExamStatisticsScreenState();
}

class _ExamStatisticsScreenState extends State<ExamStatisticsScreen> {
  late ExamModel _currentExam;

  @override
  void initState() {
    super.initState();
    _currentExam = widget.exam;
  }

  // حساب متوسط الدرجات
  double _calculateAveragePercentage() {
    double totalPercentage = 0;
    int count = 0;

    for (final student in widget.students) {
      final grade = widget.studentGrades[student.id!]?[_currentExam.id!];
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      
      if (grade != null && status == GradeStatus.present) {
        totalPercentage += (grade / _currentExam.maxScore) * 100;
        count++;
      }
    }

    return count > 0 ? totalPercentage / count : 0;
  }

  // حساب عدد الطلاب الحاضرين فقط (حالة present فقط)
  int _getPresentStudentsCount() {
    int count = 0;
    for (final student in widget.students) {
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      if (status == GradeStatus.present) {
        count++;
      }
    }
    return count;
  }

  // حساب عدد الطلاب الغائبين فقط (حالة absent فقط)
  int _getAbsentStudentsCount() {
    int count = 0;
    for (final student in widget.students) {
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      if (status == GradeStatus.absent) {
        count++;
      }
    }
    return count;
  }

  // حساب عدد حالات الغش
  int _getCheatingCount() {
    int count = 0;
    for (final student in widget.students) {
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      if (status == GradeStatus.cheating) {
        count++;
      }
    }
    return count;
  }

  // حساب عدد الأوراق المفقودة
  int _getMissingPapersCount() {
    int count = 0;
    for (final student in widget.students) {
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      if (status == GradeStatus.missing) {
        count++;
      }
    }
    return count;
  }

  // حساب توزيع النسب المئوية
  Map<String, int> _getPercentageDistribution() {
    Map<String, int> distribution = {
      '100%': 0,
      '90-99%': 0,
      '80-89%': 0,
      '70-79%': 0,
      '60-69%': 0,
      '50-59%': 0,
      '40-49%': 0,
      '30-39%': 0,
      '20-29%': 0,
      '10-19%': 0,
      '0-9%': 0,
    };

    for (final student in widget.students) {
      final grade = widget.studentGrades[student.id!]?[_currentExam.id!];
      final status = widget.studentStatus[student.id!]?[_currentExam.id!];
      
      if (grade != null && status == GradeStatus.present) {
        final percentage = (grade / _currentExam.maxScore) * 100;
        
        if (percentage == 100) {
          distribution['100%'] = distribution['100%']! + 1;
        } else if (percentage >= 90) {
          distribution['90-99%'] = distribution['90-99%']! + 1;
        } else if (percentage >= 80) {
          distribution['80-89%'] = distribution['80-89%']! + 1;
        } else if (percentage >= 70) {
          distribution['70-79%'] = distribution['70-79%']! + 1;
        } else if (percentage >= 60) {
          distribution['60-69%'] = distribution['60-69%']! + 1;
        } else if (percentage >= 50) {
          distribution['50-59%'] = distribution['50-59%']! + 1;
        } else if (percentage >= 40) {
          distribution['40-49%'] = distribution['40-49%']! + 1;
        } else if (percentage >= 30) {
          distribution['30-39%'] = distribution['30-39%']! + 1;
        } else if (percentage >= 20) {
          distribution['20-29%'] = distribution['20-29%']! + 1;
        } else if (percentage >= 10) {
          distribution['10-19%'] = distribution['10-19%']! + 1;
        } else {
          distribution['0-9%'] = distribution['0-9%']! + 1;
        }
      }
    }

    return distribution;
  }

  // الحصول على لون العمود حسب النسبة
  Color _getBarColor(String range) {
    switch (range) {
      case '100%':
        return Colors.green[900]!;
      case '90-99%':
        return Colors.green[700]!;
      case '80-89%':
        return Colors.green[500]!;
      case '70-79%':
        return Colors.lightGreen[600]!;
      case '60-69%':
        return Colors.yellow[700]!;
      case '50-59%':
        return Colors.orange[600]!;
      case '40-49%':
        return Colors.orange[800]!;
      case '30-39%':
        return Colors.red[400]!;
      case '20-29%':
        return Colors.red[600]!;
      case '10-19%':
        return Colors.red[800]!;
      default:
        return Colors.red[900]!;
    }
  }

  void _showEditExamDialog() {
    final titleController = TextEditingController(text: _currentExam.title);
    final maxScoreController = TextEditingController(text: _currentExam.maxScore.toString());
    DateTime selectedDate = _currentExam.date;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('تعديل تفاصيل الامتحان'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الامتحان',
                    prefixIcon: Icon(Icons.title),
                  ),
                  enabled: !isLoading,
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('تاريخ الامتحان'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
                  enabled: !isLoading,
                  onTap: isLoading ? null : () async {
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
                const SizedBox(height: 16),
                TextField(
                  controller: maxScoreController,
                  decoration: const InputDecoration(
                    labelText: 'الدرجة القصوى',
                    prefixIcon: Icon(Icons.grade),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !isLoading,
                ),
                if (isLoading) ...[
                  const SizedBox(height: 20),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('جاري الحفظ...'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                // تحديث فوري للواجهة
                setDialogState(() {
                  isLoading = true;
                });
                
                // تحديث فوري للبيانات في الواجهة
                final tempExam = _currentExam.copyWith(
                  title: titleController.text,
                  date: selectedDate,
                  maxScore: double.parse(maxScoreController.text),
                  updatedAt: DateTime.now(),
                );
                
                setState(() {
                  _currentExam = tempExam;
                });
                
                Navigator.pop(context);
                
                // عرض رسالة نجاح فورية
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث تفاصيل الامتحان'),
                    duration: Duration(seconds: 2),
                  ),
                );
                
                // حفظ في قاعدة البيانات في الخلفية
                try {
                  final examProvider = Provider.of<ExamProvider>(context, listen: false);
                  await examProvider.updateExam(tempExam);
                } catch (e) {
                  // في حالة فشل الحفظ، عرض رسالة خطأ
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تعذر حفظ التغييرات، يرجى المحاولة مرة أخرى'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final averagePercentage = _calculateAveragePercentage();
    final presentCount = _getPresentStudentsCount();
    final absentCount = _getAbsentStudentsCount();
    final cheatingCount = _getCheatingCount();
    final missingCount = _getMissingPapersCount();
    final distribution = _getPercentageDistribution();

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.classModel.name,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _showEditExamDialog,
            tooltip: 'تعديل تفاصيل الامتحان',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات الامتحان
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade700, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    _currentExam.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('dd/MM/yyyy').format(_currentExam.date),
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الدرجة القصوى: ${_currentExam.maxScore.toInt()}',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // الإحصائيات العامة
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade700, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الإحصائيات العامة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildStatisticRow('متوسط الدرجات', '${averagePercentage.toStringAsFixed(1)}%', Colors.blue),
                  const SizedBox(height: 12),
                  _buildStatisticRow('الطلاب الحاضرين', '$presentCount', Colors.green),
                  const SizedBox(height: 12),
                  _buildStatisticRow('الطلاب الغائبين', '$absentCount', Colors.red),
                  if (cheatingCount > 0) ...[
                    const SizedBox(height: 12),
                    _buildStatisticRow('حالات الغش', '$cheatingCount', Colors.orange),
                  ],
                  if (missingCount > 0) ...[
                    const SizedBox(height: 12),
                    _buildStatisticRow('الأوراق المفقودة', '$missingCount', Colors.purple),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // مخطط توزيع النسب المئوية
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade700, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'توزيع النسب المئوية',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // المخطط البياني
                  SizedBox(
                    height: 300,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: distribution.entries.map((entry) {
                        final maxCount = distribution.values.reduce((a, b) => a > b ? a : b);
                        final height = maxCount > 0 ? (entry.value / maxCount) * 250 : 0.0;
                        
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (entry.value > 0)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${entry.value}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                Container(
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: _getBarColor(entry.key),
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Transform.rotate(
                                  angle: -0.5,
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 8,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[300],
            fontSize: 16,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.5)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

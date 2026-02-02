import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/grade_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/class_model.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  ClassModel? _selectedClass;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ClassProvider>(context, listen: false).loadClasses();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير والإحصائيات'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'نظرة عامة', icon: Icon(Icons.dashboard)),
            Tab(text: 'الطلاب', icon: Icon(Icons.people)),
            Tab(text: 'الحضور', icon: Icon(Icons.how_to_reg)),
            Tab(text: 'الدرجات', icon: Icon(Icons.assessment)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _exportReport(context),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(
            selectedClass: _selectedClass,
            startDate: _startDate,
            endDate: _endDate,
          ),
          _StudentsReportTab(
            selectedClass: _selectedClass,
            startDate: _startDate,
            endDate: _endDate,
          ),
          _AttendanceReportTab(
            selectedClass: _selectedClass,
            startDate: _startDate,
            endDate: _endDate,
          ),
          _GradesReportTab(
            selectedClass: _selectedClass,
            startDate: _startDate,
            endDate: _endDate,
          ),
        ],
      ),
    );
  }

  void _showFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فلترة التقارير'),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Consumer<ClassProvider>(
                  builder: (context, classProvider, child) {
                    return DropdownButtonFormField<ClassModel?>(
                      initialValue: _selectedClass,
                      decoration: const InputDecoration(
                        labelText: 'الفصل',
                        hintText: 'جميع الفصول',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('جميع الفصول'),
                        ),
                        ...classProvider.classes.map((classModel) => DropdownMenuItem(
                          value: classModel,
                          child: Text(classModel.name),
                        )),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedClass = value;
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(2020),
                      lastDate: _endDate,
                    );
                    if (date != null) {
                      setState(() {
                        _startDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primaryColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text('من: ${_formatDate(_startDate)}'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _endDate,
                      firstDate: _startDate,
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() {
                        _endDate = date;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.primaryColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text('إلى: ${_formatDate(_endDate)}'),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('تطبيق'),
          ),
        ],
      ),
    );
  }

  void _exportReport(BuildContext context) async {
    try {
      // تحميل خط عربي من Google Fonts
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();
      
      final pdf = pw.Document();
      
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Text(
                    'تقرير مساعد المعلم',
                    style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.Text('الفترة: ${_formatDate(_startDate)} - ${_formatDate(_endDate)}', 
                  style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl),
                if (_selectedClass != null) 
                  pw.Text('الفصل: ${_selectedClass!.name}', 
                    style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl),
                pw.SizedBox(height: 20),
                // TODO: إضافة محتوى التقرير
                pw.Text('سيتم إضافة محتوى التقرير هنا...', 
                  style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl),
              ],
            );
          },
        ),
      );

      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'teacher_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير التقرير: $e')),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _OverviewTab extends StatelessWidget {
  final ClassModel? selectedClass;
  final DateTime startDate;
  final DateTime endDate;

  const _OverviewTab({
    required this.selectedClass,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer4<ClassProvider, StudentProvider, AttendanceProvider, GradeProvider>(
      builder: (context, classProvider, studentProvider, attendanceProvider, gradeProvider, child) {
        final totalClasses = selectedClass != null ? 1 : classProvider.classes.length;
        final totalStudents = selectedClass != null
            ? studentProvider.students.where((s) => s.classId == selectedClass!.id).length
            : studentProvider.students.length;
        final totalAttendance = attendanceProvider.attendanceRecords.length;
        final totalGrades = gradeProvider.grades.length;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // بطاقات الإحصائيات الرئيسية
              const Text(
                'إحصائيات عامة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _StatCard(
                    title: 'الفصول',
                    value: totalClasses.toString(),
                    icon: Icons.class_,
                    color: AppTheme.primaryColor,
                  ),
                  _StatCard(
                    title: 'الطلاب',
                    value: totalStudents.toString(),
                    icon: Icons.people,
                    color: AppTheme.successColor,
                  ),
                  _StatCard(
                    title: 'سجلات الحضور',
                    value: totalAttendance.toString(),
                    icon: Icons.how_to_reg,
                    color: AppTheme.secondaryColor,
                  ),
                  _StatCard(
                    title: 'الدرجات',
                    value: totalGrades.toString(),
                    icon: Icons.assessment,
                    color: AppTheme.warningColor,
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // الرسوم البيانية
              const Text(
                'الرسوم البيانية',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              // رسم بياني لتوزيع الطلاب على الفصول
              _ClassDistributionChart(classProvider: classProvider),
              
              const SizedBox(height: 24),
              
              // رسم بياني لنسب الحضور
              _AttendanceChart(attendanceProvider: attendanceProvider),
              
              const SizedBox(height: 24),
              
              // النشاطات الأخيرة
              const Text(
                'النشاطات الأخيرة',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              _RecentActivitiesList(),
            ],
          ),
        );
      },
    );
  }
}

class _StudentsReportTab extends StatelessWidget {
  final ClassModel? selectedClass;
  final DateTime startDate;
  final DateTime endDate;

  const _StudentsReportTab({
    required this.selectedClass,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<StudentProvider>(
      builder: (context, studentProvider, child) {
        final students = selectedClass != null
            ? studentProvider.students.where((s) => s.classId == selectedClass!.id).toList()
            : studentProvider.students;

        return Column(
          children: [
            // ملخص الطلاب
            Container(
              padding: const EdgeInsets.all(16),
              color: AppTheme.backgroundColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _SummaryItem(
                    label: 'إجمالي الطلاب',
                    value: students.length.toString(),
                    icon: Icons.people,
                  ),
                  const _SummaryItem(
                    label: 'متوسط الحضور',
                    value: '85%',
                    icon: Icons.trending_up,
                  ),
                  const _SummaryItem(
                    label: 'متوسط الدرجات',
                    value: '78.5',
                    icon: Icons.assessment,
                  ),
                ],
              ),
            ),
            
            // قائمة الطلاب
            Expanded(
              child: students.isEmpty
                  ? const Center(
                      child: Text('لا يوجد طلاب'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return _StudentReportCard(student: student);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AttendanceReportTab extends StatelessWidget {
  final ClassModel? selectedClass;
  final DateTime startDate;
  final DateTime endDate;

  const _AttendanceReportTab({
    required this.selectedClass,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AttendanceProvider>(
      builder: (context, attendanceProvider, child) {
        final records = attendanceProvider.attendanceRecords;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ملخص الحضور
              _AttendanceSummary(records: records),
              
              const SizedBox(height: 24),
              
              // رسم بياني للحضور
              _AttendancePieChart(records: records),
              
              const SizedBox(height: 24),
              
              // قائمة سجلات الحضور
              const Text(
                'سجلات الحضور الأخيرة',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              
              records.isEmpty
                  ? const Center(
                      child: Text('لا توجد سجلات حضور'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: records.take(10).length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return _AttendanceRecordCard(record: record);
                      },
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _GradesReportTab extends StatelessWidget {
  final ClassModel? selectedClass;
  final DateTime startDate;
  final DateTime endDate;

  const _GradesReportTab({
    required this.selectedClass,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GradeProvider>(
      builder: (context, gradeProvider, child) {
        final grades = gradeProvider.grades;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // ملخص الدرجات
              _GradesSummary(grades: grades),
              
              const SizedBox(height: 24),
              
              // رسم بياني للدرجات
              _GradesBarChart(grades: grades),
              
              const SizedBox(height: 24),
              
              // أفضل الطلاب
              _TopStudentsList(grades: grades),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: color,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassDistributionChart extends StatelessWidget {
  final ClassProvider classProvider;

  const _ClassDistributionChart({required this.classProvider});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'توزيع الطلاب على الفصول',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: classProvider.classes.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                if (value.toInt() >= classProvider.classes.length) {
                                  return const Text('');
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    classProvider.classes[value.toInt()].name.length > 8
                                        ? classProvider.classes[value.toInt()].name.substring(0, 8)
                                        : classProvider.classes[value.toInt()].name,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: classProvider.classes.asMap().entries.map((entry) {
                          return BarChartGroupData(
                            x: entry.key,
                            barRods: [
                              BarChartRodData(
                                toY: 15.0, // TODO: حساب عدد الطلاب الفعلي
                                color: AppTheme.primaryColor,
                                width: 20,
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceChart extends StatelessWidget {
  final AttendanceProvider attendanceProvider;

  const _AttendanceChart({required this.attendanceProvider});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'نسب الحضور الأسبوعية',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        const FlSpot(0, 85),
                        const FlSpot(1, 92),
                        const FlSpot(2, 78),
                        const FlSpot(3, 88),
                        const FlSpot(3, 95),
                        const FlSpot(4, 82),
                        const FlSpot(5, 90),
                      ],
                      isCurved: true,
                      color: AppTheme.successColor,
                      barWidth: 3,
                      belowBarData: BarAreaData(
                        show: true,
                        color: AppTheme.successColor.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivitiesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final activities = [
      {'title': 'إضافة طالب جديد', 'time': 'منذ 10 دقائق', 'icon': Icons.person_add},
      {'title': 'تسجيل حضور الفصل الأول', 'time': 'منذ ساعة', 'icon': Icons.how_to_reg},
      {'title': 'إضافة اختبار رياضيات', 'time': 'منذ 3 ساعات', 'icon': Icons.quiz},
      {'title': 'تعديل بيانات طالب', 'time': 'منذ يوم', 'icon': Icons.edit},
    ];

    return Card(
      child: Column(
        children: activities.map((activity) {
          return ListTile(
            leading: Icon(
              activity['icon'] as IconData,
              color: AppTheme.primaryColor,
            ),
            title: Text(activity['title'] as String),
            subtitle: Text(activity['time'] as String),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          );
        }).toList(),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 32,
          color: AppTheme.primaryColor,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _StudentReportCard extends StatelessWidget {
  final dynamic student;

  const _StudentReportCard({required this.student});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
          child: Text(
            student.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(student.name),
        subtitle: Text('الرقم: ${student.studentId}'),
        trailing: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '78.5',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.successColor,
                  ),
                ),
                Text(
                  'متوسط الدرجات',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(width: 8),
            Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
      ),
    );
  }
}

class _AttendanceSummary extends StatelessWidget {
  final List<dynamic> records;

  const _AttendanceSummary({required this.records});

  @override
  Widget build(BuildContext context) {
    final present = records.where((r) => r.status == 'present').length;
    final absent = records.where((r) => r.status == 'absent').length;
    final late = records.where((r) => r.status == 'late').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _AttendanceStat(
              label: 'حاضر',
              count: present,
              color: AppTheme.successColor,
              percentage: records.isNotEmpty ? (present / records.length * 100).round() : 0,
            ),
            _AttendanceStat(
              label: 'غائب',
              count: absent,
              color: AppTheme.errorColor,
              percentage: records.isNotEmpty ? (absent / records.length * 100).round() : 0,
            ),
            _AttendanceStat(
              label: 'متأخر',
              count: late,
              color: AppTheme.warningColor,
              percentage: records.isNotEmpty ? (late / records.length * 100).round() : 0,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final int percentage;

  const _AttendanceStat({
    required this.label,
    required this.count,
    required this.color,
    required this.percentage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          '$percentage%',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AttendancePieChart extends StatelessWidget {
  final List<dynamic> records;

  const _AttendancePieChart({required this.records});

  @override
  Widget build(BuildContext context) {
    final present = records.where((r) => r.status == 'present').length;
    final absent = records.where((r) => r.status == 'absent').length;
    final late = records.where((r) => r.status == 'late').length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'توزيع الحضور',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: records.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : PieChart(
                      PieChartData(
                        sections: [
                          PieChartSectionData(
                            value: present.toDouble(),
                            title: 'حاضر\n$present',
                            color: AppTheme.successColor,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          PieChartSectionData(
                            value: absent.toDouble(),
                            title: 'غائب\n$absent',
                            color: AppTheme.errorColor,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          PieChartSectionData(
                            value: late.toDouble(),
                            title: 'متأخر\n$late',
                            color: AppTheme.warningColor,
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttendanceRecordCard extends StatelessWidget {
  final dynamic record;

  const _AttendanceRecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    Color statusColor = AppTheme.successColor;
    String statusText = 'حاضر';
    
    if (record.status == 'absent') {
      statusColor = AppTheme.errorColor;
      statusText = 'غائب';
    } else if (record.status == 'late') {
      statusColor = AppTheme.warningColor;
      statusText = 'متأخر';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          Icons.how_to_reg,
          color: statusColor,
        ),
        title: Text(record.studentName ?? 'طالب'),
        subtitle: Text('${record.date.day}/${record.date.month}/${record.date.year}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _GradesSummary extends StatelessWidget {
  final List<dynamic> grades;

  const _GradesSummary({required this.grades});

  @override
  Widget build(BuildContext context) {
    final average = grades.isNotEmpty
        ? grades.map((g) => g.score).reduce((a, b) => a + b) / grades.length
        : 0.0;
    final highest = grades.isNotEmpty
        ? grades.map((g) => g.score).reduce((a, b) => a > b ? a : b)
        : 0.0;
    final lowest = grades.isNotEmpty
        ? grades.map((g) => g.score).reduce((a, b) => a < b ? a : b)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _GradeStat(
              label: 'المعدل',
              value: average.toStringAsFixed(1),
              color: AppTheme.primaryColor,
            ),
            _GradeStat(
              label: 'أعلى درجة',
              value: highest.toString(),
              color: AppTheme.successColor,
            ),
            _GradeStat(
              label: 'أقل درجة',
              value: lowest.toString(),
              color: AppTheme.errorColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _GradeStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _GradesBarChart extends StatelessWidget {
  final List<dynamic> grades;

  const _GradesBarChart({required this.grades});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'توزيع الدرجات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: grades.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        titlesData: const FlTitlesData(
                          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true)),
                        ),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          BarChartGroupData(
                            x: 0,
                            barRods: [
                              BarChartRodData(
                                toY: 85,
                                color: AppTheme.successColor,
                                width: 20,
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 1,
                            barRods: [
                              BarChartRodData(
                                toY: 92,
                                color: AppTheme.primaryColor,
                                width: 20,
                              ),
                            ],
                          ),
                          BarChartGroupData(
                            x: 2,
                            barRods: [
                              BarChartRodData(
                                toY: 78,
                                color: AppTheme.warningColor,
                                width: 20,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopStudentsList extends StatelessWidget {
  final List<dynamic> grades;

  const _TopStudentsList({required this.grades});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'أفضل 5 طلاب',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...List.generate(5, (index) {
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text('الطالب ${index + 1}'),
              trailing: Text(
                '${(95 - index * 2).toString()}/100',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.successColor,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

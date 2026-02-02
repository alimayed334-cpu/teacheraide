import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../models/student_model.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../database/database_helper.dart';
import '../../theme/app_theme.dart';
import '../notes/student_notes_main_screen.dart';
import 'student_assignments_screen.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final StudentModel student;
  final ClassModel classModel;
  final VoidCallback? onDataChanged;

  const StudentAttendanceScreen({
    super.key,
    required this.student,
    required this.classModel,
    this.onDataChanged,
  });

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  List<AttendanceModel> attendances = [];
  List<AttendanceModel> filteredAttendances = [];
  bool isLoading = true;
  String selectedMonth = 'الكل';
  String _selectedDateFilter = 'التواريخ: الكل';
  DateTime? _startDate;
  DateTime? _endDate;
  
  // إحصائيات الحضور
  int totalDays = 0;
  int presentDays = 0;
  int absentDays = 0;
  int lateDays = 0;
  int expelledDays = 0;
  
  @override
  void initState() {
    super.initState();
    _loadAttendanceData();
  }

  Future<void> _loadAttendanceData() async {
    setState(() => isLoading = true);
    
    try {
      final dbHelper = DatabaseHelper();
      final attendanceData = await dbHelper.getAttendanceByStudent(widget.student.id!);
      
      if (!mounted) return;
      
      setState(() {
        attendances = attendanceData;
        filteredAttendances = attendanceData;
        _calculateStatistics();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  void _calculateStatistics() {
    final filtered = _getFilteredAttendances();
    totalDays = filtered.length;
    presentDays = filtered.where((a) => a.status == AttendanceStatus.present).length;
    absentDays = filtered.where((a) => a.status == AttendanceStatus.absent).length;
    lateDays = filtered.where((a) => a.status == AttendanceStatus.late).length;
    expelledDays = filtered.where((a) => a.status == AttendanceStatus.expelled).length;
  }

  List<AttendanceModel> _getFilteredAttendances() {
    if (_selectedDateFilter == 'التواريخ: الكل') {
      return attendances;
    } else if (_selectedDateFilter == 'اليوم') {
      final today = DateTime.now();
      return attendances.where((attendance) {
        return attendance.date.year == today.year &&
               attendance.date.month == today.month &&
               attendance.date.day == today.day;
      }).toList();
    } else if (_selectedDateFilter == 'آخر أسبوع') {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));
      return attendances.where((attendance) => attendance.date.isAfter(weekAgo)).toList();
    } else if (_selectedDateFilter == 'آخر شهر') {
      final monthAgo = DateTime.now().subtract(const Duration(days: 30));
      return attendances.where((attendance) => attendance.date.isAfter(monthAgo)).toList();
    } else if (_selectedDateFilter == 'تاريخ محدد' && _startDate != null && _endDate != null) {
      return attendances.where((attendance) {
        return attendance.date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
               attendance.date.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }
    return attendances;
  }

  void _applyDateFilter() {
    setState(() {
      filteredAttendances = _getFilteredAttendances();
      _calculateStatistics();
    });
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
          _showCustomDateRangePicker();
        } else {
          setState(() {
            _selectedDateFilter = option;
          });
          _applyDateFilter();
        }
      },
    );
  }

  void _showCustomDateRangePicker() async {
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
              onTap: _selectStartDate,
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
              onTap: _selectEndDate,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              if (_startDate != null && _endDate != null) {
                setState(() {
                  _selectedDateFilter = 'تاريخ محدد';
                });
                _applyDateFilter();
              }
              Navigator.pop(context);
            },
            child: const Text('تطبيق', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      }
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              surface: Color(0xFF1A1A1A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      }
    );
    
    if (picked != null) {
      setState(() {
        _endDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  double get attendancePercentage => totalDays > 0 ? (presentDays / totalDays) * 100 : 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context); // Just go back to previous page (student details)
          },
        ),
        title: const Text(
          'الحضور',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home, color: Colors.white),
            onPressed: () {
              // Do nothing - disabled as per user request
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _exportToPDF,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStudentInfo(),
                  const SizedBox(height: 20),
                  _buildAttendanceChart(),
                  const SizedBox(height: 20),
                  _buildCalendarView(),
                  const SizedBox(height: 20),
                  _buildAttendanceLog(),
                  const SizedBox(height: 40), // مسافة إضافية في الأسفل
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildStudentInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.student.name,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.classModel.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'الحضور: ${attendancePercentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _showDateFilterDialog,
                child: Text(
                  _selectedDateFilter,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceChart() {
    return Container(
      height: 380,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'إحصائيات الحضور',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.center,
                groupsSpace: 70,
                maxY: totalDays > 0 ? totalDays.toDouble() : 10,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      String status;
                      Color color;

                      switch (group.x.toInt()) {
                        case 0: status = 'حاضر'; color = Colors.green; break;
                        case 1: status = 'غائب'; color = Colors.red; break;
                        case 2: status = 'متأخر'; color = Colors.yellow; break;
                        case 3: status = 'طرد'; color = Colors.purple; break;
                        default: status = ''; color = Colors.grey;
                      }

                      return BarTooltipItem(
                        '$status: ${rod.toY.toInt()}',
                        TextStyle(color: color, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        switch (value.toInt()) {
                          case 0: return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildStatusColumn('حاضر', Colors.green, presentDays));
                          case 1: return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildStatusColumn('غياب', Colors.red, absentDays));
                          case 2: return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildStatusColumn('تأخر', Colors.yellow, lateDays));
                          case 3: return Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _buildStatusColumn('طرد', Colors.purple, expelledDays));
                          default: return const SizedBox();
                        }
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: presentDays.toDouble(), color: Colors.green, width: 25)]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: absentDays.toDouble(), color: Colors.red, width: 25)]),
                  BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: lateDays.toDouble(), color: Colors.yellow, width: 25)]),
                  BarChartGroupData(x: 3, barRods: [BarChartRodData(toY: expelledDays.toDouble(), color: Colors.purple, width: 25)]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusColumn(String title, Color color, int count) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

  Widget _chartLabel(String text, Color color) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
  );
  }
}

  Widget _buildLegendItem(String code, Color color) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

  List<BarChartGroupData> _buildBarGroups() {
    return [
      BarChartGroupData(
        x: 0,
        barRods: [
          BarChartRodData(
            toY: presentDays.toDouble(),
            color: Colors.green,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
      BarChartGroupData(
        x: 1,
        barRods: [
          BarChartRodData(
            toY: absentDays.toDouble(),
            color: Colors.red,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
      BarChartGroupData(
        x: 2,
        barRods: [
          BarChartRodData(
            toY: lateDays.toDouble(),
            color: Colors.yellow,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
      BarChartGroupData(
        x: 3,
        barRods: [
          BarChartRodData(
            toY: expelledDays.toDouble(),
            color: Colors.purple,
            width: 20,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
      ),
    ];
  }
}

  Widget _buildCalendarView() {
    final months = _getAttendanceMonths();
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'التقويم الشهري',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...months.asMap().entries.map((entry) {
                    final isLast = entry.key == months.length - 1;
                    return Column(
                      children: [
                        _buildMonthCalendar(entry.key + 1, months[entry.key]),
                        if (!isLast) ...[
                          const SizedBox(height: 16),
                          Container(
                            height: 1,
                            color: Colors.grey.withOpacity(0.3),
                            margin: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    );
                  }
}).toList(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

  List<int> _getAttendanceMonths() {
    if (filteredAttendances.isEmpty) return [];
    
    final sortedAttendances = List.from(filteredAttendances);
    sortedAttendances.sort((a, b) => a.date.compareTo(b.date));
    
    final firstMonth = sortedAttendances.first.date.month;
    final lastMonth = sortedAttendances.last.date.month;
    
    return List.generate(lastMonth - firstMonth + 1, (index) => firstMonth + index);
  }
}

  Widget _buildMonthCalendar(int monthIndex, int month) {
    final monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    final monthAttendances = filteredAttendances.where((a) => a.date.month == month).toList();
    final weekDays = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          monthNames[month - 1],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        // أيام الأسبوع - ترتيب أفقي
        Row(
          children: weekDays.asMap().entries.map((entry) {
            final dayIndex = entry.key;
            final dayName = entry.value;
            final dayAttendances = monthAttendances.where((a) {
              final weekday = a.date.weekday == 7 ? 0 : a.date.weekday;
              return weekday == dayIndex;
            }
}).toList();
            
            return Expanded(
              child: Column(
                children: [
                  // اسم اليوم
                  Text(
                    dayName,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // مربعات الحضور تحت اسم اليوم - ترتيب عمودي
                  SizedBox(
                    height: 120, // ارتفاع كافي لعدة مربعات
                    child: SingleChildScrollView(
                      child: Column(
                        children: dayAttendances.map((attendance) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: _buildDayBox(attendance),
                          );
                        }
}).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
}).toList(),
        ),
      ],
    );
  }
}

  List<Widget> _buildWeekRows(List<AttendanceModel> monthAttendances) {
    if (monthAttendances.isEmpty) return [];
    
    final Map<int, List<AttendanceModel>> weekMap = {}
};
    for (final attendance in monthAttendances) {
      final weekNumber = _getWeekNumber(attendance.date);
      if (!weekMap.containsKey(weekNumber)) {
        weekMap[weekNumber] = [];
      }
}
      weekMap[weekNumber]!.add(attendance);
    }
}
    
    final sortedWeeks = weekMap.keys.toList()..sort();
    
    return sortedWeeks.map((weekNum) {
      final weekAttendances = weekMap[weekNum]!;
      final weekRow = List<Widget>.filled(7, const SizedBox());
      
      for (final attendance in weekAttendances) {
        int dayIndex = attendance.date.weekday == 7 ? 0 : attendance.date.weekday;
        weekRow[dayIndex] = Center(child: _buildDayBox(attendance));
      }
}
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: weekRow,
        ),
      );
    }
}).toList();
  }
}

  Widget _buildDayBox(AttendanceModel attendance) {
    final day = attendance.date.day;
    final weekday = attendance.date.weekday == 7 ? 0 : attendance.date.weekday;
    final weekDays = ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'];
    final dayName = weekDays[weekday];
    
    Color color;
    String status;
    
    switch (attendance.status) {
      case AttendanceStatus.present:
        color = Colors.green;
        status = 'حاضر';
        break;
      case AttendanceStatus.absent:
        color = Colors.red;
        status = 'غائب';
        break;
      case AttendanceStatus.late:
        color = Colors.yellow;
        status = 'متأخر';
        break;
      case AttendanceStatus.expelled:
        color = Colors.purple;
        status = 'طرد';
        break;
      default:
        color = Colors.grey;
        status = '';
    }
}
    
    return Container(
      width: 30,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.8), width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            '$day',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 0.5),
            decoration: BoxDecoration(
              color: color.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 4,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

  int _getWeekNumber(DateTime date) {
    final firstDayOfMonth = DateTime(date.year, date.month, 1);
    final daysDifference = date.difference(firstDayOfMonth).inDays;
    return (daysDifference / 7).floor() + 1;
  }
}

  Widget _buildAttendanceLog() {
    // التحقق من جميع سجلات الحضور وعرض التعليقات فقط
    final allAttendances = attendances; // استخدام جميع السجلات وليس فقط المفلترة
    final attendancesWithNotes = allAttendances.where((a) => a.notes != null && a.notes!.isNotEmpty).toList();
    
    // إضافة debug للطباعة
    print('Total attendances: ${allAttendances.length}
}');
    print('Attendances with notes: ${attendancesWithNotes.length}
}');
    for (var attendance in attendancesWithNotes) {
      print('Note: ${attendance.notes}
} on ${attendance.date}
}');
    }
}
    
    if (attendancesWithNotes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'سجل الملاحظات',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد ملاحظات',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
}
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'سجل الملاحظات',
            style: TextStyle(
              color: Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ...attendancesWithNotes.map((attendance) {
            final date = attendance.date;
            final formattedDate = DateFormat('d MMMM yyyy', 'ar').format(date);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(attendance.status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getStatusText(attendance.status),
                            style: TextStyle(
                              color: _getStatusColor(attendance.status),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          formattedDate,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _showEditNoteDialog(attendance),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                attendance.notes!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit,
                              color: Colors.amber,
                              size: 16,
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
}).toList(),
        ],
      ),
    );
  }
}

  Color _getStatusColor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green;
      case AttendanceStatus.absent:
        return Colors.red;
      case AttendanceStatus.late:
        return Colors.yellow;
      case AttendanceStatus.expelled:
        return Colors.purple;
      default:
        return Colors.grey;
    }
}
  }
}

  String _getStatusText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'طرد';
      default:
        return '';
    }
}
  }
}

  String _getStatusTextFromCode(String code) {
    switch (code) {
      case 'P':
        return 'حاضر';
      case 'UA':
        return 'غائب';
      case 'TE':
        return 'متأخر';
      case 'DR':
        return 'طرد';
      default:
        return '';
    }
}
  }
}

  Widget _buildBottomNavBar() {
    return Container(
      height: 63,
      color: const Color(0xFF1A1A1A), // Blackish gray
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem('الحضور', Icons.event_available, true),
          _buildNavItem('الامتحانات', Icons.quiz, false),
          _buildNavItem('الملاحظات', Icons.note, false),
        ],
      ),
    );
  }
}

  Widget _buildNavItem(String title, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (title == 'الامتحانات') {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => StudentAssignmentsScreen(
                student: widget.student,
                classModel: widget.classModel,
              ),
            ),
          );
        }
} else if (title == 'الملاحظات') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StudentNotesMainScreen(),
            ),
          );
        }
}
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
}

  void _showEditNoteDialog(AttendanceModel attendance) {
    final noteController = TextEditingController(text: attendance.notes);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'تعديل الملاحظة',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: noteController,
          decoration: const InputDecoration(
            hintText: 'اكتب ملاحظتك هنا...',
            hintStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.amber),
            ),
          ),
          style: const TextStyle(color: Colors.white),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // تحديث الملاحظة في قاعدة البيانات
                final dbHelper = DatabaseHelper();
                final updatedAttendance = attendance.copyWith(
                  notes: noteController.text,
                );
                await dbHelper.updateAttendance(updatedAttendance);
                
                // تحديث التعليق في SharedPreferences لمزامنة مع صفحة الحضور الرئيسي
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final commentsKey = 'student_comments_${widget.classModel.id}
}';
                  final Map<String, String> allComments = Map<String, String>.from(
                    prefs.getString(commentsKey) != null 
                      ? Map<String, String>.fromEntries(
                          prefs.getString(commentsKey)!.split(',').map((e) {
                            final parts = e.split(':');
                            if (parts.length >= 2) {
                              return MapEntry(parts[0], parts.sublist(1).join(':'));
                            }
}
                            return MapEntry(parts[0], '');
                          }
})
                        )
                      : {}
}
                  );
                  final dateKey = DateFormat('yyyy-MM-dd').format(attendance.date);
                  // Use the same key format as main attendance screen: lectureId_studentId_date
                  final finalKey = '${attendance.lectureId}
}_${attendance.studentId}
}_$dateKey';
                  allComments[finalKey] = noteController.text;
                  await prefs.setString(commentsKey, allComments.entries.map((e) => '${e.key}
}:${e.value}
}').join(','));
                  print('Updated SharedPreferences with key: $finalKey, value: ${noteController.text}
}');
                }
} catch (e) {
                  print('Error updating SharedPreferences: $e');
                }
}
                
                // إعادة تحميل البيانات
                setState(() {
                  _loadAttendanceData();
                }
});
                
                // Notify parent screen that data changed
                if (widget.onDataChanged != null) {
                  widget.onDataChanged!();
                }
}
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث الملاحظة بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
} catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('خطأ في تحديث الملاحظة: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
}
            }
},
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

  void _exportToPDF() async {
    final student = widget.student;
    final classModel = widget.classModel;
    final _dbHelper = DatabaseHelper();

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري إنشاء ملف PDF...'),
          ],
        ),
      ),
    );

    try {
      final pdf = pw.Document();
      
      // Load NotoSansArabic fonts from assets - best Arabic support
      final fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
      
      // Load attendance data
      final attendances = await _dbHelper.getAttendanceByStudent(student.id!);
      final presentCount = attendances.where((a) => a.status == AttendanceStatus.present).length;
      final absentCount = attendances.where((a) => a.status == AttendanceStatus.absent).length;
      final lateCount = attendances.where((a) => a.status == AttendanceStatus.late).length;
      final totalAttendance = attendances.length;
      
      // Load exam data
      final exams = await _dbHelper.getExamsByClass(student.classId);
      Map<String, double> grades = {}
};
      double totalScore = 0.0;
      int examCount = 0;
      
      for (final exam in exams) {
        final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
        final grade = studentGrades.firstWhere(
          (g) => g.examName == exam.title,
          orElse: () => GradeModel(
            id: 0,
            studentId: student.id!,
            examName: exam.title,
            score: 0,
            maxScore: exam.maxScore,
            examDate: DateTime.now(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        grades[exam.title] = grade.score;
        if (grade.notes?.contains('غائب') != true && 
            grade.notes?.contains('غش') != true && 
            grade.notes?.contains('مفقودة') != true) {
          totalScore += grade.score;
          examCount++;
        }
}
      }
}
      
      final averageScore = examCount > 0 ? (totalScore / examCount) : 0.0;

      // Add page to PDF
      pdf.addPage(
        pw.Page(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: fontRegular,
            bold: fontBold,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                // Header - File name and student info
                pw.Text(
                  'ملخص الفصل',
                  style: pw.TextStyle(
                    fontSize: 28,
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                    color: PdfColors.blue900,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.SizedBox(height: 16),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'الطالب:',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        font: fontBold,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      student.name,
                      style: pw.TextStyle(
                        fontSize: 18,
                        font: fontBold,
                        color: PdfColors.blue800,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(width: 20),
                    pw.Text(
                      'الفصل:',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        font: fontBold,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      classModel.name,
                      style: pw.TextStyle(
                        fontSize: 18,
                        font: fontBold,
                        color: PdfColors.green800,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                
                // Attendance Table - New Design
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'جدول الحضور',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 12),
                      _buildNewAttendanceTable(attendances, fontBold, fontRegular),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                
                // Exam Table - New Design
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'جدول الامتحانات',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 12),
                      _buildNewExamTable(grades, exams, fontBold, fontRegular),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                
                // Student Average
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text(
                        'معدل الطالب',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        '${averageScore.toStringAsFixed(1)}
}%',
                        style: pw.TextStyle(
                          fontSize: 32,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                          color: averageScore >= 85 ? PdfColors.green : 
                                 averageScore >= 75 ? PdfColors.blue : 
                                 averageScore >= 50 ? PdfColors.orange : PdfColors.red,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                
                // Attendance Bar Chart - New Design
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'رسم بياني للحضور',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 12),
                      _buildNewAttendanceChart(presentCount, absentCount, lateCount, expelledDays, fontBold),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                
                // Exam Percentage Chart - New Design
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'رسم بياني للامتحانات',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          font: fontBold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 12),
                      _buildNewExamChart(grades, fontBold),
                    ],
                  ),
                ),
              ],
            );
          }
},
        ),
      );

      // Close loading dialog
      Navigator.pop(context);

      // Show PDF directly without print dialog
      await Printing.sharePdf(
        bytes: await pdf.save(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء ملف PDF بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
} catch (e) {
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إنشاء ملف PDF: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
}
  }
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
}

  pw.Widget _buildGradeDistributionChart(Map<String, double> grades, List<ExamModel> exams, pw.Font fontBold) {
    if (grades.isEmpty) {
      return pw.Text(
        'لا توجد درجات متاحة',
        style: pw.TextStyle(font: fontBold),
        textDirection: pw.TextDirection.rtl,
      );
    }
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
      children: <pw.Widget>[
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
}

  pw.Widget _buildNewAttendanceTable(List<AttendanceModel> attendances, pw.Font fontBold, pw.Font fontRegular) {
    // Group attendances by month
    final Map<String, List<AttendanceModel>> monthlyAttendances = {}
};
    final List<String> monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    
    for (final attendance in attendances) {
      final month = monthNames[attendance.date.month - 1];
      if (!monthlyAttendances.containsKey(month)) {
        monthlyAttendances[month] = [];
      }
}
      monthlyAttendances[month]!.add(attendance);
    }
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
                child: pw.Text(
                  month,
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                    color: PdfColors.white,
                  ),
                  textDirection: pw.TextDirection.rtl,
                  textAlign: pw.TextAlign.center,
                ),
              )).toList(),
            ),
          ),
          // Date rows
          ..._generateDateRows(monthlyAttendances, selectedMonths, fontBold, fontRegular),
        ],
      ),
    );
  }
}

  List<pw.Widget> _generateDateRows(Map<String, List<AttendanceModel>> monthlyAttendances, List<String> selectedMonths, pw.Font fontBold, pw.Font fontRegular) {
    List<pw.Widget> rows = [];
    
    // Get all unique dates from all months
    Set<int> allDays = {}
};
    for (final month in selectedMonths) {
      final attendances = monthlyAttendances[month] ?? [];
      for (final attendance in attendances) {
        allDays.add(attendance.date.day);
      }
}
    }
}
    
    final sortedDays = allDays.toList()..sort();
    
    for (final day in sortedDays) {
      rows.add(
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
            children: selectedMonths.map((month) => pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    '$day',
                    style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 10,
                    ),
                    textDirection: pw.TextDirection.rtl,
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                  // Find attendance for this day and month
                  ..._buildAttendanceStatus(monthlyAttendances[month] ?? [], day, fontBold),
                ],
              ),
            )).toList(),
          ),
        ),
      );
    }
}
    
    return rows;
  }
}

  List<pw.Widget> _buildAttendanceStatus(List<AttendanceModel> attendances, int day, pw.Font fontBold) {
    final attendance = attendances.where((a) => a.date.day == day).firstOrNull;
    
    if (attendance == null) {
      return [];
    }
}
    
    String statusText = '';
    PdfColor statusColor = PdfColors.grey;
    
    switch (attendance.status) {
      case AttendanceStatus.present:
        statusText = 'حاضر';
        statusColor = PdfColors.green;
        break;
      case AttendanceStatus.absent:
        statusText = 'غائب';
        statusColor = PdfColors.red;
        break;
      case AttendanceStatus.late:
        statusText = 'متأخر';
        statusColor = PdfColors.orange;
        break;
    }
    
    return [
      pw.Text(
        statusText,
        style: pw.TextStyle(
          font: fontBold,
          fontSize: 8,
          color: statusColor,
        ),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
      ),
    ];
  }

  pw.Widget _buildNewExamTable(Map<String, double> grades, List<ExamModel> exams, pw.Font fontBold, pw.Font fontRegular) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(1),
        },
        children: [
          // Header
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey100),
            children: <pw.Widget>[
              pw.Padding(
                padding: pw.EdgeInsets.all(8),
                child: pw.Text(
                  'التاريخ',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'عنوان الامتحان',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  'الدرجة',
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: fontBold,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ],
          ),
          // Data rows
          ...grades.entries.map((entry) {
            final exam = exams.firstWhere((e) => e.title == entry.key, 
                orElse: () => ExamModel(
                  id: 0, 
                  classId: 0, 
                  title: entry.key, 
                  date: DateTime.now(), 
                  maxScore: 100,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ));
            
            String displayText = '';
            if (entry.value == 0) {
              displayText = 'غائب';
            } else if (entry.value < 0) {
              displayText = 'غش';
            } else {
              displayText = '${entry.value.toInt()}%';
            }
            
            return pw.TableRow(
              children: [
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    DateFormat('dd MMMM yyyy').format(exam.date),
                    style: pw.TextStyle(font: fontBold),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    entry.key,
                    style: pw.TextStyle(font: fontBold),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    displayText,
                    style: pw.TextStyle(
                      font: fontBold,
                      color: entry.value == 0 ? PdfColors.red : 
                             entry.value < 0 ? PdfColors.orange : PdfColors.green,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              ],
            );
          }
        }).toList(),
        ],
      ),
    );
  }

  pw.Widget _buildNewAttendanceChart(int presentCount, int absentCount, int lateCount, int expelledCount, pw.Font fontBold) {
    return pw.Container(
      height: 150,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          if (presentCount > 0)
            _buildAttendanceBarWithCount('حاضر', presentCount, PdfColors.green, fontBold),
          if (absentCount > 0)
            _buildAttendanceBarWithCount('غائب', absentCount, PdfColors.red, fontBold),
          if (lateCount > 0)
            _buildAttendanceBarWithCount('متأخر', lateCount, PdfColors.orange, fontBold),
          if (expelledCount > 0)
            _buildAttendanceBarWithCount('مطرود', expelledCount, PdfColors.purple, fontBold),
        ],
      ),
    );
  }

  pw.Widget _buildAttendanceBarWithCount(String label, int count, PdfColor color, pw.Font fontBold) {
    return pw.Column(
      children: [
        pw.Container(
          width: 50,
          height: 80,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '$label=$count',
          style: pw.TextStyle(
            fontSize: 10,
            font: fontBold,
          ),
          textDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  pw.Widget _buildNewExamChart(Map<String, double> grades, pw.Font fontBold) {
    final percent100 = grades.values.where((g) => g >= 100).length;
    final range85to99 = grades.values.where((g) => g >= 85 && g < 100).length;
    final range75to84 = grades.values.where((g) => g >= 75 && g < 85).length;
    final range50to74 = grades.values.where((g) => g >= 50 && g < 75).length;
    final below50 = grades.values.where((g) => g < 50 && g > 0).length;

    if (grades.isEmpty) {
      return pw.Container(
        height: 150,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
          children: [
            if (percent100 > 0)
              _buildExamBarWithCount('100', percent100, PdfColors.green, fontBold),
            if (range85to99 > 0)
              _buildExamBarWithCount('85-99', range85to99, PdfColors.blue, fontBold),
            if (range75to84 > 0)
              _buildExamBarWithCount('75-84', range75to84, PdfColors.orange, fontBold),
            if (range50to74 > 0)
              _buildExamBarWithCount('50-74', range50to74, PdfColors.purple, fontBold),
            if (below50 > 0)
              _buildExamBarWithCount('<50', below50, PdfColors.red, fontBold),
          ],
        ),
      );
    }

    return pw.Container(
      height: 150,
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
        children: [
          if (percent100 > 0)
            _buildExamBarWithCount('100', percent100, PdfColors.green, fontBold),
          if (range85to99 > 0)
            _buildExamBarWithCount('85-99', range85to99, PdfColors.blue, fontBold),
          if (range75to84 > 0)
            _buildExamBarWithCount('75-84', range75to84, PdfColors.orange, fontBold),
          if (range50to74 > 0)
            _buildExamBarWithCount('50-74', range50to74, PdfColors.purple, fontBold),
          if (below50 > 0)
            _buildExamBarWithCount('<50', below50, PdfColors.red, fontBold),
        ],
      ),
    );
  }

  pw.Widget _buildExamBarWithCount(String label, int count, PdfColor color, pw.Font fontBold) {
    return pw.Column(
      children: [
        pw.Container(
          width: 40,
          height: 80,
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
}

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
import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../models/attendance_model.dart';
import '../../database/database_helper.dart';
import '../../theme/app_theme.dart';
import 'student_attendance_pdf.dart';
import 'student_assignments_screen.dart';
import '../notes/student_notes_main_screen.dart';
import '../../utils/date_filter_helper.dart';
import 'package:fl_chart/fl_chart.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final StudentModel student;
  final ClassModel? classModel;

  const StudentAttendanceScreen({
    super.key,
    required this.student,
    this.classModel,
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
  int excusedDays = 0;
  
  @override
  void initState() {
    super.initState();
    _loadDateFilter();
    _loadAttendanceData();
  }

  Future<void> _loadDateFilter() async {
    final filterData = await DateFilterHelper.getDateFilter();
    setState(() {
      _selectedDateFilter = filterData['filter'];
      _startDate = filterData['startDate'];
      _endDate = filterData['endDate'];
    });
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
    excusedDays = filtered.where((a) => a.status == AttendanceStatus.excused).length;
  }

  List<AttendanceModel> _getFilteredAttendances() {
    return DateFilterHelper.filterAttendance(
      attendances, 
      _selectedDateFilter, 
      _startDate, 
      _endDate, 
      (attendance) => attendance.date
    );
  }

  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: Colors.amber,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedDateFilter = 'مخصص';
      });
      
      // Save the custom date range to shared storage
      await DateFilterHelper.saveDateFilter('مخصص', _startDate, _endDate);
      
      _calculateStatistics();
      setState(() {}); // Refresh the UI
    }
  }

  void _exportToPDF() async {
    await StudentReportPDF.generatePDF(
      context: context,
      student: widget.student,
      classModel: widget.classModel,
      reportType: 'attendance',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                Navigator.popUntil(context, (route) => route.isFirst);
              },
            ),
            const SizedBox(width: 10),
            Text(
              'سجل الحضور - ${widget.student.name} - ${widget.classModel?.name ?? ""}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildHeaderSection(),
                  _buildStatisticsCards(),
                  _buildAttendanceChart(),
                  _buildCalendarView(),
                  const SizedBox(height: 80), // Space for fixed bottom navigation
                ],
              ),
            ),
      bottomNavigationBar: Container(
        height: 64.5, // 63 + 1.5 as requested
        color: const Color(0xFF1A1A1A), // Blackish gray
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem('الحضور', Icons.event_available, true),
            _buildNavItem('الامتحانات', Icons.quiz, false),
            _buildNavItem('الملاحظات', Icons.note, false),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    // Get filtered attendances based on date filter
    final filteredAttendances = _getFilteredAttendances();
    print('DEBUG: Total attendances: ${attendances.length}');
    print('DEBUG: Filtered attendances: ${filteredAttendances.length}');
    
    // Group attendances by month and year to avoid duplicates
    final Map<String, List<AttendanceModel>> monthlyAttendances = {};
    final List<String> monthNames = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    
    // Use a Set to track unique dates to avoid duplicates
    final Set<String> uniqueDates = {};
    
    for (final attendance in filteredAttendances) {
      final dateKey = '${attendance.date.year}-${attendance.date.month}-${attendance.date.day}';
      if (!uniqueDates.contains(dateKey)) {
        uniqueDates.add(dateKey);
        
        final month = monthNames[attendance.date.month - 1];
        if (!monthlyAttendances.containsKey(month)) {
          monthlyAttendances[month] = [];
        }
        monthlyAttendances[month]!.add(attendance);
      }
    }
    
    print('DEBUG: Monthly attendances count: ${monthlyAttendances.length}');

    return Column(
      children: [
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: monthlyAttendances.length,
          itemBuilder: (context, index) {
            final monthName = monthlyAttendances.keys.elementAt(index);
            final monthAttendances = monthlyAttendances[monthName]!;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Get month number from month name
                  Builder(
                    builder: (context) {
                      int getMonthNumber(String monthName) {
                        final monthMap = {
                          'يناير': 1,
                          'فبراير': 2,
                          'مارس': 3,
                          'أبريل': 4,
                          'مايو': 5,
                          'يونيو': 6,
                          'يوليو': 7,
                          'أغسطس': 8,
                          'سبتمبر': 9,
                          'أكتوبر': 10,
                          'نوفمبر': 11,
                          'ديسمبر': 12,
                        };
                        return monthMap[monthName] ?? 1;
                      }
                      
                      return Text(
                        '$monthName -${getMonthNumber(monthName)}-',
                        style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }
                  ),
                  const SizedBox(height: 16),
                  _buildMonthCalendar(monthAttendances),
                  // Add separator line between months (except for last month)
                  if (index < monthlyAttendances.length - 1)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      height: 1,
                      color: Colors.amber.withOpacity(0.3),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMonthCalendar(List<AttendanceModel> monthAttendances) {
    // Get the first day of the month to determine starting weekday
    if (monthAttendances.isEmpty) return const SizedBox.shrink();
    
    final now = DateTime.now();
    
    // Determine date range based on filter
    DateTime startDate, endDate;
    int weeksToShow;
    
    if (_selectedDateFilter == 'اليوم') {
      startDate = DateTime(now.year, now.month, now.day);
      endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      weeksToShow = 1; // Show only 1 week for today
    } else if (_selectedDateFilter == 'آخر أسبوع') {
      startDate = DateTime(now.year, now.month, now.day - 6);
      endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
      weeksToShow = 2; // Show 2 weeks to ensure all 7 days are visible
    } else if (_selectedDateFilter == 'تاريخ محدد' && _startDate != null && _endDate != null) {
      startDate = DateTime(_startDate!.year, _startDate!.month, _startDate!.day);
      endDate = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
      
      // For custom date range, show all days from start date to end date
      // Calculate the start of the week containing the start date
      final startOfWeek = startDate.subtract(Duration(days: startDate.weekday % 7));
      // Calculate the end of the week containing the end date
      final endOfWeek = endDate.add(Duration(days: 6 - (endDate.weekday % 7)));
      
      final totalDays = endOfWeek.difference(startOfWeek).inDays + 1;
      weeksToShow = (totalDays + 6) ~/ 7;
      
      // Use startOfWeek for calendar display to ensure proper alignment
      startDate = startOfWeek;
      endDate = endOfWeek;
    } else {
      // Default to showing full month
      final firstAttendance = monthAttendances.first;
      startDate = DateTime(firstAttendance.date.year, firstAttendance.date.month, 1);
      endDate = DateTime(firstAttendance.date.year, firstAttendance.date.month + 1, 0, 23, 59, 59);
      weeksToShow = 6; // Full month needs up to 6 weeks
    }
    
    // Get the weekday of the start date (0=Sunday, 6=Saturday)
    final firstWeekday = startDate.weekday % 7;
    
    // Create a map of attendances by day
    final Map<DateTime, AttendanceModel> attendanceByDay = {};
    for (final attendance in monthAttendances) {
      final dayKey = DateTime(attendance.date.year, attendance.date.month, attendance.date.day);
      attendanceByDay[dayKey] = attendance;
    }

    return Column(
      children: [
        // Week days header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: ['أحد', 'إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت'].map((day) {
            return Expanded(
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Calendar grid - dynamic size based on date range
        Column(
          children: List.generate(weeksToShow, (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                // Calculate the actual day number for this position
                final dayNumber = (weekIndex * 7) + dayIndex - firstWeekday + 1;
                final currentDate = startDate.add(Duration(days: dayNumber - 1));
                
                // Check if this day is within our date range
                // For custom date range, only show days within the selected range
                if (_selectedDateFilter == 'تاريخ محدد' && _startDate != null && _endDate != null) {
                  if (currentDate.isBefore(DateTime(_startDate!.year, _startDate!.month, _startDate!.day)) ||
                      currentDate.isAfter(DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59))) {
                    return Expanded(
                      child: Container(
                        height: 50,
                        margin: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }
                } else if (dayNumber < 1 || currentDate.isAfter(endDate) || currentDate.isBefore(startDate)) {
                  return Expanded(
                    child: Container(
                      height: 50,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }
                
                final attendance = attendanceByDay[DateTime(currentDate.year, currentDate.month, currentDate.day)];
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _showAttendanceStatusDialog(attendance),
                    child: Container(
                      height: 50,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: _getAttendanceColor(attendance?.status),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Date number at the top
                          Text(
                            '${currentDate.day}',
                            style: TextStyle(
                              color: attendance?.status == AttendanceStatus.excused
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // Attendance status at the bottom
                          if (attendance != null)
                            Text(
                              _getAttendanceStatusText(attendance.status),
                              style: TextStyle(
                                color: attendance.status == AttendanceStatus.excused
                                    ? Colors.black87
                                    : Colors.white70,
                                fontSize: 8,
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ],
    );
  }

  // Helper method to determine the main status for a day with multiple attendances
  AttendanceStatus _getMainAttendanceStatus(List<AttendanceModel> attendances) {
    // Priority order: expelled > absent > late > present
    if (attendances.any((a) => a.status == AttendanceStatus.expelled)) {
      return AttendanceStatus.expelled;
    }
    if (attendances.any((a) => a.status == AttendanceStatus.absent)) {
      return AttendanceStatus.absent;
    }
    if (attendances.any((a) => a.status == AttendanceStatus.excused)) {
      return AttendanceStatus.excused;
    }
    if (attendances.any((a) => a.status == AttendanceStatus.late)) {
      return AttendanceStatus.late;
    }
    return AttendanceStatus.present;
  }

  void _showAttendanceStatusDialog(AttendanceModel? attendance) {
    if (attendance == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'تغيير حالة الحضور',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatusOption('حاضر', AttendanceStatus.present, attendance),
              _buildStatusOption('غائب', AttendanceStatus.absent, attendance),
              _buildStatusOption('متأخر', AttendanceStatus.late, attendance),
              _buildStatusOption('مجاز', AttendanceStatus.excused, attendance),
              _buildStatusOption('مطرود', AttendanceStatus.expelled, attendance),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOption(String title, AttendanceStatus status, AttendanceModel currentAttendance) {
    return ListTile(
      title: Text(
        title,
        style: TextStyle(
          color: currentAttendance.status == status ? Colors.amber : Colors.white,
          fontWeight: currentAttendance.status == status ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () async {
        Navigator.pop(context);
        
        // Update attendance status
        final updatedAttendance = AttendanceModel(
          id: currentAttendance.id,
          studentId: currentAttendance.studentId,
          lectureId: currentAttendance.lectureId,
          date: currentAttendance.date,
          status: status,
          notes: currentAttendance.notes,
          createdAt: currentAttendance.createdAt,
        );
        
        try {
          await DatabaseHelper().updateAttendance(updatedAttendance);
          
          // Refresh data
          setState(() {
            // Find and update the attendance in the list
            final index = attendances.indexWhere((a) => a.id == currentAttendance.id);
            if (index != -1) {
              attendances[index] = updatedAttendance;
            }
          });
          
          _calculateStatistics();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم تحديث الحالة إلى: $title'),
              backgroundColor: Colors.green,
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في تحديث الحالة: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
    );
  }

  Color _getAttendanceColor(AttendanceStatus? status) {
    switch (status) {
      case AttendanceStatus.present:
        return Colors.green.withOpacity(0.3);
      case AttendanceStatus.absent:
        return Colors.red.withOpacity(0.3);
      case AttendanceStatus.late:
        return Colors.orange.withOpacity(0.3);
      case AttendanceStatus.expelled:
        return Colors.purple.withOpacity(0.3);
      case AttendanceStatus.excused:
        return Colors.white;
      default:
        return Colors.grey.withOpacity(0.2);
    }
  }

  Color _getAttendanceTextColor(AttendanceStatus? status) {
    switch (status) {
      case AttendanceStatus.excused:
        return Colors.black;
      default:
        return _getAttendanceColor(status);
    }
  }

  String _getAttendanceStatusText(AttendanceStatus? status) {
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
      default:
        return '';
    }
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _showDateFilterDialog,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedDateFilter ?? 'التواريخ: الكل',
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'اختر فلترة التاريخ',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
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
      ),
    );
  }

  Widget _buildFilterOption(String option) {
    final isSelected = _selectedDateFilter == option;
    return GestureDetector(
      onTap: () async {
        Navigator.pop(context);
        
        if (option == 'تاريخ محدد') {
          _showCustomDateDialog();
        } else {
          // Save the filter to shared storage
          await DateFilterHelper.saveDateFilter(option, null, null);
          
          setState(() {
            _selectedDateFilter = option;
            _startDate = null;
            _endDate = null;
          });
          _calculateStatistics();
          setState(() {}); // Refresh the UI
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

  
  void _showCustomDateDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text(
                'اختر التواريخ',
                style: TextStyle(color: Colors.white),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF404040)),
            ListTile(
              title: const Text(
                'تاريخ البدء',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _startDate != null
                    ? DateFormat('dd/MM/yyyy').format(_startDate!)
                    : 'اختر',
                style: const TextStyle(color: Colors.amber),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _startDate ?? DateTime.now(),
                  firstDate: DateTime(2020), // Allow any date from 2020
                  lastDate: DateTime(2100), // Allow any date up to 2100
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: Colors.amber,
                        ),
                      ),
                      child: child!,
                    );
                  },
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
                'تاريخ النهاية',
                style: TextStyle(color: Colors.white),
              ),
              trailing: Text(
                _endDate != null
                    ? DateFormat('dd/MM/yyyy').format(_endDate!)
                    : 'اختر',
                style: const TextStyle(color: Colors.amber),
              ),
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? (_startDate ?? DateTime.now()),
                  firstDate: _startDate ?? DateTime(2020), // Must be after start date
                  lastDate: DateTime(2100), // Allow any date up to 2100
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                          primary: Colors.amber,
                        ),
                      ),
                      child: child!,
                    );
                  },
                );
                if (date != null) {
                  setState(() {
                    _endDate = date;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                TextButton(
                  onPressed: () {
                    if (_startDate != null && _endDate != null) {
                      // Save custom date range to shared storage
                      DateFilterHelper.saveDateFilter('تاريخ محدد', _startDate, _endDate);
                      
                      setState(() {
                        _selectedDateFilter = 'تاريخ محدد';
                      });
                      _calculateStatistics();
                      setState(() {}); // Refresh UI
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('حفظ'),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticsCards() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildStatCard('إجمالي الأيام', totalDays, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('حاضر', presentDays, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('غائب', absentDays, Colors.red)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildStatCard('متأخر', lateDays, Colors.orange)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('مطرود', expelledDays, Colors.purple)),
              const SizedBox(width: 8),
              Expanded(child: _buildStatCard('مجاز', excusedDays, Colors.white)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
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
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceChart() {
    if (totalDays == 0) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'مخطط الحضور',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: [
                  if (presentDays > 0)
                    PieChartSectionData(
                      value: presentDays.toDouble(),
                      title: 'حاضر\n$presentDays',
                      color: Colors.green,
                      titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  if (absentDays > 0)
                    PieChartSectionData(
                      value: absentDays.toDouble(),
                      title: 'غائب\n$absentDays',
                      color: Colors.red,
                      titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  if (lateDays > 0)
                    PieChartSectionData(
                      value: lateDays.toDouble(),
                      title: 'متأخر\n$lateDays',
                      color: Colors.orange,
                      titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  if (expelledDays > 0)
                    PieChartSectionData(
                      value: expelledDays.toDouble(),
                      title: 'مطرود\n$expelledDays',
                      color: Colors.purple,
                      titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  if (excusedDays > 0)
                    PieChartSectionData(
                      value: excusedDays.toDouble(),
                      title: 'مجاز\n$excusedDays',
                      color: Colors.white,
                      titleStyle: const TextStyle(color: Colors.black, fontSize: 12),
                    ),
                ],
                centerSpaceRadius: 60,
                sectionsSpace: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    // التحقق من جميع سجلات الحضور وعرضها
    final allAttendances = attendances; // استخدام جميع السجلات
    
    if (allAttendances.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Text(
              'سجل الحضور',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد سجلات حضور',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'سجل الحضور',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: allAttendances.length,
            itemBuilder: (context, index) {
              final attendance = allAttendances[index];
              final date = attendance.date;
              final formattedDate = DateFormat('d MMMM yyyy', 'ar').format(date);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _getAttendanceColor(attendance.status).withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getAttendanceColor(attendance.status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _getAttendanceStatusText(attendance.status),
                            style: TextStyle(
                              color: _getAttendanceTextColor(attendance.status),
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
                    if (attendance.lectureId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'محاضرة رقم ${attendance.lectureId}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                    if (attendance.notes != null && attendance.notes!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          attendance.notes!,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildNavItem('الحضور', Icons.calendar_today, true),
          _buildNavItem('الامتحانات', Icons.quiz, false),
          _buildNavItem('الملاحظات', Icons.note, false),
        ],
      ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, bool isActive) {
    return GestureDetector(
      onTap: () {
        if (title == 'الحضور') {
          // Do nothing - already on this page
        } else if (title == 'الامتحانات') {
          Navigator.pop(context);
        } else if (title == 'الملاحظات') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const StudentNotesMainScreen(),
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}

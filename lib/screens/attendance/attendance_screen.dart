import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/attendance_provider.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  ClassModel? _selectedClass;
  DateTime _selectedDate = DateTime.now();
  Map<int, AttendanceStatus> _attendanceData = {};
  Map<int, Map<String, int>> _studentStatistics = {};
  Map<int, String> _studentComments = {}; // Add comments map
  bool _sortByAbsence = true; // true for absence rate, false for name

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    if (_selectedClass == null) return;
    
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    
    // Use the already loaded students from the provider
    final students = studentProvider.students;
    
    Map<int, Map<String, int>> stats = {};
    
    for (var student in students) {
      try {
        final studentStats = await attendanceProvider.getAttendanceStatsForStudent(student.id!);
        stats[student.id!] = studentStats;
      } catch (e) {
        // If no stats exist, use empty stats
        stats[student.id!] = {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
      }
    }
    
    setState(() {
      _studentStatistics = stats;
    });
  }

  Future<void> _updateSingleStudentStatistics(int studentId) async {
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    
    try {
      final studentStats = await attendanceProvider.getAttendanceStatsForStudent(studentId);
      setState(() {
        _studentStatistics[studentId] = studentStats;
      });
    } catch (e) {
      // If no stats exist, use empty stats
      setState(() {
        _studentStatistics[studentId] = {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
      });
    }
  }

  List<StudentModel> _sortStudents(List<StudentModel> students) {
    if (!_sortByAbsence) {
      // Sort by name
      return students..sort((a, b) => a.name.compareTo(b.name));
    }
    
    // Sort by absence rate (highest first)
    return students..sort((a, b) {
      final statsA = _studentStatistics[a.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
      final statsB = _studentStatistics[b.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
      
      final totalA = statsA['present']! + statsA['absent']! + statsA['late']! + statsA['expelled']!;
      final totalB = statsB['present']! + statsB['absent']! + statsB['late']! + statsB['expelled']!;
      
      if (totalA == 0 && totalB == 0) return 0;
      if (totalA == 0) return 1;
      if (totalB == 0) return -1;
      
      final absenceRateA = (statsA['absent']! + statsA['late']! + statsA['expelled']!) / totalA;
      final absenceRateB = (statsB['absent']! + statsB['late']! + statsB['expelled']!) / totalB;
      
      return absenceRateB.compareTo(absenceRateA); // Highest first
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الحضور والغياب'),
        actions: [
          IconButton(
            icon: Icon(_sortByAbsence ? Icons.sort_by_alpha : Icons.trending_down),
            onPressed: () {
              setState(() {
                _sortByAbsence = !_sortByAbsence;
              });
            },
            tooltip: _sortByAbsence ? 'ترتيب حسب الاسم' : 'ترتيب حسب نسبة الغياب',
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // اختيار الفصل والتاريخ
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _showClassSelector(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.primaryColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.class_, color: AppTheme.primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _selectedClass?.name ?? 'اختر الفصل',
                                  style: TextStyle(
                                    color: _selectedClass != null 
                                        ? AppTheme.primaryColor 
                                        : AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDate(context),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.primaryColor),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _formatDate(_selectedDate),
                                  style: const TextStyle(color: AppTheme.primaryColor),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                color: AppTheme.primaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_selectedClass != null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _takeAttendance(),
                          icon: const Icon(Icons.how_to_reg),
                          label: const Text('تسجيل الحضور'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _viewAttendanceHistory(),
                          icon: const Icon(Icons.history),
                          label: const Text('سجل الحضور'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          
          // عرض الحضور والغياب
          Expanded(
            child: _selectedClass == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.class_,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'اختر الفصل لبدء تسجيل الحضور',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : Consumer2<StudentProvider, AttendanceProvider>(
                    builder: (context, studentProvider, attendanceProvider, child) {
                      if (studentProvider.isLoading) {
                        return const Center(
                          child: CircularProgressIndicator(),
                        );
                      }

                      final students = studentProvider.students
                          .where((s) => s.classId == _selectedClass!.id)
                          .toList();
                      
                      final sortedStudents = _sortStudents(List.from(students));

                      if (students.isEmpty) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people,
                                size: 64,
                                color: AppTheme.textSecondary,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'لا يوجد طلاب في هذا الفصل',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Column(
                        children: [
                          // ملخص الحضور
                          Container(
                            padding: const EdgeInsets.all(16),
                            margin: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D2D2D),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _AttendanceSummary(
                                  label: 'الحاضر',
                                  count: _attendanceData.values
                                      .where((status) => status == AttendanceStatus.present)
                                      .length,
                                  color: AppTheme.successColor,
                                  icon: Icons.check_circle,
                                ),
                                _AttendanceSummary(
                                  label: 'الغائب',
                                  count: _attendanceData.values
                                      .where((status) => status == AttendanceStatus.absent)
                                      .length,
                                  color: AppTheme.errorColor,
                                  icon: Icons.cancel,
                                ),
                                _AttendanceSummary(
                                  label: 'المتأخر',
                                  count: _attendanceData.values
                                      .where((status) => status == AttendanceStatus.late)
                                      .length,
                                  color: AppTheme.warningColor,
                                  icon: Icons.access_time,
                                ),
                                _AttendanceSummary(
                                  label: 'المتبقي',
                                  count: students.length - _attendanceData.length,
                                  color: AppTheme.textSecondary,
                                  icon: Icons.help_outline,
                                ),
                              ],
                            ),
                          ),
                          
                          // قائمة الطلاب
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: sortedStudents.length,
                              itemBuilder: (context, index) {
                                final student = sortedStudents[index];
                                // لا نحدد حالة افتراضية، فقط إذا كان موجود في البيانات
                                final status = _attendanceData[student.id];
                                final stats = _studentStatistics[student.id!] ?? {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0};
                                
                                return _StudentAttendanceCard(
                                  student: student,
                                  status: status,
                                  statistics: stats,
                                  comment: _studentComments[student.id!] ?? '',
                                  onStatusChanged: (newStatus) {
                                    setState(() {
                                      _attendanceData[student.id!] = newStatus;
                                      // Update statistics immediately when status changes
                                      _updateSingleStudentStatistics(student.id!);
                                    });
                                  },
                                  onCommentChanged: (comment) {
                                    setState(() {
                                      _studentComments[student.id!] = comment;
                                    });
                                  },
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
    );
  }

  void _showClassSelector(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختر الفصل'),
        content: Consumer<ClassProvider>(
          builder: (context, classProvider, child) {
            if (classProvider.classes.isEmpty) {
              return const Text('لا توجد فصول متاحة');
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: classProvider.classes.map((classModel) => ListTile(
                title: Text(classModel.name),
                subtitle: Text(classModel.subject),
                onTap: () {
                  setState(() {
                    _selectedClass = classModel;
                    _attendanceData.clear();
                    _studentStatistics.clear(); // Reset statistics when class changes
                    _studentComments.clear(); // Reset comments when class changes
                  });
                  Navigator.pop(context);
                  _loadStudents();
                },
              )).toList(),
            );
          },
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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _attendanceData.clear();
        _studentComments.clear(); // Reset comments when date changes
      });
      _loadAttendanceData();
    }
  }

  void _loadStudents() {
    if (_selectedClass != null) {
      Provider.of<StudentProvider>(context, listen: false)
          .loadStudentsByClass(_selectedClass!.id!);
      _loadAttendanceData();
      _loadStatistics(); // Load statistics when class is selected
    }
  }

  void _loadAttendanceData() async {
    if (_selectedClass != null) {
      final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
      await attendanceProvider.loadAttendanceByDate(_selectedDate);
      
      if (mounted) {
        setState(() {
          _attendanceData = {
            for (var record in attendanceProvider.attendanceRecords)
              record.studentId: record.status,
          };
          _studentComments = {
            for (var record in attendanceProvider.attendanceRecords)
              if (record.notes != null && record.notes!.isNotEmpty)
                record.studentId: record.notes!,
          };
        });
        
        debugPrint('تم تحميل ${_attendanceData.length} سجل حضور للتاريخ ${_formatDate(_selectedDate)}');
      }
    }
  }

  void _takeAttendance() {
    if (_selectedClass == null) return;
    
    if (_attendanceData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى تحديد حالة الحضور لطالب واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ سجل الحضور'),
        content: Text(
          'هل تريد حفظ سجل الحضور ليوم ${_formatDate(_selectedDate)}؟\n'
          'الحاضر: ${_attendanceData.values.where((s) => s == AttendanceStatus.present).length}\n'
          'الغائب: ${_attendanceData.values.where((s) => s == AttendanceStatus.absent).length}\n'
          'المتأخر: ${_attendanceData.values.where((s) => s == AttendanceStatus.late).length}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          Consumer<AttendanceProvider>(
            builder: (context, attendanceProvider, child) {
              return ElevatedButton(
                onPressed: attendanceProvider.isLoading ? null : () async {
                  // حفظ الحضور لكل طالب
                  List<Map<String, dynamic>> attendanceList = [];
                  _attendanceData.forEach((studentId, status) {
                    attendanceList.add({
                      'studentId': studentId,
                      'date': _selectedDate,
                      'status': status,
                      'notes': _studentComments[studentId],
                    });
                  });
                  
                  final success = await attendanceProvider.markMultipleAttendance(attendanceList);
                  
                  if (success && context.mounted) {
                    Navigator.pop(context);
                    
                    // إعادة تحميل البيانات للتأكد من الحفظ
                    _loadAttendanceData();
                    _loadStatistics(); // Refresh statistics after saving
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم حفظ سجل الحضور بنجاح (${attendanceList.length} طالب)'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                    
                    debugPrint('تم حفظ ${attendanceList.length} سجل حضور بنجاح');
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('حدث خطأ أثناء حفظ الحضور'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: attendanceProvider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('حفظ'),
              );
            },
          ),
        ],
      ),
    );
  }

  void _viewAttendanceHistory() {
    if (_selectedClass == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceHistoryScreen(classModel: _selectedClass!),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _AttendanceSummary extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _AttendanceSummary({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
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

class _StudentAttendanceCard extends StatefulWidget {
  final StudentModel student;
  final AttendanceStatus? status;
  final Function(AttendanceStatus) onStatusChanged;
  final Map<String, int> statistics;
  final String comment;
  final Function(String) onCommentChanged;

  const _StudentAttendanceCard({
    required this.student,
    this.status,
    required this.onStatusChanged,
    required this.statistics,
    required this.comment,
    required this.onCommentChanged,
  });

  @override
  State<_StudentAttendanceCard> createState() => _StudentAttendanceCardState();
}

class _StudentAttendanceCardState extends State<_StudentAttendanceCard> {
  late TextEditingController _commentController;
  
  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: widget.comment);
  }
  
  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate absence percentage
    final totalDays = widget.statistics['present']! + widget.statistics['absent']! + widget.statistics['late']! + (widget.statistics['expelled'] ?? 0);
    final absencePercentage = totalDays > 0 
        ? ((widget.statistics['absent']! + widget.statistics['late']! + (widget.statistics['expelled'] ?? 0)) / totalDays * 100).round()
        : 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF404040), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main student info row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.student.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الرقم: ${widget.student.studentId}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              // Attendance status box - positioned directly under date/header
              GestureDetector(
                onTap: () => _showStatusSelector(context, widget.student, widget.onStatusChanged),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _getStatusColor(widget.status),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade600, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor(widget.status).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getStatusIcon(widget.status),
                        size: 20,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getStatusText(widget.status),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Statistics row - improved quality
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade700, width: 0.5),
            ),
            child: Row(
              children: [
                _buildStatChip('حضور', widget.statistics['present']!, Colors.green),
                const SizedBox(width: 6),
                _buildStatChip('غياب', widget.statistics['absent']!, Colors.red),
                const SizedBox(width: 6),
                _buildStatChip('تأخر', widget.statistics['late']!, Colors.orange),
                const SizedBox(width: 6),
                _buildStatChip('طرد', widget.statistics['expelled'] ?? 0, Colors.purple),
                if (totalDays > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: absencePercentage > 20 ? Colors.red.withValues(alpha: 0.3) : 
                             absencePercentage > 10 ? Colors.orange.withValues(alpha: 0.3) : 
                             Colors.green.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                                color: absencePercentage > 20 ? Colors.red :
                                       absencePercentage > 10 ? Colors.orange :
                                       Colors.green,
                                width: 1,
                              ),
                    ),
                    child: Text(
                      '$absencePercentage%',
                      style: TextStyle(
                        fontSize: 12,
                        color: absencePercentage > 20 ? Colors.red :
                               absencePercentage > 10 ? Colors.orange :
                               Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Comment field with divider
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.grey.shade700,
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade600, width: 1),
            ),
            child: TextField(
              controller: _commentController,
              style: const TextStyle(fontSize: 13, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'إضافة تعليق على الطالب...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: InputBorder.none,
                prefixIcon: Icon(Icons.comment, size: 18, color: Colors.grey),
              ),
              onChanged: (value) {
                widget.onCommentChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(
        '$label$count',
        style: TextStyle(
          fontSize: 11,
          color: color.withValues(alpha: 0.95),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  void _showStatusSelector(BuildContext context, StudentModel student, Function(AttendanceStatus) onStatusChanged) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A1A),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Text(
                'تحديد حالة ${student.name}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _buildStatusOption(
                context,
                'حاضر',
                Icons.check_circle,
                AppTheme.successColor,
                AttendanceStatus.present,
                student,
                onStatusChanged,
              ),
              _buildStatusOption(
                context,
                'غائب',
                Icons.cancel,
                AppTheme.errorColor,
                AttendanceStatus.absent,
                student,
                onStatusChanged,
              ),
              _buildStatusOption(
                context,
                'متأخر',
                Icons.access_time,
                AppTheme.warningColor,
                AttendanceStatus.late,
                student,
                onStatusChanged,
              ),
              _buildStatusOption(
                context,
                'مطرود',
                Icons.block,
                Colors.purple,
                AttendanceStatus.expelled,
                student,
                onStatusChanged,
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    AttendanceStatus status,
    StudentModel student,
    Function(AttendanceStatus) onStatusChanged,
  ) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onStatusChanged(status);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 15),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(AttendanceStatus? status) {
    switch (status) {
      case AttendanceStatus.present:
        return AppTheme.successColor;
      case AttendanceStatus.absent:
        return AppTheme.errorColor;
      case AttendanceStatus.late:
        return AppTheme.warningColor;
      case AttendanceStatus.expelled:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(AttendanceStatus? status) {
    switch (status) {
      case AttendanceStatus.present:
        return Icons.check_circle;
      case AttendanceStatus.absent:
        return Icons.cancel;
      case AttendanceStatus.late:
        return Icons.access_time;
      case AttendanceStatus.expelled:
        return Icons.block;
      default:
        return Icons.help;
    }
  }

  String _getStatusText(AttendanceStatus? status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'مطرود';
      default:
        return 'غير محدد';
    }
  }
}

class AttendanceHistoryScreen extends StatefulWidget {
  final ClassModel classModel;

  const AttendanceHistoryScreen({super.key, required this.classModel});

  @override
  State<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    Provider.of<AttendanceProvider>(context, listen: false)
        .loadAttendanceByDate(_startDate); // تحميل الحضور للتاريخ المحدد
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('سجل الحضور - ${widget.classModel.name}'),
      ),
      body: Column(
        children: [
          // فلترة التاريخ
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'من: ${_formatDate(_startDate)}',
                              style: const TextStyle(color: AppTheme.primaryColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primaryColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'إلى: ${_formatDate(_endDate)}',
                              style: const TextStyle(color: AppTheme.primaryColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // سجل الحضور
          Expanded(
            child: Consumer<AttendanceProvider>(
              builder: (context, attendanceProvider, child) {
                if (attendanceProvider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final records = attendanceProvider.attendanceRecords;

                if (records.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'لا يوجد سجل حضور في هذه الفترة',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _AttendanceRecordCard(record: record);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectDate(bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      _loadHistory();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _AttendanceRecordCard extends StatelessWidget {
  final AttendanceModel record;

  const _AttendanceRecordCard({required this.record});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (record.status) {
      case AttendanceStatus.present:
        statusColor = AppTheme.successColor;
        statusIcon = Icons.check_circle;
        statusText = 'حاضر';
        break;
      case AttendanceStatus.late:
        statusColor = AppTheme.warningColor;
        statusIcon = Icons.access_time;
        statusText = 'متأخر';
        break;
      case AttendanceStatus.absent:
        statusColor = AppTheme.errorColor;
        statusIcon = Icons.cancel;
        statusText = 'غائب';
        break;
      case AttendanceStatus.expelled:
        statusColor = Colors.purple;
        statusIcon = Icons.block;
        statusText = 'مطرود';
        break;
      case AttendanceStatus.excused:
        statusColor = Colors.blue;
        statusIcon = Icons.info_outline;
        statusText = 'مجاز';
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          statusIcon,
          color: statusColor,
        ),
        title: Text('تاريخ: ${_formatDate(record.date)}'),
        subtitle: Text('معرف الطالب: ${record.studentId}'),
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

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

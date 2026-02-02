import 'package:flutter/foundation.dart';
import '../models/attendance_model.dart';
import '../database/database_helper.dart';

class AttendanceProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<AttendanceModel> _attendanceList = [];
  bool _isLoading = false;
  String? _error;
  DateTime _selectedDate = DateTime.now();

  List<AttendanceModel> get attendanceList => _attendanceList;
  List<AttendanceModel> get attendanceRecords => _attendanceList;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get selectedDate => _selectedDate;

  void setSelectedDate(DateTime date) {
    _selectedDate = date;
    notifyListeners();
  }

  Future<void> loadAttendanceByDate(DateTime date) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _attendanceList = await _databaseHelper.getAttendanceByDate(date);
      _selectedDate = date;
    } catch (e) {
      _error = 'خطأ في تحميل الحضور: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadAttendanceByStudent(int studentId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _attendanceList = await _databaseHelper.getAttendanceByStudent(studentId);
    } catch (e) {
      _error = 'خطأ في تحميل حضور الطالب: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> markAttendance({
    required int studentId,
    required DateTime date,
    required AttendanceStatus status,
    String? notes,
  }) async {
    try {
      final attendance = AttendanceModel(
        studentId: studentId,
        date: date,
        status: status,
        notes: notes,
        createdAt: DateTime.now(),
      );

      final id = await _databaseHelper.insertAttendance(attendance);
      if (id > 0) {
        // تحديث القائمة المحلية
        final existingIndex = _attendanceList.indexWhere(
          (a) => a.studentId == studentId && 
                 a.date.day == date.day && 
                 a.date.month == date.month && 
                 a.date.year == date.year,
        );

        if (existingIndex != -1) {
          _attendanceList[existingIndex] = attendance.copyWith(id: id);
        } else {
          _attendanceList.add(attendance.copyWith(id: id));
        }

        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في تسجيل الحضور: $e';
      debugPrint(_error);
      notifyListeners();
    }

    return false;
  }

  Future<bool> markMultipleAttendance(List<Map<String, dynamic>> attendanceData) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      bool allSuccess = true;
      
      for (var data in attendanceData) {
        final success = await markAttendance(
          studentId: data['studentId'],
          date: data['date'],
          status: data['status'],
          notes: data['notes'],
        );
        
        if (!success) {
          allSuccess = false;
        }
      }

      _isLoading = false;
      notifyListeners();
      return allSuccess;
    } catch (e) {
      _error = 'خطأ في تسجيل الحضور المتعدد: $e';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  AttendanceModel? getStudentAttendanceForDate(int studentId, DateTime date) {
    try {
      return _attendanceList.firstWhere(
        (a) => a.studentId == studentId && 
               a.date.day == date.day && 
               a.date.month == date.month && 
               a.date.year == date.year,
      );
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, int>> getAttendanceStatsForStudent(int studentId) async {
    try {
      return await _databaseHelper.getAttendanceStats(studentId);
    } catch (e) {
      debugPrint('خطأ في إحصائيات الحضور: $e');
      return {'present': 0, 'absent': 0, 'late': 0, 'expelled': 0, 'excused': 0};
    }
  }

  Map<String, int> getAttendanceStatsForDate(DateTime date) {
    final dayAttendance = _attendanceList.where(
      (a) => a.date.day == date.day && 
             a.date.month == date.month && 
             a.date.year == date.year,
    ).toList();

    Map<String, int> stats = {
      'present': 0,
      'absent': 0,
      'late': 0,
      'expelled': 0,
      'excused': 0,
      'total': dayAttendance.length,
    };

    for (var attendance in dayAttendance) {
      switch (attendance.status) {
        case AttendanceStatus.present:
          stats['present'] = stats['present']! + 1;
          break;
        case AttendanceStatus.absent:
          stats['absent'] = stats['absent']! + 1;
          break;
        case AttendanceStatus.late:
          stats['late'] = stats['late']! + 1;
          break;
        case AttendanceStatus.expelled:
          stats['expelled'] = stats['expelled']! + 1;
          break;
        case AttendanceStatus.excused:
          stats['excused'] = stats['excused']! + 1;
          break;
      }
    }

    return stats;
  }

  double getAttendancePercentage(int studentId) {
    final studentAttendance = _attendanceList.where((a) => a.studentId == studentId).toList();
    
    if (studentAttendance.isEmpty) return 0.0;
    
    final presentCount = studentAttendance.where((a) => 
      a.status == AttendanceStatus.present ||
      a.status == AttendanceStatus.late
    ).length;
    
    return (presentCount / studentAttendance.length) * 100;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearAttendance() {
    _attendanceList = [];
    notifyListeners();
  }
}

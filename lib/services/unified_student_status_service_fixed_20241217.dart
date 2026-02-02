import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_helper.dart';
import '../../models/student_model.dart';

/// خدمة موحدة لحساب حالة الطالب تجمع معايير الحضور والامتحان
class UnifiedStudentStatusService {
  static const String _prefix = 'unified_student_status_';
  
  // مفاتيح موحدة للطلاب المميزون
  static const String _excellentFeatureEnabled = 'excellent_feature_enabled';
  static const String _excellentAverageEnabled = 'excellent_average_enabled';
  static const String _excellentExamsCountEnabled = 'excellent_exams_count_enabled';
  static const String _excellentExamAttendanceEnabled = 'excellent_exam_attendance_enabled';
  static const String _excellentLectureAttendanceEnabled = 'excellent_lecture_attendance_enabled';
  
  // مفاتيح موحدة للطلاب في خطر
  static const String _atRiskFeatureEnabled = 'at_risk_feature_enabled';
  static const String _atRiskAverageEnabled = 'at_risk_average_enabled';
  static const String _atRiskMissedExamsEnabled = 'at_risk_missed_exams_enabled';
  static const String _atRiskMissedLecturesEnabled = 'at_risk_missed_lectures_enabled';
  
  // مفاتيح قيم المعايير
  static const String _excellentMinAverage = 'excellent_min_average';
  static const String _excellentMinExamsCount = 'excellent_min_exams_count';
  static const String _excellentMinExamAttendance = 'excellent_min_exam_attendance';
  static const String _excellentMinLectureAttendance = 'excellent_min_lecture_attendance';
  static const String _atRiskMaxAverage = 'at_risk_max_average';
  static const String _atRiskMaxMissedExams = 'at_risk_max_missed_exams';
  static const String _atRiskMaxMissedLectures = 'at_risk_max_missed_lectures';

  /// حساب حالة الطالب بشكل موحد يجمع الحضور والامتحان
  static Future<Map<String, bool>> checkStudentStatus(StudentModel student) async {
    final prefs = await SharedPreferences.getInstance();
    final dbHelper = DatabaseHelper();
    
    // معايير الطلاب المميزون
    final excellentFeatureEnabled = prefs.getBool(_excellentFeatureEnabled) ?? true;
    final excellentAverageEnabled = prefs.getBool(_excellentAverageEnabled) ?? true;
    final excellentExamsCountEnabled = prefs.getBool(_excellentExamsCountEnabled) ?? true;
    final excellentExamAttendanceEnabled = prefs.getBool(_excellentExamAttendanceEnabled) ?? true;
    final excellentLectureAttendanceEnabled = prefs.getBool(_excellentLectureAttendanceEnabled) ?? true;
    
    // معايير الطلاب في خطر
    final atRiskFeatureEnabled = prefs.getBool(_atRiskFeatureEnabled) ?? true;
    final atRiskAverageEnabled = prefs.getBool(_atRiskAverageEnabled) ?? true;
    final atRiskMissedExamsEnabled = prefs.getBool(_atRiskMissedExamsEnabled) ?? true;
    final atRiskMissedLecturesEnabled = prefs.getBool(_atRiskMissedLecturesEnabled) ?? true;
    
    bool isExcellent = false;
    bool isAtRisk = false;
    
    // التحقق من التعطيل الكلي للمميزون
    final isExcellentDisabled = !excellentFeatureEnabled || 
        (!excellentAverageEnabled && !excellentExamsCountEnabled && 
         !excellentExamAttendanceEnabled && !excellentLectureAttendanceEnabled);
         
    // التحقق من التعطيل الكلي للطلاب في خطر  
    final isAtRiskDisabled = !atRiskFeatureEnabled || 
        (!atRiskAverageEnabled && !atRiskMissedExamsEnabled && !atRiskMissedLecturesEnabled);
    
    // إذا كانت جميع الميزات معطلة، إرجاع false مباشرة
    if (isExcellentDisabled && isAtRiskDisabled) {
      return {
        'isExcellent': false,
        'isAtRisk': false,
        'average': false,
        'totalExams': false,
        'examAttendance': false,
        'totalLectures': false,
        'lectureAttendance': false,
      };
    }
    
    // إذا كانت ميزة التميز معطلة بالكامل، لا نتحقق منها
    if (isExcellentDisabled) {
      isExcellent = false;
    }
    
    // إذا كانت ميزة الخطر معطلة بالكامل، لا نتحقق منها
    if (isAtRiskDisabled) {
      isAtRisk = false;
    }
    
    try {
      // جلب جميع بيانات الطالب
      final grades = await dbHelper.getGradesByStudent(student.id!);
      final attendances = await dbHelper.getAttendanceByStudent(student.id!);
      
      // حساب المعدل العام من جميع الامتحانات (بشكل صحيح)
      double totalScore = 0;
      double totalMaxScore = 0;
      int validGradesCount = 0;
      
      for (final grade in grades) {
        if (grade.notes?.contains('غائب') != true &&
            grade.notes?.contains('غش') != true &&
            grade.notes?.contains('مفقودة') != true) {
          
          // البحث عن الامتحان المقابل للحصول على الدرجة القصوى
          final exams = await dbHelper.getAllExams();
          final matchingExam = exams.where((e) => e.title == grade.examName).firstOrNull;
          
          if (matchingExam != null && matchingExam.maxScore > 0) {
            totalScore += grade.score;
            totalMaxScore += matchingExam.maxScore;
            validGradesCount++;
          }
        }
      }
      
      final average = totalMaxScore > 0 ? (totalScore / totalMaxScore) * 100 : 0.0;
      
      // حساب إحصائيات الامتحانات
      final totalExams = grades.length;
      final attendedExams = grades.where((g) => 
        g.notes?.contains('غائب') != true &&
        g.notes?.contains('غش') != true &&
        g.notes?.contains('مفقودة') != true
      ).length;
      final missedExams = grades.where((g) => 
        g.notes?.contains('غائب') == true
      ).length;
      
      final examAttendancePercentage = totalExams > 0 ? (attendedExams / totalExams) * 100 : 0.0;
      
      // حساب إحصائيات المحاضرات
      final totalLectures = attendances.length;
      final attendedLectures = attendances.where((a) => a.status == 'حاضر').length;
      final missedLectures = attendances.where((a) => a.status == 'غائب').length;
      
      final lectureAttendancePercentage = totalLectures > 0 ? (attendedLectures / totalLectures) * 100 : 0.0;
      
      // التحقق من معايير الطلاب المميزون (فقط إذا لم تكن معطلة)
      if (!isExcellentDisabled) {
        // معيار المعدل المرتفع
        if (excellentAverageEnabled) {
          final double minAverage = prefs.getDouble(_excellentMinAverage) ?? 85.0;
          if (average >= minAverage) {
            isExcellent = true;
          }
        }
        
        // معيار عدد الامتحانات
        if (excellentExamsCountEnabled) {
          final int minExamsCount = prefs.getInt(_excellentMinExamsCount) ?? 3;
          if (totalExams >= minExamsCount) {
            isExcellent = true;
          }
        }
        
        // معيار حضور الامتحانات
        if (excellentExamAttendanceEnabled) {
          final double minExamAttendance = prefs.getDouble(_excellentMinExamAttendance) ?? 95.0;
          if (examAttendancePercentage >= minExamAttendance) {
            isExcellent = true;
          }
        }
        
        // معيار حضور المحاضرات
        if (excellentLectureAttendanceEnabled) {
          final double minLectureAttendance = prefs.getDouble(_excellentMinLectureAttendance) ?? 90.0;
          if (lectureAttendancePercentage >= minLectureAttendance) {
            isExcellent = true;
          }
        }
      }
      
      // التحقق من معايير الطلاب في خطر (فقط إذا لم تكن معطلة)
      if (!isAtRiskDisabled) {
        // معيار المعدل المنخفض
        if (atRiskAverageEnabled) {
          final double maxAverage = prefs.getDouble(_atRiskMaxAverage) ?? 50.0;
          if (average < maxAverage) {
            isAtRisk = true;
          }
        }
        
        // معيار الامتحانات الفائتة
        if (atRiskMissedExamsEnabled) {
          final int maxMissedExams = prefs.getInt(_atRiskMaxMissedExams) ?? 1;
          if (missedExams >= maxMissedExams) {
            isAtRisk = true;
          }
        }
        
        // معيار المحاضرات الغائبة
        if (atRiskMissedLecturesEnabled) {
          final int maxMissedLectures = prefs.getInt(_atRiskMaxMissedLectures) ?? 3;
          if (missedLectures >= maxMissedLectures) {
            isAtRisk = true;
          }
        }
      }
      
      // لا يمكن أن يكون الطالب مميزاً وفي خطر في نفس الوقت
      if (isExcellent && isAtRisk) {
        isAtRisk = false; // إعطاء الأولوية للتميز
      }
      
      return {
        'isExcellent': isExcellent,
        'isAtRisk': isAtRisk,
        'average': average > 0,
        'totalExams': totalExams > 0,
        'examAttendance': examAttendancePercentage > 0,
        'totalLectures': totalLectures > 0,
        'lectureAttendance': lectureAttendancePercentage > 0,
      };
      
    } catch (e) {
      print('Error in UnifiedStudentStatusService: $e');
      return {
        'isExcellent': false, 
        'isAtRisk': false,
        'average': false,
        'totalExams': false,
        'examAttendance': false,
        'totalLectures': false,
        'lectureAttendance': false,
      };
    }
  }
  
  /// الحصول على جميع مفاتيح الإعدادات الموحدة
  static Map<String, dynamic> getDefaultSettings() {
    return {
      // إعدادات الطلاب المميزون
      _excellentFeatureEnabled: true,
      _excellentAverageEnabled: true,
      _excellentExamsCountEnabled: false,
      _excellentExamAttendanceEnabled: true,
      _excellentLectureAttendanceEnabled: false,
      _excellentMinAverage: 85.0,
      _excellentMinExamsCount: 3,
      _excellentMinExamAttendance: 95.0,
      _excellentMinLectureAttendance: 90.0,
      
      // إعدادات الطلاب في خطر
      _atRiskFeatureEnabled: true,
      _atRiskAverageEnabled: true,
      _atRiskMissedExamsEnabled: true,
      _atRiskMissedLecturesEnabled: true,
      _atRiskMaxAverage: 50.0,
      _atRiskMaxMissedExams: 1,
      _atRiskMaxMissedLectures: 3,
    };
  }
  
  /// تهيئة الإعدادات الافتراضية
  static Future<void> initializeDefaultSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final settings = getDefaultSettings();
    
    for (final entry in settings.entries) {
      if (!prefs.containsKey(entry.key)) {
        if (entry.value is bool) {
          await prefs.setBool(entry.key, entry.value as bool);
        } else if (entry.value is double) {
          await prefs.setDouble(entry.key, entry.value as double);
        } else if (entry.value is int) {
          await prefs.setInt(entry.key, entry.value as int);
        }
      }
    }
    
    // التأكد من تفعيل الميزات الرئيسية
    await prefs.setBool('excellent_feature_enabled', true);
    await prefs.setBool('at_risk_feature_enabled', true);
  }
}

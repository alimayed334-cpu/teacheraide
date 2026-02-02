import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_helper.dart';
import '../../models/student_model.dart';
import '../../models/attendance_model.dart';

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

  // مفاتيح مستخدمة في بعض الشاشات/الإصدارات السابقة (للتوافق)
  static const String _excellentMinExamsCountAlt = 'excellent_min_exams';
  static const String _atRiskMinMissedExamsAlt = 'at_risk_min_missed_exams';
  static const String _atRiskMinMissedLecturesAlt = 'at_risk_min_missed_lectures';

  static int _getIntWithFallback(
    SharedPreferences prefs,
    String key,
    List<String> fallbacks,
    int defaultValue,
  ) {
    final direct = prefs.getInt(key);
    if (direct != null) return direct;
    for (final k in fallbacks) {
      final v = prefs.getInt(k);
      if (v != null) return v;
    }
    return defaultValue;
  }

  static bool _containsAny(String? value, List<String> needles) {
    if (value == null) return false;
    final v = value.toLowerCase();
    for (final n in needles) {
      if (v.contains(n.toLowerCase())) return true;
    }
    return false;
  }

  static bool _isExamAbsent(dynamic grade) {
    return _containsAny(grade.status, const ['غائب', 'غياب', 'absent']) ||
        _containsAny(grade.notes, const ['غائب', 'غياب', 'absent']);
  }

  static bool _isExamCheating(dynamic grade) {
    return _containsAny(grade.status, const ['غش', 'cheat']) ||
        _containsAny(grade.notes, const ['غش', 'cheat']);
  }

  static bool _isExamMissing(dynamic grade) {
    return _containsAny(grade.status, const ['مفقودة', 'missing']) ||
        _containsAny(grade.notes, const ['مفقودة', 'missing']);
  }

  static bool _isExamExemptOrPostponed(dynamic grade) {
    return _containsAny(grade.status, const ['معفئ', 'مؤجل', 'معفئ او مؤجل', 'exempt', 'postponed']) ||
        _containsAny(grade.notes, const ['معفئ', 'مؤجل', 'معفئ او مؤجل', 'exempt', 'postponed']);
  }

  static bool _isValidScoredExam(dynamic grade) {
    return !_isExamExemptOrPostponed(grade) &&
        !_isExamAbsent(grade) &&
        !_isExamCheating(grade) &&
        !_isExamMissing(grade);
  }

  static String _dateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// حساب حالة الطالب بشكل موحد يجمع الحضور والامتحان
  static Future<Map<String, bool>> checkStudentStatus(
    StudentModel student, {
    int? classId,
  }) async {
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
      final allGrades = await dbHelper.getGradesByStudent(student.id!);
      final allAttendances = await dbHelper.getAttendanceByStudent(student.id!);

      // إذا تم تحديد فصل، نقوم بتصفية البيانات على هذا الفصل فقط
      final examsInClass = classId != null ? await dbHelper.getExamsByClass(classId) : null;
      final lecturesInClass = classId != null ? await dbHelper.getLecturesByClass(classId) : null;

      final grades = examsInClass == null
          ? allGrades
          : allGrades
              .where((g) => examsInClass.any(
                    (e) =>
                        e.title == g.examName &&
                        _dateKey(e.date) == _dateKey(g.examDate),
                  ))
              .toList();

      // أخذ آخر درجة فقط لكل امتحان (لتجنب تكرار السجلات وتأثيره على الحساب)
      final Map<String, dynamic> latestGradeByExam = {};
      for (final g in grades) {
        final examKey = '${g.examName}__${_dateKey(g.examDate)}';
        final existing = latestGradeByExam[examKey];
        if (existing == null) {
          latestGradeByExam[examKey] = g;
          continue;
        }

        // GradeModel لديه createdAt/updatedAt
        // نفضّل updatedAt لأنه يعكس آخر تعديل للحالة/الدرجة
        final gStamp = (g.updatedAt).isAfter(g.createdAt) ? g.updatedAt : g.createdAt;
        final eStamp = (existing.updatedAt).isAfter(existing.createdAt)
            ? existing.updatedAt
            : existing.createdAt;

        if (gStamp.isAfter(eStamp)) {
          latestGradeByExam[examKey] = g;
        }
      }

      final filteredGrades = latestGradeByExam.values.cast<dynamic>().toList();

      final attendances = lecturesInClass == null
          ? allAttendances
          : allAttendances
              .where((a) => lecturesInClass.any((l) => l.id == a.lectureId))
              .toList();
      
      // حساب المعدل بنفس منطق المعدل الظاهر تحت اسم الطالب:
      // نحول كل امتحان إلى نسبة مئوية ثم نأخذ المتوسط.
      // الغائب/غش/مفقودة تُحسب كنسبة 0% (ولا يتم تجاهلها).
      double totalPercentage = 0;
      int countedExams = 0;

      final examsForMaxScore = examsInClass ?? await dbHelper.getAllExams();

      for (final grade in filteredGrades) {
        // تجاهل المعفئ/المؤجل من المعدل (كأن الامتحان غير موجود)
        if (_isExamExemptOrPostponed(grade)) {
          continue;
        }
        final matchingExam = examsForMaxScore
            .where(
              (e) =>
                  e.title == grade.examName &&
                  _dateKey(e.date) == _dateKey(grade.examDate),
            )
            .firstOrNull;

        final maxScore = grade.maxScore > 0
            ? grade.maxScore
            : (matchingExam?.maxScore ?? 0);

        if (maxScore > 0) {
          final percentage = _isValidScoredExam(grade) ? (grade.score / maxScore) * 100 : 0.0;
          totalPercentage += percentage;
          countedExams++;
        }
      }

      final average = countedExams > 0 ? (totalPercentage / countedExams) : 0.0;
      
      // حساب إحصائيات الامتحانات
      final totalExams = filteredGrades.where((g) => !_isExamExemptOrPostponed(g)).length;
      final attendedExams = filteredGrades.where((g) => _isValidScoredExam(g)).length;
      final missedExams = filteredGrades.where((g) => !_isExamExemptOrPostponed(g) && _isExamAbsent(g)).length;
      
      final examAttendancePercentage = totalExams > 0 ? (attendedExams / totalExams) * 100 : 0.0;
      
      // حساب إحصائيات المحاضرات
      final totalLectures = attendances.length;
      final attendedLectures =
          attendances.where((a) => a.status == AttendanceStatus.present).length;
      final missedLectures =
          attendances.where((a) => a.status == AttendanceStatus.absent).length;
      
      final lectureAttendancePercentage = totalLectures > 0 ? (attendedLectures / totalLectures) * 100 : 0.0;
      
      // التحقق من معايير الطلاب المميزون (فقط إذا لم تكن معطلة)
      if (!isExcellentDisabled) {
        // منطق موحّد: يجب أن يحقق الطالب جميع المعايير المفعّلة
        bool excellentPass = true;

        // معيار المعدل المرتفع
        if (excellentAverageEnabled) {
          final double minAverage = prefs.getDouble(_excellentMinAverage) ?? 85.0;
          if (average < minAverage) excellentPass = false;
        }
        
        // معيار عدد الامتحانات
        if (excellentExamsCountEnabled) {
          final int minExamsCount = _getIntWithFallback(
            prefs,
            _excellentMinExamsCount,
            const [_excellentMinExamsCountAlt],
            3,
          );
          if (totalExams < minExamsCount) excellentPass = false;
        }
        
        // معيار حضور الامتحانات
        if (excellentExamAttendanceEnabled) {
          final double minExamAttendance = prefs.getDouble(_excellentMinExamAttendance) ?? 95.0;
          if (examAttendancePercentage < minExamAttendance) excellentPass = false;
        }
        
        // معيار حضور المحاضرات
        if (excellentLectureAttendanceEnabled) {
          final double minLectureAttendance = prefs.getDouble(_excellentMinLectureAttendance) ?? 90.0;
          if (lectureAttendancePercentage < minLectureAttendance) excellentPass = false;
        }

        isExcellent = excellentPass;
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
          final int minMissedExams = _getIntWithFallback(
            prefs,
            _atRiskMaxMissedExams,
            const [_atRiskMinMissedExamsAlt],
            1,
          );
          if (missedExams >= minMissedExams) {
            isAtRisk = true;
          }
        }
        
        // معيار المحاضرات الغائبة
        if (atRiskMissedLecturesEnabled) {
          final int minMissedLectures = _getIntWithFallback(
            prefs,
            _atRiskMaxMissedLectures,
            const [_atRiskMinMissedLecturesAlt],
            3,
          );
          if (missedLectures >= minMissedLectures) {
            isAtRisk = true;
          }
        }
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

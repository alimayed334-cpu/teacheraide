import 'package:hive_flutter/hive_flutter.dart';
import '../models/hive_student.dart';
import '../models/hive_exam.dart';

class HiveService {
  static const String studentsBoxName = 'students';
  static const String examsBoxName = 'exams';

  // تهيئة Hive
  static Future<void> init() async {
    await Hive.initFlutter();
    
    // تسجيل Adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(HiveStudentAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(HiveExamAdapter());
    }
    
    // فتح الصناديق
    await Hive.openBox<HiveStudent>(studentsBoxName);
    await Hive.openBox<HiveExam>(examsBoxName);
  }

  // الحصول على صندوق الطلاب
  static Box<HiveStudent> get studentsBox => Hive.box<HiveStudent>(studentsBoxName);

  // الحصول على صندوق الامتحانات
  static Box<HiveExam> get examsBox => Hive.box<HiveExam>(examsBoxName);

  // ==================== عمليات الطلاب ====================

  // إضافة طالب
  static Future<void> addStudent(HiveStudent student) async {
    await studentsBox.put(student.id, student);
  }

  // تحديث طالب
  static Future<void> updateStudent(HiveStudent student) async {
    student.updatedAt = DateTime.now();
    await studentsBox.put(student.id, student);
  }

  // حذف طالب
  static Future<void> deleteStudent(String studentId) async {
    // حذف جميع امتحانات الطالب أولاً
    final exams = getExamsByStudentId(studentId);
    for (var exam in exams) {
      await deleteExam(exam.id);
    }
    
    // ثم حذف الطالب
    await studentsBox.delete(studentId);
  }

  // الحصول على طالب بالمعرف
  static HiveStudent? getStudent(String studentId) {
    return studentsBox.get(studentId);
  }

  // الحصول على جميع الطلاب
  static List<HiveStudent> getAllStudents() {
    return studentsBox.values.toList();
  }

  // البحث عن طلاب
  static List<HiveStudent> searchStudents(String query) {
    return studentsBox.values
        .where((student) =>
            student.name.toLowerCase().contains(query.toLowerCase()) ||
            student.grade.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  // الحصول على طلاب حسب الصف
  static List<HiveStudent> getStudentsByGrade(String grade) {
    return studentsBox.values
        .where((student) => student.grade == grade)
        .toList();
  }

  // الحصول على طلاب حسب الفصل
  static List<HiveStudent> getStudentsByClass(String classId) {
    return studentsBox.values
        .where((student) => student.classId == classId)
        .toList();
  }

  // ==================== عمليات الامتحانات ====================

  // إضافة امتحان
  static Future<void> addExam(HiveExam exam) async {
    await examsBox.put(exam.id, exam);
    
    // تحديث قائمة الامتحانات في الطالب
    final student = getStudent(exam.studentId);
    if (student != null) {
      if (!student.examIds.contains(exam.id)) {
        student.examIds.add(exam.id);
        await updateStudent(student);
      }
    }
  }

  // تحديث امتحان
  static Future<void> updateExam(HiveExam exam) async {
    exam.updatedAt = DateTime.now();
    await examsBox.put(exam.id, exam);
  }

  // حذف امتحان
  static Future<void> deleteExam(String examId) async {
    final exam = getExam(examId);
    if (exam != null) {
      // إزالة معرف الامتحان من الطالب
      final student = getStudent(exam.studentId);
      if (student != null) {
        student.examIds.remove(examId);
        await updateStudent(student);
      }
      
      // حذف الامتحان
      await examsBox.delete(examId);
    }
  }

  // الحصول على امتحان بالمعرف
  static HiveExam? getExam(String examId) {
    return examsBox.get(examId);
  }

  // الحصول على جميع الامتحانات
  static List<HiveExam> getAllExams() {
    return examsBox.values.toList();
  }

  // الحصول على امتحانات طالب معين
  static List<HiveExam> getExamsByStudentId(String studentId) {
    return examsBox.values
        .where((exam) => exam.studentId == studentId)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // ترتيب حسب التاريخ (الأحدث أولاً)
  }

  // الحصول على امتحانات حسب المادة
  static List<HiveExam> getExamsBySubject(String subject) {
    return examsBox.values
        .where((exam) => exam.subject == subject)
        .toList();
  }

  // الحصول على امتحانات طالب في مادة معينة
  static List<HiveExam> getStudentExamsBySubject(String studentId, String subject) {
    return examsBox.values
        .where((exam) => exam.studentId == studentId && exam.subject == subject)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  // حساب معدل الطالب
  static double getStudentAverage(String studentId) {
    final exams = getExamsByStudentId(studentId);
    if (exams.isEmpty) return 0.0;
    
    double totalPercentage = 0;
    for (var exam in exams) {
      totalPercentage += exam.percentage;
    }
    
    return totalPercentage / exams.length;
  }

  // حساب معدل الطالب في مادة معينة
  static double getStudentSubjectAverage(String studentId, String subject) {
    final exams = getStudentExamsBySubject(studentId, subject);
    if (exams.isEmpty) return 0.0;
    
    double totalPercentage = 0;
    for (var exam in exams) {
      totalPercentage += exam.percentage;
    }
    
    return totalPercentage / exams.length;
  }

  // الحصول على أفضل الطلاب
  static List<Map<String, dynamic>> getTopStudents({int limit = 10}) {
    final students = getAllStudents();
    final studentAverages = <Map<String, dynamic>>[];
    
    for (var student in students) {
      final average = getStudentAverage(student.id);
      if (average > 0) {
        studentAverages.add({
          'student': student,
          'average': average,
        });
      }
    }
    
    studentAverages.sort((a, b) => 
      (b['average'] as double).compareTo(a['average'] as double));
    
    return studentAverages.take(limit).toList();
  }

  // ==================== إحصائيات ====================

  // عدد الطلاب
  static int getStudentsCount() => studentsBox.length;

  // عدد الامتحانات
  static int getExamsCount() => examsBox.length;

  // عدد امتحانات الطالب
  static int getStudentExamsCount(String studentId) {
    return getExamsByStudentId(studentId).length;
  }

  // ==================== تنظيف البيانات ====================

  // حذف جميع الطلاب
  static Future<void> clearAllStudents() async {
    await studentsBox.clear();
  }

  // حذف جميع الامتحانات
  static Future<void> clearAllExams() async {
    await examsBox.clear();
  }

  // حذف جميع البيانات
  static Future<void> clearAllData() async {
    await clearAllStudents();
    await clearAllExams();
  }

  // إغلاق الصناديق
  static Future<void> close() async {
    await studentsBox.close();
    await examsBox.close();
  }
}

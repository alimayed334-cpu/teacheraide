import 'package:flutter/foundation.dart';
import '../models/grade_model.dart';
import '../database/database_helper.dart';

class GradeProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<GradeModel> _grades = [];
  bool _isLoading = false;
  String? _error;
  int? _currentStudentId;

  int updateCounter = 0;

  void refreshIndicators() {
    updateCounter++;
    notifyListeners();
  }

  List<GradeModel> get grades => _grades;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int? get currentStudentId => _currentStudentId;

  Future<void> loadGradesByStudent(int studentId) async {
    _currentStudentId = studentId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _grades = await _databaseHelper.getGradesByStudent(studentId);
    } catch (e) {
      _error = 'خطأ في تحميل الدرجات: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  // دالة جديدة: حفظ الدرجة (تحديث إذا موجودة، إضافة إذا جديدة)
  Future<bool> saveGrade({
    required int studentId,
    required String examName,
    required double score,
    required double maxScore,
    required DateTime examDate,
    String? notes,
  }) async {
    try {
      // البحث عن درجة موجودة لنفس الطالب ونفس الامتحان
      final allGrades = await _databaseHelper.getGradesByStudent(studentId);
      final existingGrade = allGrades.where((g) => g.examName == examName).firstOrNull;
      
      if (existingGrade != null) {
        // تحديث الدرجة الموجودة
        final updatedGrade = existingGrade.copyWith(
          score: score,
          maxScore: maxScore,
          examDate: examDate,
          notes: notes,
          updatedAt: DateTime.now(),
        );
        final ok = await updateGrade(updatedGrade);
        if (ok) refreshIndicators();
        return ok;
      } else {
        // إضافة درجة جديدة
        final ok = await addGrade(
          studentId: studentId,
          examName: examName,
          score: score,
          maxScore: maxScore,
          examDate: examDate,
          notes: notes,
        );
        if (ok) refreshIndicators();
        return ok;
      }
    } catch (e) {
      _error = 'خطأ في حفظ الدرجة: $e';
      debugPrint(_error);
      return false;
    }
  }

  Future<bool> addGrade({
    required int studentId,
    required String examName,
    required double score,
    required double maxScore,
    required DateTime examDate,
    String? notes,
    String? status,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      
      // التحقق أولاً إذا كان يوجد سجل للطالب والامتحان
      final allGrades = await _databaseHelper.getGradesByStudent(studentId);
      final existingGrade = allGrades.where((g) => g.examName == examName).firstOrNull;
      
      // إذا كان يوجد سجل قديم، قم بحذفه أولاً
      if (existingGrade != null) {
        print('حذف السجل القديم للطالب $studentId والامتحان $examName');
        await _databaseHelper.deleteGrade(existingGrade.id!);
      }
      
      // تنظيف الملاحظات: إذا كانت الدرجة > 0، نحذف الملاحظات القديمة (غائب، غش، إلخ)
      String? cleanedNotes = notes;
      if (score > 0) {
        // إزالة الملاحظات السلبية إذا كانت الدرجة موجودة
        if (notes != null) {
          cleanedNotes = notes
              .replaceAll('غائب', '')
              .replaceAll('غش', '')
              .replaceAll('مفقودة', '')
              .replaceAll('طرد', '')
              .trim();
          // إذا أصبحت الملاحظات فارغة بعد التنظيف، نجعلها null
          if (cleanedNotes.isEmpty || cleanedNotes == '-') {
            cleanedNotes = null;
          }
        }
      }
      
      // إضافة سجل جديد دائماً
      final newGrade = GradeModel(
        studentId: studentId,
        examName: examName,
        score: score,
        maxScore: maxScore,
        examDate: examDate,
        notes: cleanedNotes,
        status: status,
        createdAt: now,
        updatedAt: now,
      );

      final id = await _databaseHelper.insertGrade(newGrade);
      if (id > 0) {
        print('تم إضافة سجل جديد للطالب $studentId والامتحان $examName');
        if (_currentStudentId == studentId) {
          await loadGradesByStudent(studentId);
        }
        _isLoading = false;
        notifyListeners();
        refreshIndicators();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في إضافة الدرجة: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateGrade(GradeModel grade) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // تنظيف الملاحظات: إذا كانت الدرجة > 0، نحذف الملاحظات القديمة
      String? cleanedNotes = grade.notes;
      if (grade.score > 0 && grade.notes != null) {
        cleanedNotes = grade.notes!
            .replaceAll('غائب', '')
            .replaceAll('غش', '')
            .replaceAll('مفقودة', '')
            .replaceAll('طرد', '')
            .trim();
        if (cleanedNotes.isEmpty || cleanedNotes == '-') {
          cleanedNotes = null;
        }
      }
      
      final updatedGrade = grade.copyWith(
        updatedAt: DateTime.now(),
        notes: cleanedNotes,
      );
      final result = await _databaseHelper.updateGrade(updatedGrade);
      
      if (result > 0) {
        if (_currentStudentId == grade.studentId) {
          await loadGradesByStudent(grade.studentId);
        }
        _isLoading = false;
        notifyListeners();
        refreshIndicators();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في تحديث الدرجة: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteGrade(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _databaseHelper.deleteGrade(id);
      
      if (result > 0) {
        if (_currentStudentId != null) {
          await loadGradesByStudent(_currentStudentId!);
        }
        _isLoading = false;
        notifyListeners();
        refreshIndicators();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في حذف الدرجة: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  GradeModel? getGradeById(int id) {
    try {
      return _grades.firstWhere((g) => g.id == id);
    } catch (e) {
      return null;
    }
  }

  List<GradeModel> searchGrades(String query) {
    if (query.isEmpty) return _grades;
    
    return _grades.where((g) =>
      g.examName.toLowerCase().contains(query.toLowerCase()) ||
      g.gradeLevel.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  double getStudentAverage() {
    if (_grades.isEmpty) return 0.0;
    
    double totalPercentage = 0.0;
    for (var grade in _grades) {
      totalPercentage += grade.percentage;
    }
    
    return totalPercentage / _grades.length;
  }

  Map<String, int> getGradeDistribution() {
    Map<String, int> distribution = {
      'ممتاز': 0,
      'جيد جداً': 0,
      'جيد': 0,
      'مقبول': 0,
      'ضعيف': 0,
    };

    for (var grade in _grades) {
      distribution[grade.gradeLevel] = distribution[grade.gradeLevel]! + 1;
    }

    return distribution;
  }

  List<GradeModel> getGradesByDateRange(DateTime startDate, DateTime endDate) {
    return _grades.where((grade) =>
      grade.examDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
      grade.examDate.isBefore(endDate.add(const Duration(days: 1)))
    ).toList();
  }

  double getHighestScore() {
    if (_grades.isEmpty) return 0.0;
    return _grades.map((g) => g.percentage).reduce((a, b) => a > b ? a : b);
  }

  double getLowestScore() {
    if (_grades.isEmpty) return 0.0;
    return _grades.map((g) => g.percentage).reduce((a, b) => a < b ? a : b);
  }

  List<GradeModel> getRecentGrades({int limit = 5}) {
    final sortedGrades = List<GradeModel>.from(_grades);
    sortedGrades.sort((a, b) => b.examDate.compareTo(a.examDate));
    return sortedGrades.take(limit).toList();
  }

  // دالة للحصول على درجات طالب معين
  Future<List<GradeModel>> getGradesByStudent(int studentId) async {
    try {
      return await _databaseHelper.getGradesByStudent(studentId);
    } catch (e) {
      debugPrint('خطأ في تحميل درجات الطالب: $e');
      return [];
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearGrades() {
    _grades = [];
    _currentStudentId = null;
    notifyListeners();
  }
}

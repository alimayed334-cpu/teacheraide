import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/exam_model.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';

class ExamProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  
  List<ExamModel> _exams = [];
  bool _isLoading = false;
  String? _error;
  int? _currentClassId;

  late final StreamSubscription<void> _syncSub;
  Timer? _syncDebounce;
  bool _reloadInFlight = false;

  List<ExamModel> get exams => _exams;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ExamProvider() {
    _syncSub = SyncService.instance.changes.listen((_) {
      final cid = _currentClassId;
      if (cid == null) return;

      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 200), () {
        final current = _currentClassId;
        if (current == null) return;
        if (_reloadInFlight) return;
        _reloadInFlight = true;
        loadExamsByClass(current).whenComplete(() {
          _reloadInFlight = false;
        });
      });
    });
  }

  void clearExams() {
    _exams = [];
    _currentClassId = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncSub.cancel();
    super.dispose();
  }

  // تحميل امتحانات فصل معين
  Future<void> loadExamsByClass(int classId) async {
    _isLoading = true;
    _error = null;
    _currentClassId = classId;
    notifyListeners();

    try {
      _exams = await _databaseHelper.getExamsByClass(classId);
      print('📚 Loaded ${_exams.length} exams for class $classId');
    } catch (e) {
      _error = 'خطأ في تحميل الامتحانات: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  // إضافة امتحان جديد
  Future<bool> addExam({
    required String title,
    required DateTime date,
    required double maxScore,
    required int classId,
    String? description,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('🔹 ExamProvider.addExam called with title: $title, classId: $classId');
      final now = DateTime.now();
      final newExam = ExamModel(
        title: title,
        date: date,
        maxScore: maxScore,
        classId: classId,
        description: description,
        createdAt: now,
        updatedAt: now,
      );

      final id = await _databaseHelper.insertExam(newExam);
      print('✅ Exam added with ID: $id, Title: $title, ClassId: $classId');
      
      if (id > 0) {
        // إعادة تحميل الامتحانات للفصل الحالي
        if (_currentClassId == classId) {
          await loadExamsByClass(classId);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في إضافة الامتحان: $e';
      debugPrint('❌ Error adding exam: $_error');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // تحديث امتحان
  Future<bool> updateExam(ExamModel exam) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedExam = exam.copyWith(updatedAt: DateTime.now());
      final result = await _databaseHelper.updateExam(updatedExam);
      
      if (result > 0) {
        // إعادة تحميل الامتحانات
        if (_currentClassId != null) {
          await loadExamsByClass(_currentClassId!);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في تحديث الامتحان: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // حذف امتحان
  Future<bool> deleteExam(int examId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _databaseHelper.deleteExam(examId);
      
      if (result > 0) {
        // إعادة تحميل الامتحانات
        if (_currentClassId != null) {
          await loadExamsByClass(_currentClassId!);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في حذف الامتحان: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // تحميل جميع الامتحانات
  Future<void> loadAllExams() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _exams = await _databaseHelper.getAllExams();
      _currentClassId = null;
    } catch (e) {
      _error = 'خطأ في تحميل الامتحانات: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  // البحث في الامتحانات
  List<ExamModel> searchExams(String query) {
    if (query.isEmpty) return _exams;
    
    return _exams.where((exam) {
      return exam.title.toLowerCase().contains(query.toLowerCase()) ||
             (exam.description?.toLowerCase().contains(query.toLowerCase()) ?? false);
    }).toList();
  }

  // فلترة الامتحانات حسب التاريخ
  List<ExamModel> getExamsByDateRange(DateTime start, DateTime end) {
    return _exams.where((exam) {
      return exam.date.isAfter(start.subtract(const Duration(days: 1))) &&
             exam.date.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }
}

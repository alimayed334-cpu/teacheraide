import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/class_model.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';

class ClassProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<ClassModel> _classes = [];
  bool _isLoading = false;
  String? _error;

  late final StreamSubscription<void> _syncSub;
  Timer? _syncDebounce;
  bool _reloadInFlight = false;

  List<ClassModel> get classes => _classes;
  bool get isLoading => _isLoading;
  String? get error => _error;

  // Constructor - تحميل البيانات تلقائياً عند إنشاء الـ Provider
  ClassProvider() {
    loadClasses();

    _syncSub = SyncService.instance.changes.listen((_) {
      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 200), () {
        if (_reloadInFlight) return;
        _reloadInFlight = true;
        loadClasses().whenComplete(() {
          _reloadInFlight = false;
        });
      });
    });
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncSub.cancel();
    super.dispose();
  }

  Future<void> loadClasses() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _classes = await _databaseHelper.getAllClasses();
    } catch (e) {
      _error = 'خطأ في تحميل الفصول: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> addClass(String name, String subject, String year, {String? description}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final newClass = ClassModel(
        name: name,
        subject: subject,
        year: year,
        description: description,
        createdAt: now,
        updatedAt: now,
      );

      final id = await _databaseHelper.insertClass(newClass);
      if (id > 0) {
        await loadClasses();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في إضافة الفصل: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> updateClass(ClassModel classModel) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedClass = classModel.copyWith(updatedAt: DateTime.now());
      final result = await _databaseHelper.updateClass(updatedClass);
      
      if (result > 0) {
        await loadClasses();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في تحديث الفصل: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteClass(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _databaseHelper.deleteClass(id);
      
      if (result > 0) {
        await loadClasses();
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في حذف الفصل: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteClassCascade(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _databaseHelper.deleteClassCascade(id);

      // Try to flush outbox immediately so cloud deletes happen without waiting.
      try {
        await SyncService.instance.flushOutboxOnce();
      } catch (_) {
        // Ignore: offline / Firebase not initialized.
      }

      _classes = await _databaseHelper.getAllClasses();

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'خطأ في حذف الفصل: $e';
      debugPrint(_error);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  ClassModel? getClassById(int id) {
    try {
      return _classes.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }

  List<ClassModel> searchClasses(String query) {
    if (query.isEmpty) return _classes;
    
    return _classes.where((c) =>
      c.name.toLowerCase().contains(query.toLowerCase()) ||
      c.subject.toLowerCase().contains(query.toLowerCase()) ||
      c.year.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<int> getStudentCount(int classId) async {
    try {
      final students = await _databaseHelper.getStudentsByClass(classId);
      return students.length;
    } catch (e) {
      debugPrint('خطأ في حساب عدد الطلاب: $e');
      return 0;
    }
  }
}

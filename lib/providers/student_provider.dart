import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import '../models/student_model.dart';
import '../database/database_helper.dart';
import '../services/sync_service.dart';

class StudentProvider with ChangeNotifier {
  final DatabaseHelper _databaseHelper = DatabaseHelper();
  List<StudentModel> _students = [];
  bool _isLoading = false;
  String? _error;
  int? _currentClassId;
  bool _isNotifying = false;
  int updateCounter = 0;

  late final StreamSubscription<void> _syncSub;
  Timer? _syncDebounce;
  bool _reloadInFlight = false;

  StudentProvider() {
    _syncSub = SyncService.instance.changes.listen((_) {
      final cid = _currentClassId;
      if (cid == null) return;

      _syncDebounce?.cancel();
      _syncDebounce = Timer(const Duration(milliseconds: 200), () {
        final current = _currentClassId;
        if (current == null) return;
        if (_reloadInFlight) return;
        _reloadInFlight = true;
        loadStudentsByClass(current).whenComplete(() {
          _reloadInFlight = false;
        });
      });
    });
  }

  void clearStudents() {
    _students = [];
    _currentClassId = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }

  List<StudentModel> get students => _students;
  bool get isLoading => _isLoading;
  String? get error => _error;
  @override
  void notifyListeners() {
    if (_isNotifying) return;

    void doNotify() {
      if (_isNotifying) return;
      _isNotifying = true;
      super.notifyListeners();
      _isNotifying = false;
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final isBuildingFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (isBuildingFrame) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        doNotify();
      });
      return;
    }

    doNotify();
  }

  Future<void> loadStudentsByClass(int classId) async {
    _currentClassId = classId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _students = await _databaseHelper.getStudentsByClass(classId);
      print('📚 Loaded ${_students.length} students for class $classId');
    } catch (e) {
      _error = 'خطأ في تحميل الطلاب: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  // دالة إعادة حساب حالة الخطر لجميع الطلاب
  void recalculateRiskForAllStudents() {
    // فقط notifyListeners لإجبار الواجهات على إعادة بناء نفسها
    // سيتم حساب حالة الخطر في الواجهات نفسها
    notifyListeners();
  }

  // دالة تحديث المؤشرات لإجبار FutureBuilder على إعادة الحساب
  void refreshIndicators() {
    updateCounter++;
    notifyListeners();
  }

  Future<bool> addStudent({
    required int classId,
    required String name,
    String? photo,
    String? photoPath,
    String? notes,
    String? parentPhone,
    String? parentEmail,
    String? studentId,
    String? email,
    String? phone,
    String? location,
    DateTime? birthDate,
    GuardianModel? primaryGuardian,
    GuardianModel? secondaryGuardian,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      print('🔹 StudentProvider.addStudent called with classId: $classId, name: $name');
      // توليد رقم الطالب تلقائياً إذا لم يتم إدخاله
      String? resolvedStudentId = studentId?.trim();

      // If user provided an ID, it must be unique across the whole app.
      if ((resolvedStudentId ?? '').isNotEmpty) {
        final taken = await _databaseHelper.isStudentIdTaken(resolvedStudentId!);
        if (taken) {
          _error = 'رقم الطالب مستخدم بالفعل. الرجاء اختيار رقم مختلف';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      } else {
        // Auto-generate a globally unique numeric student id.
        resolvedStudentId = await _databaseHelper.getNextUniqueStudentId();
      }
      final student = StudentModel(
        classId: classId,
        name: name,
        photo: photo,
        photoPath: photoPath,
        notes: notes,
        parentPhone: parentPhone,
        parentEmail: parentEmail,
        studentId: resolvedStudentId,
        email: email,
        phone: phone,
        location: location,
        birthDate: birthDate,
        primaryGuardian: primaryGuardian,
        secondaryGuardian: secondaryGuardian,
        createdAt: now,
        updatedAt: now,
      );

      final id = await _databaseHelper.insertStudent(student);
      print('✅ Student added with ID: $id, Name: $name, ClassId: $classId');
      if (id > 0) {
        print('🔄 Reloading students for class: $_currentClassId (adding to class: $classId)');
        if (_currentClassId == classId) {
          await loadStudentsByClass(classId);
        } else {
          print('⚠️ Not reloading: _currentClassId ($_currentClassId) != classId ($classId)');
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في إضافة الطالب: $e';
      debugPrint('❌ Error adding student: $_error');
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<void> loadAllStudents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _students = await _databaseHelper.getAllStudents();
    } catch (e) {
      _error = 'خطأ في تحميل جميع الطلاب: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  // Add missing methods
  Future<List<StudentModel>> getAllStudents() async {
    try {
      return await _databaseHelper.getAllStudents();
    } catch (e) {
      _error = 'خطأ في جلب جميع الطلاب: $e';
      debugPrint(_error);
      return [];
    }
  }

  Future<List<StudentModel>> getStudentsByClass(int classId) async {
    try {
      return await _databaseHelper.getStudentsByClass(classId);
    } catch (e) {
      _error = 'خطأ في جلب طلاب الفصل: $e';
      debugPrint(_error);
      return [];
    }
  }

  Future<bool> updateStudent(StudentModel student) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updatedStudent = student.copyWith(updatedAt: DateTime.now());
      final result = await _databaseHelper.updateStudent(updatedStudent);
      
      if (result > 0) {
        if (_currentClassId == student.classId) {
          await loadStudentsByClass(student.classId);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } catch (e) {
      _error = 'خطأ في تحديث الطالب: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<bool> deleteStudent(int id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (id <= 0) {
        _error = 'خطأ في حذف الطالب: معرف غير صالح';
        _isLoading = false;
        notifyListeners();
        return false;
      }
      final result = await _databaseHelper.deleteStudent(id);
      
      if (result > 0) {
        if (_currentClassId != null) {
          await loadStudentsByClass(_currentClassId!);
        }
        _isLoading = false;
        notifyListeners();
        return true;
      }
      _error = 'تعذر حذف الطالب (ربما تم حذفه مسبقاً)';
    } catch (e) {
      _error = 'خطأ في حذف الطالب: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  Future<StudentModel?> getStudentById(int id) async {
    try {
      // أولاً حاول البحث في القائمة المحملة
      final student = _students.firstWhere((s) => s.id == id);
      return student;
    } catch (e) {
      try {
        // إذا لم يتم العثور عليه، جلب من قاعدة البيانات
        return await _databaseHelper.getStudent(id);
      } catch (e) {
        debugPrint('Error getting student by id: $e');
        return null;
      }
    }
  }

  List<StudentModel> searchStudents(String query) {
    if (query.isEmpty) return _students;
    
    return _students.where((s) =>
      s.name.toLowerCase().contains(query.toLowerCase()) ||
      (s.parentPhone?.contains(query) ?? false) ||
      (s.parentEmail?.toLowerCase().contains(query.toLowerCase()) ?? false)
    ).toList();
  }

  Future<double> getStudentAverage(int studentId) async {
    try {
      return await _databaseHelper.getStudentAverage(studentId);
    } catch (e) {
      debugPrint('خطأ في حساب متوسط الطالب: $e');
      return 0.0;
    }
  }

  Future<Map<String, int>> getStudentAttendanceStats(int studentId) async {
    try {
      return await _databaseHelper.getAttendanceStats(studentId);
    } catch (e) {
      debugPrint('خطأ في إحصائيات الحضور: $e');
      return {'present': 0, 'absent': 0, 'late': 0};
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncDebounce?.cancel();
    _syncSub.cancel();
    super.dispose();
  }
}

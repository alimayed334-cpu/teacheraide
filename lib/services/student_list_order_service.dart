import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StudentListOrderEvent {
  final int classId;
  final List<int> studentIds;
  final int updatedAtMs;

  const StudentListOrderEvent({
    required this.classId,
    required this.studentIds,
    required this.updatedAtMs,
  });
}

class StudentSortModeEvent {
  final int classId;
  final String mode;
  final int updatedAtMs;

  const StudentSortModeEvent({
    required this.classId,
    required this.mode,
    required this.updatedAtMs,
  });
}

class StudentListOrderService {
  StudentListOrderService._();

  static final StudentListOrderService instance = StudentListOrderService._();

  static String _key(int classId) => 'student_list_order_$classId';
  static String _sortKey(int classId) => 'student_sort_mode_$classId';

  final StreamController<StudentListOrderEvent> _controller =
      StreamController<StudentListOrderEvent>.broadcast();

  final StreamController<StudentSortModeEvent> _sortController =
      StreamController<StudentSortModeEvent>.broadcast();

  Stream<StudentListOrderEvent> get changes => _controller.stream;
  Stream<StudentSortModeEvent> get sortModeChanges => _sortController.stream;

  Future<StudentListOrderEvent?> getOrder(int classId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(classId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final idsRaw = map['ids'];
      final updatedAtMs = (map['updatedAtMs'] is int) ? map['updatedAtMs'] as int : 0;
      if (idsRaw is! List) return null;
      final ids = idsRaw.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
      return StudentListOrderEvent(classId: classId, studentIds: ids, updatedAtMs: updatedAtMs);
    } catch (_) {
      return null;
    }
  }

  Future<StudentSortModeEvent?> getSortMode(int classId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sortKey(classId));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      final mode = (map['mode'] ?? '').toString();
      final updatedAtMs = (map['updatedAtMs'] is int) ? map['updatedAtMs'] as int : 0;
      if (mode.isEmpty) return null;
      return StudentSortModeEvent(classId: classId, mode: mode, updatedAtMs: updatedAtMs);
    } catch (_) {
      return null;
    }
  }

  Future<void> setOrder({required int classId, required List<int> studentIds}) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;

    final payload = jsonEncode({
      'ids': studentIds,
      'updatedAtMs': updatedAtMs,
    });

    await prefs.setString(_key(classId), payload);
    _controller.add(
      StudentListOrderEvent(classId: classId, studentIds: List<int>.from(studentIds), updatedAtMs: updatedAtMs),
    );
  }

  Future<void> setSortMode({required int classId, required String mode}) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;

    final payload = jsonEncode({
      'mode': mode,
      'updatedAtMs': updatedAtMs,
    });

    await prefs.setString(_sortKey(classId), payload);
    _sortController.add(
      StudentSortModeEvent(classId: classId, mode: mode, updatedAtMs: updatedAtMs),
    );
  }

  static List<T> applyOrder<T>({
    required List<T> items,
    required int Function(T item) getId,
    required List<int> order,
  }) {
    if (order.isEmpty) return items;

    final map = <int, T>{};
    for (final i in items) {
      map[getId(i)] = i;
    }

    final out = <T>[];
    for (final id in order) {
      final item = map.remove(id);
      if (item != null) out.add(item);
    }

    // Append remaining (new students not in saved order)
    out.addAll(map.values);
    return out;
  }
}

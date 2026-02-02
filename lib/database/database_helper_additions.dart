// دوال إضافية لإدارة الأقساط

  // حذف دفعة
  Future<int> deleteInstallment(int installmentId) async {
    final db = await database;
    return await db.delete(
      'installments',
      where: 'id = ?',
      whereArgs: [installmentId],
    );
  }

  // تحديث دفعة
  Future<int> updateInstallment(int installmentId, int newAmount, String newDate) async {
    final db = await database;
    return await db.update(
      'installments',
      {
        'amount': newAmount,
        'date': newDate,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [installmentId],
    );
  }

  // جلب إجمالي المدفوعات لطلاب محددين لكورس محدد
  Future<Map<int, int>> getTotalPaidByStudentIdsForCourse({
    required List<int> studentIds,
    required String courseId,
  }) async {
    if (studentIds.isEmpty) return {};

    final db = await database;
    final placeholders = List.filled(studentIds.length, '?').join(',');
    final result = await db.rawQuery(
      'SELECT student_id, COALESCE(SUM(amount), 0) AS total_paid '
      'FROM installments '
      'WHERE student_id IN ($placeholders) AND course_id = ? '
      'GROUP BY student_id',
      [...studentIds, courseId],
    );

    final map = <int, int>{};
    for (final row in result) {
      final sid = row['student_id'];
      final total = row['total_paid'];
      final sidInt = (sid is int) ? sid : int.tryParse(sid?.toString() ?? '');
      if (sidInt == null) continue;

      int totalInt;
      if (total is int) {
        totalInt = total;
      } else if (total is num) {
        totalInt = total.toInt();
      } else {
        totalInt = int.tryParse(total?.toString() ?? '') ?? 0;
      }
      map[sidInt] = totalInt;
    }

    return map;
  }

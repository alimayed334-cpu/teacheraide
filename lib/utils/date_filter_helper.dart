import 'package:shared_preferences/shared_preferences.dart';

class DateFilterHelper {
  static const String _filterKey = 'student_date_filter';
  static const String _startDateKey = 'student_start_date';
  static const String _endDateKey = 'student_end_date';

  // حفظ التصفية الحالية
  static Future<void> saveDateFilter(String filter, DateTime? startDate, DateTime? endDate) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_filterKey, filter);
    
    if (startDate != null) {
      await prefs.setString(_startDateKey, startDate.toIso8601String());
    } else {
      await prefs.remove(_startDateKey);
    }
    
    if (endDate != null) {
      await prefs.setString(_endDateKey, endDate.toIso8601String());
    } else {
      await prefs.remove(_endDateKey);
    }
  }

  // جلب التصفية المحفوظة
  static Future<Map<String, dynamic>> getDateFilter() async {
    final prefs = await SharedPreferences.getInstance();
    final filter = prefs.getString(_filterKey) ?? 'التواريخ: الكل';
    
    DateTime? startDate;
    DateTime? endDate;
    
    final startDateString = prefs.getString(_startDateKey);
    final endDateString = prefs.getString(_endDateKey);
    
    if (startDateString != null) {
      startDate = DateTime.parse(startDateString);
    }
    
    if (endDateString != null) {
      endDate = DateTime.parse(endDateString);
    }
    
    return {
      'filter': filter,
      'startDate': startDate,
      'endDate': endDate,
    };
  }

  // مسح التصفية
  static Future<void> clearDateFilter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_filterKey);
    await prefs.remove(_startDateKey);
    await prefs.remove(_endDateKey);
  }

  // تطبيق التصفية على البيانات (للحضور)
  static List<T> filterAttendance<T>(List<T> items, String filter, DateTime? startDate, DateTime? endDate, DateTime Function(T) getDate) {
    final now = DateTime.now();
    
    if (filter == 'التواريخ: الكل' || filter == 'كل الفترة') {
      return items;
    } else if (filter == 'اليوم') {
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر أسبوع') {
      // Show last 7 days from today (including today)
      final weekAgo = DateTime(now.year, now.month, now.day - 6); // -6 to include today (7 days total)
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(weekAgo.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر شهر') {
      // Show last complete month (not current month)
      if (now.month == 1) {
        // If current month is January, show December of last year
        final lastMonthStart = DateTime(now.year - 1, 12, 1);
        final lastMonthEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      } else {
        // Show previous complete month
        final lastMonthStart = DateTime(now.year, now.month - 1, 1);
        final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      }
    } else if (filter == 'تاريخ محدد' || filter == 'مخصص') {
      if (startDate == null || endDate == null) return items;
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
               itemDate.isBefore(endDate.add(const Duration(days: 1)));
      }).toList();
    }
    return items;
  }

  // تطبيق التصفية على البيانات (للامتحانات)
  static List<T> filterExams<T>(List<T> items, String filter, DateTime? startDate, DateTime? endDate, DateTime Function(T) getDate) {
    final now = DateTime.now();
    
    if (filter == 'التواريخ: الكل' || filter == 'كل الفترة') {
      return items;
    } else if (filter == 'اليوم') {
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر أسبوع') {
      // Show last 7 days from today (including today)
      final weekAgo = DateTime(now.year, now.month, now.day - 6); // -6 to include today (7 days total)
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(weekAgo.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر شهر') {
      // Show last complete month (not current month)
      if (now.month == 1) {
        // If current month is January, show December of last year
        final lastMonthStart = DateTime(now.year - 1, 12, 1);
        final lastMonthEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      } else {
        // Show previous complete month
        final lastMonthStart = DateTime(now.year, now.month - 1, 1);
        final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      }
    } else if (filter == 'تاريخ محدد' || filter == 'مخصص') {
      if (startDate == null || endDate == null) return items;
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
               itemDate.isBefore(endDate.add(const Duration(days: 1)));
      }).toList();
    }
    return items;
  }

  // تطبيق التصفية على البيانات (للملاحظات)
  static List<T> filterNotes<T>(List<T> items, String filter, DateTime? startDate, DateTime? endDate, DateTime Function(T) getDate) {
    final now = DateTime.now();
    
    if (filter == 'التواريخ: الكل' || filter == 'كل الفترة') {
      return items;
    } else if (filter == 'اليوم') {
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر أسبوع') {
      // Show last 7 days from today (including today)
      final weekAgo = DateTime(now.year, now.month, now.day - 6); // -6 to include today (7 days total)
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(weekAgo.subtract(const Duration(seconds: 1))) &&
               itemDate.isBefore(todayEnd.add(const Duration(seconds: 1)));
      }).toList();
    } else if (filter == 'آخر شهر') {
      // Show last complete month (not current month)
      if (now.month == 1) {
        // If current month is January, show December of last year
        final lastMonthStart = DateTime(now.year - 1, 12, 1);
        final lastMonthEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      } else {
        // Show previous complete month
        final lastMonthStart = DateTime(now.year, now.month - 1, 1);
        final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);
        return items.where((item) {
          final itemDate = getDate(item);
          return itemDate.isAfter(lastMonthStart.subtract(const Duration(seconds: 1))) &&
                 itemDate.isBefore(lastMonthEnd.add(const Duration(seconds: 1)));
        }).toList();
      }
    } else if (filter == 'تاريخ محدد' || filter == 'مخصص') {
      if (startDate == null || endDate == null) return items;
      return items.where((item) {
        final itemDate = getDate(item);
        return itemDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
               itemDate.isBefore(endDate.add(const Duration(days: 1)));
      }).toList();
    }
    return items;
  }
}

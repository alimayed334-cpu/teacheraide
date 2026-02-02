import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../providers/student_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';

class FinancialDashboardScreen extends StatefulWidget {
  final ClassModel classModel;

  const FinancialDashboardScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<FinancialDashboardScreen> createState() => _FinancialDashboardScreenState();
}

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    
    final int? value = int.tryParse(newValue.text.replaceAll(',', ''));
    if (value == null) {
      return oldValue;
    }
    
    return TextEditingValue(
      text: _formatNumber(value),
      selection: TextSelection.collapsed(offset: _formatNumber(value).length),
    );
  }
  
  String _formatNumber(int number) {
    return number.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }
}

class _FinancialDashboardScreenState extends State<FinancialDashboardScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  int _totalStudents = 0;
  int _firstInstallmentLate = 0;
  int _secondInstallmentLate = 0;
  int _receivedPayments = 0;
  List<Map<String, dynamic>> _locationStats = [];

  Timer? _dashboardAutoRefreshTimer;
  int _expectedRevenue = 0;
  int _receivedRevenue = 0;
  String _dashboardSelectedLocation = 'all';
  List<Map<String, dynamic>> _monthlyRevenue = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  // متغيرات البحث والتصفية لسجل الدفعات
  final TextEditingController _paymentSearchController = TextEditingController();
  String _selectedPaymentLocation = 'all';
  String _selectedPaymentCourse = 'all';
  Timer? _searchTimer;

  // متغيرات صفحة المتأخرين بالدفع
  final TextEditingController _latePaymentsSearchController = TextEditingController();
  String _latePaymentsSelectedLocation = 'all';
  String _latePaymentsSelectedCourseId = 'all';
  final Map<String, DateTime?> _latePaymentsDueDatesByCourseId = {};
  final Map<String, DateTime?> _latePaymentsDueDatesByClassCourseKey = {};
  final ScrollController _latePaymentsVerticalScrollController = ScrollController();
  final ScrollController _latePaymentsHorizontalScrollController = ScrollController();
  List<Map<String, dynamic>> _latePaymentsRows = [];
  bool _latePaymentsDidInitialLoad = false;

  // متغيرات استلام القسط
  final TextEditingController _studentNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  String _selectedStudentId = '';
  String _selectedClassId = '';
  String _selectedLocation = '';
  String _selectedCourse = '';
  DateTime _paymentDate = DateTime.now();
  List<Map<String, dynamic>> _students = [];
  List<String> _locations = [];
  
  // متغيرات إيصال الاستلام
  bool _showReceipt = false;
  Map<String, dynamic> _lastPayment = {};

  // متغيرات إدارة الكورسات والأسعار
  List<Map<String, dynamic>> _courses = [];
  Map<String, List<Map<String, dynamic>>> _locationCourses = {};
  Map<String, Map<String, dynamic>> _classCourseStatus = {};
  bool _showAddCourseDialog = false;
  final TextEditingController _courseNameController = TextEditingController();
  final TextEditingController _coursePriceController = TextEditingController();
  String _selectedLocationForCourse = '';
  List<Map<String, dynamic>> _classes = [];

  final TextEditingController _installmentsSearchController = TextEditingController();
  String _installmentsSelectedLocation = 'جميع المواقع';
  String _installmentsSelectedClass = 'جميع الفصول';
  String _installmentsSelectedCourseId = 'الكل';
  bool _installmentsIsLoading = false;
  List<Map<String, dynamic>> _installmentsRows = [];
  int _installmentsTotalDue = 0;
  int _installmentsTotalPaid = 0;
  int _installmentsTotalRemaining = 0;

  List<Map<String, dynamic>> _getInstallmentsCourseOptions() {
    final location = _installmentsSelectedLocation;
    final classId = widget.classModel.id.toString();
    final classCourses = _classCourseStatus[classId] ?? {};

    Iterable<Map<String, dynamic>> courses;
    if (location == 'جميع المواقع') {
      courses = _locationCourses.values.expand((list) => list);
    } else {
      courses = (_locationCourses[location] ?? const <Map<String, dynamic>>[]);
    }

    final unique = <String, Map<String, dynamic>>{};
    for (final c in courses) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (classCourses[id]?['enabled'] != true) continue;
      unique[id] = c;
    }

    return unique.values.toList();
  }

  void _ensureInstallmentsSelectedCourseIsValid() {
    if (_installmentsSelectedCourseId == 'الكل') return;
    final availableIds = _getInstallmentsCourseOptions()
        .map((c) => c['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (!availableIds.contains(_installmentsSelectedCourseId)) {
      setState(() {
        _installmentsSelectedCourseId = 'الكل';
      });
    }
  }

  final List<String> _tabTitles = [
    'المعلومات المالية',
    'استلام قسط',
    'إدارة الأقساط',
    'المتأخرين بالدفع',
    'سجل الدفعات',
    'إضافة الأسعار',
  ];

  @override
  void initState() {
    super.initState();
    _loadFinancialData();
    // عند فتح الصفحة لأول مرة: إذا كنت على تبويب المعلومات المالية فعّل التحديث التلقائي
    _startDashboardAutoRefresh();
  }

  @override
  void dispose() {
    _dashboardAutoRefreshTimer?.cancel();
    _paymentSearchController.dispose();
    _latePaymentsSearchController.dispose();
    _latePaymentsVerticalScrollController.dispose();
    _latePaymentsHorizontalScrollController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _startDashboardAutoRefresh() {
    _dashboardAutoRefreshTimer?.cancel();
    _dashboardAutoRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      if (!mounted) return;
      // لا تُحدث إلا إذا كنت على تبويب المعلومات المالية
      if (_selectedTabIndex != 0) return;
      try {
        // أعد تحميل الدفعات/الطلاب لتحديث الأرقام بشكل فعلي
        await _loadFinancialData();
      } catch (_) {
        // تجاهل
      }
    });
  }

  void _stopDashboardAutoRefresh() {
    _dashboardAutoRefreshTimer?.cancel();
    _dashboardAutoRefreshTimer = null;
  }

  Future<void> _loadLatePaymentsDueDates() async {
    final classId = widget.classModel.id?.toString() ?? '';
    if (classId.isEmpty) return;
    // نحمّل تواريخ هذا الفصل (لواجهة اختيار التاريخ) + كل الفصول (لصفحة المتأخرين العامة)
    final map = await _dbHelper.getCourseDueDatesForClass(classId);
    final allMap = await _dbHelper.getAllCourseDueDates();
    if (!mounted) return;
    setState(() {
      _latePaymentsDueDatesByCourseId
        ..clear()
        ..addEntries(
          map.entries.map(
            (e) => MapEntry(
              e.key,
              DateTime.tryParse(e.value),
            ),
          ),
        );

      _latePaymentsDueDatesByClassCourseKey
        ..clear()
        ..addEntries(
          allMap.entries.map(
            (e) => MapEntry(
              e.key,
              DateTime.tryParse(e.value),
            ),
          ),
        );
    });
  }

  Future<void> _recomputeDashboardStats() async {
    if (!mounted) return;

    final location = _dashboardSelectedLocation;
    final isAll = location == 'all';
    final filteredStudents = _students.where((s) {
      final loc = s['location']?.toString() ?? '';
      return isAll || loc == location;
    }).toList();

    final totalStudents = filteredStudents.length;

    // الإيرادات المستلمة من جدول installments
    final receivedRevenue = await _dbHelper.getTotalInstallmentsAmount(
      location: isAll ? null : location,
    );

    // الإيرادات الشهرية (مدفوعات مستلمة) للرسم البياني
    final monthly = await _dbHelper.getMonthlyInstallmentsTotals(
      location: isAll ? null : location,
    );

    // الإيرادات المتوقعة = مجموع الأقساط المستحقة لكل طالب حسب الأسعار المخصصة للفصل
    int expectedRevenue = 0;
    for (final student in filteredStudents) {
      final studentClassId = student['classId']?.toString() ?? '';
      final studentLocation = student['location']?.toString() ?? '';
      if (studentClassId.isEmpty || studentLocation.isEmpty) continue;

      final classCourses = _classCourseStatus[studentClassId] ?? {};
      final locationCourses = _locationCourses[studentLocation] ?? const <Map<String, dynamic>>[];

      for (final course in locationCourses) {
        final courseId = course['id']?.toString() ?? '';
        if (courseId.isEmpty) continue;

        final dynamic classCourseRow = classCourses[courseId];
        final bool hasClassPriceRow = classCourses.containsKey(courseId);
        final bool enabled = hasClassPriceRow
            ? ((classCourseRow is Map) && (classCourseRow['enabled'] == true))
            : true;
        if (!enabled) continue;

        final dynamic amount = hasClassPriceRow
            ? ((classCourseRow is Map) ? classCourseRow['amount'] : null)
            : course['price'];
        final v = (amount is int) ? amount : int.tryParse(amount?.toString() ?? '') ?? 0;
        if (v <= 0) continue;
        expectedRevenue += v;
      }
    }

    // عدد المتأخرين بالدفع: خذه من نفس منطق صفحة المتأخرين لضمان التطابق
    final allCoursesForLate = _courses.isNotEmpty ? _courses : await _dbHelper.getCourses();
    final lateRowsForDashboard = await _computeLatePaymentsRows(
      allCourses: allCoursesForLate,
      location: isAll ? 'all' : location,
      courseId: 'all',
      query: '',
    );
    final lateCount = lateRowsForDashboard.length;

    // جدول الإيرادات حسب الموقع
    final allLocations = _locations.toList()..sort();
    final stats = <Map<String, dynamic>>[];
    for (final loc in allLocations) {
      final studentsCount = _students.where((s) => (s['location']?.toString() ?? '') == loc).length;
      final totalPaid = await _dbHelper.getTotalInstallmentsAmount(location: loc);
      stats.add({
        'location': loc,
        'students': studentsCount,
        'revenue': totalPaid,
      });
    }

    if (!mounted) return;
    setState(() {
      _totalStudents = totalStudents;
      _expectedRevenue = expectedRevenue;
      _receivedRevenue = receivedRevenue;
      _receivedPayments = receivedRevenue; // لعرضه في حاوية الحالة أيضاً
      _firstInstallmentLate = lateCount; // إجمالي المتأخرين (حسب الموقع)
      _secondInstallmentLate = 0;
      _monthlyRevenue = monthly;
      _locationStats = stats;
    });
  }

  Future<void> _pickAndSaveDueDateForCourse({
    required String courseId,
    DateTime? initialDate,
  }) async {
    if (courseId.isEmpty || courseId == 'all') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار كورس أولاً')),
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked == null) return;
    final classId = widget.classModel.id?.toString() ?? '';
    if (classId.isEmpty) return;

    final iso = DateTime(picked.year, picked.month, picked.day).toIso8601String();
    await _dbHelper.upsertCourseDueDate(
      classId: classId,
      courseId: courseId,
      dueDateIso: iso,
    );

    if (!mounted) return;
    setState(() {
      _latePaymentsDueDatesByCourseId[courseId] = DateTime(picked.year, picked.month, picked.day);
    });

    // تحديث الجدول مباشرة بعد حفظ التاريخ
    try {
      final courses = await _dbHelper.getCourses();
      if (!mounted) return;
      await _loadLatePaymentsDueDates();
      await _loadLatePaymentsRows(courses);
    } catch (_) {
      // تجاهل
    }
  }

  List<Map<String, dynamic>> _getLatePaymentsCourseOptionsForLocation(
    List<Map<String, dynamic>> allCourses,
    String location,
  ) {
    // استبعاد بيانات الاختبار القديمة (مثل: كورس أول/كورس ثاني) إذا كان هناك مواقع حقيقية أخرى
    final locationToCourses = <String, List<Map<String, dynamic>>>{};
    for (final c in allCourses) {
      final loc = c['location']?.toString() ?? '';
      if (loc.isEmpty) continue;
      (locationToCourses[loc] ??= []).add(c);
    }

    bool _isSampleLocation(List<Map<String, dynamic>> coursesForLocation) {
      if (coursesForLocation.isEmpty) return true;
      return coursesForLocation.every((c) {
        final name = c['name']?.toString() ?? '';
        return name.startsWith('كورس ') && (name.contains('أول') || name.contains('ثاني'));
      });
    }

    final hasRealLocations = locationToCourses.entries.any((e) => !_isSampleLocation(e.value));
    final allowedLocations = locationToCourses.entries
        .where((e) => !hasRealLocations || !_isSampleLocation(e.value))
        .map((e) => e.key)
        .toSet();

    final locationCourses = allCourses.where((c) {
      final courseLocation = c['location']?.toString() ?? '';
      if (courseLocation.isEmpty) return false;
      if (!allowedLocations.contains(courseLocation)) return false;
      if (location == 'all') return true;
      return courseLocation == location;
    }).toList();

    final unique = <String, Map<String, dynamic>>{};
    for (final c in locationCourses) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      unique[id] = c;
    }

    final list = unique.values.toList();
    list.sort((a, b) {
      final an = a['name']?.toString() ?? '';
      final bn = b['name']?.toString() ?? '';
      return an.compareTo(bn);
    });
    return list;
  }

  Future<void> _loadLatePaymentsRows(List<Map<String, dynamic>> allCourses) async {
    final classId = widget.classModel.id?.toString() ?? '';
    if (classId.isEmpty) return;

    final query = _latePaymentsSearchController.text.trim().toLowerCase();
    final selectedLocation = _latePaymentsSelectedLocation;
    final selectedCourseId = _latePaymentsSelectedCourseId;

    final rows = await _computeLatePaymentsRows(
      allCourses: allCourses,
      location: selectedLocation,
      courseId: selectedCourseId,
      query: query,
    );

    if (!mounted) return;
    setState(() {
      _latePaymentsRows
        ..clear()
        ..addAll(rows);
    });
  }

  Future<List<Map<String, dynamic>>> _computeLatePaymentsRows({
    required List<Map<String, dynamic>> allCourses,
    required String location,
    required String courseId,
    required String query,
  }) async {
    final now = DateTime.now();

    final filteredStudents = _students.where((s) {
      final name = s['name']?.toString().toLowerCase() ?? '';
      final loc = s['location']?.toString() ?? '';
      final matchesName = query.isEmpty || name.contains(query);
      final matchesLocation = location == 'all' || loc == location;
      return matchesName && matchesLocation;
    }).toList();

    final visibleCourses = _getLatePaymentsCourseOptionsForLocation(allCourses, location);
    final courseById = {
      for (final c in allCourses) (c['id']?.toString() ?? ''): c,
    };

    int rowIndex = 0;
    final rows = <Map<String, dynamic>>[];

    for (final student in filteredStudents) {
      final sid = int.tryParse(student['id']?.toString() ?? '');
      if (sid == null) continue;
      final studentName = student['name']?.toString() ?? '';
      final studentLocation = student['location']?.toString() ?? '';
      final className = student['class_name']?.toString() ?? '';

      final studentClassId = student['classId']?.toString() ?? '';
      final classCourses = _classCourseStatus[studentClassId] ?? {};

      final coursesToCheck = (courseId == 'all')
          ? visibleCourses
          : visibleCourses.where((c) => c['id']?.toString() == courseId).toList();

      final perCourse = <String, Map<String, dynamic>>{};
      int totalDue = 0;
      int totalPaid = 0;
      bool hasAnyLate = false;

      for (final course in coursesToCheck) {
        final cid = course['id']?.toString() ?? '';
        if (cid.isEmpty) continue;

        final bool hasClassPriceRow = classCourses.containsKey(cid);
        final dynamic classCourseRow = classCourses[cid];
        final bool enabled = hasClassPriceRow
            ? ((classCourseRow is Map) && (classCourseRow['enabled'] == true))
            : true;
        if (!enabled) continue;

        final dynamic courseRow = courseById[cid];
        final dynamic fallbackPrice = (courseRow is Map) ? courseRow['price'] : null;
        final dynamic amount = hasClassPriceRow
            ? ((classCourseRow is Map) ? classCourseRow['amount'] : null)
            : fallbackPrice;
        final due = (amount is int) ? amount : int.tryParse(amount?.toString() ?? '') ?? 0;
        if (due <= 0) continue;

        final paid = await _dbHelper.getTotalPaidByStudentAndCourse(
          studentId: sid,
          courseId: cid,
        );
        final remaining = (due - paid).clamp(0, 1 << 30);

        totalDue += due;
        totalPaid += paid;

        final dueKey = '${studentClassId}|$cid';
        DateTime? dueDate = _latePaymentsDueDatesByClassCourseKey[dueKey];
        if (dueDate == null) {
          for (final entry in _latePaymentsDueDatesByClassCourseKey.entries) {
            if (entry.key.endsWith('|$cid')) {
              dueDate = entry.value;
              break;
            }
          }
        }
        final daysLate = (dueDate == null)
            ? null
            : now.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;

        final isLate = dueDate != null && daysLate != null && daysLate > 0 && remaining > 0;
        if (isLate) hasAnyLate = true;

        perCourse[cid] = {
          'courseName': courseById[cid]?['name']?.toString() ?? course['name']?.toString() ?? '',
          'due': due,
          'paid': paid,
          'remaining': remaining,
          'dueDate': dueDate,
          'daysLate': daysLate,
          'isLate': isLate,
        };
      }

      if (!hasAnyLate) continue;

      rowIndex++;
      rows.add({
        'index': rowIndex,
        'studentId': sid,
        'studentName': studentName,
        'className': className,
        'location': studentLocation,
        'totalDue': totalDue,
        'totalPaid': totalPaid,
        'totalRemaining': (totalDue - totalPaid).clamp(0, 1 << 30),
        'perCourse': perCourse,
      });
    }

    return rows;
  }

  Future<void> _loadInstallmentsManagementData() async {
    if (_installmentsIsLoading) return;
    setState(() {
      _installmentsIsLoading = true;
    });

    try {
      final classId = widget.classModel.id?.toString() ?? '';

      final allStudents = List<Map<String, dynamic>>.from(_students);
      final query = _installmentsSearchController.text.trim().toLowerCase();
      final locationFilter = _installmentsSelectedLocation;
      final classFilter = _installmentsSelectedClass;

      final filteredStudents = allStudents.where((s) {
        final name = s['name']?.toString().toLowerCase() ?? '';
        final location = s['location']?.toString() ?? '';
        final className = s['class_name']?.toString() ?? '';
        final matchesName = query.isEmpty || name.contains(query);
        final matchesLocation = locationFilter == 'جميع المواقع' || location == locationFilter;
        final matchesClass = classFilter == 'جميع الفصول' || className == classFilter;
        return matchesName && matchesLocation && matchesClass;
      }).toList();

      _ensureInstallmentsSelectedCourseIsValid();
      final selectedCourseId = _installmentsSelectedCourseId;

      final studentIds = filteredStudents
          .map((s) => int.tryParse(s['id']?.toString() ?? ''))
          .whereType<int>()
          .toList();

      final Map<int, int> paidByStudent = (selectedCourseId == 'الكل')
          ? await _dbHelper.getTotalPaidByStudentIds(studentIds)
          : await _dbHelper.getTotalPaidByStudentIdsForCourse(
              studentIds: studentIds,
              courseId: selectedCourseId,
            );

      int totalDue = 0;
      int totalPaid = 0;
      int totalRemaining = 0;
      final rows = <Map<String, dynamic>>[];

      for (int i = 0; i < filteredStudents.length; i++) {
        final student = filteredStudents[i];
        final sid = int.tryParse(student['id']?.toString() ?? '');
        if (sid == null) continue;
        final name = student['name']?.toString() ?? '';
        final location = student['location']?.toString() ?? '';
        final className = student['class_name']?.toString() ?? '';

        final studentClassId = student['classId']?.toString() ?? '';
        final classCourses = _classCourseStatus[studentClassId] ?? {};

        final locationCourses = _locationCourses[location] ?? [];
        int due = 0;
        if (selectedCourseId == 'الكل') {
          for (final course in locationCourses) {
            final courseId = course['id']?.toString() ?? '';
            if (courseId.isEmpty) continue;
            if (classCourses[courseId]?['enabled'] != true) continue;
            final amount = classCourses[courseId]?['amount'];
            final amountInt = (amount is int)
                ? amount
                : int.tryParse(amount?.toString() ?? '') ?? 0;
            due += amountInt;
          }
        } else {
          final isCourseInLocation = locationCourses
              .any((c) => c['id']?.toString() == selectedCourseId);
          final isEnabled = classCourses[selectedCourseId]?['enabled'] == true;
          if (isCourseInLocation && isEnabled) {
            final amount = classCourses[selectedCourseId]?['amount'];
            due = (amount is int)
                ? amount
                : int.tryParse(amount?.toString() ?? '') ?? 0;
          }
        }

        final paid = paidByStudent[sid] ?? 0;
        final remaining = (due - paid).clamp(0, 1 << 30);

        totalDue += due;
        totalPaid += paid;
        totalRemaining += remaining;

        rows.add({
          'index': i + 1,
          'studentId': sid,
          'studentName': name,
          'className': className,
          'location': location,
          'due': due,
          'paid': paid,
          'remaining': remaining,
        });
      }

      if (!mounted) return;
      setState(() {
        _installmentsRows = rows;
        _installmentsTotalDue = totalDue;
        _installmentsTotalPaid = totalPaid;
        _installmentsTotalRemaining = totalRemaining;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _installmentsIsLoading = false;
        });
      }
    }
  }

  Future<void> _exportInstallmentsManagementPdf() async {
    final doc = pw.Document();

    final arabicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    final arabicBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );

    final totalDue = _installmentsTotalDue;
    final totalPaid = _installmentsTotalPaid;
    final totalRemaining = _installmentsTotalRemaining;

    final selectedCourseId = _installmentsSelectedCourseId;
    final String courseTitle = (selectedCourseId == 'الكل')
        ? 'الكل'
        : (() {
            try {
              final c = _courses.firstWhere(
                (e) => e['id']?.toString() == selectedCourseId,
              );
              return c['name']?.toString() ?? selectedCourseId;
            } catch (_) {
              return selectedCourseId;
            }
          })();

    final String locationTitle = _installmentsSelectedLocation;

    doc.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
        ),
        pageFormat: pdf.PdfPageFormat.a4,
        build: (context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'البيانات المالية - $courseTitle',
                  style: pw.TextStyle(
                    font: arabicBold,
                    fontSize: 18,
                    color: PdfColor.fromInt(0xFF000000),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'الموقع: $locationTitle',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontSize: 11,
                    color: PdfColor.fromInt(0xFF555555),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColor.fromInt(0xFFCCCCCC),
                            width: 1,
                          ),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('القسط الكلي', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                            pw.SizedBox(height: 4),
                            pw.Text('${_formatAmount(totalDue.toDouble())} د.ع'),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColor.fromInt(0xFFCCCCCC),
                            width: 1,
                          ),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('إجمالي المدفوعات', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                            pw.SizedBox(height: 4),
                            pw.Text('${_formatAmount(totalPaid.toDouble())} د.ع'),
                          ],
                        ),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(
                            color: PdfColor.fromInt(0xFFCCCCCC),
                            width: 1,
                          ),
                          borderRadius: pw.BorderRadius.circular(8),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('المبلغ المتبقي', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                            pw.SizedBox(height: 4),
                            pw.Text('${_formatAmount(totalRemaining.toDouble())} د.ع'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 1),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1),
                    1: const pw.FlexColumnWidth(3),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(2),
                    4: const pw.FlexColumnWidth(2),
                    5: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('ت', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('اسم الطالب', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('الموقع', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('القسط الكلي', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('إجمالي المدفوعات', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('المبلغ المتبقي', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                      ],
                    ),
                    ..._installmentsRows.map((r) {
                      final due = r['due'] ?? 0;
                      final paid = r['paid'] ?? 0;
                      final remaining = r['remaining'] ?? 0;
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(r['index']?.toString() ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(r['studentName']?.toString() ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(r['location']?.toString() ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('${_formatAmount((due is num ? due.toDouble() : (num.tryParse(due.toString()) ?? 0).toDouble()))} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('${_formatAmount((paid is num ? paid.toDouble() : (num.tryParse(paid.toString()) ?? 0).toDouble()))} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('${_formatAmount((remaining is num ? remaining.toDouble() : (num.tryParse(remaining.toString()) ?? 0).toDouble()))} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    try {
      final bytes = await doc.save();
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final safeCourseTitle = courseTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .replaceAll(' ', '_');
      final filename = 'البيانات_المالية_${dateStr}_$safeCourseTitle.pdf';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      final uri = Uri.file(file.path);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw Exception('تعذر فتح الملف');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء الملف وفتحه: $filename'),
          backgroundColor: const Color(0xFFFEC619),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تصدير الملف: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _loadFinancialData() async {
    try {
      // جلب بيانات الطلاب
      final students = await _dbHelper.getAllStudents();
      
      // جلب بيانات الفصول الحقيقية
      final classesData = await _dbHelper.getAllClasses();
      final classes = classesData.map((class_) => {
        'id': class_.id?.toString() ?? '',
        'name': class_.name,
        'location': class_.subject, // استخدام subject كموقع مؤقت
      }).toList();
      
      // جلب المواقع الفريدة من الفصول الحقيقية
      final locations = classes.map((class_) => class_['location'] as String).toSet().toList();

      // تجهيز القيم قبل تحميل الأسعار (لمنع تحميل أسعار بدون مواقع/فصول)
      _classes = classes;
      _locations = locations;

      // تحميل بيانات الكورسات والأسعار
      await _loadCoursePricingData();
      
      if (mounted) {
        setState(() {
          _students = students.map((s) => {
            'id': s.id?.toString() ?? '',
            'name': s.name,
            'classId': s.classId?.toString() ?? '',
            'class_name': classes.firstWhere((c) => c['id'] == s.classId?.toString(), orElse: () => {'name': ''})['name'],
            'location': s.location ?? classes.firstWhere((c) => c['id'] == s.classId?.toString(), orElse: () => {'location': ''})['location'],
          }).toList();
          _classes = classes;
          _locations = locations;
          _isLoading = false;
        });

        // بعد تحميل الطلاب/الأسعار: حمّل تواريخ الاستحقاق ثم احسب بيانات الداشبورد الحقيقية
        await _loadLatePaymentsDueDates();
        await _recomputeDashboardStats();
      }
    } catch (e) {
      print('Error loading financial data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // دالة البحث عن الطلاب وتحديث المعلومات تلقائياً
  void _onStudentNameChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _selectedStudentId = '';
        _selectedClassId = '';
        _selectedLocation = '';
      });
      return;
    }

    // البحث عن طالب مطابق للاسم
    final matchingStudents = _students.where((student) => 
      student['name'].toString().toLowerCase().contains(value.toLowerCase())
    ).toList();

    if (matchingStudents.isNotEmpty) {
      final student = matchingStudents.first;
      setState(() {
        _selectedStudentId = student['id'].toString();
        _selectedClassId = student['classId']?.toString() ?? '';
        _selectedLocation = student['location']?.toString() ?? '';
        // تحديث الكورسات المتاحة بناءً على الموقع الجديد
        _updateAvailableCourses();
      });
    }
  }

  // تحديث الكورسات المتاحة
  void _updateAvailableCourses() {
    setState(() {
      _selectedCourse = '';
      _amountController.clear();
    });
  }

  void _ensureSelectedCourseIsValid() {
    if (_selectedCourse.isEmpty) return;
    final availableIds = _getAvailableCourses()
        .map((c) => c['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    if (!availableIds.contains(_selectedCourse)) {
      setState(() {
        _selectedCourse = '';
        _amountController.clear();
      });
    }
  }

  Future<void> _confirmDeleteCourse(Map<String, dynamic> course) async {
    final courseId = course['id']?.toString() ?? '';
    if (courseId.isEmpty) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'حذف الكورس',
          style: TextStyle(color: Color(0xFFFEC619)),
        ),
        content: Text(
          'هل تريد حذف هذا الكورس نهائياً؟',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _dbHelper.deleteCourse(courseId);
      await _loadCoursePricingData();

      if (mounted) {
        setState(() {
          if (_selectedCourse == courseId) {
            _selectedCourse = '';
            _amountController.clear();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الكورس بنجاح')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الحذف: ${e.toString()}')),
        );
      }
    }
  }

  // إضافة كورسات تجريبية للاختبار
  Future<void> _addSampleCourses() async {
    try {
      final sampleCourses = [
        {'id': '1', 'name': 'كورس أول', 'price': 5000, 'location': 'منصور'},
        {'id': '2', 'name': 'كورس ثاني', 'price': 6000, 'location': 'منصور'},
        {'id': '3', 'name': 'كورس أول', 'price': 5500, 'location': 'الرياض'},
        {'id': '4', 'name': 'كورس ثاني', 'price': 6500, 'location': 'الرياض'},
      ];

      for (var course in sampleCourses) {
        await _dbHelper.insertCourse(course);
      }

      // إضافة أسعار للفصول
      final classes = await _dbHelper.getAllClasses();
      for (var class_ in classes) {
        final classId = class_.id!;
        final location = class_.subject;
        
        final courses = await _dbHelper.getCoursesByLocation(location);
        for (var course in courses) {
          await _dbHelper.insertClassCoursePrice({
            'class_id': classId,
            'course_id': course['id'],
            'amount': course['price'],
            'enabled': 1,
            'paid': 0,
          });
        }
      }

      // إعادة تحميل البيانات
      await _loadCoursePricingData();
      
      print('✅ تم إضافة الكورسات التجريبية بنجاح');
    } catch (e) {
      print('❌ خطأ في إضافة الكورسات التجريبية: $e');
    }
  }

  Future<void> _loadCoursePricingData() async {
    try {
      // جلب الكورسات من قاعدة البيانات
      final courses = await _dbHelper.getCourses();
      
      // تنظيم الكورسات حسب الموقع
      final locationCourses = <String, List<Map<String, dynamic>>>{};
      for (var location in _locations) {
        locationCourses[location] = courses.where((course) => 
          course['location'] == location
        ).toList();
      }

      // جلب أسعار الكورسات للفصول
      final classCourseStatus = <String, Map<String, dynamic>>{};
      for (var class_ in _classes) {
        final classId = class_['id'].toString();
        classCourseStatus[classId] = {};
        
        // جلب الأسعار لهذا الفصل
        final classPrices = await _dbHelper.getClassCoursePrices(int.parse(classId));
        for (var price in classPrices) {
          final courseId = price['course_id'].toString();
          classCourseStatus[classId]![courseId] = {
            'priceId': price['id'],
            'amount': price['amount'],
            'enabled': price['enabled'] == 1,
            'paid': price['paid'] == 1,
          };
        }
      }

      if (mounted) {
        setState(() {
          _courses = courses;
          _locationCourses = locationCourses;
          _classCourseStatus = classCourseStatus;
        });
      }
    } catch (e) {
      print('Error loading course pricing data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A2A2A), // خلفية رمادية فاتحة
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFEC619)),
              ),
            )
          : Column(
              children: [
                // القائمة العلوية الجديدة
                _buildTopTabBar(),
                // محتوى الصفحة الحالية
                Expanded(
                  child: _buildCurrentTabContent(),
                ),
              ],
            ),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // خلفية سوداء للقائمة العلوية فقط
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFFEC619).withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _tabTitles.length,
        itemBuilder: (context, index) {
          final isSelected = _selectedTabIndex == index;
          return GestureDetector(
            onTap: () {
              if (mounted) {
                setState(() {
                  _selectedTabIndex = index;
                });
              }

              if (index == 0) {
                _startDashboardAutoRefresh();
              } else {
                _stopDashboardAutoRefresh();
              }

              if (index == 2) {
                _loadInstallmentsManagementData();
              }

              // تحميل بيانات المتأخرين تلقائياً عند فتح التبويب
              if (index == 3) {
                _dbHelper.getCourses().then((courses) {
                  if (!mounted) return;
                  _loadLatePaymentsDueDates().then((_) {
                    _loadLatePaymentsRows(courses);
                  });
                });
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? const Color(0xFFFEC619).withOpacity(0.2)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected 
                      ? const Color(0xFFFEC619)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  _tabTitles[index],
                  style: TextStyle(
                    color: isSelected 
                        ? const Color(0xFFFEC619)
                        : Colors.grey.shade400,
                    fontSize: 14,
                    fontWeight: isSelected 
                        ? FontWeight.bold 
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildFinancialDashboard();
      case 1:
        return _buildInstallmentCollection();
      case 2:
        return _buildInstallmentManagement();
      case 3:
        return _buildLatePayments();
      case 4:
        return _buildPaymentHistory();
      case 5:
        return _buildCoursePricing();
      default:
        return _buildFinancialDashboard();
    }
  }

  Widget _buildFinancialDashboard() {
    final locationOptions = ['all', ...(_locations.toList()..sort())];
    final effectiveLocation = locationOptions.contains(_dashboardSelectedLocation)
        ? _dashboardSelectedLocation
        : 'all';
    if (effectiveLocation != _dashboardSelectedLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _dashboardSelectedLocation = effectiveLocation;
        });
        _recomputeDashboardStats();
      });
    }

    return RefreshIndicator(
      onRefresh: _loadFinancialData,
      color: const Color(0xFFFEC619),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: _dashboardSelectedLocation,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: locationOptions
                        .map(
                          (l) => DropdownMenuItem<String>(
                            value: l,
                            child: Text(
                              l == 'all' ? 'كل المواقع' : l,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        _dashboardSelectedLocation = v ?? 'all';
                      });
                      _recomputeDashboardStats();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // بطاقات الإحصائيات
            _buildStatCards(),
            const SizedBox(height: 24),
            
            // قسم التحليلات
            _buildAnalyticsSection(),
            const SizedBox(height: 24),
            
            // جدول الإيرادات حسب الموقع
            _buildRevenueTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallmentCollection() {
    if (_showReceipt) {
      return _buildReceiptView();
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFEC619).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان النموذج
            const Text(
              'تسجيل قسط طالب',
              style: TextStyle(
                color: Color(0xFFFEC619),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            
            // حقل اسم الطالب مع البحث
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اسم الطالب',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _studentNameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'اكتب اسم الطالب...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: (value) {
                      // تحديث الفصل والموقع تلقائياً عند البحث
                      _onStudentNameChanged(value);
                      _filterStudents(value);
                    },
                  ),
                ),
                
                // عرض قائمة الطلاب المطابقة
                if (_studentNameController.text.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFEC619).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: _getFilteredStudents().take(5).map((student) {
                        return ListTile(
                          title: Text(
                            student['name'],
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            'الفصل: ${_getClassName(student['classId'])}',
                            style: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _studentNameController.text = student['name'];
                              _selectedStudentId = student['id'].toString();
                              _selectedClassId = student['classId']?.toString() ?? '';
                              _selectedLocation = student['location']?.toString() ?? '';
                              // تحديث الكورسات المتاحة
                              _updateAvailableCourses();
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل اختيار الفصل
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الفصل',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedClassId.isNotEmpty && _classes.any((c) => c['id']?.toString() == _selectedClassId) 
                        ? _selectedClassId 
                        : null,
                    hint: Text(
                      'اختر الفصل',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: (() {
                      final uniqueById = <String, Map<String, dynamic>>{};
                      for (final c in _classes) {
                        final id = c['id']?.toString() ?? '';
                        if (id.isEmpty) continue;
                        uniqueById[id] = c;
                      }

                      return uniqueById.values.map((class_) {
                        final classId = class_['id']?.toString() ?? '';
                        return DropdownMenuItem<String>(
                          value: classId,
                          child: Text(class_['name']?.toString() ?? ''),
                        );
                      }).toList();
                    })(),
                    onChanged: (value) {
                      setState(() {
                        _selectedClassId = value ?? '';

                        // عند اختيار فصل يدوياً نُحدث الموقع وفقاً للفصل، بدون لمس حقل اسم الطالب
                        try {
                          final selectedClass = _classes.firstWhere(
                            (c) => c['id']?.toString() == value,
                          );
                          _selectedLocation = selectedClass['location']?.toString() ?? '';
                        } catch (e) {
                          _selectedLocation = '';
                        }

                        // إعادة تعيين الكورس والمبلغ
                        _selectedCourse = '';
                        _amountController.clear();
                      });
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل الموقع
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الموقع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedLocation.isNotEmpty ? _selectedLocation : null,
                    hint: Text(
                      'اختر الموقع',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: _locations.map((location) {
                      return DropdownMenuItem<String>(
                        value: location,
                        child: Text(location),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedLocation = value ?? '';
                        // عند تغيير الموقع يدوياً نعيد تحميل الكورسات المتاحة
                        _updateAvailableCourses();
                      });
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل اختيار القسط
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر القسط',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: DropdownButton<String>(
                    value: (_selectedCourse.isNotEmpty &&
                            _getAvailableCourses().any((c) =>
                                c['id']?.toString() == _selectedCourse))
                        ? _selectedCourse
                        : null,
                    hint: Text(
                      'اختر القسط',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: _getAvailableCourses().map((course) {
                      final courseId = course['id']?.toString() ?? '';
                      return DropdownMenuItem<String>(
                        value: courseId,
                        child: Text(course['name']?.toString() ?? ''),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedCourse = value ?? '';
                      });
                      // تحديث المبلغ تلقائياً بناءً على الفصل والكورس المختار
                      _updateAmountForSelectedCourse();
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل المبلغ المستحق
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'المبلغ المستحق للكورس ${_getSelectedCourseName()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _amountController,
                    readOnly: true,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorInputFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: '0 د.ع',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل المبلغ المدفوع
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'المبلغ المدفوع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade600,
                      width: 1,
                    ),
                  ),
                  child: TextField(
                    controller: _paidAmountController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      ThousandsSeparatorInputFormatter(),
                    ],
                    decoration: InputDecoration(
                      hintText: '0 د.ع',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل تاريخ الدفع
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تاريخ الدفع',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _selectDate(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.shade600,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_paymentDate.day}/${_paymentDate.month}/${_paymentDate.year}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Icon(
                          Icons.calendar_today,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // زر تسجيل الدفع
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _registerPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEC619),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'تسجيل الدفع',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredStudents() {
    if (_studentNameController.text.isEmpty) return [];
    
    return _students.where((student) {
      return student['name'].toString().toLowerCase()
          .contains(_studentNameController.text.toLowerCase());
    }).toList();
  }

  void _filterStudents(String value) {
    setState(() {
      // تحديث قائمة الطلاب المطابقة
    });
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2025),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFFEC619),
              surface: Color(0xFF2A2A2A),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != _paymentDate) {
      setState(() {
        _paymentDate = picked;
      });
    }
  }

  String _formatAmount(double amount) {
    if (amount == 0) return '0';
    
    final String amountStr = amount.toStringAsFixed(0);
    final int amountInt = int.parse(amountStr);
    
    return amountInt.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  Future<void> _registerPayment() async {
    // التحقق من الحقول
    if (_selectedStudentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار الطالب'),
          backgroundColor: Color(0xFFFEC619),
        ),
      );
      return;
    }

    if (_selectedCourse.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار القسط/الكورس'),
          backgroundColor: Color(0xFFFEC619),
        ),
      );
      return;
    }

    if (_amountController.text.isEmpty || _paidAmountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء إدخال المبلغ المستحق والمبلغ المدفوع'),
          backgroundColor: Color(0xFFFEC619),
        ),
      );
      return;
    }

    try {
      // تنظيف النصوص من الفواصل والرموز
      final dueAmountText = _amountController.text.replaceAll(',', '').replaceAll('د.ع', '').trim();
      final paidAmountText = _paidAmountController.text.replaceAll(',', '').replaceAll('د.ع', '').trim();
      
      final dueAmount = double.parse(dueAmountText);
      final paidAmount = double.parse(paidAmountText);

      int dueIntForReceipt = dueAmount.toInt();

      if (paidAmount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('المبلغ المدفوع يجب أن يكون أكبر من صفر'),
            backgroundColor: Color(0xFFFEC619),
          ),
        );
        return;
      }

      double remainingAmount = dueAmount - paidAmount;

      // حفظ الدفعة في قاعدة البيانات
      final parsedStudentId = int.tryParse(_selectedStudentId);
      if (parsedStudentId != null && _selectedCourse.isNotEmpty) {
        final classCourses = _classCourseStatus[_selectedClassId] ?? {};
        final due = classCourses[_selectedCourse]?['amount'];
        final dueInt = (due is int) ? due : int.tryParse(due?.toString() ?? '') ?? dueAmount.toInt();

        final totalPaidBefore = await _dbHelper.getTotalPaidByStudentAndCourse(
          studentId: parsedStudentId,
          courseId: _selectedCourse,
        );

        final remainingBefore = (dueInt - totalPaidBefore).clamp(0, 1 << 30);

        // في الإيصال: "المبلغ المستحق" = المتبقي وقت تسجيل الدفعة
        dueIntForReceipt = remainingBefore;

        if (dueInt <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد مبلغ مستحق لهذا الكورس'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (remainingBefore <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الطالب مسدد لأقساط هذا الكورس بالكامل ولا يمكن إضافة دفعة جديدة'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (paidAmount.toInt() > remainingBefore) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('المبلغ المدفوع أكبر من المتبقي. المتبقي: ${_formatIqd(remainingBefore)}'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        await _dbHelper.insertInstallment({
          'student_id': parsedStudentId,
          'course_id': _selectedCourse,
          'amount': paidAmount.toInt(),
          'date': _paymentDate.toString().split(' ')[0],
          'notes': null,
        });

        // تحديث فوري للواجهة والإحصائيات بعد إضافة دفعة جديدة
        await _loadFinancialData();

        final totalPaid = await _dbHelper.getTotalPaidByStudentAndCourse(
          studentId: parsedStudentId,
          courseId: _selectedCourse,
        );
        remainingAmount = (dueInt - totalPaid).clamp(0, 1 << 30).toDouble();
      }

      // التحقق من وجود الطالب في القائمة
      final studentIndex = _students.indexWhere((s) => s['id'] == _selectedStudentId);
      if (studentIndex == -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('الطالب المحدد غير موجود'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      if (mounted) {
        setState(() {
          _lastPayment = {
            'studentId': _selectedStudentId,
            'studentName': _students[studentIndex]['name'],
            'className': widget.classModel.name,
            'location': _selectedLocation,
            'courseId': _selectedCourse,
            'courseName': _getSelectedCourseName(),
            'dueAmount': _formatAmount(dueIntForReceipt.toDouble()),
            'paidAmount': _formatAmount(paidAmount),
            'remainingAmount': _formatAmount(remainingAmount),
            'date': _paymentDate.toString().split(' ')[0],
          };
          _showReceipt = true;
        });
      }

      // تحديث الإحصائيات
      if (mounted) {
        setState(() {
          _receivedPayments++;
          final availableCourses = _getAvailableCourses();
          final firstCourseId = availableCourses.isNotEmpty
              ? availableCourses.first['id']?.toString()
              : null;
          if (firstCourseId != null && _selectedCourse == firstCourseId) {
            _firstInstallmentLate = (_firstInstallmentLate - 1).clamp(0, _totalStudents);
          } else {
            _secondInstallmentLate = (_secondInstallmentLate - 1).clamp(0, _totalStudents);
          }
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل الدفع بنجاح'),
          backgroundColor: Color(0xFFFEC619),
        ),
      );
    } catch (e) {
      print('Error in _registerPayment: $e'); // للتصحيح
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ في تسجيل الدفع: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _updateStatistics() {
    setState(() {
      _receivedPayments++;
      // تحديث الإحصائيات الأخرى حسب الحاجة
    });
  }

  Widget _buildReceiptView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFFEC619).withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // عنوان الإيصال
            const Text(
              'إيصال الاستلام',
              style: TextStyle(
                color: Color(0xFFFEC619),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            
            // معلومات الطالب
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text(
                    'اسم الطالب:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastPayment['studentName'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFFFEC619),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    'ID: ${_lastPayment['studentId'] ?? ''}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // معلومات الفصل والموقع
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Text(
                    'اسم الفصل: ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastPayment['className'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFFFEC619),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    'الموقع: ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastPayment['location'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFFFEC619),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // معلومات الدفع
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  // الكورس المدفوع
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _lastPayment['courseName'] ?? '',
                      style: const TextStyle(
                        color: Color(0xFFFEC619),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  
                  // المبلغ المستحق
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        children: [
                          const Text(
                            'المبلغ المستحق',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatIqd(_lastPayment['dueAmount']),
                            style: const TextStyle(
                              color: Color(0xFFFEC619),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // المبلغ المدفوع في الوسط
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Column(
                        children: [
                          const Text(
                            'المبلغ المدفوع',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            _formatIqd(_lastPayment['paidAmount']),
                            style: const TextStyle(
                              color: Color(0xFFFEC619),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // التاريخ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      children: [
                        const Text(
                          'تاريخ الدفع',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _lastPayment['date'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // عنوان المبلغ المتبقي
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'المبلغ المتبقي',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFEC619),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _buildRemainingByCourseItems(),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'لا توجد كورسات مفعّلة لهذا الفصل/الموقع',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: items.map((item) {
                    return SizedBox(
                      width: 220,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              item['courseName']?.toString() ?? '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFFEC619),
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatIqd(item['remaining']),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            
            const SizedBox(height: 16),
            
            // الإجمالي المتبقي
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text(
                    'اجمالي المتبقي',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFEC619),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _buildRemainingByCourseItems(),
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? [];
                      final totalRemaining = items.fold<int>(
                        0,
                        (sum, item) => sum + (item['remaining'] as int? ?? 0),
                      );
                      return Text(
                        _formatIqd(totalRemaining),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFFEC619),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // الأزرار
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _exportReceipt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFEC619),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'إصدار ملف',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _closeReceipt,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'إغلاق',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _closeReceipt() {
    setState(() {
      _showReceipt = false;
      _clearForm();
    });
  }

  Future<void> _exportReceipt() async {
    final doc = pw.Document();

    final remainingItems = await _buildRemainingByCourseItems();

    // استخدام خط NotoSansArabic مع font fallback للإنجليزية
    final arabicFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
    );
    
    final arabicBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
    );

    doc.addPage(
      pw.Page(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
        ),
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              // عنوان الإيصال
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColor.fromInt(0xFFFEC619), width: 2),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'إيصال استلام قسط',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),

              // ملخص المبالغ المتبقية حسب الكورسات (ديناميكي)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF000000),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'المبالغ المتبقية حسب الكورسات',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    if (remainingItems.isEmpty)
                      pw.Text(
                        'لا توجد كورسات مفعّلة لهذا الفصل/الموقع',
                        style: pw.TextStyle(
                          font: arabicFont,
                          fontFallback: [pw.Font.helvetica()],
                          fontSize: 12,
                          color: PdfColor.fromInt(0xFFCCCCCC),
                        ),
                      )
                    else
                      pw.Table(
                        border: pw.TableBorder.all(
                          color: PdfColor.fromInt(0xFFFEC619),
                          width: 1,
                        ),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2),
                          1: const pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromInt(0xFF333333),
                            ),
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'الكورس',
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    font: arabicBold,
                                    fontFallback: [pw.Font.helvetica()],
                                    fontSize: 12,
                                    color: PdfColor.fromInt(0xFFFEC619),
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(
                                  'المتبقي',
                                  textAlign: pw.TextAlign.center,
                                  style: pw.TextStyle(
                                    font: arabicBold,
                                    fontFallback: [pw.Font.helvetica()],
                                    fontSize: 12,
                                    color: PdfColor.fromInt(0xFFFEC619),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...remainingItems.map((item) {
                            final remaining = item['remaining'] ?? 0;
                            final remainingFormatted = _formatAmount(
                              (remaining is num)
                                  ? remaining.toDouble()
                                  : (num.tryParse(remaining.toString()) ?? 0).toDouble(),
                            );
                            return pw.TableRow(
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    item['courseName']?.toString() ?? '',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      font: arabicFont,
                                      fontFallback: [pw.Font.helvetica()],
                                      fontSize: 12,
                                      color: PdfColor.fromInt(0xFFFFFFFF),
                                    ),
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text(
                                    '$remainingFormatted د.ع',
                                    textAlign: pw.TextAlign.center,
                                    style: pw.TextStyle(
                                      font: arabicFont,
                                      fontFallback: [pw.Font.helvetica()],
                                      fontSize: 12,
                                      color: PdfColor.fromInt(0xFFFEC619),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ],
                      ),
                  ],
                ),
              ),
              
              // معلومات الطالب
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF2A2A2A),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'اسم الطالب: ${_lastPayment['studentName'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'رقم الطالب: ${_lastPayment['studentId'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 14,
                        color: PdfColor.fromInt(0xFFCCCCCC),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'اسم الفصل: ${_lastPayment['className'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 14,
                        color: PdfColor.fromInt(0xFFCCCCCC),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الموقع: ${_lastPayment['location'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 14,
                        color: PdfColor.fromInt(0xFFCCCCCC),
                      ),
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // جدول القسط الأول
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF000000),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'القسط الأول',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFFEC619), width: 1),
                      columnWidths: {
                        0: pw.FlexColumnWidth(1),
                        1: pw.FlexColumnWidth(1),
                        2: pw.FlexColumnWidth(1),
                        3: pw.FlexColumnWidth(1),
                      },
                      children: [
                        // العناوين
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF333333)),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المبلغ المدفوع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المبلغ المستحق',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المتبقي',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'تاريخ الدفع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // البيانات
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '${_lastPayment['paidAmount'] ?? '0'} د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '${_lastPayment['dueAmount'] ?? '0'} د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '${_lastPayment['remainingAmount'] ?? '0'} د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '${_lastPayment['date'] ?? ''}',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // جدول القسط الثاني
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFF000000),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'القسط الثاني',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFFEC619), width: 1),
                      columnWidths: {
                        0: pw.FlexColumnWidth(1),
                        1: pw.FlexColumnWidth(1),
                        2: pw.FlexColumnWidth(1),
                        3: pw.FlexColumnWidth(1),
                      },
                      children: [
                        // العناوين
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF333333)),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المبلغ المدفوع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المبلغ المستحق',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المتبقي',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'تاريخ الدفع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicBold,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // بيانات فارغة للقسط الثاني
                        pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '0 د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '0 د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '0 د.ع',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(
                                '---',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(
                                  font: arabicFont,
                                  fontFallback: [pw.Font.helvetica()],
                                  fontSize: 12,
                                  color: PdfColor.fromInt(0xFFFFFFFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final now = DateTime.now();
    final studentName = _lastPayment['studentName']?.toString().replaceAll(' ', '_') ?? 'Unknown';
    final fileName = 'ايصال_${studentName}_${now.day}-${now.month}-${now.year}.pdf';

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: fileName,
    );
  }

  pw.Widget _buildInfoSection(String title, List<String> items) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF9F9F9),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE0E0E0)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFFFEC619),
            ),
          ),
          pw.SizedBox(height: 10),
          ...items.map((item) => pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Text(
              item,
              style: pw.TextStyle(fontSize: 12),
            ),
          )).toList(),
        ],
      ),
    );
  }

  pw.Widget _buildPaymentSection() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF0F8FF),
        border: pw.Border.all(color: PdfColor.fromInt(0xFF4169E1)),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PAYMENT DETAILS',
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF4169E1),
            ),
          ),
          pw.SizedBox(height: 15),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Due Amount:', style: pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFF666666))),
                    pw.Text(
                      '${_lastPayment['dueAmount'] ?? ''} IQD',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF333333),
                      ),
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Paid Amount:', style: pw.TextStyle(fontSize: 12, color: PdfColor.fromInt(0xFF666666))),
                    pw.Text(
                      '${_lastPayment['paidAmount'] ?? ''} IQD',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF28A745),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSummarySection() {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFEC619),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            'REMAINING AMOUNT',
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '${_lastPayment['remainingAmount'] ?? ''} IQD',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _clearForm() {
    setState(() {
      _studentNameController.clear();
      _amountController.clear();
      _paidAmountController.clear();
      _selectedStudentId = '';
      _selectedLocation = widget.classModel.subject;
      _selectedCourse = '';
      _paymentDate = DateTime.now();
    });
  }

  Widget _buildInstallmentManagement() {
    final locations = <String>{'جميع المواقع', ..._locations}.toList();
    final classes = <String>{'جميع الفصول', ..._classes.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty)}.toList();
    final courseOptions = _getInstallmentsCourseOptions();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص الرسوم الدراسية',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: _installmentsRows.isEmpty ? null : _exportInstallmentsManagementPdf,
              icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF1A1A1A)),
              label: const Text(
                'تصدير PDF',
                style: TextStyle(color: Color(0xFF1A1A1A), fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFEC619),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFEC619).withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _installmentsSearchController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم الطالب',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        value: locations.contains(_installmentsSelectedLocation)
                            ? _installmentsSelectedLocation
                            : 'جميع المواقع',
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: locations
                            .map(
                              (l) => DropdownMenuItem<String>(
                                value: l,
                                child: Text(l, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _installmentsSelectedLocation = v ?? 'جميع المواقع';
                            _ensureInstallmentsSelectedCourseIsValid();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<String>(
                        value: classes.contains(_installmentsSelectedClass)
                            ? _installmentsSelectedClass
                            : 'جميع الفصول',
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: classes
                            .map(
                              (c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _installmentsSelectedClass = v ?? 'جميع الفصول';
                            _ensureInstallmentsSelectedCourseIsValid();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _loadInstallmentsManagementData,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEC619),
                        foregroundColor: const Color(0xFF1A1A1A),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('بحث'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _installmentsSearchController.clear();
                          _installmentsSelectedLocation = 'جميع المواقع';
                          _installmentsSelectedClass = 'جميع الفصول';
                          _installmentsSelectedCourseId = 'الكل';
                        });
                        _loadInstallmentsManagementData();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFEC619),
                        side: const BorderSide(color: Color(0xFFFEC619)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('إعادة'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'المبلغ المتبقي',
                  value: _formatIqd(_installmentsTotalRemaining),
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'إجمالي المدفوعات',
                  value: _formatIqd(_installmentsTotalPaid),
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: 'القسط الكلي',
                  value: _formatIqd(_installmentsTotalDue),
                  icon: Icons.receipt_long_outlined,
                  color: const Color(0xFFFEC619),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFEC619).withOpacity(0.25),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'جدول البيانات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: (_installmentsSelectedCourseId == 'الكل' ||
                                courseOptions.any((c) =>
                                    c['id']?.toString() ==
                                    _installmentsSelectedCourseId))
                            ? _installmentsSelectedCourseId
                            : 'الكل',
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: 'الكل',
                            child: Text('الكل'),
                          ),
                          ...courseOptions.map((c) {
                            final id = c['id']?.toString() ?? '';
                            final name = c['name']?.toString() ?? '';
                            return DropdownMenuItem<String>(
                              value: id,
                              child: Text(name, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _installmentsSelectedCourseId = v ?? 'الكل';
                          });
                          _loadInstallmentsManagementData();
                        },
                      ),
                    ),
                    if (_installmentsIsLoading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFEC619)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      const Color(0xFF2A2A2A),
                    ),
                    dataRowColor: WidgetStateProperty.all(
                      const Color(0xFF1A1A1A),
                    ),
                    columns: const [
                      DataColumn(label: Text('ت', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('اسم الطالب', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('الفصل', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('الموقع', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('القسط الكلي', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('إجمالي المدفوعات', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('المبلغ المتبقي', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                    ],
                    rows: _installmentsRows.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(Text(r['index']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(r['studentName']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(r['className']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(r['location']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(_formatIqd(r['due']), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(_formatIqd(r['paid']), style: const TextStyle(color: Colors.white))),
                          DataCell(Text(_formatIqd(r['remaining']), style: const TextStyle(color: Colors.white))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLatePayments() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dbHelper.getCourses(),
      builder: (context, snapshot) {
        final courses = snapshot.data ?? const <Map<String, dynamic>>[];
        final classId = widget.classModel.id?.toString() ?? '';

        // تحميل أولي تلقائي لملء الجدول (ولتظهر تواريخ الاستحقاق بعد إعادة التشغيل)
        if (!_latePaymentsDidInitialLoad && snapshot.connectionState == ConnectionState.done) {
          _latePaymentsDidInitialLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadLatePaymentsDueDates().then((_) {
              _loadLatePaymentsRows(courses);
            });
          });
        }

        // المواقع الحقيقية = تقاطع (مواقع الطلاب) مع (مواقع الكورسات المفعّلة لهذا الفصل)
        final studentLocations = _students
            .map((s) => s['location']?.toString() ?? '')
            .where((l) => l.isNotEmpty)
            .toSet();

        final classCourses = _classCourseStatus[classId] ?? {};
        final enabledCourseLocations = courses
            .where((c) {
              final id = c['id']?.toString() ?? '';
              if (id.isEmpty) return false;
              return classCourses.isEmpty || classCourses[id]?['enabled'] == true;
            })
            .map((c) => c['location']?.toString() ?? '')
            .where((l) => l.isNotEmpty)
            .toSet();

        final locations = enabledCourseLocations
            .where((l) => studentLocations.isEmpty ? true : studentLocations.contains(l))
            .toList()
          ..sort();

        final locationOptions = ['all', ...locations];
        final effectiveSelectedLocation = locationOptions.contains(_latePaymentsSelectedLocation)
            ? _latePaymentsSelectedLocation
            : 'all';
        if (effectiveSelectedLocation != _latePaymentsSelectedLocation) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _latePaymentsSelectedLocation = effectiveSelectedLocation;
              _latePaymentsSelectedCourseId = 'all';
            });
          });
        }

        final courseOptions = _getLatePaymentsCourseOptionsForLocation(
          courses,
          effectiveSelectedLocation,
        );
        final availableCourseIds = courseOptions.map((c) => c['id']?.toString() ?? '').toSet();
        final effectiveSelectedCourseId = (_latePaymentsSelectedCourseId == 'all' ||
                availableCourseIds.contains(_latePaymentsSelectedCourseId))
            ? _latePaymentsSelectedCourseId
            : 'all';
        if (effectiveSelectedCourseId != _latePaymentsSelectedCourseId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _latePaymentsSelectedCourseId = effectiveSelectedCourseId;
            });
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // أدوات التحكم والبحث
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFEC619).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'تصدير PDF',
                          onPressed: () => _exportLatePaymentsPdf(_latePaymentsRows),
                          icon: const Icon(Icons.picture_as_pdf, color: Color(0xFFFEC619)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _latePaymentsSearchController,
                            decoration: InputDecoration(
                              hintText: 'بحث داخل البيانات',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                              filled: true,
                              fillColor: const Color(0xFF2A2A2A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey.shade600),
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                            onChanged: (_) {
                              _searchTimer?.cancel();
                              _searchTimer = Timer(const Duration(milliseconds: 350), () {
                                if (!mounted) return;
                                _loadLatePaymentsDueDates().then((_) {
                                  _loadLatePaymentsRows(courses);
                                });
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        SizedBox(
                          width: 220,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade600),
                            ),
                            child: DropdownButton<String>(
                              value: effectiveSelectedCourseId,
                              items: [
                                const DropdownMenuItem(
                                  value: 'all',
                                  child: Text('جميع الكورسات'),
                                ),
                                ...courseOptions.map((c) {
                                  final id = c['id']?.toString() ?? '';
                                  final name = c['name']?.toString() ?? '';
                                  return DropdownMenuItem(
                                    value: id,
                                    child: Text(name, overflow: TextOverflow.ellipsis),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _latePaymentsSelectedCourseId = value ?? 'all';
                                });

                                _loadLatePaymentsDueDates().then((_) {
                                  _loadLatePaymentsRows(courses);
                                });
                              },
                              style: const TextStyle(color: Colors.white),
                              dropdownColor: const Color(0xFF2A2A2A),
                              underline: const SizedBox(),
                              isExpanded: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade600),
                            ),
                            child: DropdownButton<String>(
                              value: effectiveSelectedLocation,
                              items: [
                                const DropdownMenuItem(value: 'all', child: Text('جميع المواقع')),
                                ...locations.map((location) => DropdownMenuItem(
                                      value: location,
                                      child: Text(location),
                                    )),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _latePaymentsSelectedLocation = value ?? 'all';
                                  _latePaymentsSelectedCourseId = 'all';
                                });

                                _loadLatePaymentsDueDates().then((_) {
                                  _loadLatePaymentsRows(courses);
                                });
                              },
                              style: const TextStyle(color: Colors.white),
                              dropdownColor: const Color(0xFF2A2A2A),
                              underline: const SizedBox(),
                              isExpanded: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // تواريخ الاستحقاق (حفظ دائم)
                    if (classId.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade700),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'آخر موعد للسداد',
                              style: TextStyle(
                                color: Colors.grey.shade200,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (effectiveSelectedCourseId != 'all')
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (() {
                                        final due =
                                            _latePaymentsDueDatesByCourseId[effectiveSelectedCourseId];
                                        if (due == null) return 'غير محدد';
                                        return DateFormat('yyyy-MM-dd').format(due);
                                      })(),
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _pickAndSaveDueDateForCourse(
                                        courseId: effectiveSelectedCourseId,
                                        initialDate:
                                            _latePaymentsDueDatesByCourseId[effectiveSelectedCourseId],
                                      );
                                    },
                                    icon: const Icon(Icons.date_range, size: 18),
                                    label: const Text('تحديد التاريخ'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFEC619),
                                      foregroundColor: const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: courseOptions.map((c) {
                                  final courseId = c['id']?.toString() ?? '';
                                  final courseName = c['name']?.toString() ?? '';
                                  final due = _latePaymentsDueDatesByCourseId[courseId];
                                  final dueLabel = due == null ? 'غير محدد' : DateFormat('yyyy-MM-dd').format(due);
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            courseName,
                                            style: const TextStyle(color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(dueLabel, style: TextStyle(color: Colors.grey.shade300)),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: () {
                                            _pickAndSaveDueDateForCourse(
                                              courseId: courseId,
                                              initialDate: due,
                                            );
                                          },
                                          icon: const Icon(Icons.date_range, size: 18, color: Color(0xFFFEC619)),
                                          label: const Text('تغيير', style: TextStyle(color: Color(0xFFFEC619))),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(color: Color(0xFFFEC619)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // الجدول
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFEC619).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Expanded(
                            child: Text(
                              'الطلاب المتأخرين بالدفع',
                              style: TextStyle(
                                color: Color(0xFFFEC619),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final visibleCourses = courseOptions;
                        final isAllCourses = effectiveSelectedCourseId == 'all';
                        final selectedCourseName = !isAllCourses
                            ? (() {
                                try {
                                  final c = courseOptions.firstWhere(
                                    (e) => e['id']?.toString() == effectiveSelectedCourseId,
                                  );
                                  return c['name']?.toString() ?? '';
                                } catch (_) {
                                  return '';
                                }
                              })()
                            : '';

                        return Scrollbar(
                          controller: _latePaymentsHorizontalScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _latePaymentsHorizontalScrollController,
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: constraints.maxWidth),
                              child: SizedBox(
                                height: 520,
                                child: Scrollbar(
                                  controller: _latePaymentsVerticalScrollController,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _latePaymentsVerticalScrollController,
                                    primary: false,
                                    scrollDirection: Axis.vertical,
                                    child: DataTable(
                                      border: TableBorder.all(
                                        color: const Color(0xFF5A5A5A),
                                        width: 0.6,
                                      ),
                                      headingRowColor:
                                          MaterialStateProperty.all(const Color(0xFF1A1A1A)),
                                      columnSpacing: 16,
                                      columns: [
                                        const DataColumn(
                                          label: SizedBox(
                                            width: 200,
                                            child: Text(
                                              'اسم الطالب',
                                              style: TextStyle(
                                                color: Color(0xFFFEC619),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const DataColumn(
                                          label: SizedBox(
                                            width: 150,
                                            child: Text(
                                              'الفصل',
                                              style: TextStyle(
                                                color: Color(0xFFFEC619),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const DataColumn(
                                          label: SizedBox(
                                            width: 140,
                                            child: Text(
                                              'الموقع',
                                              style: TextStyle(
                                                color: Color(0xFFFEC619),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataColumn(
                                          label: SizedBox(
                                            width: 170,
                                            child: Text(
                                              isAllCourses
                                                  ? 'إجمالي المدفوعات'
                                                  : 'إجمالي المدفوعات ($selectedCourseName)',
                                              style: const TextStyle(
                                                color: Color(0xFFFEC619),
                                                fontWeight: FontWeight.bold,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        const DataColumn(
                                          label: SizedBox(
                                            width: 170,
                                            child: Text(
                                              'المبلغ المتبقي الكلي',
                                              style: TextStyle(
                                                color: Color(0xFFFEC619),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        if (!isAllCourses)
                                          const DataColumn(
                                            label: SizedBox(
                                              width: 140,
                                              child: Text(
                                                'أيام التأخير',
                                                style: TextStyle(
                                                  color: Color(0xFFFEC619),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (isAllCourses)
                                          ...visibleCourses.expand((c) {
                                            final courseName = c['name']?.toString() ?? '';
                                            return [
                                              DataColumn(
                                                label: SizedBox(
                                                  width: 170,
                                                  child: Text(
                                                    'المتبقي - $courseName',
                                                    style: const TextStyle(
                                                      color: Color(0xFFFEC619),
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              DataColumn(
                                                label: SizedBox(
                                                  width: 140,
                                                  child: Text(
                                                    'التأخير - $courseName',
                                                    style: const TextStyle(
                                                      color: Color(0xFFFEC619),
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                            ];
                                          }),
                                      ],
                                      rows: _latePaymentsRows.map((r) {
                                        final perCourse =
                                            (r['perCourse'] as Map?)?.cast<String, dynamic>() ?? {};
                                        final paid = (() {
                                          if (isAllCourses) return r['totalPaid'];
                                          final data = perCourse[effectiveSelectedCourseId] as Map?;
                                          return data?['paid'] ?? 0;
                                        })();
                                        final remaining = (() {
                                          if (isAllCourses) return r['totalRemaining'];
                                          final data = perCourse[effectiveSelectedCourseId] as Map?;
                                          return data?['remaining'] ?? 0;
                                        })();
                                        final daysLate = (() {
                                          if (isAllCourses) return null;
                                          final data = perCourse[effectiveSelectedCourseId] as Map?;
                                          return data?['daysLate'];
                                        })();

                                        return DataRow(
                                          cells: [
                                            DataCell(
                                              SizedBox(
                                                width: 200,
                                                child: Text(
                                                  r['studentName']?.toString() ?? '',
                                                  style: const TextStyle(color: Colors.white),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 150,
                                                child: Text(
                                                  r['className']?.toString() ?? '',
                                                  style: const TextStyle(color: Colors.white),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 140,
                                                child: Text(
                                                  r['location']?.toString() ?? '',
                                                  style: const TextStyle(color: Colors.white),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 170,
                                                child: Text(
                                                  _formatIqd(paid),
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ),
                                            DataCell(
                                              SizedBox(
                                                width: 170,
                                                child: Text(
                                                  _formatIqd(remaining),
                                                  style: const TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ),
                                            if (!isAllCourses)
                                              DataCell(
                                                SizedBox(
                                                  width: 140,
                                                  child: Text(
                                                    daysLate == null ? '-' : daysLate.toString(),
                                                    style: const TextStyle(color: Colors.white),
                                                  ),
                                                ),
                                              ),
                                            if (isAllCourses)
                                              ...visibleCourses.expand((c) {
                                                final courseId = c['id']?.toString() ?? '';
                                                final data = perCourse[courseId] as Map?;
                                                final courseRemaining = data?['remaining'];
                                                final courseDaysLate = data?['daysLate'];
                                                final courseDueDate = data?['dueDate'];

                                                final remainingValue = (courseRemaining is int)
                                                    ? courseRemaining
                                                    : int.tryParse(courseRemaining?.toString() ?? '') ?? 0;
                                                final daysLateValue = (courseDaysLate is int)
                                                    ? courseDaysLate
                                                    : int.tryParse(courseDaysLate?.toString() ?? '');

                                                final bool isCompleted = remainingValue <= 0;
                                                final bool hasDueDate = courseDueDate != null;
                                                final daysText = (!hasDueDate)
                                                    ? '-'
                                                    : ((daysLateValue != null && daysLateValue > 0)
                                                        ? daysLateValue.toString()
                                                        : '0');

                                                final remainingText = isCompleted
                                                    ? 'مكتمل'
                                                    : _formatIqd(remainingValue);
                                                return [
                                                  DataCell(
                                                    SizedBox(
                                                      width: 170,
                                                      child: Text(
                                                        remainingText,
                                                        style: const TextStyle(color: Colors.white),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  DataCell(
                                                    SizedBox(
                                                      width: 140,
                                                      child: Text(
                                                        daysText,
                                                        style: const TextStyle(color: Colors.white),
                                                      ),
                                                    ),
                                                  ),
                                                ];
                                              }),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _latePaymentsRows.isEmpty
                            ? 'الجدول فارغ حالياً'
                            : 'عدد الطلاب المتأخرين: ${_latePaymentsRows.length}',
                        style: TextStyle(color: Colors.grey.shade400),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _exportLatePaymentsPdf(List<Map<String, dynamic>> rows) async {
    try {
      // snapshot للصفوف لحظة الضغط حتى لا يخرج ملف فارغ إذا تغيرت الحالة أثناء التصدير
      final snapshotRows = rows.map((e) => Map<String, dynamic>.from(e)).toList();

      // لضمان أن ملف الـ PDF لا يكون فارغاً: أعِد تحميل الصفوف قبل التصدير
      final refreshedCourses = await _dbHelper.getCourses();
      await _loadLatePaymentsDueDates();
      await _loadLatePaymentsRows(refreshedCourses);

      final exportRows = _latePaymentsRows.isNotEmpty ? _latePaymentsRows : snapshotRows;
      if (exportRows.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد بيانات لتصديرها حالياً')),
          );
        }
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          backgroundColor: Color(0xFF2A2A2A),
          content: Row(
            children: [
              CircularProgressIndicator(color: Color(0xFFFEC619)),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );
      final fallbackFont = pw.Font.helvetica();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
        ),
      );

      final effectiveLocation = _latePaymentsSelectedLocation;
      final effectiveCourseId = _latePaymentsSelectedCourseId;
      final allCourses = refreshedCourses;
      final courseNameById = {
        for (final c in allCourses) (c['id']?.toString() ?? ''): (c['name']?.toString() ?? ''),
      };

      final isAllCourses = effectiveCourseId == 'all';
      final selectedCourseName =
          (!isAllCourses && courseNameById.containsKey(effectiveCourseId))
              ? (courseNameById[effectiveCourseId] ?? '')
              : '';

      // بناء عناوين الأعمدة مثل الجدول الظاهر
      final visibleCourses = isAllCourses
          ? _getLatePaymentsCourseOptionsForLocation(allCourses, effectiveLocation)
          : const <Map<String, dynamic>>[];

      final headers = <String>[
        'اسم الطالب',
        'الفصل',
        'الموقع',
        isAllCourses ? 'إجمالي المدفوعات' : 'إجمالي المدفوعات ($selectedCourseName)',
        'المبلغ المتبقي الكلي',
        if (!isAllCourses) 'أيام التأخير',
        if (isAllCourses)
          ...visibleCourses.expand((c) {
            final courseName = c['name']?.toString() ?? '';
            return [
              'المتبقي - $courseName',
              'التأخير - $courseName',
            ];
          }),
      ];

      final data = exportRows.map((r) {
        final perCourse = (r['perCourse'] as Map?)?.cast<String, dynamic>() ?? {};
        final paid = (() {
          if (isAllCourses) return r['totalPaid'];
          final m = perCourse[effectiveCourseId] as Map?;
          return m?['paid'] ?? 0;
        })();
        final remaining = (() {
          if (isAllCourses) return r['totalRemaining'];
          final m = perCourse[effectiveCourseId] as Map?;
          return m?['remaining'] ?? 0;
        })();
        final daysLate = (() {
          if (isAllCourses) return null;
          final m = perCourse[effectiveCourseId] as Map?;
          return m?['daysLate'];
        })();

        final row = <String>[
          r['studentName']?.toString() ?? '',
          r['className']?.toString() ?? '',
          r['location']?.toString() ?? '',
          _formatIqd(paid),
          _formatIqd(remaining),
          if (!isAllCourses) (daysLate == null ? '-' : daysLate.toString()),
        ];

        if (isAllCourses) {
          row.addAll(
            visibleCourses.expand((c) {
              final courseId = c['id']?.toString() ?? '';
              final m = perCourse[courseId] as Map?;
              final remAny = m?['remaining'];
              final dueDate = m?['dueDate'];
              final daysLateAny = m?['daysLate'];

              final remainingValue = (remAny is int)
                  ? remAny
                  : int.tryParse(remAny?.toString() ?? '') ?? 0;
              final bool isCompleted = remainingValue <= 0;
              final bool hasDueDate = dueDate != null;
              final int? daysLateVal = (daysLateAny is int)
                  ? daysLateAny
                  : int.tryParse(daysLateAny?.toString() ?? '');

              final bool isLate = hasDueDate && (daysLateVal != null && daysLateVal > 0) && !isCompleted;

              final remainingText = isCompleted
                  ? 'مكتمل'
                  : _formatIqd(remainingValue);
              final daysText = (!hasDueDate)
                  ? '-'
                  : ((daysLateVal != null && daysLateVal > 0) ? daysLateVal.toString() : '0');
              return [
                isLate ? remainingText : remainingText,
                isLate ? daysText : daysText,
              ];
            }),
          );
        }

        return row;
      }).toList();

      pw.Table _buildPdfTable() {
        // توزيع أعمدة متوازن حتى تبقى العناوين واضحة
        final columnWidths = <int, pw.TableColumnWidth>{
          0: const pw.FlexColumnWidth(2.3), // اسم الطالب
          1: const pw.FlexColumnWidth(1.6), // الفصل
          2: const pw.FlexColumnWidth(1.4), // الموقع
          3: const pw.FlexColumnWidth(1.6), // إجمالي المدفوعات
          4: const pw.FlexColumnWidth(1.6), // المتبقي الكلي
        };

        final startDynamic = 5;
        for (int i = startDynamic; i < headers.length; i++) {
          columnWidths[i] = const pw.FlexColumnWidth(1.3);
        }

        pw.Widget headerCell(String text) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: arabicBold,
                fontFallback: [fallbackFont],
                fontSize: 9,
                color: PdfColor.fromInt(0xFFFEC619),
              ),
            ),
          );
        }

        pw.Widget cell(String text) {
          return pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              text,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: arabicFont,
                fontFallback: [fallbackFont],
                fontSize: 8,
                // لون أسود لأن خلفية صفحة PDF بيضاء (كان يظهر وكأنه فارغ)
                color: PdfColor.fromInt(0xFF000000),
              ),
            ),
          );
        }

        return pw.Table(
          border: pw.TableBorder.all(
            color: const PdfColor(0.35, 0.35, 0.35),
            width: 0.5,
          ),
          columnWidths: columnWidths,
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF1A1A1A),
              ),
              children: headers.map(headerCell).toList(),
            ),
            ...data.map(
              (row) => pw.TableRow(
                children: row.map((v) => cell(v.toString())).toList(),
              ),
            ),
          ],
        );
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.DefaultTextStyle(
                style: pw.TextStyle(font: arabicFont, fontFallback: [fallbackFont]),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'الطلاب المتأخرين بالدفع',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الموقع: ${effectiveLocation == 'all' ? 'كل المواقع' : effectiveLocation}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'الكورس: ${effectiveCourseId == 'all' ? 'كل الكورسات' : selectedCourseName}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      rows.isEmpty ? 'لا توجد بيانات' : 'عدد السجلات: ${rows.length}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 12),
                    if (rows.isNotEmpty)
                      _buildPdfTable(),
                  ],
                ),
              ),
            );
          },
        ),
      );

      Navigator.pop(context);

      final fileName = 'المتأخرين_بالدفع_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save());

      final uri = Uri.file(file.path);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw Exception('تعذر فتح الملف');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إنشاء ملف PDF بنجاح: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPaymentHistory() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadPaymentData(),
      builder: (context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFFFEC619)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'حدث خطأ: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }

        final data = snapshot.data ?? {};
        final payments = data['payments'] as List<Map<String, dynamic>>? ?? [];
        final statistics = data['statistics'] as Map<String, dynamic>? ?? {};
        final courseStatistics = data['courseStatistics'] as List<Map<String, dynamic>>? ?? [];
        final locations = data['locations'] as List<String>? ?? [];
        final courses = data['courses'] as List<Map<String, dynamic>>? ?? [];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الإحصائيات العامة (ثابتة)
              Row(
                children: [
                  Expanded(
                    child: _buildPaymentStatCard(
                      icon: Icons.receipt_long,
                      value: '${statistics['total_payments'] ?? 0}',
                      label: 'إجمالي الدفعات',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildPaymentStatCard(
                      icon: Icons.attach_money,
                      value: _formatIqd(statistics['total_amount'] ?? 0),
                      label: 'المبلغ الإجمالي',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // إحصائيات الكورسات للموقع المختار
              if (_selectedPaymentLocation != 'all')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إحصائيات الكورسات',
                      style: TextStyle(
                        color: Color(0xFFFEC619),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (courseStatistics.isEmpty)
                      Text(
                        'لا توجد كورسات لهذا الموقع',
                        style: TextStyle(color: Colors.grey.shade400),
                      )
                    else
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: courseStatistics.map((courseStat) {
                          final course = courseStat['course'] as Map<String, dynamic>;
                          final stats = courseStat['statistics'] as Map<String, dynamic>;
                          return SizedBox(
                            width: 260,
                            child: _buildPaymentStatCard(
                              icon: Icons.school,
                              value:
                                  '${stats['total_payments'] ?? 0} | ${_formatIqd(stats['total_amount'] ?? 0)}',
                              label: course['name']?.toString() ?? '',
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),

              // شريط البحث والتصفية
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFEC619).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    // حقول البحث والتصفية
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _paymentSearchController,
                            decoration: InputDecoration(
                              hintText: 'ادخل اسم الطالب',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                              filled: true,
                              fillColor: const Color(0xFF2A2A2A),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey.shade600),
                              ),
                            ),
                            style: const TextStyle(color: Colors.white),
                            onChanged: (value) {
                              _searchTimer?.cancel();
                              _searchTimer = Timer(const Duration(milliseconds: 800), () {
                                if (mounted) {
                                  setState(() {});
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedPaymentLocation,
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('جميع المواقع')),
                              ...locations.map((location) => DropdownMenuItem(
                                value: location,
                                child: Text(location),
                              )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentLocation = value ?? 'all';
                                _selectedPaymentCourse = 'all';
                              });
                            },
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF2A2A2A),
                            underline: const SizedBox(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedPaymentCourse,
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('جميع الكورسات')),
                              ...courses.map((course) => DropdownMenuItem(
                                value: course['id'] as String,
                                child: Text(course['name'] as String),
                              )),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentCourse = value ?? 'all';
                              });
                            },
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF2A2A2A),
                            underline: const SizedBox(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'البحث يتم باسم الطالب',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // جدول البيانات
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFEC619).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'سجل الدفعات',
                              style: TextStyle(
                                color: Color(0xFFFEC619),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'تصدير PDF',
                            onPressed: payments.isEmpty ? null : () => _exportPaymentHistoryPdf(payments),
                            icon: const Icon(Icons.picture_as_pdf, color: Color(0xFFFEC619)),
                          ),
                        ],
                      ),
                    ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowColor:
                                  MaterialStateProperty.all(const Color(0xFF1A1A1A)),
                              columnSpacing: 16,
                              columns: const [
                                DataColumn(
                                  label: SizedBox(
                                    width: 60,
                                    child: Text(
                                      'الرقم',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 180,
                                    child: Text(
                                      'اسم الطالب',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 130,
                                    child: Text(
                                      'الفصل',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 140,
                                    child: Text(
                                      'القسط',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 140,
                                    child: Text(
                                      'المبلغ المدفوع',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 120,
                                    child: Text(
                                      'تاريخ الدفع',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 120,
                                    child: Text(
                                      'إجراءات',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              rows: payments.asMap().entries.map((entry) {
                                final index = entry.key;
                                final payment = entry.value;
                                return DataRow(
                                  cells: [
                                    DataCell(SizedBox(
                                      width: 60,
                                      child: Text(
                                        '${index + 1}',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 180,
                                      child: Text(
                                        payment['student_name'] ?? '',
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 130,
                                      child: Text(
                                        payment['class_name'] ?? '',
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 140,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEC619).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFFEC619),
                                            width: 1,
                                          ),
                                        ),
                                        child: Text(
                                          payment['course_name'] ?? '',
                                          style: const TextStyle(
                                            color: Color(0xFFFEC619),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 140,
                                      child: Text(
                                        _formatIqd(payment['amount'] ?? 0),
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 120,
                                      child: Text(
                                        payment['date'] ?? '',
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 120,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.blue),
                                            onPressed: () => _showEditPaymentDialog(payment),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red),
                                            onPressed: () => _showDeletePaymentDialog(payment),
                                          ),
                                        ],
                                      ),
                                    )),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadPaymentData() async {
    try {
      final db = DatabaseHelper();

      // جلب الكورسات
      final allCourses = await db.getCourses();

      // المواقع يجب أن تكون فقط من الكورسات المنشأة فعلياً
      // مع استبعاد بيانات الاختبار القديمة (مثل: كورس أول/كورس ثاني)
      final locationToCourses = <String, List<Map<String, dynamic>>>{};
      for (final c in allCourses) {
        final loc = c['location']?.toString() ?? '';
        if (loc.isEmpty) continue;
        (locationToCourses[loc] ??= []).add(c);
      }

      bool _isSampleLocation(List<Map<String, dynamic>> coursesForLocation) {
        if (coursesForLocation.isEmpty) return true;
        return coursesForLocation.every((c) {
          final name = c['name']?.toString() ?? '';
          return name.startsWith('كورس ') && (name.contains('أول') || name.contains('ثاني'));
        });
      }

      final locations = locationToCourses.entries
          .where((e) => !_isSampleLocation(e.value))
          .map((e) => e.key)
          .toList()
        ..sort();

      // جلب الكورسات حسب الموقع المحدد
      final courses = _selectedPaymentLocation == 'all'
          ? allCourses
          : allCourses.where((c) => (c['location']?.toString() ?? '') == _selectedPaymentLocation).toList();
      
      // جلب بيانات الأقساط مع الفلاتر
      final payments = await db.getAllInstallmentsWithDetails(
        locationFilter: _selectedPaymentLocation == 'all' ? null : _selectedPaymentLocation,
        courseFilter: _selectedPaymentCourse == 'all' ? null : _selectedPaymentCourse,
        studentNameFilter: _paymentSearchController.text.isEmpty ? null : _paymentSearchController.text,
      );
      
      // جلب الإحصائيات العامة
      final statistics = await db.getInstallmentsStatistics(
        locationFilter: _selectedPaymentLocation == 'all' ? null : _selectedPaymentLocation,
        courseFilter: _selectedPaymentCourse == 'all' ? null : _selectedPaymentCourse,
      );
      
      // جلب إحصائيات حسب الكورسات
      final courseStatistics = <Map<String, dynamic>>[];
      for (final course in courses) {
        final courseId = course['id'] as String;
        final courseStats = await db.getInstallmentsStatistics(
          locationFilter: _selectedPaymentLocation == 'all' ? null : _selectedPaymentLocation,
          courseFilter: courseId,
        );
        courseStatistics.add({
          'course': course,
          'statistics': courseStats,
        });
      }
      
      return {
        'payments': payments,
        'statistics': statistics,
        'courseStatistics': courseStatistics,
        'locations': locations,
        'courses': courses,
      };
    } catch (e) {
      print('Error loading payment data: $e');
      return {
        'payments': <Map<String, dynamic>>[],
        'statistics': <String, dynamic>{},
        'courseStatistics': <Map<String, dynamic>>[],
        'locations': <String>[],
        'courses': <Map<String, dynamic>>[],
      };
    }
  }

  
  Widget _buildPaymentStatCard({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFFEC619),
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueOverview() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.trending_up, size: 80, color: Color(0xFFFEC619)),
          SizedBox(height: 16),
          Text(
            'الإيرادات',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '0 د.ع',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationsOverview() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.location_on, size: 80, color: Color(0xFFFEC619)),
          SizedBox(height: 16),
          Text(
            'المواقع',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'بنوك: 0 طالب\nالمنصور: 0 طالب\nزيونة: 0 طالب',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  void _showDeletePaymentDialog(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف دفعة الطالب ${payment['student_name']}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deletePayment(payment['id']);
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePayment(int paymentId) async {
    try {
      await _dbHelper.deleteInstallment(paymentId);
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showEditPaymentDialog(Map<String, dynamic> payment) {
    final amountController = TextEditingController(text: payment['amount'].toString());
    final dateController = TextEditingController(text: payment['date']);
    DateTime selectedDate = DateTime.tryParse(payment['date']) ?? DateTime.now();
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('تعديل دفعة ${payment['student_name']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // اختيار الكورس
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _dbHelper.getCoursesByLocation(payment['course_location']),
                builder: (context, snapshot) {
                  final courses = snapshot.data ?? [];
                  return DropdownButtonFormField<String>(
                    value: payment['course_id'],
                    decoration: const InputDecoration(
                      labelText: 'القسط',
                      border: OutlineInputBorder(),
                    ),
                    items: courses.map((course) => DropdownMenuItem(
                      value: course['id'] as String,
                      child: Text(course['name'] as String),
                    )).toList(),
                    onChanged: (value) {
                      setState(() {});
                    },
                  );
                },
              ),
              const SizedBox(height: 16),
              // المبلغ المستحق
              FutureBuilder<int>(
                future: _getCoursePrice(payment['course_id']),
                builder: (context, snapshot) {
                  final dueAmount = snapshot.data ?? 0;
                  return Text(
                    'المبلغ المستحق: ${_formatIqd(dueAmount)}',
                    style: const TextStyle(
                      color: Color(0xFFFEC619),
                      fontWeight: FontWeight.bold,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              // المبلغ المدفوع
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'المبلغ المدفوع',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              // التاريخ
              TextField(
                controller: dateController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'تاريخ الدفع',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    setState(() {
                      selectedDate = date;
                      dateController.text = DateFormat('yyyy-MM-dd').format(date);
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () async {
                final newAmount = int.tryParse(amountController.text);
                if (newAmount != null) {
                  Navigator.pop(context);
                  await _updatePayment(payment['id'], payment['course_id'], newAmount, dateController.text);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<int> _getCoursePrice(String courseId) async {
    try {
      final courses = await _dbHelper.getCourses();
      final course = courses.firstWhere((c) => c['id'] == courseId, orElse: () => {});
      return course['price'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<void> _updatePayment(int paymentId, String courseId, int newAmount, String newDate) async {
    try {
      await _dbHelper.updateInstallment({
        'id': paymentId,
        'course_id': courseId,
        'amount': newAmount,
        'date': newDate,
      });
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportPaymentHistoryPdf(List<Map<String, dynamic>> payments) async {
    try {
      // عرض مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Color(0xFFFEC619)),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );

      final fallbackFont = pw.Font.helvetica();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
        ),
      );
      
      // إضافة الصفحة الأولى
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.DefaultTextStyle(
                style: pw.TextStyle(
                  font: arabicFont,
                  fontFallback: [fallbackFont],
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // العنوان
                    pw.Text(
                      'سجل الدفعات',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 16),

                    // الجدول
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFF333333)),
                      columnWidths: {
                        0: pw.FixedColumnWidth(30),
                        1: const pw.FlexColumnWidth(2),
                        2: const pw.FlexColumnWidth(1.5),
                        3: const pw.FlexColumnWidth(1.5),
                        4: const pw.FlexColumnWidth(1.5),
                        5: const pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        // Header
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF2A2A2A)),
                          children: [
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'الرقم',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'اسم الطالب',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'الفصل',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'القسط',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'المبلغ المدفوع',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'تاريخ الدفع',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // Data rows
                        ...List.generate(payments.length, (index) {
                          final payment = payments[index];
                          return pw.TableRow(
                            children: [
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text('${index + 1}', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(payment['student_name'] ?? '', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(payment['class_name'] ?? '', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(payment['course_name'] ?? '', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(_formatIqd(payment['amount'] ?? 0), style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text(payment['date'] ?? '', style: pw.TextStyle(fontSize: 10)),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // إغلاق مؤشر التحميل
      Navigator.pop(context);

      // حفظ الملف
      final fileName = 'سجل_الدفعات_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await doc.save());

      // فتح الملف مباشرة بدون نافذة طباعة
      final uri = Uri.file(file.path);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        throw Exception('تعذر فتح الملف');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text('تم إنشاء ملف PDF بنجاح: $fileName'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // إغلاق مؤشر التحميل
      Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildControlButton(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // خلفية سوداء للأزرار
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFEC619),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildStatCards() {
    return Row(
      children: [
        // بطاقة إجمالي الطلاب
        Expanded(
          child: _buildStatCard(
            icon: Icons.group,
            title: 'إجمالي الطلاب',
            value: _totalStudents.toString(),
            color: const Color(0xFFFEC619),
            isMain: true,
          ),
        ),
        const SizedBox(width: 12),
        // بطاقة الإيرادات المتوقعة
        Expanded(
          child: _buildStatCard(
            icon: Icons.attach_money,
            title: 'الإيرادات المتوقعة',
            value: _formatIqd(_expectedRevenue),
            color: const Color(0xFFFEC619),
          ),
        ),
        const SizedBox(width: 12),
        // بطاقة الإيرادات المستلمة
        Expanded(
          child: _buildStatCard(
            icon: Icons.receipt,
            title: 'الإيرادات المستلمة',
            value: _formatIqd(_receivedRevenue),
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    bool isMain = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A), // بطاقات رمادية
        borderRadius: BorderRadius.circular(12),
        border: isMain
            ? Border.all(
                color: color.withOpacity(0.3),
                width: 1.5,
              )
            : null,
        boxShadow: isMain
            ? [
                BoxShadow(
                  color: color.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // الأيقونة
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A), // خلفية سوداء صغيرة للأيقونة
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          // العنوان
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          // القيمة
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الرسم البياني
        Expanded(
          flex: 2,
          child: _buildChartSection(),
        ),
        const SizedBox(width: 16),
        // قائمة الحالة
        Expanded(
          flex: 1,
          child: _buildStatusList(),
        ),
      ],
    );
  }

  Widget _buildChartSection() {
    final points = _monthlyRevenue
        .where((r) => (r['month']?.toString() ?? '').isNotEmpty)
        .toList();

    return Container(
      height: 250,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // خلفية سوداء للرسم البياني
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الإيرادات الشهرية',
            style: const TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A), // خلفية رمادية للمنطقة الداخلية
                borderRadius: BorderRadius.circular(8),
              ),
              child: points.isEmpty
                  ? const Center(
                      child: Text(
                        'لا توجد بيانات متاحة',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(12),
                      child: ListView.builder(
                        itemCount: points.length,
                        itemBuilder: (context, i) {
                          final month = points[i]['month']?.toString() ?? '';
                          final total = int.tryParse(points[i]['total']?.toString() ?? '') ?? 0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    month,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                Text(
                                  _formatIqd(total),
                                  style: const TextStyle(color: Color(0xFFFEC619)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusList() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A), // خلفية رمادية لقائمة الحالة
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الحالة',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildStatusItem('الطلاب المتأخرين بالدفع', _firstInstallmentLate),
          const SizedBox(height: 12),
          _buildStatusItem('إجمالي المدفوعات', _receivedRevenue),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String title, int value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ),
        Text(
          value.toString(),
          style: TextStyle(
            color: value > 0 ? const Color(0xFFFEC619) : Colors.grey,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildRevenueTable() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A), // خلفية سوداء للجدول
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان الجدول
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'الإيرادات حسب الموقع',
                  style: TextStyle(
                    color: Color(0xFFFEC619),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEC619).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'تحديث',
                    style: TextStyle(
                      color: Color(0xFFFEC619),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // الجدول
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A), // خلفية رمادية للجدول الداخلي
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // رأس الجدول
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2A2A2A), // خلفية رمادية للرأس
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          'الموقع',
                          style: TextStyle(
                            color: Color(0xFFFEC619),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'عدد الطلاب',
                          style: TextStyle(
                            color: Color(0xFFFEC619),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'الإيرادات الكلية',
                          style: TextStyle(
                            color: Color(0xFFFEC619),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // صفوف البيانات
                ..._locationStats.asMap().entries.map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isLast = index == _locationStats.length - 1;
                  final revenueNumber = num.tryParse(
                        data['revenue']
                                ?.toString()
                                .replaceAll(',', '')
                                .replaceAll('د.ع', '')
                                .replaceAll('IQD', '')
                                .trim() ??
                            '',
                      ) ??
                      0;
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A), // خلفية رمادية للصفوف
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.grey.shade700,
                          width: isLast ? 0 : 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            data['location'],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            data['students'].toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            _formatIqd(revenueNumber),
                            style: TextStyle(
                              color: revenueNumber > 0
                                  ? const Color(0xFFFEC619)
                                  : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildCoursePricing() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان الصفحة
          const Text(
            'إدارة أسعار الكورسات',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // عرض المواقع والفصول والكورسات
          ..._locations.map((location) => _buildLocationSection(location)).toList(),
        ],
      ),
    );
  }

  Widget _buildLocationSection(String location) {
    final locationClasses = _classes.where((class_) => class_['location'] == location).toList();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFEC619).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // عنوان الموقع مع زر إضافة كورس
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () => _showAddCourseDialogForLocation(location),
                icon: const Icon(Icons.add, color: Color(0xFF1A1A1A)),
                label: const Text(
                  'إضافة كورس',
                  style: TextStyle(color: Color(0xFF1A1A1A)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFEC619),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Text(
                location,
                style: const TextStyle(
                  color: Color(0xFFFEC619),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // جدول الفصول والكورسات
          if (locationClasses.isNotEmpty)
            _buildClassesCoursesTable(location, locationClasses)
          else
            const Text(
              'لا يوجد فصول في هذا الموقع',
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildClassesCoursesTable(String location, List<Map<String, dynamic>> classes) {
    final locationCourses = _locationCourses[location] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade600),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(const Color(0xFF1A1A1A)),
          dataRowColor: MaterialStateProperty.all(const Color(0xFF2A2A2A)),
          border: TableBorder.all(color: Colors.grey.shade600),
          columns: [
            // عمود اسم الفصل
            DataColumn(
              label: Container(
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'اسم الفصل',
                  style: TextStyle(
                    color: Color(0xFFFEC619),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // أعمدة الكورسات
            ...locationCourses.map((course) => DataColumn(
              label: Container(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () => _confirmDeleteCourse(course),
                      child: Text(
                        course['name'],
                        style: const TextStyle(
                          color: Color(0xFFFEC619),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      _formatIqd(course['price']),
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )),
            // عمود المبلغ الكلي
            DataColumn(
              label: Container(
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'المبلغ الكلي',
                  style: TextStyle(
                    color: Color(0xFFFEC619),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
          rows: classes.map((class_) {
            final classId = class_['id'].toString();
            final classCourses = _classCourseStatus[classId] ?? {};
            
            // حساب المبلغ الكلي
            int totalAmount = 0;
            for (var course in locationCourses) {
              final courseId = course['id']?.toString() ?? '';
              if (classCourses[courseId]?['enabled'] == true) {
                final amount = classCourses[courseId]?['amount'] ?? course['price'];
                totalAmount += (amount is num ? amount.toInt() : int.tryParse(amount.toString()) ?? 0);
              }
            }
            
            return DataRow(
              cells: [
                // اسم الفصل
                DataCell(
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      class_['name']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
                // خلايا الكورسات
                ...locationCourses.map((course) {
                  final courseId = course['id']?.toString() ?? '';
                  final courseStatus = classCourses[courseId] ?? {};
                  final isEnabled = courseStatus['enabled'] == true;
                  final amount = courseStatus['amount'] ?? course['price'];
                  
                  return DataCell(
                    Container(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // زر تعديل المبلغ
                          if (isEnabled)
                            GestureDetector(
                              onTap: () => _editCourseAmount(classId, courseId, amount),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEC619).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFFEC619)),
                                ),
                                child: Text(
                                  _formatIqd(amount),
                                  style: const TextStyle(
                                    color: Color(0xFFFEC619),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          // زر ناقص/زائد
                          GestureDetector(
                            onTap: () => _toggleCourseStatus(classId, courseId),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isEnabled 
                                    ? Colors.green.withOpacity(0.3)
                                    : Colors.grey.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isEnabled ? Colors.green : Colors.grey,
                                ),
                              ),
                              child: Icon(
                                isEnabled ? Icons.remove : Icons.add,
                                color: isEnabled ? Colors.green : Colors.grey,
                                size: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                // المبلغ الكلي
                DataCell(
                  Container(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      _formatIqd(totalAmount),
                      style: const TextStyle(
                        color: Color(0xFFFEC619),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showAddCourseDialogForLocation(String location) {
    setState(() {
      _selectedLocationForCourse = location;
      _showAddCourseDialog = true;
    });
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'إضافة كورس جديد',
          style: TextStyle(color: Color(0xFFFEC619)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _courseNameController,
              decoration: InputDecoration(
                labelText: 'اسم الكورس',
                labelStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFEC619)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _coursePriceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'المبلغ المطلوب',
                labelStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey.shade600),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFEC619)),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await _addNewCourse();
              if (!context.mounted) return;
              if (ok) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEC619),
            ),
            child: const Text('إضافة', style: TextStyle(color: Color(0xFF1A1A1A))),
          ),
        ],
      ),
    );
  }

  Future<bool> _addNewCourse() async {
    final name = _courseNameController.text.trim();
    final price = int.tryParse(_coursePriceController.text);
    
    if (name.isEmpty || price == null) return false;

    final newCourseId = DateTime.now().millisecondsSinceEpoch.toString();
    final newCourse = {
      'id': newCourseId,
      'name': name,
      'price': price,
      'location': _selectedLocationForCourse,
    };

    try {
      await _dbHelper.insertCourse(Map<String, dynamic>.from(newCourse));

      // إضافة سعر للكورس لكل فصل في نفس الموقع
      for (final class_ in _classes) {
        if (class_['location'].toString() == _selectedLocationForCourse) {
          final classId = class_['id']?.toString() ?? '';
          final parsedClassId = int.tryParse(classId);
          if (parsedClassId == null) continue;

          await _dbHelper.insertClassCoursePrice({
            'class_id': parsedClassId,
            'course_id': newCourseId,
            'amount': price,
            'enabled': 1,
            'paid': 0,
          });
        }
      }

      await _loadCoursePricingData();

      if (mounted) {
        setState(() {
          _courseNameController.clear();
          _coursePriceController.clear();
          _showAddCourseDialog = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تمت إضافة الكورس بنجاح')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إضافة الكورس: ${e.toString()}')),
        );
      }
      return false;
    }
  }

  void _editCourseAmount(String classId, String courseId, int currentAmount) {
    final controller = TextEditingController(text: currentAmount.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: const Text(
          'تعديل المبلغ',
          style: TextStyle(color: Color(0xFFFEC619)),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'المبلغ المستحق',
            labelStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade600),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.grey.shade600),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFEC619)),
            ),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newAmount = int.tryParse(controller.text);
              if (newAmount != null) {
                final priceId = _classCourseStatus[classId]?[courseId]?['priceId'];
                try {
                  if (priceId != null) {
                    await _dbHelper.updateClassCoursePrice({
                      'id': priceId,
                      'amount': newAmount,
                    });
                  } else {
                    final parsedClassId = int.tryParse(classId);
                    if (parsedClassId == null) return;

                    await _dbHelper.insertClassCoursePrice({
                      'class_id': parsedClassId,
                      'course_id': courseId,
                      'amount': newAmount,
                      'enabled': 1,
                      'paid': 0,
                    });
                  }

                  await _loadCoursePricingData();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('حدث خطأ أثناء حفظ السعر: ${e.toString()}'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                  return;
                }
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFEC619),
            ),
            child: const Text('حفظ', style: TextStyle(color: Color(0xFF1A1A1A))),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleCourseStatus(String classId, String courseId) async {
    final current = _classCourseStatus[classId]?[courseId];
    final currentStatus = current?['enabled'] == true;
    final nextEnabled = !currentStatus;

    setState(() {
      _classCourseStatus[classId] ??= {};
      _classCourseStatus[classId]![courseId] ??= {
        'priceId': null,
        'amount': 0,
        'enabled': false,
        'paid': false,
      };
      _classCourseStatus[classId]![courseId]['enabled'] = nextEnabled;
    });

    try {
      final priceId = current?['priceId'];
      if (priceId != null) {
        await _dbHelper.updateClassCoursePrice({
          'id': priceId,
          'enabled': nextEnabled ? 1 : 0,
        });
      } else {
        final parsedClassId = int.tryParse(classId);
        if (parsedClassId == null) return;

        final course = _courses.firstWhere(
          (c) => c['id']?.toString() == courseId,
          orElse: () => const <String, dynamic>{},
        );
        final fallbackAmount = (course['price'] is num)
            ? (course['price'] as num).toInt()
            : int.tryParse(course['price']?.toString() ?? '') ?? 0;

        await _dbHelper.insertClassCoursePrice({
          'class_id': parsedClassId,
          'course_id': courseId,
          'amount': fallbackAmount,
          'enabled': nextEnabled ? 1 : 0,
          'paid': 0,
        });
      }

      await _loadCoursePricingData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تحديث الحالة: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );

      // rollback UI
      if (!mounted) return;
      setState(() {
        _classCourseStatus[classId]?[courseId]?['enabled'] = currentStatus;
      });
    }
  }

  String _getSelectedCourseName() {
    if (_selectedCourse.isEmpty) return '';
    try {
      final course = _courses.firstWhere(
        (c) => c['id']?.toString() == _selectedCourse,
      );
      return course['name']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }

  String _formatIqd(dynamic amount) {
    if (amount == null) return '0 د.ع';
    final num? parsed = (amount is num)
        ? amount
        : num.tryParse(amount.toString().replaceAll(',', '').replaceAll('د.ع', '').trim());
    if (parsed == null) return '0 د.ع';
    return '${_formatAmount(parsed.toDouble())} د.ع';
  }

  Future<List<Map<String, dynamic>>> _buildRemainingByCourseItems() async {
    if (_selectedClassId.isEmpty) return [];
    if (_selectedStudentId.isEmpty) return [];
    final studentId = int.tryParse(_selectedStudentId);
    if (studentId == null) return [];

    final courses = _getAvailableCourses();
    final items = <Map<String, dynamic>>[];

    for (final course in courses) {
      final courseId = course['id']?.toString() ?? '';
      if (courseId.isEmpty) continue;

      final classCourses = _classCourseStatus[_selectedClassId] ?? {};
      final due = classCourses[courseId]?['amount'];
      final dueInt = (due is int) ? due : int.tryParse(due?.toString() ?? '') ?? 0;

      final paid = await _dbHelper.getTotalPaidByStudentAndCourse(
        studentId: studentId,
        courseId: courseId,
      );

      final remaining = (dueInt - paid).clamp(0, 1 << 30);

      items.add({
        'courseId': courseId,
        'courseName': course['name']?.toString() ?? '',
        'due': dueInt,
        'paid': paid,
        'remaining': remaining,
      });
    }

    return items;
  }

  String _getClassName(String classId) {
    try {
      final classItem = _classes.firstWhere((c) => c['id'].toString() == classId);
      return classItem['name']?.toString() ?? 'غير معروف';
    } catch (e) {
      return 'غير معروف';
    }
  }

  List<Map<String, dynamic>> _getAvailableCourses() {
    // الحصول على موقع الفصل المختار (الأولوية للقيمة المختارة يدوياً)
    String selectedLocation = _selectedLocation;

    if (selectedLocation.isEmpty && _selectedClassId.isNotEmpty) {
      try {
        final selectedClass = _classes.firstWhere(
          (c) => c['id']?.toString() == _selectedClassId,
        );
        selectedLocation = selectedClass['location']?.toString() ?? '';
      } catch (e) {
        selectedLocation = '';
      }
    }

    if (selectedLocation.isEmpty) return [];

    // الحصول على الكورسات لهذا الموقع
    final locationCourses = _locationCourses[selectedLocation] ?? [];
    
    // فلترة الكورسات المفعلة لهذا الفصل
    final classCourses = _classCourseStatus[_selectedClassId] ?? {};
    
    return locationCourses.where((course) {
      final courseId = course['id']?.toString() ?? '';
      return classCourses[courseId]?['enabled'] == true;
    }).toList();
  }

  Future<void> _updateAmountForSelectedCourse() async {
    if (_selectedClassId.isEmpty || _selectedCourse.isEmpty) {
      _amountController.clear();
      return;
    }

    final classCourses = _classCourseStatus[_selectedClassId] ?? {};
    final courseStatus = classCourses[_selectedCourse];

    if (courseStatus == null || courseStatus['enabled'] != true) {
      _amountController.clear();
      return;
    }

    final amount = courseStatus['amount'] ?? 0;
    final dueInt = (amount is int) ? amount : int.tryParse(amount.toString()) ?? 0;

    final studentId = int.tryParse(_selectedStudentId);
    if (studentId == null) {
      // إذا لم يتم اختيار طالب بعد، اعرض المبلغ الكلي مؤقتاً
      _amountController.text = _formatAmount(dueInt.toDouble());
      return;
    }

    try {
      final totalPaid = await _dbHelper.getTotalPaidByStudentAndCourse(
        studentId: studentId,
        courseId: _selectedCourse,
      );

      final remaining = (dueInt - totalPaid).clamp(0, 1 << 30);
      if (!mounted) return;
      _amountController.text = _formatAmount(remaining.toDouble());
    } catch (_) {
      // fallback
      if (!mounted) return;
      _amountController.text = _formatAmount(dueInt.toDouble());
    }
  }
}

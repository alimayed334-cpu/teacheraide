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
import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'student_financial_details_screen.dart';

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

enum _InfoNotesStatusKind {
  neverPaid,
  regular,
  late,
  paidLate,
}

class _InfoNotesStudentStatus {
  final _InfoNotesStatusKind kind;
  final String label;
  final Color color;
  final bool isSmall;

  const _InfoNotesStudentStatus({
    required this.kind,
    required this.label,
    required this.color,
    required this.isSmall,
  });
}

class _InstallmentComputed {
  final int installmentNo;
  final int dueAmount;
  final String dueDate;
  final int paidSum;
  final int remaining;
  final int paymentsCount;
  final String completionDate;
  final int? daysLate;
  final bool isComplete;
  final bool isLateNow;
  final bool completedLate;

  const _InstallmentComputed({
    required this.installmentNo,
    required this.dueAmount,
    required this.dueDate,
    required this.paidSum,
    required this.remaining,
    required this.paymentsCount,
    required this.completionDate,
    required this.daysLate,
    required this.isComplete,
    required this.isLateNow,
    required this.completedLate,
  });
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
  int _expectedRemainingRevenue = 0;
  int _discountedStudentsCount = 0;
  int _currentCash = 0;
  int _totalCashWithdrawals = 0;
  int _totalCashIncomes = 0;
  List<Map<String, dynamic>> _cashWithdrawalsRows = [];
  List<Map<String, dynamic>> _cashIncomesRows = [];
  String _dashboardSelectedLocation = 'all';
  List<Map<String, dynamic>> _monthlyRevenue = [];
  bool _isLoading = true;
  int _selectedTabIndex = 0;

  // متغيرات البحث والتصفية لسجل الدفعات
  final TextEditingController _paymentSearchController = TextEditingController();
  String _selectedPaymentLocation = 'all';
  String _selectedPaymentCourse = 'all';
  String _selectedPaymentClassId = 'all';
  int _selectedPaymentPlanId = 0;
  String _selectedPaymentPlanName = '';
  int _selectedPaymentInstallmentNo = 0;
  Timer? _searchTimer;

  // متغيرات صفحة المتأخرين بالدفع
  final TextEditingController _latePaymentsSearchController = TextEditingController();
  String _latePaymentsSelectedLocation = 'all';
  String _latePaymentsSelectedCourseId = 'all';
  String _latePaymentsSelectedClassId = 'all';
  String _latePaymentsSelectedPlanName = '';
  int _latePaymentsSelectedInstallmentNo = 0;
  final Map<String, DateTime?> _latePaymentsDueDatesByCourseId = {};
  final Map<String, DateTime?> _latePaymentsDueDatesByClassCourseKey = {};
  final ScrollController _latePaymentsVerticalScrollController = ScrollController();
  final ScrollController _latePaymentsHorizontalScrollController = ScrollController();
  List<Map<String, dynamic>> _latePaymentsRows = [];
  bool _latePaymentsDidInitialLoad = false;

  Future<List<Map<String, dynamic>>> _getLatePlanOptionsForClassFilter() async {
    final classIdFilter = _latePaymentsSelectedClassId;
    final classIds = <int>[];
    if (classIdFilter != 'all') {
      final id = int.tryParse(classIdFilter);
      if (id != null) classIds.add(id);
    } else {
      for (final c in _classes) {
        final id = int.tryParse(c['id']?.toString() ?? '');
        if (id != null) classIds.add(id);
      }
    }

    final plans = <Map<String, dynamic>>[];
    for (final cid in classIds.toSet()) {
      plans.addAll(await _dbHelper.getClassTuitionPlans(cid));
    }

    final uniq = <int, Map<String, dynamic>>{};
    for (final p in plans) {
      final id = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
      if (id > 0) uniq[id] = p;
    }
    final list = uniq.values.toList();
    list.sort((a, b) {
      final ca = int.tryParse(a['class_id']?.toString() ?? '') ?? 0;
      final cb = int.tryParse(b['class_id']?.toString() ?? '') ?? 0;
      if (ca != cb) return ca.compareTo(cb);
      final na = a['name']?.toString() ?? '';
      final nb = b['name']?.toString() ?? '';
      return na.compareTo(nb);
    });
    return list;
  }

  // متغيرات استلام القسط
  final TextEditingController _studentNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  bool _studentSelectedFromSuggestions = false;
  bool _suppressStudentNameOnChanged = false;
  String _selectedStudentId = '';
  String _selectedClassId = '';
  String _selectedLocation = '';
  String _selectedCourse = '';
  int _selectedTuitionPlanId = 0;
  int _selectedTuitionInstallmentNo = 0;
  List<Map<String, dynamic>> _tuitionPlansForClass = [];
  List<Map<String, dynamic>> _tuitionInstallmentsForPlan = [];
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

  String _pricingPageClassFilterId = 'all';
  String _pricingActiveClassId = 'all';
  int _pricingActivePlanId = 0;
  final Map<String, int> _pricingSelectedPlanByClassId = {};
  List<Map<String, dynamic>> _pricingPlansForClass = [];
  List<Map<String, dynamic>> _pricingInstallmentsForPlan = [];
  List<Map<String, dynamic>> _pricingStudentsForClass = [];
  Map<int, Map<int, Map<String, dynamic>>> _pricingOverridesByStudentInstallment = {};

  Future<void> _loadPricingPlansForSelectedClass() async {
    final cid = int.tryParse(_pricingActiveClassId);
    if (cid == null || cid <= 0) {
      if (!mounted) return;
      setState(() {
        _pricingPlansForClass = [];
        _pricingActivePlanId = 0;
        _pricingInstallmentsForPlan = [];
        _pricingStudentsForClass = [];
        _pricingOverridesByStudentInstallment = {};
      });
      return;
    }

    final plans = await _dbHelper.getClassTuitionPlans(cid);
    if (!mounted) return;
    setState(() {
      _pricingPlansForClass = plans;
      if (_pricingActivePlanId != 0) {
        final ids = plans
            .map((p) => (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0)
            .where((id) => id > 0)
            .toSet();
        if (!ids.contains(_pricingActivePlanId)) {
          _pricingActivePlanId = 0;
        }
      }
    });
    await _loadPricingDataForSelectedPlan();
  }

  Future<void> _loadPricingDataForSelectedPlan() async {
    final planId = _pricingActivePlanId;
    final classId = int.tryParse(_pricingActiveClassId);
    if (planId <= 0 || classId == null || classId <= 0) {
      if (!mounted) return;
      setState(() {
        _pricingInstallmentsForPlan = [];
        _pricingStudentsForClass = [];
        _pricingOverridesByStudentInstallment = {};
      });
      return;
    }

    final installments = await _dbHelper.getTuitionPlanInstallments(planId);
    final students = _students
        .where((s) => (s['classId']?.toString() ?? '') == classId.toString())
        .toList();
    final studentIds = students
        .map((s) => int.tryParse(s['id']?.toString() ?? ''))
        .whereType<int>()
        .toList();

    final overrides = await _dbHelper.getStudentTuitionOverridesMap(
      planId: planId,
      studentIds: studentIds,
    );

    if (!mounted) return;
    setState(() {
      _pricingInstallmentsForPlan = installments;
      _pricingStudentsForClass = students;
      _pricingOverridesByStudentInstallment = overrides;
    });
  }

  List<Map<String, dynamic>> _classes = [];

  final TextEditingController _installmentsSearchController = TextEditingController();
  String _installmentsSelectedLocation = 'جميع المواقع';
  String _installmentsSelectedClass = 'جميع الفصول';
  String _installmentsSelectedCourseId = 'الكل';
  int _installmentsSelectedPlanId = 0;
  String _installmentsSelectedPlanName = '';
  int _installmentsSelectedInstallmentNo = 0;
  int _installmentsSelectedPaymentIndex = 0;
  List<int> _installmentsPaymentIndexOptions = [];
  bool _installmentsIsLoading = false;
  List<Map<String, dynamic>> _installmentsRows = [];
  int _installmentsTotalDue = 0;
  int _installmentsTotalPaid = 0;
  int _installmentsTotalRemaining = 0;

  Future<List<Map<String, dynamic>>> _getInstallmentsPlanOptionsForClassFilter() async {
    final classFilter = _installmentsSelectedClass;
    final classIds = <int>[];
    if (classFilter != 'جميع الفصول') {
      try {
        final c = _classes.firstWhere((x) => (x['name']?.toString() ?? '') == classFilter);
        final id = int.tryParse(c['id']?.toString() ?? '');
        if (id != null) classIds.add(id);
      } catch (_) {}
    } else {
      for (final c in _classes) {
        final id = int.tryParse(c['id']?.toString() ?? '');
        if (id != null) classIds.add(id);
      }
    }

    final plans = <Map<String, dynamic>>[];
    for (final cid in classIds.toSet()) {
      final p = await _dbHelper.getClassTuitionPlans(cid);
      plans.addAll(p);
    }

    final uniq = <int, Map<String, dynamic>>{};
    for (final p in plans) {
      final id = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
      if (id > 0) uniq[id] = p;
    }
    final list = uniq.values.toList();
    list.sort((a, b) {
      final ca = int.tryParse(a['class_id']?.toString() ?? '') ?? 0;
      final cb = int.tryParse(b['class_id']?.toString() ?? '') ?? 0;
      if (ca != cb) return ca.compareTo(cb);
      final na = a['name']?.toString() ?? '';
      final nb = b['name']?.toString() ?? '';
      return na.compareTo(nb);
    });
    return list;
  }

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

  Future<void> _exportPricingTablePdf({
    required int classId,
    required String className,
    required int planId,
    required String planName,
  }) async {
    try {
      if (planId <= 0) return;

      final students = _students.where((s) => (s['classId']?.toString() ?? '') == classId.toString()).toList();
      final studentIds = students.map((s) => int.tryParse(s['id']?.toString() ?? '')).whereType<int>().toList();

      final installmentsRaw = await _dbHelper.getTuitionPlanInstallments(planId);
      final installments = installmentsRaw
          .map((i) => {
                ...i,
                'installment_no': (i['installment_no'] is int)
                    ? i['installment_no'] as int
                    : int.tryParse(i['installment_no']?.toString() ?? '') ?? 0,
                'amount': (i['amount'] is int) ? i['amount'] as int : int.tryParse(i['amount']?.toString() ?? '') ?? 0,
              })
          .where((i) => (i['installment_no'] as int) > 0)
          .toList();
      installments.sort((a, b) => (a['installment_no'] as int).compareTo(b['installment_no'] as int));
      final installmentNos = installments.map((i) => i['installment_no'] as int).toList();

      final overrides = await _dbHelper.getStudentTuitionOverridesMap(
        planId: planId,
        studentIds: studentIds,
      );

      int effectiveAmountForStudentInstallment(int studentId, int installmentNo) {
        final o = overrides[studentId]?[installmentNo];
        final raw = o?['amount'];
        final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
        if (oa != null && oa > 0) return oa;
        for (final inst in installments) {
          if ((inst['installment_no'] as int) != installmentNo) continue;
          return inst['amount'] as int;
        }
        return 0;
      }

      String dueDateForStudentInstallment(int studentId, int installmentNo) {
        final o = overrides[studentId]?[installmentNo];
        final od = o?['due_date']?.toString().trim() ?? '';
        if (od.isNotEmpty) return od;
        for (final inst in installments) {
          if ((inst['installment_no'] as int) != installmentNo) continue;
          return inst['due_date']?.toString() ?? '';
        }
        return '';
      }

      String discountReasonForStudent(int studentId) {
        final byNo = overrides[studentId];
        if (byNo == null) return '';
        for (final n in installmentNos) {
          final r = byNo[n]?['reason']?.toString() ?? '';
          if (r.trim().isNotEmpty) return r.trim();
        }
        return '';
      }

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

      pw.Widget cell(String text, {bool header = false}) {
        return pw.Padding(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            text,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              font: header ? arabicBold : arabicFont,
              fontFallback: [fallbackFont],
              fontSize: header ? 9 : 9,
              color: header ? PdfColor.fromInt(0xFFFEC619) : PdfColor.fromInt(0xFF000000),
            ),
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat.a4,
          build: (context) {
            final rows = <pw.TableRow>[];

            rows.add(
              pw.TableRow(
                decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF2A2A2A)),
                children: [
                  cell('الطالب', header: true),
                  cell('سبب التخفيض', header: true),
                  cell('المبلغ الكلي', header: true),
                  ...installmentNos.map((n) => cell('دفعة $n', header: true)),
                ],
              ),
            );

            for (final s in students) {
              final sid = int.tryParse(s['id']?.toString() ?? '') ?? 0;
              final name = s['name']?.toString() ?? '';

              int total = 0;
              for (final n in installmentNos) {
                total += effectiveAmountForStudentInstallment(sid, n);
              }

              rows.add(
                pw.TableRow(
                  children: [
                    cell(name),
                    cell(discountReasonForStudent(sid)),
                    cell(_formatIqd(total)),
                    ...installmentNos.map((n) {
                      final amount = effectiveAmountForStudentInstallment(sid, n);
                      final date = dueDateForStudentInstallment(sid, n).trim();
                      final value = date.isNotEmpty ? '$date\n${_formatIqd(amount)}' : _formatIqd(amount);
                      return cell(value);
                    }),
                  ],
                ),
              );
            }

            return [
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'إضافة الأسعار',
                      style: pw.TextStyle(
                        font: arabicBold,
                        fontSize: 18,
                        color: PdfColor.fromInt(0xFF000000),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'الفصل: $className - القسط: $planName',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 11,
                        color: PdfColor.fromInt(0xFF555555),
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 1),
                      children: rows,
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      final bytes = await doc.save();

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final safeClass = className.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final safePlan = planName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final filename = 'اضافة_الاسعار_${dateStr}_${safeClass}_${safePlan}.pdf';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
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

  final List<String> _tabTitles = [
    'المعلومات المالية',
    'استلام دفعة',
    'إدارة الأقساط',
    'المتأخرين بالدفع',
    'سجل الدفعات',
    'إضافة الأسعار',
    'معلومات وملاحظات',
    'الصادرات',
    'الواردات',
  ];

  String _infoNotesSelectedClassId = 'all';
  int _infoNotesSelectedPlanId = 0;
  String _infoNotesSelectedPlanName = '';

  bool _infoNotesAutoPlanSelected = false;

  bool _infoNotesIsLoading = false;
  List<Map<String, dynamic>> _infoNotesPlanInstallments = [];
  Map<int, List<Map<String, dynamic>>> _infoNotesInstallmentsByPlanId = {};
  Map<int, int> _infoNotesPlanIdByStudentId = {};
  Set<String> _infoNotesVisibleClassIds = {};
  Map<int, Map<int, Map<String, dynamic>>> _infoNotesOverridesByStudentInstallment = {};
  Map<int, String> _infoNotesDiscountReasonByStudentId = {};
  Map<int, String> _infoNotesLatestNoteByStudentId = {};
  Map<int, List<Map<String, dynamic>>> _infoNotesPaymentsByStudentId = {};

  bool _infoNotesDialogOpen = false;

  final Map<int, _InfoNotesStudentStatus> _infoNotesStatusByStudentId = {};

  String _shorten(String text, {int max = 22}) {
    final t = text.trim();
    if (t.isEmpty) return '';
    if (t.length <= max) return t;
    return '${t.substring(0, max)}...';
  }

  Future<void> _loadInfoNotesData() async {
    final classId = int.tryParse(_infoNotesSelectedClassId);
    final planId = _infoNotesSelectedPlanId;
    if ((_infoNotesSelectedClassId != 'all' && (classId == null || classId <= 0 || _infoNotesSelectedPlanName.trim().isEmpty)) ||
        (_infoNotesSelectedClassId == 'all' && _infoNotesSelectedPlanName.trim().isEmpty)) {
      if (!mounted) return;
      setState(() {
        _infoNotesIsLoading = false;
        _infoNotesPlanInstallments = [];
        _infoNotesInstallmentsByPlanId = {};
        _infoNotesPlanIdByStudentId = {};
        _infoNotesVisibleClassIds = {};
        _infoNotesOverridesByStudentInstallment = {};
        _infoNotesDiscountReasonByStudentId = {};
        _infoNotesLatestNoteByStudentId = {};
        _infoNotesPaymentsByStudentId = {};
        _infoNotesStatusByStudentId.clear();
      });
      return;
    }

    final visibleClasses = _infoNotesVisibleClasses();
    final studentIds = <int>[];
    final planIdByStudentId = <int, int>{};
    final classIdByStudentId = <int, int>{};
    final visibleClassIds = <String>{};

    for (final c in visibleClasses) {
      final cid = int.tryParse(c['id']?.toString() ?? '');
      if (cid == null || cid <= 0) continue;

      int effectivePlanId = planId;
      final plans = await _dbHelper.getClassTuitionPlans(cid);
      if (_infoNotesSelectedPlanName.trim().isNotEmpty) {
        final match = plans.firstWhere(
          (p) => (p['name']?.toString().trim() ?? '') == _infoNotesSelectedPlanName.trim(),
          orElse: () => const <String, dynamic>{},
        );
        effectivePlanId = (match['id'] is int) ? match['id'] as int : int.tryParse(match['id']?.toString() ?? '') ?? 0;
      }

      if (effectivePlanId <= 0) continue;

      final students = _studentsForClassId(cid.toString());
      for (final s in students) {
        final sid = int.tryParse(s['id']?.toString() ?? '');
        if (sid == null || sid <= 0) continue;
        studentIds.add(sid);
        planIdByStudentId[sid] = effectivePlanId;
        classIdByStudentId[sid] = cid;
      }

      if (effectivePlanId > 0) {
        visibleClassIds.add(cid.toString());
      }
    }

    if (!mounted) return;
    setState(() {
      _infoNotesIsLoading = true;
      _infoNotesVisibleClassIds = visibleClassIds;
    });

    try {
      final installmentsByPlanId = <int, List<Map<String, dynamic>>>{};
      final overridesByStudentInstallment = <int, Map<int, Map<String, dynamic>>>{};
      final discountReasonByStudentId = <int, String>{};
      final latestNoteByStudentId = <int, String>{};
      final paymentsByStudent = <int, List<Map<String, dynamic>>>{};
      final statusByStudent = <int, _InfoNotesStudentStatus>{};
      final now = DateTime.now();

      final planIdsToLoad = planIdByStudentId.values.toSet().where((x) => x > 0).toList();
      planIdsToLoad.sort();

      for (final pid in planIdsToLoad) {
        final idsForPlan = planIdByStudentId.entries.where((e) => e.value == pid).map((e) => e.key).toList();
        if (idsForPlan.isEmpty) continue;

        final installments = await _dbHelper.getTuitionPlanInstallments(pid);
        installmentsByPlanId[pid] = installments;

        final overrides = await _dbHelper.getStudentTuitionOverridesMap(
          planId: pid,
          studentIds: idsForPlan,
        );
        for (final e in overrides.entries) {
          overridesByStudentInstallment[e.key] = e.value;
        }

        final reasons = await _dbHelper.getStudentPlanDiscountReasonsMap(
          planId: pid,
          studentIds: idsForPlan,
        );
        discountReasonByStudentId.addAll(reasons);

        final notes = await _dbHelper.getLatestStudentFinancialNotesMap(
          planId: pid,
          studentIds: idsForPlan,
        );
        latestNoteByStudentId.addAll(notes);

        final payments = await _dbHelper.getTuitionPaymentsForStudentsPlan(
          planId: pid,
          studentIds: idsForPlan,
        );
        for (final p in payments) {
          final sid = (p['student_id'] is int) ? p['student_id'] as int : int.tryParse(p['student_id']?.toString() ?? '');
          if (sid == null) continue;
          (paymentsByStudent[sid] ??= <Map<String, dynamic>>[]).add(p);
        }
      }

      int _dueAmountFor(int studentId, int installmentNo) {
        final pid = planIdByStudentId[studentId] ?? 0;
        final installments = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
        final o = overridesByStudentInstallment[studentId]?[installmentNo];
        final raw = o?['amount'];
        final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
        if (oa != null && oa > 0) return oa;
        for (final inst in installments) {
          final n = (inst['installment_no'] is int)
              ? inst['installment_no'] as int
              : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
          if (n != installmentNo) continue;
          final a = (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
          return a;
        }
        return 0;
      }

      String _dueDateFor(int studentId, int installmentNo) {
        final pid = planIdByStudentId[studentId] ?? 0;
        final installments = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
        final o = overridesByStudentInstallment[studentId]?[installmentNo];
        final od = o?['due_date']?.toString().trim() ?? '';
        if (od.isNotEmpty) return od;
        for (final inst in installments) {
          final n = (inst['installment_no'] is int)
              ? inst['installment_no'] as int
              : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
          if (n != installmentNo) continue;
          return inst['due_date']?.toString() ?? '';
        }
        return '';
      }

      _InstallmentComputed _computeInstallment({
        required int studentId,
        required int installmentNo,
      }) {
        final dueAmount = _dueAmountFor(studentId, installmentNo);
        final dueDateStr = _dueDateFor(studentId, installmentNo);
        final dueDate = DateTime.tryParse(dueDateStr);

        final studentPayments = paymentsByStudent[studentId] ?? const <Map<String, dynamic>>[];
        final instPayments = studentPayments.where((p) {
          final ino = (p['installment_no'] is int) ? p['installment_no'] as int : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
          return ino == installmentNo;
        }).toList();

        int paidSum = 0;
        int count = 0;
        DateTime? completionDate;
        for (final p in instPayments) {
          final amt = (p['paid_amount'] is int) ? p['paid_amount'] as int : int.tryParse(p['paid_amount']?.toString() ?? '') ?? 0;
          paidSum += amt;
          count++;
          if (completionDate == null && dueAmount > 0 && paidSum >= dueAmount) {
            completionDate = DateTime.tryParse(p['payment_date']?.toString() ?? '');
          }
          if (completionDate != null && dueAmount > 0 && paidSum >= dueAmount) {
            // keep last completion date when still >= due
            final d = DateTime.tryParse(p['payment_date']?.toString() ?? '');
            if (d != null) completionDate = d;
          }
        }

        final remaining = (dueAmount - paidSum) > 0 ? (dueAmount - paidSum) : 0;
        final isComplete = dueAmount > 0 && paidSum >= dueAmount;

        int? daysLate;
        if (dueDate != null) {
          final ref = isComplete ? (completionDate ?? now) : now;
          final diffDays = ref.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
          if (diffDays > 0 && (!isComplete || (completionDate != null && completionDate!.isAfter(dueDate)))) {
            daysLate = diffDays;
          }
        }

        final completedLate = isComplete && daysLate != null && daysLate > 0;
        final isLateNow = !isComplete && daysLate != null && daysLate > 0;

        return _InstallmentComputed(
          installmentNo: installmentNo,
          dueAmount: dueAmount,
          dueDate: dueDateStr,
          paidSum: paidSum,
          remaining: remaining,
          paymentsCount: count,
          completionDate: completionDate == null ? '' : DateFormat('yyyy-MM-dd').format(completionDate!),
          daysLate: daysLate,
          isComplete: isComplete,
          isLateNow: isLateNow,
          completedLate: completedLate,
        );
      }

      for (final sid in studentIds.toSet()) {
        final pid = planIdByStudentId[sid] ?? 0;
        final installments = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
        final installmentNos = installments
            .map((r) => (r['installment_no'] is int) ? r['installment_no'] as int : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0)
            .where((n) => n > 0)
            .toList();
        installmentNos.sort();

        if (installmentNos.isEmpty) {
          statusByStudent[sid] = _InfoNotesStudentStatus(
            kind: _InfoNotesStatusKind.regular,
            label: 'منتظم',
            color: Colors.green,
            isSmall: false,
          );
          continue;
        }

        // الحالة تعتمد على "الدفعة الحالية" = أول دفعة غير مكتملة.
        // - إذا الدفعة الحالية متأخرة => متأخر
        // - إذا الدفعة الحالية غير مكتملة لكنها ليست متأخرة => منتظم (غير منتهي)
        // - إذا لا توجد دفعات غير مكتملة (كلها مكتملة): إذا أي دفعة اكتملت متأخر => تم الدفع متأخر وإلا منتظم

        int firstUnfinished = 0;
        _InstallmentComputed? current;
        for (final n in installmentNos) {
          final c = _computeInstallment(studentId: sid, installmentNo: n);
          if (!c.isComplete) {
            firstUnfinished = n;
            current = c;
            break;
          }
        }

        bool anyCompletedLate = false;
        for (final n in installmentNos) {
          final c = _computeInstallment(studentId: sid, installmentNo: n);
          if (c.completedLate) {
            anyCompletedLate = true;
            break;
          }
        }

        if (firstUnfinished > 0 && current != null) {
          if (current.isLateNow) {
            statusByStudent[sid] = _InfoNotesStudentStatus(
              kind: _InfoNotesStatusKind.late,
              label: 'متأخر',
              color: Colors.redAccent,
              isSmall: false,
            );
          } else if (anyCompletedLate && current.paymentsCount == 0) {
            statusByStudent[sid] = _InfoNotesStudentStatus(
              kind: _InfoNotesStatusKind.paidLate,
              label: 'تم الدفع متأخر',
              color: Colors.orangeAccent,
              isSmall: false,
            );
          } else {
            statusByStudent[sid] = _InfoNotesStudentStatus(
              kind: _InfoNotesStatusKind.regular,
              label: 'منتظم (غير منتهي)',
              color: Colors.green,
              isSmall: true,
            );
          }
          continue;
        }

        if (anyCompletedLate) {
          statusByStudent[sid] = _InfoNotesStudentStatus(
            kind: _InfoNotesStatusKind.paidLate,
            label: 'تم الدفع متأخر',
            color: Colors.orangeAccent,
            isSmall: false,
          );
        } else {
          statusByStudent[sid] = _InfoNotesStudentStatus(
            kind: _InfoNotesStatusKind.regular,
            label: 'منتظم',
            color: Colors.green,
            isSmall: false,
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _infoNotesInstallmentsByPlanId = installmentsByPlanId;
        _infoNotesPlanIdByStudentId = planIdByStudentId;
        _infoNotesVisibleClassIds = visibleClassIds;
        _infoNotesPlanInstallments = (_infoNotesSelectedClassId != 'all') ? (installmentsByPlanId[planId] ?? const <Map<String, dynamic>>[]) : const <Map<String, dynamic>>[];
        _infoNotesOverridesByStudentInstallment = overridesByStudentInstallment;
        _infoNotesDiscountReasonByStudentId = discountReasonByStudentId;
        _infoNotesLatestNoteByStudentId = latestNoteByStudentId;
        _infoNotesPaymentsByStudentId = paymentsByStudent;
        _infoNotesStatusByStudentId
          ..clear()
          ..addAll(statusByStudent);
        _infoNotesIsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _infoNotesIsLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadFinancialData();
    // عند فتح الصفحة لأول مرة: إذا كنت على تبويب المعلومات المالية فعّل التحديث التلقائي
    _startDashboardAutoRefresh();
  }

  Future<void> _loadCashTabsData() async {
    final withdrawals = await _dbHelper.getCashWithdrawals();
    final incomes = await _dbHelper.getCashIncomes();
    final totalWithdraw = await _dbHelper.getTotalCashWithdrawalsAmount();
    final totalIncome = await _dbHelper.getTotalCashIncomesAmount();
    final totalStudentPayments = await _dbHelper.getTotalTuitionPaymentsAmount();

    if (!mounted) return;
    setState(() {
      _cashWithdrawalsRows = withdrawals;
      _cashIncomesRows = incomes;
      _totalCashWithdrawals = totalWithdraw;
      _totalCashIncomes = totalIncome;
      _currentCash = totalStudentPayments + totalIncome - totalWithdraw;
    });
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

    final selectedClassId = _dashboardSelectedLocation;
    final isAll = selectedClassId == 'all';
    final filteredStudents = _students.where((s) {
      final cid = s['classId']?.toString() ?? '';
      return isAll || cid == selectedClassId;
    }).toList();

    final totalStudents = filteredStudents.length;

    final classIdFilter = !isAll ? int.tryParse(selectedClassId) : null;

    // الإيرادات المستلمة من جدول tuition_payments (حسب فلتر الفصل)
    final receivedRevenue = await _dbHelper.getTotalTuitionPaymentsAmount(
      classId: classIdFilter,
    );

    // النقد الحالي (عام لا يتغير مع فلتر الفصل)
    final totalStudentPayments = await _dbHelper.getTotalTuitionPaymentsAmount();
    final totalWithdraw = await _dbHelper.getTotalCashWithdrawalsAmount();
    final totalIncome = await _dbHelper.getTotalCashIncomesAmount();

    // الإيرادات الشهرية (مدفوعات مستلمة) للرسم البياني
    final monthly = await _dbHelper.getMonthlyTuitionPaymentsTotals(
      classId: classIdFilter,
    );

    final studentIds = filteredStudents
        .map((s) => int.tryParse(s['id']?.toString() ?? ''))
        .whereType<int>()
        .toList();

    // الإيرادات المتوقعة (المتبقي) = مجموع المتبقي غير المدفوع (مع احتساب الدفع الجزئي + التخفيض)
    int expectedRevenue = 0;
    final discountedStudents = <int>{};
    if (filteredStudents.isNotEmpty) {
      final studentIdsByClassId = <int, List<int>>{};
      for (final s in filteredStudents) {
        final cid = int.tryParse(s['classId']?.toString() ?? '');
        final sid = int.tryParse(s['id']?.toString() ?? '');
        if (cid == null || cid <= 0 || sid == null || sid <= 0) continue;
        (studentIdsByClassId[cid] ??= []).add(sid);
      }

      final classIds = <int>[];
      if (!isAll) {
        final cid = int.tryParse(selectedClassId);
        if (cid != null && cid > 0) classIds.add(cid);
      } else {
        classIds.addAll(studentIdsByClassId.keys);
      }

      for (final cid in classIds.toSet()) {
        final classStudentIds = studentIdsByClassId[cid] ?? const <int>[];
        if (classStudentIds.isEmpty) continue;

        final plans = await _dbHelper.getClassTuitionPlans(cid);
        for (final p in plans) {
          final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
          if (pid <= 0) continue;

          final installments = await _dbHelper.getTuitionPlanInstallments(pid);
          if (installments.isEmpty) continue;

          final baseAmounts = <int, int>{};
          for (final inst in installments) {
            final no = (inst['installment_no'] is int)
                ? inst['installment_no'] as int
                : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
            final amount = (inst['amount'] is int)
                ? inst['amount'] as int
                : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
            if (no > 0 && amount > 0) baseAmounts[no] = amount;
          }
          if (baseAmounts.isEmpty) continue;

          final overrides = await _dbHelper.getStudentTuitionOverridesMap(
            planId: pid,
            studentIds: classStudentIds,
          );

          final payments = await _dbHelper.getTuitionPaymentsForStudentsPlan(
            planId: pid,
            studentIds: classStudentIds,
          );

          final paidByStudentNo = <int, Map<int, int>>{};
          for (final pay in payments) {
            final sid = (pay['student_id'] is int) ? pay['student_id'] as int : int.tryParse(pay['student_id']?.toString() ?? '') ?? 0;
            final no = (pay['installment_no'] is int) ? pay['installment_no'] as int : int.tryParse(pay['installment_no']?.toString() ?? '') ?? 0;
            if (sid <= 0 || no <= 0) continue;
            final amt = (pay['paid_amount'] is int) ? pay['paid_amount'] as int : int.tryParse(pay['paid_amount']?.toString() ?? '') ?? 0;
            (paidByStudentNo[sid] ??= <int, int>{})[no] = (paidByStudentNo[sid]?[no] ?? 0) + amt;
          }

          for (final sid in classStudentIds) {
            final byNo = overrides[sid] ?? const <int, Map<String, dynamic>>{};
            bool hasAmountDiscount = false;
            for (final e in baseAmounts.entries) {
              final ovr = byNo[e.key];
              final raw = ovr?['amount'];
              final int? oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
              final amount = (oa != null && oa > 0) ? oa : e.value;
              if (oa != null && oa > 0 && oa != e.value) {
                hasAmountDiscount = true;
              }
              if (amount <= 0) continue;
              final paid = paidByStudentNo[sid]?[e.key] ?? 0;
              final remaining = (amount - paid).clamp(0, 1 << 30);
              if (remaining > 0) expectedRevenue += remaining;
            }

            if (hasAmountDiscount) discountedStudents.add(sid);
          }
        }
      }
    }

    // عدد المتأخرين بالدفع: احسبه حسب فصل الطالب أيضاً لتجنب إدخال طلاب غير تابعين للخطة
    final lateStudents = <int>{};
    if (filteredStudents.isNotEmpty) {
      final studentIdsByClassId = <int, List<int>>{};
      for (final s in filteredStudents) {
        final cid = int.tryParse(s['classId']?.toString() ?? '');
        final sid = int.tryParse(s['id']?.toString() ?? '');
        if (cid == null || cid <= 0 || sid == null || sid <= 0) continue;
        (studentIdsByClassId[cid] ??= []).add(sid);
      }

      final classIds = <int>[];
      if (!isAll) {
        final cid = int.tryParse(selectedClassId);
        if (cid != null && cid > 0) classIds.add(cid);
      } else {
        classIds.addAll(studentIdsByClassId.keys);
      }

      for (final cid in classIds.toSet()) {
        final classStudentIds = studentIdsByClassId[cid] ?? const <int>[];
        if (classStudentIds.isEmpty) continue;

        final plans = await _dbHelper.getClassTuitionPlans(cid);
        for (final p in plans) {
          final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
          if (pid <= 0) continue;

          final late = await _dbHelper.getLateTuitionInstallmentsBatch(
            planId: pid,
            studentIds: classStudentIds,
          );
          for (final r in late) {
            final sid = (r['student_id'] is int)
                ? r['student_id'] as int
                : int.tryParse(r['student_id']?.toString() ?? '') ?? 0;
            if (sid > 0) lateStudents.add(sid);
          }
        }
      }
    }
    final lateCount = lateStudents.length;

    // جدول الإيرادات حسب الفصل
    final allClasses = _classes
        .map((c) => {
              'id': c['id']?.toString() ?? '',
              'name': c['name']?.toString() ?? '',
            })
        .where((c) => (c['id'] ?? '').toString().isNotEmpty)
        .toList();
    allClasses.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
    final stats = <Map<String, dynamic>>[];
    for (final c in allClasses) {
      final cid = int.tryParse(c['id'] ?? '');
      if (cid == null || cid <= 0) continue;
      if (!isAll && cid.toString() != selectedClassId) continue;
      final studentsCount = _students.where((s) => (s['classId']?.toString() ?? '') == cid.toString()).length;
      final totalPaid = await _dbHelper.getTotalTuitionPaymentsAmount(classId: cid);
      stats.add({
        'location': c['name'] ?? '',
        'students': studentsCount,
        'revenue': totalPaid,
      });
    }

    if (!mounted) return;
    setState(() {
      _totalStudents = totalStudents;
      _expectedRevenue = expectedRevenue;
      _expectedRemainingRevenue = expectedRevenue;
      _receivedRevenue = receivedRevenue;
      _receivedPayments = receivedRevenue; // لعرضه في حاوية الحالة أيضاً
      _firstInstallmentLate = lateCount; // إجمالي المتأخرين
      _secondInstallmentLate = 0;
      _monthlyRevenue = monthly;
      _locationStats = stats;
      _discountedStudentsCount = discountedStudents.length;

      _totalCashWithdrawals = totalWithdraw;
      _totalCashIncomes = totalIncome;
      _currentCash = totalStudentPayments + totalIncome - totalWithdraw;
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
    final query = _latePaymentsSearchController.text.trim().toLowerCase();

    final courses = allCourses.isEmpty ? await _dbHelper.getCourses() : allCourses;

    final rows = await _computeLatePaymentsRows(
      allCourses: courses,
      location: _latePaymentsSelectedLocation,
      courseId: _latePaymentsSelectedCourseId,
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
    final studentsFiltered = _students.where((s) {
      final name = s['name']?.toString().toLowerCase() ?? '';
      final matchesName = query.isEmpty || name.contains(query);
      if (!matchesName) return false;

      if (_latePaymentsSelectedClassId != 'all') {
        final cid = s['classId']?.toString() ?? '';
        if (cid != _latePaymentsSelectedClassId) return false;
      }

      // فلترة الموقع/الكورس (أفضل جهد حسب البيانات المتاحة في _students)
      if (location != 'all') {
        final studentLoc = s['location']?.toString() ?? '';
        if (studentLoc.isNotEmpty && studentLoc != location) return false;
      }
      if (courseId != 'all') {
        final studentCourse = s['course_id']?.toString() ?? '';
        if (studentCourse.isNotEmpty && studentCourse != courseId) return false;
      }
      return true;
    }).toList();

    final studentIds = studentsFiltered
        .map((s) => int.tryParse(s['id']?.toString() ?? ''))
        .whereType<int>()
        .toList();
    if (studentIds.isEmpty) return [];

    final selectedPlanName = _latePaymentsSelectedPlanName.trim();

    final classIdByStudentId = <int, int>{};
    for (final s in studentsFiltered) {
      final sid = int.tryParse(s['id']?.toString() ?? '');
      final cid = int.tryParse(s['classId']?.toString() ?? '');
      if (sid == null || sid <= 0 || cid == null || cid <= 0) continue;
      classIdByStudentId[sid] = cid;
    }

    final plansByClassId = <int, List<Map<String, dynamic>>>{};
    for (final cid in classIdByStudentId.values.toSet()) {
      plansByClassId[cid] = await _dbHelper.getClassTuitionPlans(cid);
    }

    final planNameById = <int, String>{};
    final studentIdsByPlanId = <int, List<int>>{};

    for (final e in classIdByStudentId.entries) {
      final sid = e.key;
      final cid = e.value;
      final plansForClass = plansByClassId[cid] ?? const <Map<String, dynamic>>[];

      for (final p in plansForClass) {
        final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
        if (pid <= 0) continue;
        final name = p['name']?.toString() ?? '';
        if (selectedPlanName.isNotEmpty && name.trim() != selectedPlanName) continue;
        planNameById[pid] = name;
        (studentIdsByPlanId[pid] ??= <int>[]).add(sid);
      }
    }

    if (studentIdsByPlanId.isEmpty) return [];

    final studentById = <int, Map<String, dynamic>>{};
    for (final s in studentsFiltered) {
      final sid = int.tryParse(s['id']?.toString() ?? '');
      if (sid != null) studentById[sid] = s;
    }

    final rows = <Map<String, dynamic>>[];
    for (final pid in studentIdsByPlanId.keys.toSet()) {
      final idsForPlan = (studentIdsByPlanId[pid] ?? const <int>[]).toSet().toList();
      if (idsForPlan.isEmpty) continue;

      final late = await _dbHelper.getLateTuitionInstallmentsBatch(
        planId: pid,
        studentIds: idsForPlan,
      );

      for (final r in late) {
        final sid = (r['student_id'] is int)
            ? r['student_id'] as int
            : int.tryParse(r['student_id']?.toString() ?? '') ?? 0;
        if (sid <= 0) continue;
        final student = studentById[sid];
        if (student == null) continue;

        final installmentNo = (r['installment_no'] is int)
            ? r['installment_no'] as int
            : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0;
        if (_latePaymentsSelectedInstallmentNo > 0 && installmentNo != _latePaymentsSelectedInstallmentNo) {
          continue;
        }

        final dueAmount = (r['due_amount'] is num)
            ? (r['due_amount'] as num).toInt()
            : int.tryParse(r['due_amount']?.toString() ?? '') ?? 0;
        final paidAmount = (r['paid_amount'] is num)
            ? (r['paid_amount'] as num).toInt()
            : int.tryParse(r['paid_amount']?.toString() ?? '') ?? 0;
        final remainingAmount = (r['remaining_amount'] is num)
            ? (r['remaining_amount'] as num).toInt()
            : int.tryParse(r['remaining_amount']?.toString() ?? '') ?? 0;
        if (remainingAmount <= 0) continue;

        final daysLate = (r['days_late'] is num)
            ? (r['days_late'] as num).toInt()
            : int.tryParse(r['days_late']?.toString() ?? '') ?? 0;
        if (daysLate <= 0) continue;

        rows.add({
          'studentId': sid,
          'studentName': student['name']?.toString() ?? '',
          'className': student['class_name']?.toString() ?? '',
          'planId': pid,
          'planName': planNameById[pid] ?? '',
          'installmentNo': installmentNo,
          'dueDate': r['due_date']?.toString() ?? '',
          'due': dueAmount,
          'paid': paidAmount,
          'remaining': remainingAmount,
          'daysLate': daysLate,
        });
      }
    }

    rows.sort((a, b) {
      final cn = (a['className']?.toString() ?? '').compareTo(b['className']?.toString() ?? '');
      if (cn != 0) return cn;
      final sn = (a['studentName']?.toString() ?? '').compareTo(b['studentName']?.toString() ?? '');
      if (sn != 0) return sn;
      final pa = int.tryParse(a['planId']?.toString() ?? '') ?? 0;
      final pb = int.tryParse(b['planId']?.toString() ?? '') ?? 0;
      if (pa != pb) return pa.compareTo(pb);
      final ia = int.tryParse(a['installmentNo']?.toString() ?? '') ?? 0;
      final ib = int.tryParse(b['installmentNo']?.toString() ?? '') ?? 0;
      return ia.compareTo(ib);
    });

    for (int i = 0; i < rows.length; i++) {
      rows[i]['index'] = i + 1;
    }

    return rows;
  }

  Future<void> _loadInstallmentsManagementData() async {
    if (_installmentsIsLoading) return;
    setState(() {
      _installmentsIsLoading = true;
    });

    try {
      final allStudents = List<Map<String, dynamic>>.from(_students);
      final query = _installmentsSearchController.text.trim().toLowerCase();
      final classFilter = _installmentsSelectedClass;

      final filteredStudents = allStudents.where((s) {
        final name = s['name']?.toString().toLowerCase() ?? '';
        final className = s['class_name']?.toString() ?? '';
        final matchesName = query.isEmpty || name.contains(query);
        final matchesClass = classFilter == 'جميع الفصول' || className == classFilter;
        return matchesName && matchesClass;
      }).toList();

      final selectedPlanName = _installmentsSelectedPlanName.trim();
      final selectedInstallmentNo = _installmentsSelectedInstallmentNo;
      final selectedPaymentIndex = 0;

      final studentIds = filteredStudents
          .map((s) => int.tryParse(s['id']?.toString() ?? ''))
          .whereType<int>()
          .toList();

      // حدد الأقساط (plans) التي سنحسبها
      final classIdByStudentId = <int, int>{};
      for (final s in filteredStudents) {
        final sid = int.tryParse(s['id']?.toString() ?? '');
        final cid = int.tryParse(s['classId']?.toString() ?? '');
        if (sid != null && cid != null) {
          classIdByStudentId[sid] = cid;
        }
      }

      final planIds = <int>{};
      final plansByClassId = <int, List<Map<String, dynamic>>>{};
      for (final cid in classIdByStudentId.values.toSet()) {
        final plans = await _dbHelper.getClassTuitionPlans(cid);
        plansByClassId[cid] = plans;
        for (final p in plans) {
          final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
          if (pid > 0) planIds.add(pid);
        }
      }

      final effectivePlanIds = <int>[];
      if (selectedPlanName.isNotEmpty) {
        for (final e in plansByClassId.entries) {
          for (final p in e.value) {
            final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
            if (pid <= 0) continue;
            if ((p['name']?.toString().trim() ?? '') == selectedPlanName) {
              effectivePlanIds.add(pid);
            }
          }
        }
      } else {
        effectivePlanIds.addAll(planIds);
      }

      final Map<int, int> paidByStudent = (effectivePlanIds.isEmpty || studentIds.isEmpty)
          ? <int, int>{}
          : await _dbHelper.getTotalPaidByStudentIdsForTuitionPlans(
              studentIds: studentIds,
              planIds: effectivePlanIds,
              installmentNo: selectedInstallmentNo > 0 ? selectedInstallmentNo : null,
            );

      // preload installments for plans + overrides map
      final installmentsByPlanId = <int, List<Map<String, dynamic>>>{};
      for (final pid in effectivePlanIds) {
        installmentsByPlanId[pid] = await _dbHelper.getTuitionPlanInstallments(pid);
      }
      final overridesByPlanStudent = await _dbHelper.getStudentTuitionOverridesMapForPlans(
        studentIds: studentIds,
        planIds: effectivePlanIds,
      );

      final paymentIndexOptions = const <int>[];
      final effectivePaymentIndex = 0;

      int totalDue = 0;
      int totalPaid = 0;
      int totalRemaining = 0;
      final rows = <Map<String, dynamic>>[];

      for (int i = 0; i < filteredStudents.length; i++) {
        final student = filteredStudents[i];
        final sid = int.tryParse(student['id']?.toString() ?? '');
        if (sid == null) continue;
        final name = student['name']?.toString() ?? '';
        final className = student['class_name']?.toString() ?? '';

        final classId = classIdByStudentId[sid] ?? int.tryParse(student['classId']?.toString() ?? '') ?? 0;
        final plansForClass = plansByClassId[classId] ?? const <Map<String, dynamic>>[];
        final studentPlanIds = <int>[];
        if (selectedPlanName.isNotEmpty) {
          for (final p in plansForClass) {
            final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
            if (pid <= 0) continue;
            if ((p['name']?.toString().trim() ?? '') == selectedPlanName) {
              studentPlanIds.add(pid);
            }
          }
        } else {
          for (final p in plansForClass) {
            final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
            if (pid > 0) studentPlanIds.add(pid);
          }
        }

        if (selectedInstallmentNo > 0) {
          bool hasSelectedInstallment = false;
          for (final pid in studentPlanIds) {
            final instList = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
            final has = instList.any((inst) {
              final no = (inst['installment_no'] is int)
                  ? inst['installment_no'] as int
                  : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
              return no == selectedInstallmentNo;
            });
            if (has) {
              hasSelectedInstallment = true;
              break;
            }
          }
          if (!hasSelectedInstallment) {
            continue;
          }
        }

        int due = 0;
        for (final pid in studentPlanIds) {
          final instList = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
          for (final inst in instList) {
            final no = (inst['installment_no'] is int)
                ? inst['installment_no'] as int
                : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
            if (no <= 0) continue;
            if (selectedInstallmentNo > 0 && no != selectedInstallmentNo) continue;

            final override = overridesByPlanStudent[pid]?[sid]?[no];
            final rawAmount = override?['amount'] ?? inst['amount'];
            final amount = (rawAmount is int) ? rawAmount : int.tryParse(rawAmount?.toString() ?? '') ?? 0;
            due += amount;
          }
        }

        int paid = 0;
        int remaining = 0;
        int dueToShow = due;

        paid = paidByStudent[sid] ?? 0;
        remaining = (due - paid).clamp(0, 1 << 30);

        totalDue += dueToShow;
        totalPaid += paid;
        totalRemaining += remaining;

        rows.add({
          'index': i + 1,
          'studentId': sid,
          'studentName': name,
          'className': className,
          'due': dueToShow,
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
        _installmentsPaymentIndexOptions = paymentIndexOptions;
        _installmentsSelectedPaymentIndex = 0;
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
    final fallbackFont = pw.Font.helvetica();

    final totalDue = _installmentsTotalDue;
    final totalPaid = _installmentsTotalPaid;
    final totalRemaining = _installmentsTotalRemaining;

    final String classTitle = _installmentsSelectedClass;
    final String planTitle = _installmentsSelectedPlanName.trim().isNotEmpty ? _installmentsSelectedPlanName : 'جميع الأقساط';
    final int instNo = _installmentsSelectedInstallmentNo;
    final int payIdx = 0;

    final String installmentTitle = instNo > 0 ? 'دفعة $instNo' : 'جميع الدفعات';
    final String paymentTitle = payIdx > 0 ? 'دفعة $payIdx' : 'جميع الدفعات';
    final String suffix = instNo > 0 ? (payIdx > 0 ? ' (دفعة $instNo - دفعة $payIdx)' : ' (دفعة $instNo)') : '';
    final bool isPaymentView = payIdx > 0;

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
            child: pw.DefaultTextStyle(
              style: pw.TextStyle(font: arabicFont, fontFallback: [fallbackFont]),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                pw.Text(
                  'إدارة الأقساط',
                  style: pw.TextStyle(
                    font: arabicBold,
                    fontSize: 18,
                    color: PdfColor.fromInt(0xFF000000),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'الفصل: $classTitle - القسط: $planTitle - $installmentTitle - $paymentTitle',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontFallback: [fallbackFont],
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
                            pw.Text('${isPaymentView ? 'سعر الدفعة' : 'القسط الكلي'}$suffix', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
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
                            pw.Text('${isPaymentView ? 'مدفوع الدفعة' : 'إجمالي المدفوعات'}$suffix', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
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
                            pw.Text('${isPaymentView ? 'متبقي الدفعة' : 'المبلغ المتبقي'}$suffix', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
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
                          child: pw.Text('الفصل', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${isPaymentView ? 'سعر الدفعة' : 'القسط الكلي'}$suffix', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${isPaymentView ? 'مدفوع الدفعة' : 'إجمالي المدفوعات'}$suffix', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${isPaymentView ? 'متبقي الدفعة' : 'المبلغ المتبقي'}$suffix', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: arabicBold, fontSize: 10)),
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
                            child: pw.Text(r['className']?.toString() ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
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
            ),
          );
        },
      ),
    );

    try {
      final bytes = await doc.save();
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final safeClass = classTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final safePlan = planTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final safeInst = installmentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final safePay = paymentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').replaceAll(' ', '_');
      final filename = 'ادارة_الاقساط_${dateStr}_${safeClass}_${safePlan}_${safeInst}_$safePay.pdf';
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes, flush: true);

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
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
    if (_suppressStudentNameOnChanged) return;
    if (value.isEmpty) {
      setState(() {
        _selectedStudentId = '';
        _selectedClassId = '';
        _selectedLocation = '';
        _studentSelectedFromSuggestions = false;
        _selectedTuitionPlanId = 0;
        _selectedTuitionInstallmentNo = 0;
        _tuitionPlansForClass = [];
        _tuitionInstallmentsForPlan = [];
        _amountController.clear();
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
        _selectedTuitionPlanId = 0;
        _selectedTuitionInstallmentNo = 0;
        _tuitionPlansForClass = [];
        _tuitionInstallmentsForPlan = [];
        _amountController.clear();
      });
      _loadTuitionPlansForSelectedClass();
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
      backgroundColor: const Color(0xFF1E1E1E),
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
        color: const Color(0xFF1E1E1E),
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
                _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
              }

              if (index == 5) {
                if (_pricingActiveClassId == 'all') {
                  try {
                    final first = _classes.firstWhere((c) => (c['id']?.toString() ?? '').isNotEmpty);
                    final firstId = first['id']?.toString() ?? 'all';
                    _pricingActiveClassId = firstId;
                    _pricingActivePlanId = _pricingSelectedPlanByClassId[firstId] ?? 0;
                  } catch (_) {}
                }
                _loadPricingPlansForSelectedClass();
              }

              if (index == 6) {
                _infoNotesAutoPlanSelected = false;
              }

              if (index == 7 || index == 8) {
                _loadCashTabsData();
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              decoration: BoxDecoration(
                border: isSelected
                    ? const Border(
                        bottom: BorderSide(color: Color(0xFFFEC619), width: 3),
                      )
                    : null,
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
      case 6:
        return _buildInfoNotes();
      case 7:
        return _buildCashWithdrawalsTab();
      case 8:
        return _buildCashIncomesTab();
      default:
        return _buildFinancialDashboard();
    }
  }

  List<Map<String, dynamic>> _infoNotesVisibleClasses() {
    if (_infoNotesSelectedClassId != 'all') {
      return _classes.where((c) => c['id']?.toString() == _infoNotesSelectedClassId).toList();
    }

    if (_infoNotesSelectedPlanName.trim().isEmpty) return _classes;
    if (_infoNotesVisibleClassIds.isEmpty) return _classes;

    return _classes.where((c) {
      final id = c['id']?.toString() ?? '';
      if (id.isEmpty) return false;
      return _infoNotesVisibleClassIds.contains(id);
    }).toList();
  }

  List<Map<String, dynamic>> _studentsForClassId(String classId) {
    return _students.where((s) => (s['classId']?.toString() ?? '') == classId).toList();
  }

  Widget _buildInfoNotes() {
    final classOptions = [
      'all',
      ...(_classes
          .map((c) => c['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          String an = '';
          String bn = '';
          try {
            an = _classes.firstWhere((c) => c['id']?.toString() == a)['name']?.toString() ?? '';
          } catch (_) {}
          try {
            bn = _classes.firstWhere((c) => c['id']?.toString() == b)['name']?.toString() ?? '';
          } catch (_) {}
          return an.compareTo(bn);
        }))
    ];

    final effectiveClass = classOptions.contains(_infoNotesSelectedClassId) ? _infoNotesSelectedClassId : 'all';
    if (effectiveClass != _infoNotesSelectedClassId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _infoNotesSelectedClassId = effectiveClass;
          _infoNotesSelectedPlanId = 0;
        });
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
            const Text(
              'معلومات وملاحظات',
              style: TextStyle(
                color: Color(0xFFFEC619),
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    value: effectiveClass,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'الفصل',
                      labelStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    items: classOptions.map((id) {
                      if (id == 'all') {
                        return const DropdownMenuItem<String>(
                          value: 'all',
                          child: Text('جميع الفصول'),
                        );
                      }
                      String name = id;
                      try {
                        name = _classes.firstWhere((c) => c['id']?.toString() == id)['name']?.toString() ?? id;
                      } catch (_) {}
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (!mounted) return;
                      setState(() {
                        _infoNotesSelectedClassId = v ?? 'all';
                        _infoNotesSelectedPlanId = 0;
                        _infoNotesSelectedPlanName = '';
                        _infoNotesAutoPlanSelected = false;
                      });
                      _loadInfoNotesData();
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: FutureBuilder<List<String>>(
                    future: () async {
                      final classIds = <int>[];
                      if (_infoNotesSelectedClassId == 'all') {
                        for (final c in _classes) {
                          final cid = int.tryParse(c['id']?.toString() ?? '');
                          if (cid != null && cid > 0) classIds.add(cid);
                        }
                      } else {
                        final cid = int.tryParse(_infoNotesSelectedClassId);
                        if (cid != null && cid > 0) classIds.add(cid);
                      }

                      final names = <String>{};
                      for (final cid in classIds.toSet()) {
                        final plans = await _dbHelper.getClassTuitionPlans(cid);
                        for (final p in plans) {
                          final n = p['name']?.toString().trim() ?? '';
                          if (n.isNotEmpty) names.add(n);
                        }
                      }
                      final list = names.toList()..sort();
                      return list;
                    }(),
                    builder: (context, snap) {
                      final list = snap.data ?? const <String>[];
                      final dropdownValue = list.contains(_infoNotesSelectedPlanName) ? _infoNotesSelectedPlanName : '';

                      if (!_infoNotesAutoPlanSelected && dropdownValue.trim().isEmpty && list.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() {
                            _infoNotesAutoPlanSelected = true;
                            _infoNotesSelectedPlanName = list.first;
                            _infoNotesSelectedPlanId = 0;
                          });
                          _loadInfoNotesData();
                        });
                      }

                      return DropdownButtonFormField<String>(
                        value: dropdownValue,
                        dropdownColor: const Color(0xFF2A2A2A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'القسط',
                          labelStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: const Color(0xFF2A2A2A),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('اختر القسط')),
                          ...list.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                        ],
                        onChanged: (v) {
                          if (!mounted) return;
                          setState(() {
                            _infoNotesSelectedPlanName = v ?? '';
                            _infoNotesSelectedPlanId = 0;
                            _infoNotesAutoPlanSelected = true;
                          });
                          _loadInfoNotesData();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_infoNotesSelectedPlanName.trim().isNotEmpty) ...[
              if (_infoNotesIsLoading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    color: Color(0xFFFEC619),
                    backgroundColor: Color(0xFF2A2A2A),
                    minHeight: 3,
                  ),
                ),
              ..._infoNotesVisibleClasses().map((c) {
              final classId = c['id']?.toString() ?? '';
              final className = c['name']?.toString() ?? '';
              final students = classId.isEmpty ? const <Map<String, dynamic>>[] : _studentsForClassId(classId);

              void showTextDialog({required String title, required String text}) {
                if (text.trim().isEmpty) return;
                showDialog<void>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      backgroundColor: const Color(0xFF2A2A2A),
                      title: Text(title, style: const TextStyle(color: Color(0xFFFEC619))),
                      content: SizedBox(
                        width: 520,
                        child: SingleChildScrollView(
                          child: Text(text, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                        ),
                      ],
                    );
                  },
                );
              }

              Future<void> showAddNoteDialog({
                required int studentId,
                required String studentName,
              }) async {
                if (_infoNotesDialogOpen) return;
                if (!mounted) return;
                int pid = _infoNotesSelectedClassId == 'all'
                    ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                    : _infoNotesSelectedPlanId;
                if (pid <= 0) {
                  await _loadInfoNotesData();
                  if (!mounted) return;
                  pid = _infoNotesSelectedClassId == 'all'
                      ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                      : _infoNotesSelectedPlanId;
                  if (pid <= 0) return;
                }
                final ctrl = TextEditingController();
                _infoNotesDialogOpen = true;
                try {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: const Color(0xFF2A2A2A),
                        title: Text(studentName, style: const TextStyle(color: Color(0xFFFEC619))),
                        content: SizedBox(
                          width: 520,
                          child: TextField(
                            controller: ctrl,
                            style: const TextStyle(color: Colors.white),
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: 'إضافة ملاحظة',
                              labelStyle: const TextStyle(color: Colors.grey),
                              filled: true,
                              fillColor: const Color(0xFF3A3A3A),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(color: Colors.grey.shade700, width: 1.2),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(color: Color(0xFFFEC619), width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                            child: const Text('حفظ', style: TextStyle(color: Color(0xFF1A1A1A))),
                          ),
                        ],
                      );
                    },
                  );

                  if (ok != true) return;
                  final text = ctrl.text.trim();
                  if (text.isEmpty) return;
                  await _dbHelper.addStudentFinancialNote(
                    studentId: studentId,
                    planId: pid,
                    note: text,
                  );
                  await _loadInfoNotesData();

                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تمت إضافة الملاحظة')),
                  );
                } finally {
                  _infoNotesDialogOpen = false;
                }
              }

              Future<void> showNotesListDialog({
                required int studentId,
                required String studentName,
              }) async {
                if (_infoNotesDialogOpen) return;
                if (!mounted) return;
                int pid = _infoNotesSelectedClassId == 'all'
                    ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                    : _infoNotesSelectedPlanId;
                if (pid <= 0) {
                  await _loadInfoNotesData();
                  if (!mounted) return;
                  pid = _infoNotesSelectedClassId == 'all'
                      ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                      : _infoNotesSelectedPlanId;
                  if (pid <= 0) return;
                }

                _infoNotesDialogOpen = true;
                try {
                  final notes = await _dbHelper.getStudentFinancialNotes(
                    studentId: studentId,
                    planId: pid,
                  );

                  if (!mounted) return;
                  final ctrl = TextEditingController();
                  await showDialog<void>(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setLocalState) {
                          Future<void> addNote() async {
                            final text = ctrl.text.trim();
                            if (text.isEmpty) return;
                            await _dbHelper.addStudentFinancialNote(
                              studentId: studentId,
                              planId: pid,
                              note: text,
                            );
                            ctrl.clear();
                            final refreshed = await _dbHelper.getStudentFinancialNotes(
                              studentId: studentId,
                              planId: pid,
                            );
                            notes
                              ..clear()
                              ..addAll(refreshed);
                            setLocalState(() {});
                            await _loadInfoNotesData();
                          }

                          return AlertDialog(
                            backgroundColor: const Color(0xFF2A2A2A),
                            title: Text(studentName, style: const TextStyle(color: Color(0xFFFEC619))),
                            content: SizedBox(
                              width: 620,
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (notes.isEmpty)
                                      const Text('لا توجد ملاحظات', style: TextStyle(color: Colors.grey)),
                                    if (notes.isNotEmpty)
                                      ...notes.map((n) {
                                        final text = n['note']?.toString() ?? '';
                                        final createdAt = (n['created_at']?.toString() ?? '').trim();
                                        return Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF1A1A1A),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              if (createdAt.isNotEmpty)
                                                Text(createdAt, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
                                              if (createdAt.isNotEmpty) const SizedBox(height: 6),
                                              Text(text, style: const TextStyle(color: Colors.white)),
                                            ],
                                          ),
                                        );
                                      }),
                                    const SizedBox(height: 8),
                                    TextField(
                                      controller: ctrl,
                                      style: const TextStyle(color: Colors.white),
                                      maxLines: 3,
                                      decoration: InputDecoration(
                                        labelText: 'إضافة ملاحظة جديدة',
                                        labelStyle: const TextStyle(color: Colors.grey),
                                        filled: true,
                                        fillColor: const Color(0xFF3A3A3A),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(6),
                                          borderSide: BorderSide(color: Colors.grey.shade700, width: 1.2),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(6),
                                          borderSide: const BorderSide(color: Color(0xFFFEC619), width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                              ),
                              ElevatedButton(
                                onPressed: addNote,
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                                child: const Text('إضافة', style: TextStyle(color: Color(0xFF1A1A1A))),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                } finally {
                  _infoNotesDialogOpen = false;
                }
              }

              Future<void> showDiscountDialog({
                required int studentId,
                required String studentName,
              }) async {
                if (_infoNotesDialogOpen) return;
                if (!mounted) return;
                int planId = _infoNotesSelectedClassId == 'all'
                    ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                    : _infoNotesSelectedPlanId;
                if (planId <= 0) {
                  await _loadInfoNotesData();
                  if (!mounted) return;
                  planId = _infoNotesSelectedClassId == 'all'
                      ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                      : _infoNotesSelectedPlanId;
                  if (planId <= 0) return;
                }

                final installments = _infoNotesInstallmentsByPlanId[planId] ?? const <Map<String, dynamic>>[];
                if (installments.isEmpty) return;

                _infoNotesDialogOpen = true;
                try {

                final installmentNos = installments
                    .map((r) => (r['installment_no'] is int)
                        ? r['installment_no'] as int
                        : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0)
                    .where((n) => n > 0)
                    .toList()
                  ..sort();

                final baseAmountByNo = <int, int>{};
                final baseDueByNo = <int, String>{};
                for (final inst in installments) {
                  final n = (inst['installment_no'] is int)
                      ? inst['installment_no'] as int
                      : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
                  if (n <= 0) continue;
                  final a = (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
                  baseAmountByNo[n] = a;
                  baseDueByNo[n] = inst['due_date']?.toString() ?? '';
                }

                final currentOverrides = _infoNotesOverridesByStudentInstallment[studentId] ?? const <int, Map<String, dynamic>>{};
                final amountControllers = <int, TextEditingController>{};
                final dueControllers = <int, TextEditingController>{};
                for (final n in installmentNos) {
                  final o = currentOverrides[n];
                  final rawAmount = o?['amount'];
                  final oa = (rawAmount is int) ? rawAmount : int.tryParse(rawAmount?.toString() ?? '');
                  final effectiveAmount = (oa != null && oa > 0) ? oa : (baseAmountByNo[n] ?? 0);
                  final effectiveDue = (o?['due_date']?.toString().trim() ?? '').isNotEmpty
                      ? (o?['due_date']?.toString() ?? '')
                      : (baseDueByNo[n] ?? '');
                  amountControllers[n] = TextEditingController(text: effectiveAmount > 0 ? effectiveAmount.toString() : '');
                  dueControllers[n] = TextEditingController(text: effectiveDue);
                }

                final originalTotal = baseAmountByNo.values.fold<int>(0, (a, b) => a + b);
                final currentTotal = installmentNos.fold<int>(0, (sum, n) {
                  final v = int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
                  return sum + v;
                });

                final discountedTotalController = TextEditingController(text: currentTotal > 0 ? currentTotal.toString() : '');
                final reasonController = TextEditingController(text: (_infoNotesDiscountReasonByStudentId[studentId] ?? '').trim());

                bool _updatingControllers = false;
                bool _totalManuallyEdited = false;

                InputDecoration greyBox(String label) {
                  return InputDecoration(
                    labelText: label,
                    labelStyle: const TextStyle(color: Colors.grey),
                    filled: true,
                    fillColor: const Color(0xFF3A3A3A),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade700, width: 1.2),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: Color(0xFFFEC619), width: 1.5),
                    ),
                  );
                }

                Future<void> pickDueDateFor(int n) async {
                  final initial = DateTime.tryParse(dueControllers[n]!.text.trim()) ?? DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: initial,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.dark(
                            primary: Color(0xFFFEC619),
                            onPrimary: Color(0xFF1A1A1A),
                            surface: Color(0xFF2A2A2A),
                            onSurface: Colors.white,
                          ),
                          dialogBackgroundColor: const Color(0xFF2A2A2A),
                        ),
                        child: child ?? const SizedBox.shrink(),
                      );
                    },
                  );
                  if (picked == null) return;
                  dueControllers[n]!.text = DateFormat('yyyy-MM-dd').format(picked);
                }

                void recomputeTotal() {
                  if (_updatingControllers) return;
                  int sum = 0;
                  for (final n in installmentNos) {
                    sum += int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
                  }
                  if (!_totalManuallyEdited) {
                    discountedTotalController.text = sum > 0 ? sum.toString() : '';
                  }
                }

                void applyDiscountedTotal(String value) {
                  if (_updatingControllers) return;
                  final newTotal = int.tryParse(value.trim()) ?? 0;
                  if (newTotal <= 0) return;
                  if (originalTotal <= 0) return;

                  _totalManuallyEdited = true;
                  _updatingControllers = true;
                  try {
                    int remaining = newTotal;
                    for (int i = 0; i < installmentNos.length; i++) {
                      final n = installmentNos[i];
                      final isLast = i == installmentNos.length - 1;
                      int amt;
                      if (isLast) {
                        amt = remaining;
                      } else {
                        final base = baseAmountByNo[n] ?? 0;
                        amt = ((base / originalTotal) * newTotal).floor();
                        if (amt < 0) amt = 0;
                        if (amt > remaining) amt = remaining;
                        remaining -= amt;
                      }
                      amountControllers[n]!.text = amt > 0 ? amt.toString() : '0';
                    }
                  } finally {
                    _updatingControllers = false;
                  }
                }

                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      backgroundColor: const Color(0xFF2A2A2A),
                      title: Text(studentName, style: const TextStyle(color: Color(0xFFFEC619))),
                      content: SizedBox(
                        width: 560,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('القسط الكامل: ${_formatIqd(originalTotal)}', style: const TextStyle(color: Colors.white)),
                              const SizedBox(height: 12),
                              TextField(
                                controller: discountedTotalController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                style: const TextStyle(color: Colors.white),
                                decoration: greyBox('بعد التخفيض'),
                                onChanged: applyDiscountedTotal,
                              ),
                              const SizedBox(height: 16),
                              const Text('تفاصيل الدفعات', style: TextStyle(color: Colors.white)),
                              const SizedBox(height: 12),
                              ...installmentNos.map((n) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('دفعة $n', style: const TextStyle(color: Colors.grey)),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: amountControllers[n],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                        style: const TextStyle(color: Colors.white),
                                        decoration: greyBox('مبلغ الدفعة بعد التخفيض'),
                                        onChanged: (_) => recomputeTotal(),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: dueControllers[n],
                                        readOnly: true,
                                        style: const TextStyle(color: Colors.white),
                                        decoration: greyBox('آخر تاريخ للسداد (YYYY-MM-DD)'),
                                        onTap: () => pickDueDateFor(n),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const SizedBox(height: 12),
                              TextField(
                                controller: reasonController,
                                style: const TextStyle(color: Colors.white),
                                decoration: greyBox('سبب التخفيض'),
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                          child: const Text('حفظ', style: TextStyle(color: Color(0xFF1A1A1A))),
                        ),
                      ],
                    );
                  },
                );

                if (ok != true) return;

                bool anyAmountChanged = false;
                int sum = 0;
                for (final n in installmentNos) {
                  final amount = int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
                  final due = dueControllers[n]!.text.trim();
                  if (amount <= 0 || due.isEmpty || DateTime.tryParse(due) == null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('يرجى إدخال مبلغ وتاريخ صحيح لكل دفعة')),
                    );
                    return;
                  }
                  if (amount != (baseAmountByNo[n] ?? 0)) {
                    anyAmountChanged = true;
                  }
                  sum += amount;
                }

                final reason = reasonController.text.trim();
                if (!anyAmountChanged) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('لا يمكن حفظ سبب التخفيض بدون تعديل مبالغ الدفعات')),
                  );
                  return;
                }

                for (final n in installmentNos) {
                  await _dbHelper.upsertStudentTuitionOverride(
                    studentId: studentId,
                    planId: planId,
                    installmentNo: n,
                    amount: int.tryParse(amountControllers[n]!.text.trim()) ?? 0,
                    dueDate: dueControllers[n]!.text.trim(),
                    reason: reason.isEmpty ? null : reason,
                  );
                }
                await _dbHelper.upsertStudentPlanDiscountReason(
                  studentId: studentId,
                  planId: planId,
                  reason: reason.isEmpty ? null : reason,
                );

                await _loadInfoNotesData();

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم حفظ التخفيض')),
                );
                } finally {
                  _infoNotesDialogOpen = false;
                }
              }

              Future<void> showStatusDetails({required int studentId, required String studentName}) async {
                final pid = _infoNotesSelectedClassId == 'all'
                    ? (_infoNotesPlanIdByStudentId[studentId] ?? 0)
                    : _infoNotesSelectedPlanId;
                if (pid <= 0) return;
                final installments = _infoNotesInstallmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
                if (installments.isEmpty) return;

                int dueAmountFor(int installmentNo) {
                  final o = _infoNotesOverridesByStudentInstallment[studentId]?[installmentNo];
                  final raw = o?['amount'];
                  final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
                  if (oa != null && oa > 0) return oa;
                  for (final inst in installments) {
                    final n = (inst['installment_no'] is int)
                        ? inst['installment_no'] as int
                        : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
                    if (n != installmentNo) continue;
                    return (inst['amount'] is int)
                        ? inst['amount'] as int
                        : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
                  }
                  return 0;
                }

                String dueDateFor(int installmentNo) {
                  final o = _infoNotesOverridesByStudentInstallment[studentId]?[installmentNo];
                  final od = o?['due_date']?.toString().trim() ?? '';
                  if (od.isNotEmpty) return od;
                  for (final inst in installments) {
                    final n = (inst['installment_no'] is int)
                        ? inst['installment_no'] as int
                        : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
                    if (n != installmentNo) continue;
                    return inst['due_date']?.toString() ?? '';
                  }
                  return '';
                }

                final payments = _infoNotesPaymentsByStudentId[studentId] ?? const <Map<String, dynamic>>[];
                final nos = installments
                    .map((r) => (r['installment_no'] is int)
                        ? r['installment_no'] as int
                        : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0)
                    .where((n) => n > 0)
                    .toList()
                  ..sort();

                final now = DateTime.now();

                _InstallmentComputed compute(int installmentNo) {
                  final dueAmount = dueAmountFor(installmentNo);
                  final dueDateStr = dueDateFor(installmentNo);
                  final dueDate = DateTime.tryParse(dueDateStr);
                  final instPayments = payments.where((p) {
                    final ino = (p['installment_no'] is int)
                        ? p['installment_no'] as int
                        : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
                    return ino == installmentNo;
                  }).toList();

                  int paidSum = 0;
                  int count = 0;
                  DateTime? completionDate;
                  for (final p in instPayments) {
                    final amt = (p['paid_amount'] is int) ? p['paid_amount'] as int : int.tryParse(p['paid_amount']?.toString() ?? '') ?? 0;
                    paidSum += amt;
                    count++;
                    if (completionDate == null && dueAmount > 0 && paidSum >= dueAmount) {
                      completionDate = DateTime.tryParse(p['payment_date']?.toString() ?? '');
                    }
                    if (completionDate != null && dueAmount > 0 && paidSum >= dueAmount) {
                      final d = DateTime.tryParse(p['payment_date']?.toString() ?? '');
                      if (d != null) completionDate = d;
                    }
                  }

                  final remaining = (dueAmount - paidSum) > 0 ? (dueAmount - paidSum) : 0;
                  final isComplete = dueAmount > 0 && paidSum >= dueAmount;

                  int? daysLate;
                  if (dueDate != null) {
                    final ref = isComplete ? (completionDate ?? now) : now;
                    final diffDays = ref.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
                    if (diffDays > 0 && (!isComplete || (completionDate != null && completionDate!.isAfter(dueDate)))) {
                      daysLate = diffDays;
                    }
                  }
                  final completedLate = isComplete && daysLate != null && daysLate > 0;
                  final isLateNow = !isComplete && daysLate != null && daysLate > 0;

                  return _InstallmentComputed(
                    installmentNo: installmentNo,
                    dueAmount: dueAmount,
                    dueDate: dueDateStr,
                    paidSum: paidSum,
                    remaining: remaining,
                    paymentsCount: count,
                    completionDate: completionDate == null ? '' : DateFormat('yyyy-MM-dd').format(completionDate!),
                    daysLate: daysLate,
                    isComplete: isComplete,
                    isLateNow: isLateNow,
                    completedLate: completedLate,
                  );
                }

                await showDialog<void>(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      backgroundColor: const Color(0xFF2A2A2A),
                      title: Text(studentName, style: const TextStyle(color: Color(0xFFFEC619))),
                      content: SizedBox(
                        width: 620,
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: nos.map((n) {
                              final c = compute(n);
                              final Color border = c.isLateNow
                                  ? Colors.redAccent
                                  : c.completedLate
                                      ? Colors.orangeAccent
                                      : Colors.green;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1A1A1A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: border.withOpacity(0.9)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('الدفعة $n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 6),
                                    Text('آخر تاريخ للسداد: ${c.dueDate}', style: TextStyle(color: Colors.grey.shade300)),
                                    Text('تاريخ اكتمال الدفع: ${c.completionDate.isEmpty ? '-' : c.completionDate}', style: TextStyle(color: Colors.grey.shade300)),
                                    if (c.daysLate != null && c.daysLate! > 0)
                                      Text('أيام التأخير: ${c.daysLate}', style: const TextStyle(color: Colors.redAccent)),
                                    const SizedBox(height: 6),
                                    Text('عدد مرات الدفع: ${c.paymentsCount}', style: TextStyle(color: Colors.grey.shade300)),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(child: Text('المستحق: ${_formatIqd(c.dueAmount)}', style: const TextStyle(color: Colors.white))),
                                        Expanded(child: Text('المدفوع: ${_formatIqd(c.paidSum)}', style: const TextStyle(color: Colors.white))),
                                        Expanded(child: Text('المتبقي: ${_formatIqd(c.remaining)}', style: const TextStyle(color: Colors.white))),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                        ),
                      ],
                    );
                  },
                );
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      className,
                      style: const TextStyle(color: Color(0xFFFEC619), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(const Color(0xFF1A1A1A)),
                        dataRowColor: MaterialStateProperty.all(const Color(0xFF2A2A2A)),
                        columns: const [
                          DataColumn(
                            label: Text('الطالب', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                          DataColumn(
                            label: Text('مبلغ القسط', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                          DataColumn(
                            label: Text('تخفيض؟', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                          DataColumn(
                            label: Text('سبب التخفيض', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                          DataColumn(
                            label: Text('الحالة', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                          DataColumn(
                            label: Text('الملاحظات', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                          ),
                        ],
                        rows: students.map((s) {
                          final name = s['name']?.toString() ?? '';
                          final sid = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                          final status = _infoNotesStatusByStudentId[sid];
                          final reason = _infoNotesDiscountReasonByStudentId[sid] ?? '';
                          final note = _infoNotesLatestNoteByStudentId[sid] ?? '';
                          final hasDiscount = (_infoNotesOverridesByStudentInstallment[sid]?.isNotEmpty ?? false) || reason.trim().isNotEmpty;

                          int effectiveTotalForStudent() {
                            final pid = _infoNotesSelectedClassId == 'all'
                                ? (_infoNotesPlanIdByStudentId[sid] ?? 0)
                                : _infoNotesSelectedPlanId;
                            if (pid <= 0) return 0;
                            final inst = _infoNotesInstallmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
                            if (inst.isEmpty) return 0;
                            int sum = 0;
                            for (final r in inst) {
                              final no = (r['installment_no'] is int)
                                  ? r['installment_no'] as int
                                  : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0;
                              if (no <= 0) continue;
                              final o = _infoNotesOverridesByStudentInstallment[sid]?[no];
                              final raw = o?['amount'];
                              final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
                              if (oa != null && oa > 0) {
                                sum += oa;
                              } else {
                                final a = (r['amount'] is int) ? r['amount'] as int : int.tryParse(r['amount']?.toString() ?? '') ?? 0;
                                sum += a;
                              }
                            }
                            return sum;
                          }

                          Widget statusChip() {
                            if (status == null) {
                              return const Text('-', style: TextStyle(color: Colors.white));
                            }
                            return InkWell(
                              onTap: sid <= 0 ? null : () => showStatusDetails(studentId: sid, studentName: name),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: status.isSmall ? 4 : 6),
                                decoration: BoxDecoration(
                                  color: status.color.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: status.color.withOpacity(0.9)),
                                ),
                                child: Text(
                                  status.label,
                                  style: TextStyle(
                                    color: status.color,
                                    fontWeight: FontWeight.bold,
                                    fontSize: status.isSmall ? 11 : 12,
                                  ),
                                ),
                              ),
                            );
                          }

                          return DataRow(
                            cells: [
                              DataCell(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    InkWell(
                                      onTap: sid <= 0 || (_infoNotesPlanIdByStudentId[sid] ?? 0) <= 0
                                          ? null
                                          : () async {
                                              final pid = _infoNotesPlanIdByStudentId[sid] ?? 0;
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => StudentFinancialDetailsScreen(
                                                    studentId: sid,
                                                    planId: pid,
                                                  ),
                                                ),
                                              );

                                              await _loadFinancialData();
                                              await _loadInfoNotesData();
                                            },
                                      child: Text(name, style: const TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ),
                              DataCell(
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    _formatIqd(effectiveTotalForStudent()),
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                InkWell(
                                  onTap: sid <= 0 || (_infoNotesPlanIdByStudentId[sid] ?? 0) <= 0
                                      ? null
                                      : () async => await showDiscountDialog(studentId: sid, studentName: name),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: (hasDiscount ? Colors.green : Colors.grey).withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(color: (hasDiscount ? Colors.green : Colors.grey).withOpacity(0.9)),
                                    ),
                                    child: Text(
                                      hasDiscount ? 'لديه' : 'بدون',
                                      style: TextStyle(
                                        color: hasDiscount ? Colors.green : Colors.grey,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(
                                InkWell(
                                  onTap: reason.trim().isEmpty ? null : () => showTextDialog(title: 'سبب التخفيض', text: reason),
                                  child: SizedBox(
                                    width: 180,
                                    child: Text(
                                      _shorten(reason),
                                      style: const TextStyle(color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              DataCell(statusChip()),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: InkWell(
                                          onTap: sid <= 0 || _infoNotesSelectedPlanName.trim().isEmpty
                                              ? null
                                              : () async => await showNotesListDialog(studentId: sid, studentName: name),
                                          child: Text(
                                            _shorten(_infoNotesLatestNoteByStudentId[sid] ?? ''),
                                            style: const TextStyle(color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'إضافة ملاحظة',
                                        onPressed: sid <= 0 || (_infoNotesPlanIdByStudentId[sid] ?? 0) <= 0
                                            ? null
                                            : () async => await showAddNoteDialog(studentId: sid, studentName: name),
                                        icon: const Icon(Icons.add_comment, color: Color(0xFFFEC619), size: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialDashboard() {
    final classOptions = [
      'all',
      ...(_classes
          .map((c) => c['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) {
          String an = '';
          String bn = '';
          try {
            an = _classes.firstWhere((c) => c['id']?.toString() == a)['name']?.toString() ?? '';
          } catch (_) {}
          try {
            bn = _classes.firstWhere((c) => c['id']?.toString() == b)['name']?.toString() ?? '';
          } catch (_) {}
          return an.compareTo(bn);
        }))
    ];

    final effectiveLocation = classOptions.contains(_dashboardSelectedLocation)
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
                    items: classOptions.map((id) {
                      if (id == 'all') {
                        return const DropdownMenuItem<String>(
                          value: 'all',
                          child: Text('جميع الفصول'),
                        );
                      }
                      String name = id;
                      try {
                        name = _classes.firstWhere((c) => c['id']?.toString() == id)['name']?.toString() ?? id;
                      } catch (_) {}
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
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

            // إحصائيات الحالة (تحت الإحصائيات الخمس)
            _buildStatusList(),
            const SizedBox(height: 24),

            // الرسم البياني (يبقى كما هو)
            _buildChartSection(),
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
              'تسجيل دفعة طالب',
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
                      if (_suppressStudentNameOnChanged) return;
                      if (_studentSelectedFromSuggestions) {
                        setState(() {
                          _studentSelectedFromSuggestions = false;
                        });
                      }
                      // تحديث الفصل والموقع تلقائياً عند البحث
                      _onStudentNameChanged(value);
                      _filterStudents(value);
                    },
                  ),
                ),
                
                // عرض قائمة الطلاب المطابقة
                if (_studentNameController.text.isNotEmpty && !_studentSelectedFromSuggestions)
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
                              _suppressStudentNameOnChanged = true;
                              _studentNameController.text = student['name'];
                              _selectedStudentId = student['id'].toString();
                              _selectedClassId = student['classId']?.toString() ?? '';
                              _selectedLocation = student['location']?.toString() ?? '';
                              _studentSelectedFromSuggestions = true;
                              _selectedTuitionPlanId = 0;
                              _selectedTuitionInstallmentNo = 0;
                              _tuitionPlansForClass = [];
                              _tuitionInstallmentsForPlan = [];
                              _amountController.clear();
                            });
                            _loadTuitionPlansForSelectedClass();
                            _suppressStudentNameOnChanged = false;
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
                        _selectedTuitionPlanId = 0;
                        _selectedTuitionInstallmentNo = 0;
                        _tuitionPlansForClass = [];
                        _tuitionInstallmentsForPlan = [];
                        _amountController.clear();
                      });
                      _loadTuitionPlansForSelectedClass();
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
                  child: DropdownButton<int>(
                    value: _selectedTuitionPlanId > 0
                        ? _selectedTuitionPlanId
                        : null,
                    hint: Text(
                      'اختر القسط',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: _tuitionPlansForClass.map((p) {
                      final pid = (p['id'] is int)
                          ? p['id'] as int
                          : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                      final name = p['name']?.toString() ?? '';
                      return DropdownMenuItem<int>(
                        value: pid,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTuitionPlanId = value ?? 0;
                        _selectedTuitionInstallmentNo = 0;
                        _tuitionInstallmentsForPlan = [];
                        _amountController.clear();
                      });
                      _loadTuitionInstallmentsForSelectedPlan();
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // حقل اختيار الدفعة
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر الدفعة',
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
                  child: DropdownButton<int>(
                    value: _selectedTuitionInstallmentNo > 0
                        ? _selectedTuitionInstallmentNo
                        : null,
                    hint: Text(
                      'اختر الدفعة',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                    isExpanded: true,
                    dropdownColor: const Color(0xFF2A2A2A),
                    style: const TextStyle(color: Colors.white),
                    items: _tuitionInstallmentsForPlan.map((inst) {
                      final no = (inst['installment_no'] is int)
                          ? inst['installment_no'] as int
                          : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
                      final dueDate = inst['due_date']?.toString() ?? '';
                      return DropdownMenuItem<int>(
                        value: no,
                        child: Text('الدفعة $no${dueDate.isNotEmpty ? ' - $dueDate' : ''}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedTuitionInstallmentNo = value ?? 0;
                        _amountController.clear();
                      });
                      _updateAmountForSelectedTuitionInstallment();
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
                  'المبلغ المستحق للدفعة',
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

    if (_selectedTuitionPlanId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار القسط'),
          backgroundColor: Color(0xFFFEC619),
        ),
      );
      return;
    }

    if (_selectedTuitionInstallmentNo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('الرجاء اختيار الدفعة'),
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

      // حفظ الدفعة في قاعدة البيانات (tuition_payments)
      final parsedStudentId = int.tryParse(_selectedStudentId);
      int createdReceiptNo = 0;
      if (parsedStudentId != null) {
        final effective = await _dbHelper.getEffectiveTuitionInstallment(
          studentId: parsedStudentId,
          planId: _selectedTuitionPlanId,
          installmentNo: _selectedTuitionInstallmentNo,
        );

        final baseAmount = effective?['amount'];
        final installmentAmount = (baseAmount is int)
            ? baseAmount
            : int.tryParse(baseAmount?.toString() ?? '') ?? dueAmount.toInt();

        final totalPaidBefore = await _dbHelper.getTotalPaidForTuitionInstallment(
          studentId: parsedStudentId,
          planId: _selectedTuitionPlanId,
          installmentNo: _selectedTuitionInstallmentNo,
        );

        final remainingBefore = (installmentAmount - totalPaidBefore).clamp(0, 1 << 30);

        // في الإيصال: "المبلغ المستحق" = المتبقي وقت تسجيل الدفعة
        dueIntForReceipt = remainingBefore;

        if (installmentAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد مبلغ مستحق لهذه الدفعة'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        if (remainingBefore <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('الطالب مسدد لهذه الدفعة بالكامل ولا يمكن إضافة دفعة جديدة'),
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

        final receiptNo = await _dbHelper.getNextTuitionReceiptNo();
        createdReceiptNo = receiptNo;
        await _dbHelper.insertTuitionPayment(
          receiptNo: receiptNo,
          studentId: parsedStudentId,
          planId: _selectedTuitionPlanId,
          installmentNo: _selectedTuitionInstallmentNo,
          dueAmount: remainingBefore,
          paidAmount: paidAmount.toInt(),
          paymentDate: _paymentDate.toString().split(' ')[0],
          notes: null,
        );

        // تحديث فوري للواجهة والإحصائيات بعد إضافة دفعة جديدة
        await _loadFinancialData();

        final totalPaidAfter = await _dbHelper.getTotalPaidForTuitionInstallment(
          studentId: parsedStudentId,
          planId: _selectedTuitionPlanId,
          installmentNo: _selectedTuitionInstallmentNo,
        );
        remainingAmount = (installmentAmount - totalPaidAfter).clamp(0, 1 << 30).toDouble();
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
            'receiptNo': createdReceiptNo,
            'studentId': _selectedStudentId,
            'studentName': _students[studentIndex]['name'],
            'className': _getClassName(_selectedClassId),
            'planId': _selectedTuitionPlanId,
            'planName': _getSelectedTuitionPlanName(),
            'installmentNo': _selectedTuitionInstallmentNo,
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
          _firstInstallmentLate = (_firstInstallmentLate - 1).clamp(0, _totalStudents);
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

            if ((_lastPayment['receiptNo'] ?? 0).toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'رقم الوصل: ${_lastPayment['receiptNo'] ?? ''}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            
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

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الفصل: ${_lastPayment['className'] ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'القسط: ${_lastPayment['planName'] ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'الدفعة: ${_lastPayment['installmentNo'] ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // معلومات الدفع
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
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
                      'لا توجد دفعات لهذا القسط',
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
                              item['label']?.toString() ?? '',
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
                        'لا توجد دفعات لهذا القسط',
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
                                  'الدفعة',
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
                                    item['label']?.toString() ?? '',
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
                      'رقم الوصل: ${_lastPayment['receiptNo'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 14,
                        color: PdfColor.fromInt(0xFFCCCCCC),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'القسط: ${_lastPayment['planName'] ?? ''}',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontFallback: [pw.Font.helvetica()],
                        fontSize: 14,
                        color: PdfColor.fromInt(0xFFCCCCCC),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'الدفعة: ${_lastPayment['installmentNo'] ?? ''}',
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
                      'تفاصيل الدفعة',
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
                      'تفاصيل الدفعة',
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
      _selectedTuitionPlanId = 0;
      _selectedTuitionInstallmentNo = 0;
      _tuitionPlansForClass = [];
      _tuitionInstallmentsForPlan = [];
      _paymentDate = DateTime.now();
    });
  }

  Widget _buildInstallmentManagement() {
    final classes = <String>{'جميع الفصول', ..._classes.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty)}.toList();
    final instNo = _installmentsSelectedInstallmentNo;
    final instSuffix = instNo > 0 ? ' (دفعة $instNo)' : '';
    final bool isPaymentView = false;
    final String paySuffix = '';

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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
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
                      onChanged: (_) {
                        _searchTimer?.cancel();
                        _searchTimer = Timer(const Duration(milliseconds: 350), () {
                          if (!mounted) return;
                          _loadInstallmentsManagementData();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: classes.contains(_installmentsSelectedClass) ? _installmentsSelectedClass : 'جميع الفصول',
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
                          .map((c) => DropdownMenuItem<String>(
                                value: c,
                                child: Text(c, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _installmentsSelectedClass = v ?? 'جميع الفصول';
                          _installmentsSelectedPlanId = 0;
                          _installmentsSelectedPlanName = '';
                          _installmentsSelectedInstallmentNo = 0;
                          _installmentsSelectedPaymentIndex = 0;
                          _installmentsPaymentIndexOptions = [];
                        });
                        _loadInstallmentsManagementData();
                      },
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: () async {
                        final classFilter = _installmentsSelectedClass;
                        final classIds = <int>[];
                        if (classFilter != 'جميع الفصول') {
                          try {
                            final c = _classes.firstWhere((x) => (x['name']?.toString() ?? '') == classFilter);
                            final id = int.tryParse(c['id']?.toString() ?? '');
                            if (id != null) classIds.add(id);
                          } catch (_) {}
                        } else {
                          for (final c in _classes) {
                            final id = int.tryParse(c['id']?.toString() ?? '');
                            if (id != null) classIds.add(id);
                          }
                        }

                        final byName = <String, Map<String, dynamic>>{};
                        for (final cid in classIds.toSet()) {
                          final plans = await _dbHelper.getClassTuitionPlans(cid);
                          for (final p in plans) {
                            final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                            if (pid <= 0) continue;
                            final name = p['name']?.toString().trim() ?? '';
                            if (name.isEmpty) continue;
                            byName[name] = p;
                          }
                        }

                        final list = byName.keys.toList()..sort();
                        return list.map((n) => {'name': n}).toList();
                      }(),
                      builder: (context, snapshot) {
                        final plans = snapshot.data ?? const <Map<String, dynamic>>[];
                        final names = plans.map((p) => p['name']?.toString() ?? '').where((n) => n.trim().isNotEmpty).toList()..sort();
                        final effectiveName = names.contains(_installmentsSelectedPlanName) ? _installmentsSelectedPlanName : '';

                        if (effectiveName != _installmentsSelectedPlanName) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _installmentsSelectedPlanId = 0;
                              _installmentsSelectedPlanName = effectiveName;
                              _installmentsSelectedInstallmentNo = 0;
                              _installmentsSelectedPaymentIndex = 0;
                              _installmentsPaymentIndexOptions = [];
                            });
                          });
                        }

                        return DropdownButtonFormField<String>(
                          value: effectiveName,
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
                          items: [
                            const DropdownMenuItem<String>(value: '', child: Text('جميع الأقساط')),
                            ...names.map((n) => DropdownMenuItem<String>(value: n, child: Text(n, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _installmentsSelectedPlanId = 0;
                              _installmentsSelectedPlanName = v ?? '';
                              _installmentsSelectedInstallmentNo = 0;
                              _installmentsSelectedPaymentIndex = 0;
                              _installmentsPaymentIndexOptions = [];
                            });
                            _loadInstallmentsManagementData();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<List<int>>(
                      future: () async {
                        final classFilter = _installmentsSelectedClass;
                        final selectedPlanName = _installmentsSelectedPlanName.trim();
                        final classIds = <int>[];
                        if (classFilter != 'جميع الفصول') {
                          try {
                            final c = _classes.firstWhere((x) => (x['name']?.toString() ?? '') == classFilter);
                            final id = int.tryParse(c['id']?.toString() ?? '');
                            if (id != null) classIds.add(id);
                          } catch (_) {}
                        } else {
                          for (final c in _classes) {
                            final id = int.tryParse(c['id']?.toString() ?? '');
                            if (id != null) classIds.add(id);
                          }
                        }

                        final nos = <int>{};
                        for (final cid in classIds.toSet()) {
                          final plans = await _dbHelper.getClassTuitionPlans(cid);
                          for (final p in plans) {
                            final pid = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                            if (pid <= 0) continue;
                            if (selectedPlanName.isNotEmpty && (p['name']?.toString().trim() ?? '') != selectedPlanName) continue;
                            final inst = await _dbHelper.getTuitionPlanInstallments(pid);
                            for (final r in inst) {
                              final n = (r['installment_no'] is int)
                                  ? r['installment_no'] as int
                                  : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0;
                              if (n > 0) nos.add(n);
                            }
                          }
                        }

                        final list = nos.toList()..sort();
                        return list;
                      }(),
                      builder: (context, snapshot) {
                        final nos = snapshot.data ?? const <int>[];
                        final effectiveNo = (_installmentsSelectedInstallmentNo > 0 && nos.contains(_installmentsSelectedInstallmentNo))
                            ? _installmentsSelectedInstallmentNo
                            : 0;

                        if (effectiveNo != _installmentsSelectedInstallmentNo) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            setState(() {
                              _installmentsSelectedInstallmentNo = effectiveNo;
                              _installmentsSelectedPlanId = 0;
                            });
                          });
                        }

                        return DropdownButtonFormField<int>(
                          value: effectiveNo,
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
                          items: [
                            const DropdownMenuItem<int>(value: 0, child: Text('جميع الدفعات')),
                            ...nos.map((n) => DropdownMenuItem<int>(value: n, child: Text('دفعة $n'))),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _installmentsSelectedInstallmentNo = v ?? 0;
                              // لا تغيّر البلان هنا
                              _installmentsSelectedPaymentIndex = 0;
                              _installmentsPaymentIndexOptions = [];
                            });
                            _loadInstallmentsManagementData();
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    // تم حذف فلتر الدفعة الرابع (المكرر) حسب الطلب
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _loadInstallmentsManagementData,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFEC619),
                              foregroundColor: const Color(0xFF1A1A1A),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('بحث'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _installmentsSearchController.clear();
                                _installmentsSelectedClass = 'جميع الفصول';
                                _installmentsSelectedPlanId = 0;
                                _installmentsSelectedPlanName = '';
                                _installmentsSelectedInstallmentNo = 0;
                                _installmentsSelectedPaymentIndex = 0;
                                _installmentsPaymentIndexOptions = [];
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
                        ),
                      ],
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
                  title: '${isPaymentView ? 'متبقي الدفعة' : 'المبلغ المتبقي'}$instSuffix$paySuffix',
                  value: _formatIqd(_installmentsTotalRemaining),
                  icon: Icons.account_balance_wallet_outlined,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: '${isPaymentView ? 'مدفوع الدفعة' : 'إجمالي المدفوعات'}$instSuffix$paySuffix',
                  value: _formatIqd(_installmentsTotalPaid),
                  icon: Icons.payments_outlined,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  title: '${isPaymentView ? 'سعر الدفعة' : 'القسط الكلي'}$instSuffix$paySuffix',
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
                    columns: [
                      DataColumn(label: Text('ت', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('اسم الطالب', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('الفصل', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                      DataColumn(
                        label: Text(
                          '${isPaymentView ? 'سعر الدفعة' : 'القسط الكلي'}$instSuffix$paySuffix',
                          style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          '${isPaymentView ? 'مدفوع الدفعة' : 'إجمالي المدفوعات'}$instSuffix$paySuffix',
                          style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          '${isPaymentView ? 'متبقي الدفعة' : 'المبلغ المتبقي'}$instSuffix$paySuffix',
                          style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: _installmentsRows.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(Text(r['index']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(r['studentName']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                          DataCell(Text(r['className']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
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
    return FutureBuilder<List<ClassModel>>(
      future: _dbHelper.getAllClasses(),
      builder: (context, snapshot) {
        final classModels = snapshot.data ?? const <ClassModel>[];
        final classOptions = <Map<String, String>>[
          {'id': 'all', 'name': 'جميع الفصول'},
          ...classModels
              .where((c) => (c.id ?? 0) > 0)
              .map((c) => {'id': c.id.toString(), 'name': c.name}),
        ];

        if (!_latePaymentsDidInitialLoad && snapshot.connectionState == ConnectionState.done) {
          _latePaymentsDidInitialLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3A),
                  borderRadius: BorderRadius.circular(12),
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
                              hintText: 'بحث باسم الطالب',
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
                                _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<String>(
                            value: _latePaymentsSelectedClassId,
                            items: classOptions
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c['id'],
                                    child: Text(c['name'] ?? ''),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _latePaymentsSelectedClassId = value ?? 'all';
                                _latePaymentsSelectedPlanName = '';
                                _latePaymentsSelectedInstallmentNo = 0;
                              });
                              _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
                            },
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF2A2A2A),
                            underline: const SizedBox(),
                            isExpanded: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _getLatePlanOptionsForClassFilter(),
                          builder: (context, snap) {
                            final plans = snap.data ?? const <Map<String, dynamic>>[];
                            final names = plans
                                .map((p) => p['name']?.toString().trim() ?? '')
                                .where((n) => n.isNotEmpty)
                                .toSet()
                                .toList();
                            names.sort();
                            final effectiveName = names.contains(_latePaymentsSelectedPlanName)
                                ? _latePaymentsSelectedPlanName
                                : '';

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade600),
                              ),
                              child: DropdownButton<String>(
                                value: effectiveName,
                                items: [
                                  const DropdownMenuItem(value: '', child: Text('جميع الأقساط')),
                                  ...names.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _latePaymentsSelectedPlanName = value ?? '';
                                    _latePaymentsSelectedInstallmentNo = 0;
                                  });
                                  _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
                                },
                                style: const TextStyle(color: Colors.white),
                                dropdownColor: const Color(0xFF2A2A2A),
                                underline: const SizedBox(),
                                isExpanded: true,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: () async {
                            final plans = await _getLatePlanOptionsForClassFilter();
                            final selectedName = _latePaymentsSelectedPlanName.trim();
                            final ids = plans
                                .where((p) => selectedName.isEmpty || (p['name']?.toString().trim() ?? '') == selectedName)
                                .map((p) => (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0)
                                .where((x) => x > 0)
                                .toList();
                            if (ids.isEmpty) return const <Map<String, dynamic>>[];
                            final all = <Map<String, dynamic>>[];
                            for (final pid in ids.toSet()) {
                              all.addAll(await _dbHelper.getTuitionPlanInstallments(pid));
                            }
                            return all;
                          }(),
                          builder: (context, snap) {
                            final inst = snap.data ?? const <Map<String, dynamic>>[];
                            final nos = inst
                                .map((i) => (i['installment_no'] is int)
                                    ? i['installment_no'] as int
                                    : int.tryParse(i['installment_no']?.toString() ?? '') ?? 0)
                                .where((n) => n > 0)
                                .toList();
                            nos.sort();
                            final effectiveNo = (_latePaymentsSelectedInstallmentNo > 0 && nos.contains(_latePaymentsSelectedInstallmentNo))
                                ? _latePaymentsSelectedInstallmentNo
                                : 0;

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade600),
                              ),
                              child: DropdownButton<int>(
                                value: effectiveNo,
                                items: [
                                  const DropdownMenuItem(value: 0, child: Text('جميع الدفعات')),
                                  ...nos.map((n) => DropdownMenuItem(value: n, child: Text('الدفعة $n'))),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    _latePaymentsSelectedInstallmentNo = value ?? 0;
                                  });
                                  _loadLatePaymentsRows(const <Map<String, dynamic>>[]);
                                },
                                style: const TextStyle(color: Colors.white),
                                dropdownColor: const Color(0xFF2A2A2A),
                                underline: const SizedBox(),
                                isExpanded: true,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: MaterialStateProperty.all(const Color(0xFF1A1A1A)),
                        dataRowColor: MaterialStateProperty.all(const Color(0xFF2A2A2A)),
                        columns: const [
                          DataColumn(label: Text('ت', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('اسم الطالب', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الفصل', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('القسط', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('الدفعة', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('آخر موعد', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('المستحق', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('المدفوع', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('المتبقي', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('أيام التأخير', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold))),
                        ],
                        rows: _latePaymentsRows.map((r) {
                          return DataRow(cells: [
                            DataCell(Text(r['index']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['studentName']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['className']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['planName']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['installmentNo']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['dueDate']?.toString() ?? '', style: const TextStyle(color: Colors.white))),
                            DataCell(Text(_formatIqd(r['due']), style: const TextStyle(color: Colors.white))),
                            DataCell(Text(_formatIqd(r['paid']), style: const TextStyle(color: Colors.white))),
                            DataCell(Text(_formatIqd(r['remaining']), style: const TextStyle(color: Colors.white))),
                            DataCell(Text(r['daysLate']?.toString() ?? '', style: const TextStyle(color: Colors.redAccent))),
                          ]);
                        }).toList(),
                      ),
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
      await _loadLatePaymentsRows(const <Map<String, dynamic>>[]);

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

      final headers = <String>[
        'اسم الطالب',
        'الفصل',
        'القسط',
        'الدفعة',
        'آخر موعد',
        'المستحق',
        'المدفوع',
        'المتبقي',
        'أيام التأخير',
      ];

      final data = exportRows.map((r) {
        return <String>[
          r['studentName']?.toString() ?? '',
          r['className']?.toString() ?? '',
          r['planName']?.toString() ?? '',
          r['installmentNo']?.toString() ?? '',
          r['dueDate']?.toString() ?? '',
          _formatIqd(r['due'] ?? 0),
          _formatIqd(r['paid'] ?? 0),
          _formatIqd(r['remaining'] ?? 0),
          r['daysLate']?.toString() ?? '',
        ];
      }).toList();

      pw.Table _buildPdfTable() {
        // توزيع أعمدة متوازن حتى تبقى العناوين واضحة
        final columnWidths = <int, pw.TableColumnWidth>{
          0: const pw.FlexColumnWidth(2.2),
          1: const pw.FlexColumnWidth(1.4),
          2: const pw.FlexColumnWidth(1.4),
          3: const pw.FlexColumnWidth(0.9),
          4: const pw.FlexColumnWidth(1.2),
          5: const pw.FlexColumnWidth(1.1),
          6: const pw.FlexColumnWidth(1.1),
          7: const pw.FlexColumnWidth(1.1),
          8: const pw.FlexColumnWidth(1.0),
        };

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
                      'الفصل: ${_latePaymentsSelectedClassId == 'all' ? 'جميع الفصول' : _latePaymentsSelectedClassId}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'القسط: ${_latePaymentsSelectedPlanName.trim().isEmpty ? 'جميع الأقساط' : _latePaymentsSelectedPlanName}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'الدفعة: ${_latePaymentsSelectedInstallmentNo == 0 ? 'جميع الدفعات' : _latePaymentsSelectedInstallmentNo}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      exportRows.isEmpty ? 'لا توجد بيانات' : 'عدد السجلات: ${exportRows.length}',
                      style: pw.TextStyle(fontSize: 12),
                    ),
                    pw.SizedBox(height: 12),
                    if (exportRows.isNotEmpty)
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

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
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
        final classes = data['classes'] as List<Map<String, dynamic>>? ?? [];
        final plans = data['courses'] as List<Map<String, dynamic>>? ?? [];
        final installments = data['installments'] as List<Map<String, dynamic>>? ?? [];

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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
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
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedPaymentClassId,
                            items: [
                              const DropdownMenuItem(value: 'all', child: Text('جميع الفصول')),
                              ...classes.map((c) {
                                final id = c['id']?.toString() ?? '';
                                final name = c['name']?.toString() ?? '';
                                return DropdownMenuItem(value: id, child: Text(name));
                              }),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentClassId = value ?? 'all';
                                _selectedPaymentPlanId = 0;
                                _selectedPaymentInstallmentNo = 0;
                              });
                            },
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF2A2A2A),
                            underline: const SizedBox(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<String>(
                            value: _selectedPaymentPlanName,
                            items: [
                              const DropdownMenuItem(value: '', child: Text('جميع الأقساط')),
                              ...(() {
                                final names = plans
                                    .where((p) {
                                      if (_selectedPaymentClassId == 'all') return true;
                                      final cid = p['class_id']?.toString() ?? '';
                                      return cid == _selectedPaymentClassId;
                                    })
                                    .map((p) => p['name']?.toString().trim() ?? '')
                                    .where((n) => n.isNotEmpty)
                                    .toSet()
                                    .toList();
                                names.sort();
                                return names.map((n) => DropdownMenuItem(value: n, child: Text(n)));
                              }()),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentPlanId = 0;
                                _selectedPaymentPlanName = value ?? '';
                                _selectedPaymentInstallmentNo = 0;
                              });
                            },
                            style: const TextStyle(color: Colors.white),
                            dropdownColor: const Color(0xFF2A2A2A),
                            underline: const SizedBox(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade600),
                          ),
                          child: DropdownButton<int>(
                            value: _selectedPaymentInstallmentNo,
                            items: [
                              const DropdownMenuItem(value: 0, child: Text('جميع الدفعات')),
                              ...(() {
                                final nos = installments
                                    .map((inst) => (inst['installment_no'] is int)
                                        ? inst['installment_no'] as int
                                        : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0)
                                    .where((n) => n > 0)
                                    .toSet()
                                    .toList();
                                nos.sort();
                                return nos.map((no) => DropdownMenuItem(value: no, child: Text('الدفعة $no')));
                              }()),
                            ],
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentInstallmentNo = value ?? 0;
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
                                    width: 90,
                                    child: Text(
                                      'الدفعة',
                                      style: TextStyle(
                                        color: Color(0xFFFEC619),
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                DataColumn(
                                  label: SizedBox(
                                    width: 90,
                                    child: Text(
                                      'الوصل',
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
                                          payment['plan_name'] ?? '',
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
                                      width: 90,
                                      child: Text(
                                        '${payment['installment_no'] ?? ''}',
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    )),
                                    DataCell(SizedBox(
                                      width: 90,
                                      child: Text(
                                        '${payment['receipt_no'] ?? ''}',
                                        style: const TextStyle(color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
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

      // الفصول
      final classesData = await db.getAllClasses();
      final classes = classesData
          .map((c) => {
                'id': c.id?.toString() ?? '',
                'name': c.name,
              })
          .where((c) => (c['id']?.toString() ?? '').isNotEmpty)
          .toList();
      classes.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));

      // الأقساط (plans)
      final plans = <Map<String, dynamic>>[];
      for (final c in classes) {
        final cid = int.tryParse(c['id']?.toString() ?? '');
        if (cid == null) continue;
        final p = await db.getClassTuitionPlans(cid);
        plans.addAll(p);
      }

      // الدفعات (installment_no options) حسب القسط المختار
      final classFilterId = _selectedPaymentClassId;
      final selectedPlanName = _selectedPaymentPlanName.trim();

      final planIdsForFilter = plans
          .where((p) {
            if (classFilterId != 'all') {
              final cid = p['class_id']?.toString() ?? '';
              if (cid != classFilterId) return false;
            }
            if (selectedPlanName.isEmpty) return true;
            return (p['name']?.toString().trim() ?? '') == selectedPlanName;
          })
          .map((p) => (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0)
          .where((x) => x > 0)
          .toSet()
          .toList();

      final installmentRows = <Map<String, dynamic>>[];
      if (planIdsForFilter.isNotEmpty) {
        for (final pid in planIdsForFilter) {
          installmentRows.addAll(await db.getTuitionPlanInstallments(pid));
        }
      }

      // تحميل السجل
      final all = await db.getAllTuitionPaymentsWithDetails();

      final query = _paymentSearchController.text.trim().toLowerCase();
      final planFilterName = selectedPlanName;
      final installmentNo = _selectedPaymentInstallmentNo;

      final filtered = all.where((p) {
        final studentName = p['student_name']?.toString().toLowerCase() ?? '';
        if (query.isNotEmpty && !studentName.contains(query)) return false;

        if (classFilterId != 'all') {
          final cid = p['class_id']?.toString() ?? '';
          if (cid != classFilterId) return false;
        }

        if (planFilterName.isNotEmpty) {
          final pn = p['plan_name']?.toString().trim() ?? '';
          if (pn != planFilterName) return false;
        }

        if (installmentNo > 0) {
          final no = (p['installment_no'] is int)
              ? p['installment_no'] as int
              : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
          if (no != installmentNo) return false;
        }

        return true;
      }).toList();

      // حساب المتبقي لكل دفعة: (مستحق الدفعة - مجموع المدفوعات حتى هذه الدفعة)
      final List<Map<String, dynamic>> enriched = filtered.map((e) => Map<String, dynamic>.from(e)).toList();
      final paymentKeys = <String>{};
      final planIds = <int>{};
      final studentIds = <int>{};
      for (final p in enriched) {
        final pid = (p['plan_id'] is int) ? p['plan_id'] as int : int.tryParse(p['plan_id']?.toString() ?? '') ?? 0;
        final sid = (p['student_id'] is int) ? p['student_id'] as int : int.tryParse(p['student_id']?.toString() ?? '') ?? 0;
        if (pid > 0) planIds.add(pid);
        if (sid > 0) studentIds.add(sid);
        paymentKeys.add('$sid|$pid');
      }

      final installmentsByPlanId = <int, List<Map<String, dynamic>>>{};
      for (final pid in planIds) {
        installmentsByPlanId[pid] = await db.getTuitionPlanInstallments(pid);
      }
      final overridesByPlanStudent = await _dbHelper.getStudentTuitionOverridesMapForPlans(
        studentIds: studentIds.toList(),
        planIds: planIds.toList(),
      );

      int dueFor(int planId, int studentId, int installmentNo) {
        final o = overridesByPlanStudent[planId]?[studentId]?[installmentNo];
        final raw = o?['amount'];
        final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
        if (oa != null && oa > 0) return oa;
        final list = installmentsByPlanId[planId] ?? const <Map<String, dynamic>>[];
        for (final inst in list) {
          final no = (inst['installment_no'] is int)
              ? inst['installment_no'] as int
              : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
          if (no != installmentNo) continue;
          final amt = (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
          return amt;
        }
        return 0;
      }

      // sort to compute cumulative
      enriched.sort((a, b) {
        final da = a['date']?.toString() ?? '';
        final dbb = b['date']?.toString() ?? '';
        final c = da.compareTo(dbb);
        if (c != 0) return c;
        final ia = (a['id'] is int) ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '') ?? 0;
        final ib = (b['id'] is int) ? b['id'] as int : int.tryParse(b['id']?.toString() ?? '') ?? 0;
        return ia.compareTo(ib);
      });

      final paidSoFarByKey = <String, int>{};
      for (final p in enriched) {
        final pid = (p['plan_id'] is int) ? p['plan_id'] as int : int.tryParse(p['plan_id']?.toString() ?? '') ?? 0;
        final sid = (p['student_id'] is int) ? p['student_id'] as int : int.tryParse(p['student_id']?.toString() ?? '') ?? 0;
        final ino = (p['installment_no'] is int)
            ? p['installment_no'] as int
            : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
        final amt = (p['amount'] is int) ? p['amount'] as int : int.tryParse(p['amount']?.toString() ?? '') ?? 0;
        final key = '$sid|$pid|$ino';
        final prev = paidSoFarByKey[key] ?? 0;
        final next = prev + amt;
        paidSoFarByKey[key] = next;
        final due = (sid > 0 && pid > 0 && ino > 0) ? dueFor(pid, sid, ino) : 0;
        final remaining = (due - next) > 0 ? (due - next) : 0;
        p['remaining_after'] = remaining;
      }

      // إحصائيات عامة
      int totalPayments = filtered.length;
      int totalAmount = 0;
      for (final p in filtered) {
        final a = p['amount'];
        final ai = (a is int) ? a : int.tryParse(a?.toString() ?? '') ?? 0;
        totalAmount += ai;
      }

      final statistics = {
        'total_payments': totalPayments,
        'total_amount': totalAmount,
      };

      return {
        'payments': enriched,
        'statistics': statistics,
        'courseStatistics': <Map<String, dynamic>>[],
        'locations': classes.map((c) => c['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList(),
        'courses': plans,
        'installments': installmentRows,
        'classes': classes,
      };
    } catch (e) {
      print('Error loading payment data: $e');
      return {
        'payments': <Map<String, dynamic>>[],
        'statistics': <String, dynamic>{},
        'courseStatistics': <Map<String, dynamic>>[],
        'locations': <String>[],
        'courses': <Map<String, dynamic>>[],
        'installments': <Map<String, dynamic>>[],
        'classes': <Map<String, dynamic>>[],
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
      await _dbHelper.deleteTuitionPayment(paymentId);
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
                  await _updatePayment(payment['id'], newAmount, dateController.text);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updatePayment(int paymentId, int newAmount, String newDate) async {
    try {
      await _dbHelper.updateTuitionPaymentAmount(paymentId, newAmount, newDate);
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
                        4: const pw.FlexColumnWidth(1),
                        5: const pw.FlexColumnWidth(1),
                        6: const pw.FlexColumnWidth(1.5),
                        7: const pw.FlexColumnWidth(1.5),
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
                                'الدفعة',
                                style: pw.TextStyle(
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColor.fromInt(0xFFFEC619),
                                ),
                              ),
                            ),
                            pw.Container(
                              padding: pw.EdgeInsets.all(8),
                              child: pw.Text(
                                'الوصل',
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
                                child: pw.Text(payment['plan_name'] ?? '', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text('${payment['installment_no'] ?? ''}', style: pw.TextStyle(fontSize: 10)),
                              ),
                              pw.Container(
                                padding: pw.EdgeInsets.all(8),
                                child: pw.Text('${payment['receipt_no'] ?? ''}', style: pw.TextStyle(fontSize: 10)),
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
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
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
    return Column(
      children: [
        _buildSlimStatTile(
          title: 'إجمالي الطلاب',
          value: _totalStudents.toString(),
          subtitle: 'من الطلاب',
        ),
        const SizedBox(height: 10),
        _buildSlimStatTile(
          title: 'المبالغ المستلمة',
          value: _formatIqd(_receivedRevenue),
          subtitle: 'من الطلاب',
        ),
        const SizedBox(height: 10),
        _buildSlimStatTile(
          title: 'النقد الحالي',
          value: _formatIqd(_currentCash),
          subtitle: 'بعد الواردات والصادرات',
        ),
        const SizedBox(height: 10),
        _buildSlimStatTile(
          title: 'المبالغ المتوقعة (المتبقي)',
          value: _formatIqd(_expectedRemainingRevenue),
          subtitle: 'المتبقي من الدفعات غير المدفوعة',
        ),
        const SizedBox(height: 10),
        _buildSlimStatTile(
          title: 'إجمالي السحب',
          value: _formatIqd(_totalCashWithdrawals),
          subtitle: 'بعد السحب',
        ),
        const SizedBox(height: 10),
        _buildSlimStatTile(
          title: 'إجمالي الإيراد',
          value: _formatIqd(_totalCashIncomes),
          subtitle: 'بعد السحب و الإيراد',
        ),
      ],
    );
  }

  Widget _buildCashHeaderCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddWithdrawalDialog() async {
    final amountCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('سحب', style: TextStyle(color: Color(0xFFFEC619))),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'مبلغ السحب',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: purposeCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'غرض السحب',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'اسم الساحب',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFFEC619),
                                    onPrimary: Color(0xFF1A1A1A),
                                    surface: Color(0xFF2A2A2A),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child ?? const SizedBox.shrink(),
                              );
                            },
                          );
                          if (picked == null) return;
                          setLocal(() {
                            selectedDate = picked;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A3A3A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: Colors.grey),
                              const SizedBox(width: 10),
                              Text(
                                DateFormat('yyyy-MM-dd').format(selectedDate),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('إضافة', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال مبلغ سحب صحيح')),
      );
      return;
    }

    await _dbHelper.addCashWithdrawal(
      amount: amount,
      withdrawDate: DateFormat('yyyy-MM-dd').format(selectedDate),
      purpose: purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim(),
      withdrawerName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    await _loadCashTabsData();
    await _recomputeDashboardStats();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إضافة عملية السحب')),
    );
  }

  Future<void> _openAddIncomeDialog() async {
    final amountCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime selectedDate = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('إضافة وارد', style: TextStyle(color: Color(0xFFFEC619))),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: amountCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'مبلغ الإيراد',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: purposeCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'غرض الإيراد',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'اسم المورد',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFFFEC619),
                                    onPrimary: Color(0xFF1A1A1A),
                                    surface: Color(0xFF2A2A2A),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child ?? const SizedBox.shrink(),
                              );
                            },
                          );
                          if (picked == null) return;
                          setLocal(() {
                            selectedDate = picked;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3A3A3A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: Colors.grey),
                              const SizedBox(width: 10),
                              Text(
                                DateFormat('yyyy-MM-dd').format(selectedDate),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteCtrl,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظة',
                          labelStyle: TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Color(0xFF3A3A3A),
                          border: OutlineInputBorder(borderSide: BorderSide.none),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text('إضافة', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    final amount = int.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال مبلغ إيراد صحيح')),
      );
      return;
    }

    await _dbHelper.addCashIncome(
      amount: amount,
      incomeDate: DateFormat('yyyy-MM-dd').format(selectedDate),
      purpose: purposeCtrl.text.trim().isEmpty ? null : purposeCtrl.text.trim(),
      supplierName: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    await _loadCashTabsData();
    await _recomputeDashboardStats();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تمت إضافة الإيراد')),
    );
  }

  Widget _buildCashWithdrawalsTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCashTabsData();
        await _recomputeDashboardStats();
      },
      color: const Color(0xFFFEC619),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildCashHeaderCard(
                    title: 'النقد الحالي',
                    value: _formatIqd(_currentCash),
                    icon: Icons.account_balance_wallet,
                    color: const Color(0xFFFEC619),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCashHeaderCard(
                    title: 'إجمالي المسحوبات',
                    value: _formatIqd(_totalCashWithdrawals),
                    icon: Icons.arrow_circle_up,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddWithdrawalDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('سحب', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('عمليات السحب', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_cashWithdrawalsRows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Center(child: Text('لا توجد عمليات سحب', style: TextStyle(color: Colors.grey))),
              ),
            if (_cashWithdrawalsRows.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _cashWithdrawalsRows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = _cashWithdrawalsRows[i];
                  final id = (r['id'] is int) ? r['id'] as int : int.tryParse(r['id']?.toString() ?? '') ?? 0;
                  final amount = (r['amount'] is int) ? r['amount'] as int : int.tryParse(r['amount']?.toString() ?? '') ?? 0;
                  final name = (r['withdrawer_name']?.toString() ?? '').trim();
                  final date = (r['withdraw_date']?.toString() ?? '').trim();
                  final purpose = (r['purpose']?.toString() ?? '').trim();
                  final note = (r['note']?.toString() ?? '').trim();

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF2A2A2A),
                                    title: Text(name.isEmpty ? 'سحب' : name, style: const TextStyle(color: Color(0xFFFEC619))),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('المبلغ: ${_formatIqd(amount)}', style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 8),
                                        Text('التاريخ: $date', style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 8),
                                        if (purpose.isNotEmpty)
                                          Text('الغرض: $purpose', style: const TextStyle(color: Colors.white)),
                                        if (note.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text('ملاحظة: $note', style: const TextStyle(color: Colors.white)),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isEmpty ? 'بدون اسم' : name,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(date, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatIqd(amount), style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            IconButton(
                              onPressed: id <= 0
                                  ? null
                                  : () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            backgroundColor: const Color(0xFF2A2A2A),
                                            title: const Text('حذف السحب', style: TextStyle(color: Colors.redAccent)),
                                            content: const Text('هل تريد حذف عملية السحب؟', style: TextStyle(color: Colors.white)),
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
                                          );
                                        },
                                      );
                                      if (ok != true) return;
                                      await _dbHelper.deleteCashWithdrawal(id);
                                      await _loadCashTabsData();
                                      await _recomputeDashboardStats();
                                    },
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashIncomesTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadCashTabsData();
        await _recomputeDashboardStats();
      },
      color: const Color(0xFFFEC619),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildCashHeaderCard(
                    title: 'النقد الحالي',
                    value: _formatIqd(_currentCash),
                    icon: Icons.account_balance_wallet,
                    color: const Color(0xFFFEC619),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCashHeaderCard(
                    title: 'إجمالي الواردات',
                    value: _formatIqd(_totalCashIncomes),
                    icon: Icons.arrow_circle_down,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openAddIncomeDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('إضافة وارد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('عمليات الوارد', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            if (_cashIncomesRows.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Center(child: Text('لا توجد واردات', style: TextStyle(color: Colors.grey))),
              ),
            if (_cashIncomesRows.isNotEmpty)
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _cashIncomesRows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final r = _cashIncomesRows[i];
                  final id = (r['id'] is int) ? r['id'] as int : int.tryParse(r['id']?.toString() ?? '') ?? 0;
                  final amount = (r['amount'] is int) ? r['amount'] as int : int.tryParse(r['amount']?.toString() ?? '') ?? 0;
                  final name = (r['supplier_name']?.toString() ?? '').trim();
                  final date = (r['income_date']?.toString() ?? '').trim();
                  final purpose = (r['purpose']?.toString() ?? '').trim();
                  final note = (r['note']?.toString() ?? '').trim();

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.green.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              await showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF2A2A2A),
                                    title: Text(name.isEmpty ? 'وارد' : name, style: const TextStyle(color: Color(0xFFFEC619))),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('المبلغ: ${_formatIqd(amount)}', style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 8),
                                        Text('التاريخ: $date', style: const TextStyle(color: Colors.white)),
                                        const SizedBox(height: 8),
                                        if (purpose.isNotEmpty)
                                          Text('الغرض: $purpose', style: const TextStyle(color: Colors.white)),
                                        if (note.isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Text('ملاحظة: $note', style: const TextStyle(color: Colors.white)),
                                        ],
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('إغلاق', style: TextStyle(color: Colors.grey)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name.isEmpty ? 'بدون اسم' : name,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 6),
                                Text(date, style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_formatIqd(amount), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            IconButton(
                              onPressed: id <= 0
                                  ? null
                                  : () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (context) {
                                          return AlertDialog(
                                            backgroundColor: const Color(0xFF2A2A2A),
                                            title: const Text('حذف الإيراد', style: TextStyle(color: Colors.redAccent)),
                                            content: const Text('هل تريد حذف عملية الإيراد؟', style: TextStyle(color: Colors.white)),
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
                                          );
                                        },
                                      );
                                      if (ok != true) return;
                                      await _dbHelper.deleteCashIncome(id);
                                      await _loadCashTabsData();
                                      await _recomputeDashboardStats();
                                    },
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlimStatTile({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                value,
                style: const TextStyle(color: Color(0xFFFEC619), fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
          ),
        ],
      ),
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
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إحصائيات الحالة',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildStatusItem('إجمالي المدفوعات', _receivedRevenue),
          const SizedBox(height: 12),
          _buildStatusItem('الطلاب المتأخرين بالدفع', _firstInstallmentLate),
          const SizedBox(height: 12),
          _buildStatusItem('إجمالي الطلاب المخفضين', _discountedStudentsCount),
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
                  'الإيرادات حسب الفصل',
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
                          'الفصل',
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
    final classItems = _classes
        .where((c) => (c['id']?.toString() ?? '').isNotEmpty)
        .toList()
      ..sort((a, b) {
        final an = a['name']?.toString() ?? '';
        final bn = b['name']?.toString() ?? '';
        return an.compareTo(bn);
      });

    final visibleClasses = (_pricingPageClassFilterId == 'all')
        ? classItems
        : classItems.where((c) => c['id']?.toString() == _pricingPageClassFilterId).toList();

    final installmentNos = _pricingInstallmentsForPlan
        .map((i) => (i['installment_no'] is int)
            ? i['installment_no'] as int
            : int.tryParse(i['installment_no']?.toString() ?? '') ?? 0)
        .where((n) => n > 0)
        .toList();
    installmentNos.sort();

    String _planName(int planId) {
      try {
        final p = _pricingPlansForClass.firstWhere((x) {
          final id = (x['id'] is int) ? x['id'] as int : int.tryParse(x['id']?.toString() ?? '') ?? 0;
          return id == planId;
        });
        return p['name']?.toString() ?? '';
      } catch (_) {
        return '';
      }
    }

    Map<String, dynamic> _getEffectiveForStudentInstallment({
      required int studentId,
      required int installmentNo,
    }) {
      final override = _pricingOverridesByStudentInstallment[studentId]?[installmentNo];
      if (override != null) {
        final amount = (override['amount'] is int)
            ? override['amount'] as int
            : int.tryParse(override['amount']?.toString() ?? '') ?? 0;
        return {
          'amount': amount,
          'dueDate': override['due_date']?.toString() ?? '',
          'isOverride': true,
        };
      }

      try {
        final inst = _pricingInstallmentsForPlan.firstWhere((x) {
          final no = (x['installment_no'] is int)
              ? x['installment_no'] as int
              : int.tryParse(x['installment_no']?.toString() ?? '') ?? 0;
          return no == installmentNo;
        });
        final amount = (inst['amount'] is int)
            ? inst['amount'] as int
            : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
        return {
          'amount': amount,
          'dueDate': inst['due_date']?.toString() ?? '',
          'isOverride': false,
        };
      } catch (_) {
        return {'amount': 0, 'dueDate': '', 'isOverride': false};
      }
    }

    String _baseDueDateForInstallment(int installmentNo) {
      try {
        final inst = _pricingInstallmentsForPlan.firstWhere((x) {
          final no = (x['installment_no'] is int)
              ? x['installment_no'] as int
              : int.tryParse(x['installment_no']?.toString() ?? '') ?? 0;
          return no == installmentNo;
        });
        return inst['due_date']?.toString() ?? '';
      } catch (_) {
        return '';
      }
    }

    Future<void> _openCreatePlanDialog({required String classIdStr}) async {
      final classId = int.tryParse(classIdStr);
      if (classId == null || classId <= 0) return;

      final existingPlans = await _dbHelper.getClassTuitionPlans(classId);
      final autoName = 'قسط ${existingPlans.length + 1}';

      final totalController = TextEditingController();
      final countController = TextEditingController();

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setLocalState) {
              int count = int.tryParse(countController.text.trim()) ?? 0;
              if (count < 0) count = 0;
              if (count > 60) count = 60;

              final instAmountControllers = List.generate(count, (_) => TextEditingController());
              final instDueControllers = List.generate(count, (_) => TextEditingController());

              InputDecoration greyBox(String label) {
                return InputDecoration(
                  labelText: label,
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF3A3A3A),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade600),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFFEC619), width: 1.5),
                  ),
                );
              }

              Future<void> pickDueDateFor(int i) async {
                DateTime? initial;
                final current = instDueControllers[i].text.trim();
                if (current.isNotEmpty) {
                  initial = DateTime.tryParse(current);
                }
                final picked = await showDatePicker(
                  context: context,
                  initialDate: initial ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                instDueControllers[i].text = DateFormat('yyyy-MM-dd').format(picked);
              }

              return AlertDialog(
                backgroundColor: const Color(0xFF2A2A2A),
                title: const Text('إنشاء قسط', style: TextStyle(color: Color(0xFFFEC619))),
                content: SizedBox(
                  width: 560,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اسم القسط: $autoName', style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: totalController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.white),
                          decoration: greyBox('مبلغ القسط'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: countController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.white),
                          decoration: greyBox('عدد الدفعات'),
                          onChanged: (_) => setLocalState(() {}),
                        ),
                        const SizedBox(height: 16),
                        if (count > 0) ...[
                          const Text('تفاصيل الدفعات', style: TextStyle(color: Colors.white)),
                          const SizedBox(height: 12),
                          ...List.generate(count, (i) {
                            final no = i + 1;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('الدفعة $no', style: const TextStyle(color: Colors.white)),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: instAmountControllers[i],
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: greyBox('سعر الدفعة'),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: instDueControllers[i],
                                    readOnly: true,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: greyBox('تاريخ آخر السداد (YYYY-MM-DD)'),
                                    onTap: () => pickDueDateFor(i),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final total = int.tryParse(totalController.text.trim()) ?? 0;
                      final cnt = int.tryParse(countController.text.trim()) ?? 0;
                      if (total <= 0 || cnt <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إدخال مبلغ وعدد دفعات صحيح')),
                        );
                        return;
                      }
                      if (cnt != count) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('يرجى إعادة إدخال عدد الدفعات')),
                        );
                        return;
                      }
                      final installments = <Map<String, dynamic>>[];
                      for (int i = 0; i < cnt; i++) {
                        final amount = int.tryParse(instAmountControllers[i].text.trim()) ?? 0;
                        final due = instDueControllers[i].text.trim();
                        if (amount <= 0 || due.isEmpty || DateTime.tryParse(due) == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('يرجى إدخال مبلغ وتاريخ صحيح لكل دفعة')),
                          );
                          return;
                        }
                        installments.add({'installment_no': i + 1, 'amount': amount, 'due_date': due});
                      }
                      Navigator.pop(context, {
                        'name': autoName,
                        'total': total,
                        'installments': installments,
                      });
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                    child: const Text('حفظ', style: TextStyle(color: Color(0xFF1A1A1A))),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء إنشاء القسط')),
          );
        }
        return;
      }

      final name = result['name']?.toString() ?? '';
      final total = result['total'] as int? ?? 0;
      final installments = (result['installments'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
      if (name.isEmpty || total <= 0 || installments.isEmpty) return;

      final planId = await _dbHelper.createClassTuitionPlan(
        classId: classId,
        name: name,
        totalAmount: total,
        installments: installments,
      );

      if (!mounted) return;
      setState(() {
        _pricingSelectedPlanByClassId[classIdStr] = planId;
        _pricingActiveClassId = classIdStr;
        _pricingActivePlanId = planId;
      });
      await _loadPricingPlansForSelectedClass();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنشاء القسط بنجاح')),
        );
      }
    }

    Future<void> _openOverrideDialog({
      required int studentId,
      required List<int> installmentNos,
    }) async {
      final planId = _pricingActivePlanId;
      if (planId <= 0) return;

      installmentNos = installmentNos.where((n) => n > 0).toList()..sort();
      if (installmentNos.isEmpty) return;

      InputDecoration _greyBox(String label) {
        return InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: const Color(0xFF3A3A3A),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: Colors.grey.shade700, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFFEC619), width: 1.5),
          ),
        );
      }

      final baseAmountByNo = <int, int>{};
      for (final inst in _pricingInstallmentsForPlan) {
        final no = (inst['installment_no'] is int)
            ? inst['installment_no'] as int
            : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
        final amount = (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
        if (no > 0 && amount > 0) baseAmountByNo[no] = amount;
      }
      int originalTotal = 0;
      for (final n in installmentNos) {
        originalTotal += baseAmountByNo[n] ?? 0;
      }

      final discountedTotalController = TextEditingController();
      final reasonController = TextEditingController();

      final amountControllers = <int, TextEditingController>{};
      final dueControllers = <int, TextEditingController>{};
      for (final n in installmentNos) {
        final existing = _pricingOverridesByStudentInstallment[studentId]?[n];
        amountControllers[n] = TextEditingController(text: existing?['amount']?.toString() ?? '');
        dueControllers[n] = TextEditingController(text: existing?['due_date']?.toString() ?? '');
        discountedTotalController.text = '';
        reasonController.text = existing?['reason']?.toString() ?? '';
      }

      final bool hasAnyOverride = (_pricingOverridesByStudentInstallment[studentId]?.isNotEmpty ?? false);

      Future<void> _pickDueDateFor(int installmentNo) async {
        final controller = dueControllers[installmentNo]!;
        DateTime? initial;
        final current = controller.text.trim();
        if (current.isNotEmpty) {
          initial = DateTime.tryParse(current);
        }
        final picked = await showDatePicker(
          context: context,
          initialDate: initial ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked == null) return;
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: const Color(0xFF2A2A2A),
            title: const Text('التخفيض', style: TextStyle(color: Color(0xFFFEC619))),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('القسط الكامل: ${_formatIqd(originalTotal)}', style: const TextStyle(color: Colors.white)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: discountedTotalController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white),
                      decoration: _greyBox('بعد التخفيض'),
                    ),
                    const SizedBox(height: 16),
                    const Text('تفاصيل الدفعات', style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 12),
                    ...installmentNos.map((n) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الدفعة $n', style: const TextStyle(color: Colors.white)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: amountControllers[n],
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: const TextStyle(color: Colors.white),
                              decoration: _greyBox('مبلغ الدفعة بعد التخفيض'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: dueControllers[n],
                              readOnly: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: _greyBox('آخر تاريخ للسداد (YYYY-MM-DD)'),
                              onTap: () => _pickDueDateFor(n),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _greyBox('سبب التخفيض'),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
              ),
              if (hasAnyOverride)
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context, null);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.redAccent),
                    foregroundColor: Colors.redAccent,
                  ),
                  child: const Text('إلغاء التخفيض'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                child: const Text('حفظ', style: TextStyle(color: Color(0xFF1A1A1A))),
              ),
            ],
          );
        },
      );

      if (ok == null) {
        for (final n in installmentNos) {
          await _dbHelper.deleteStudentTuitionOverride(
            studentId: studentId,
            planId: planId,
            installmentNo: n,
          );
        }
        await _loadPricingDataForSelectedPlan();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إلغاء التخفيض')),
          );
        }
        return;
      }

      if (ok != true) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم الإلغاء')),
          );
        }
        return;
      }
      final discountedTotal = int.tryParse(discountedTotalController.text.trim()) ?? 0;
      if (discountedTotal <= 0) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('يرجى إدخال مبلغ بعد التخفيض بشكل صحيح')),
          );
        }
        return;
      }

      int sum = 0;
      for (final n in installmentNos) {
        final amount = int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
        final due = dueControllers[n]!.text.trim();
        if (amount <= 0 || due.isEmpty || DateTime.tryParse(due) == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('يرجى إدخال مبلغ وتاريخ صحيح لكل دفعة')),
            );
          }
          return;
        }
        sum += amount;
      }
      if (sum != discountedTotal) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('مجموع الدفعات يجب أن يساوي المبلغ بعد التخفيض')),
          );
        }
        return;
      }

      final reason = reasonController.text.trim();

      bool anyAmountChanged = false;
      for (final n in installmentNos) {
        final amount = int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
        if (amount != (baseAmountByNo[n] ?? 0)) {
          anyAmountChanged = true;
          break;
        }
      }

      if (!anyAmountChanged) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حفظ سبب التخفيض بدون تعديل مبالغ الدفعات')),
          );
        }
        return;
      }

      for (final n in installmentNos) {
        final amount = int.tryParse(amountControllers[n]!.text.trim()) ?? 0;
        final due = dueControllers[n]!.text.trim();
        await _dbHelper.upsertStudentTuitionOverride(
          studentId: studentId,
          planId: planId,
          installmentNo: n,
          amount: amount,
          dueDate: due,
          reason: reason.isEmpty ? null : reason,
        );
      }

      await _loadPricingDataForSelectedPlan();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ التخفيض')),
        );
      }
    }

    Future<void> _openDiscountMenuForStudent({
      required int studentId,
      required List<int> installmentNos,
    }) async {
      if (installmentNos.isEmpty) return;
      await _openOverrideDialog(studentId: studentId, installmentNos: installmentNos);
    }

    Widget _buildPricingTable({
      required String planName,
      required List<int> installmentNos,
      required String Function(int installmentNo) baseDueDateForInstallment,
      required Future<void> Function({required int studentId, required List<int> installmentNos}) openDiscountMenuForStudent,
      required List<Map<String, dynamic>> students,
    }) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              planName,
              style: const TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(const Color(0xFF1A1A1A)),
                dataRowColor: MaterialStateProperty.all(const Color(0xFF2A2A2A)),
                columns: [
                  const DataColumn(
                    label: Text('الطالب', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                  ),
                  const DataColumn(
                    label: Text('تخفيض', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                  ),
                  const DataColumn(
                    label: Text('سبب التخفيض', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                  ),
                  const DataColumn(
                    label: Text('المبلغ الكلي', style: TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold)),
                  ),
                  ...installmentNos.map(
                    (n) => DataColumn(
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'دفعة $n',
                            style: const TextStyle(color: Color(0xFFFEC619), fontWeight: FontWeight.bold, height: 1.15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            baseDueDateForInstallment(n),
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 11, height: 1.1),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                rows: students.map((s) {
                  final sid = int.tryParse(s['id']?.toString() ?? '') ?? 0;
                  final name = s['name']?.toString() ?? '';
                  final hasAnyOverride = (_pricingOverridesByStudentInstallment[sid]?.isNotEmpty ?? false);

                  String discountReason = '';
                  if (hasAnyOverride) {
                    final byInstallment = _pricingOverridesByStudentInstallment[sid]!;
                    for (final n in installmentNos) {
                      final r = byInstallment[n]?['reason']?.toString() ?? '';
                      if (r.trim().isNotEmpty) {
                        discountReason = r.trim();
                        break;
                      }
                    }
                  }

                  int totalForStudent = 0;
                  for (final n in installmentNos) {
                    final eff = _getEffectiveForStudentInstallment(studentId: sid, installmentNo: n);
                    totalForStudent += (eff['amount'] as int? ?? 0);
                  }

                  return DataRow(
                    cells: [
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            InkWell(
                              onTap: sid <= 0 || _pricingActivePlanId <= 0
                                  ? null
                                  : () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => StudentFinancialDetailsScreen(
                                            studentId: sid,
                                            planId: _pricingActivePlanId,
                                          ),
                                        ),
                                      );
                                      await _loadPricingDataForSelectedPlan();
                                    },
                              child: Text(name, style: const TextStyle(color: Colors.white)),
                            ),
                            if (hasAnyOverride)
                              Text(
                                'لديه تخفيض',
                                style: TextStyle(color: Colors.green.shade300, fontSize: 11),
                              ),
                          ],
                        ),
                      ),
                      DataCell(
                        ElevatedButton(
                          onPressed: sid <= 0
                              ? null
                              : () => openDiscountMenuForStudent(studentId: sid, installmentNos: installmentNos),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          child: const Text('تخفيض', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 160,
                          child: Text(
                            discountReason,
                            style: const TextStyle(color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_formatIqd(totalForStudent), style: const TextStyle(color: Colors.white))),
                      ...installmentNos.map((n) {
                        final eff = _getEffectiveForStudentInstallment(studentId: sid, installmentNo: n);
                        final amount = eff['amount'] as int? ?? 0;
                        final isOverride = eff['isOverride'] == true;
                        final due = (eff['dueDate']?.toString() ?? '').trim();
                        final baseAmount = (() {
                          try {
                            final inst = _pricingInstallmentsForPlan.firstWhere((x) {
                              final no = (x['installment_no'] is int)
                                  ? x['installment_no'] as int
                                  : int.tryParse(x['installment_no']?.toString() ?? '') ?? 0;
                              return no == n;
                            });
                            return (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
                          } catch (_) {
                            return 0;
                          }
                        })();

                        return DataCell(
                          SizedBox(
                            width: 140,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (due.isNotEmpty) ...[
                                  Text(
                                    due,
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                ],
                                Text(
                                  _formatIqd(amount),
                                  style: TextStyle(
                                    color: isOverride ? const Color(0xFFFEC619) : Colors.white,
                                    fontWeight: isOverride ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                if (isOverride && baseAmount > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatIqd(baseAmount),
                                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إضافة الأسعار',
            style: TextStyle(
              color: Color(0xFFFEC619),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.25)),
            ),
            child: SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                value: _pricingPageClassFilterId,
                dropdownColor: const Color(0xFF2A2A2A),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'الفصول',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('جميع الفصول')),
                  ...classItems.map((c) => DropdownMenuItem<String>(
                        value: c['id']?.toString() ?? 'all',
                        child: Text(c['name']?.toString() ?? ''),
                      )),
                ],
                onChanged: (v) {
                  final next = v ?? 'all';
                  setState(() {
                    _pricingPageClassFilterId = next;
                  });

                  if (next != 'all') {
                    final nextPlan = _pricingSelectedPlanByClassId[next] ?? 0;
                    setState(() {
                      _pricingActiveClassId = next;
                      _pricingActivePlanId = nextPlan;
                    });
                    _loadPricingPlansForSelectedClass();
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...visibleClasses.map((c) {
            final classIdStr = c['id']?.toString() ?? '';
            final className = c['name']?.toString() ?? '';
            final selectedPlanForClass = _pricingSelectedPlanByClassId[classIdStr] ?? 0;
            final bool isActive = (_pricingActiveClassId == classIdStr) && (_pricingActivePlanId > 0);

            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    className,
                    style: const TextStyle(color: Color(0xFFFEC619), fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _dbHelper.getClassTuitionPlans(int.tryParse(classIdStr) ?? 0),
                    builder: (context, snap) {
                      final plans = snap.data ?? const <Map<String, dynamic>>[];
                      final ids = plans
                          .map((p) => (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0)
                          .where((id) => id > 0)
                          .toSet();
                      final effectiveSelected = ids.contains(selectedPlanForClass) ? selectedPlanForClass : 0;

                      return Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: effectiveSelected,
                              dropdownColor: const Color(0xFF2A2A2A),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'القسط',
                                labelStyle: const TextStyle(color: Colors.grey),
                                filled: true,
                                fillColor: const Color(0xFF2A2A2A),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(value: 0, child: Text('اختر القسط')),
                                ...plans.map((p) {
                                  final id = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                                  final name = p['name']?.toString() ?? '';
                                  return DropdownMenuItem(value: id, child: Text(name));
                                }),
                              ],
                              onChanged: (v) {
                                final pid = v ?? 0;
                                setState(() {
                                  _pricingSelectedPlanByClassId[classIdStr] = pid;
                                  _pricingActiveClassId = classIdStr;
                                  _pricingActivePlanId = pid;
                                });
                                _loadPricingPlansForSelectedClass();
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'تصدير PDF',
                            onPressed: effectiveSelected <= 0
                                ? null
                                : () => _exportPricingTablePdf(
                                      classId: int.tryParse(classIdStr) ?? 0,
                                      className: className,
                                      planId: effectiveSelected,
                                      planName: plans
                                              .firstWhere(
                                                (p) {
                                                  final id = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                                                  return id == effectiveSelected;
                                                },
                                                orElse: () => const <String, dynamic>{},
                                              )
                                              .isNotEmpty
                                          ? (plans.firstWhere((p) {
                                              final id = (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0;
                                              return id == effectiveSelected;
                                            })['name']?.toString() ?? '')
                                          : '',
                                    ),
                            icon: const Icon(Icons.picture_as_pdf, color: Color(0xFFFEC619)),
                          ),
                          ElevatedButton.icon(
                            onPressed: () => _openCreatePlanDialog(classIdStr: classIdStr),
                            icon: const Icon(Icons.add, color: Color(0xFF1A1A1A)),
                            label: const Text('إضافة قسط', style: TextStyle(color: Color(0xFF1A1A1A))),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_pricingActiveClassId != classIdStr || _pricingActivePlanId <= 0)
                    const Text('اختر قسطاً لعرض الأسعار', style: TextStyle(color: Colors.grey)),
                  if (isActive)
                    _buildPricingTable(
                      planName: _planName(_pricingActivePlanId),
                      installmentNos: installmentNos,
                      baseDueDateForInstallment: _baseDueDateForInstallment,
                      openDiscountMenuForStudent: _openDiscountMenuForStudent,
                      students: _pricingStudentsForClass,
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
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

  Future<void> _loadTuitionPlansForSelectedClass() async {
    final classId = int.tryParse(_selectedClassId);
    if (classId == null || classId <= 0) {
      if (!mounted) return;
      setState(() {
        _tuitionPlansForClass = [];
        _tuitionInstallmentsForPlan = [];
        _selectedTuitionPlanId = 0;
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
      return;
    }

    try {
      final plans = await _dbHelper.getClassTuitionPlans(classId);
      if (!mounted) return;
      setState(() {
        _tuitionPlansForClass = plans;
        _tuitionInstallmentsForPlan = [];
        _selectedTuitionPlanId = 0;
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tuitionPlansForClass = [];
        _tuitionInstallmentsForPlan = [];
        _selectedTuitionPlanId = 0;
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
    }
  }

  Future<void> _loadTuitionInstallmentsForSelectedPlan() async {
    if (_selectedTuitionPlanId <= 0) {
      if (!mounted) return;
      setState(() {
        _tuitionInstallmentsForPlan = [];
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
      return;
    }

    try {
      final inst = await _dbHelper.getTuitionPlanInstallments(_selectedTuitionPlanId);
      if (!mounted) return;
      setState(() {
        _tuitionInstallmentsForPlan = inst;
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _tuitionInstallmentsForPlan = [];
        _selectedTuitionInstallmentNo = 0;
        _amountController.clear();
      });
    }
  }

  Future<void> _updateAmountForSelectedTuitionInstallment() async {
    final studentId = int.tryParse(_selectedStudentId);
    if (studentId == null || _selectedTuitionPlanId <= 0 || _selectedTuitionInstallmentNo <= 0) {
      _amountController.clear();
      return;
    }

    try {
      final effective = await _dbHelper.getEffectiveTuitionInstallment(
        studentId: studentId,
        planId: _selectedTuitionPlanId,
        installmentNo: _selectedTuitionInstallmentNo,
      );

      final rawAmount = effective?['amount'];
      final installmentAmount = (rawAmount is int)
          ? rawAmount
          : int.tryParse(rawAmount?.toString() ?? '') ?? 0;

      final paid = await _dbHelper.getTotalPaidForTuitionInstallment(
        studentId: studentId,
        planId: _selectedTuitionPlanId,
        installmentNo: _selectedTuitionInstallmentNo,
      );

      final remaining = (installmentAmount - paid).clamp(0, 1 << 30);
      if (!mounted) return;
      _amountController.text = _formatAmount(remaining.toDouble());
    } catch (_) {
      if (!mounted) return;
      _amountController.clear();
    }
  }

  String _getSelectedTuitionPlanName() {
    if (_selectedTuitionPlanId <= 0) return '';
    try {
      final p = _tuitionPlansForClass.firstWhere((x) {
        final id = (x['id'] is int) ? x['id'] as int : int.tryParse(x['id']?.toString() ?? '') ?? 0;
        return id == _selectedTuitionPlanId;
      });
      return p['name']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<List<Map<String, dynamic>>> _buildRemainingByCourseItems() async {
    if (_selectedClassId.isEmpty) return [];
    if (_selectedStudentId.isEmpty) return [];
    final studentId = int.tryParse(_selectedStudentId);
    if (studentId == null) return [];

    if (_selectedTuitionPlanId <= 0) return [];
    final installments = await _dbHelper.getTuitionPlanInstallments(_selectedTuitionPlanId);
    if (installments.isEmpty) return [];

    final items = <Map<String, dynamic>>[];
    for (final inst in installments) {
      final no = (inst['installment_no'] is int)
          ? inst['installment_no'] as int
          : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
      if (no <= 0) continue;

      final effective = await _dbHelper.getEffectiveTuitionInstallment(
        studentId: studentId,
        planId: _selectedTuitionPlanId,
        installmentNo: no,
      );
      final rawAmount = effective?['amount'];
      final amount = (rawAmount is int) ? rawAmount : int.tryParse(rawAmount?.toString() ?? '') ?? 0;
      final dueDate = (effective?['due_date'] ?? inst['due_date'] ?? '').toString();

      final paid = await _dbHelper.getTotalPaidForTuitionInstallment(
        studentId: studentId,
        planId: _selectedTuitionPlanId,
        installmentNo: no,
      );
      final remaining = (amount - paid).clamp(0, 1 << 30);

      items.add({
        'installmentNo': no,
        'dueDate': dueDate,
        'due': amount,
        'paid': paid,
        'remaining': remaining,
        'label': 'الدفعة $no',
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

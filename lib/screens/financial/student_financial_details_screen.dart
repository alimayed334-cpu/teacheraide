import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../database/database_helper.dart';
import '../../models/student_model.dart';

class StudentFinancialDetailsScreen extends StatefulWidget {
  final int studentId;
  final int planId;

  const StudentFinancialDetailsScreen({
    super.key,
    required this.studentId,
    required this.planId,
  });

  @override
  State<StudentFinancialDetailsScreen> createState() => _StudentFinancialDetailsScreenState();
}

class _StudentFinancialDetailsScreenState extends State<StudentFinancialDetailsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  final TextEditingController _noteCtrl = TextEditingController();

  bool _loading = true;
  StudentModel? _student;

  List<Map<String, dynamic>> _installments = [];
  Map<int, Map<String, dynamic>> _overridesByInstallment = {};
  List<Map<String, dynamic>> _payments = [];

  String _discountReason = '';
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _addNote(String note) async {
    final text = note.trim();
    if (text.isEmpty) return;
    await _dbHelper.addStudentFinancialNote(
      studentId: widget.studentId,
      planId: widget.planId,
      note: text,
    );
    await _load();
  }

  Widget _buildNotesSection() {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        bool saving = false;

        Future<void> add() async {
          if (saving) return;
          final text = _noteCtrl.text;
          if (text.trim().isEmpty) return;
          setLocalState(() {
            saving = true;
          });
          try {
            await _addNote(text);
            _noteCtrl.clear();
          } finally {
            setLocalState(() {
              saving = false;
            });
          }
        }

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
                'الملاحظات المالية',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (_notes.isEmpty) const Text('لا توجد ملاحظات', style: TextStyle(color: Colors.grey)),
              if (_notes.isNotEmpty)
                ..._notes.map((n) {
                  final text = n['note']?.toString() ?? '';
                  final createdAt = (n['created_at']?.toString() ?? '').trim();
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.18)),
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
                controller: _noteCtrl,
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
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  onPressed: saving ? null : add,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                  child: Text(
                    saving ? 'جارِ الإضافة...' : 'إضافة',
                    style: const TextStyle(color: Color(0xFF1A1A1A)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final student = await _dbHelper.getStudent(widget.studentId);
      final installments = await _dbHelper.getTuitionPlanInstallments(widget.planId);
      final overrides = await _dbHelper.getStudentTuitionOverridesMap(
        planId: widget.planId,
        studentIds: [widget.studentId],
      );
      final payments = await _dbHelper.getTuitionPaymentsForStudentPlan(
        studentId: widget.studentId,
        planId: widget.planId,
      );

      final reason = await _dbHelper.getStudentPlanDiscountReason(
        studentId: widget.studentId,
        planId: widget.planId,
      );

      final notes = await _dbHelper.getStudentFinancialNotes(
        studentId: widget.studentId,
        planId: widget.planId,
      );

      final byNo = overrides[widget.studentId] ?? const <int, Map<String, dynamic>>{};

      if (!mounted) return;
      setState(() {
        _student = student;
        _installments = installments;
        _overridesByInstallment = byNo;
        _payments = payments;
        _discountReason = reason ?? '';
        _notes = notes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  int _baseAmountFor(int installmentNo) {
    for (final inst in _installments) {
      final n = (inst['installment_no'] is int)
          ? inst['installment_no'] as int
          : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
      if (n != installmentNo) continue;
      return (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  String _baseDueFor(int installmentNo) {
    for (final inst in _installments) {
      final n = (inst['installment_no'] is int)
          ? inst['installment_no'] as int
          : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
      if (n != installmentNo) continue;
      return inst['due_date']?.toString() ?? '';
    }
    return '';
  }

  int _effectiveDueAmountFor(int installmentNo) {
    final o = _overridesByInstallment[installmentNo];
    final raw = o?['amount'];
    final oa = (raw is int) ? raw : int.tryParse(raw?.toString() ?? '');
    if (oa != null && oa > 0) return oa;
    return _baseAmountFor(installmentNo);
  }

  String _effectiveDueDateFor(int installmentNo) {
    final o = _overridesByInstallment[installmentNo];
    final od = o?['due_date']?.toString().trim() ?? '';
    if (od.isNotEmpty) return od;
    return _baseDueFor(installmentNo);
  }

  _InstallmentCardData _computeInstallment(int installmentNo) {
    final dueAmount = _effectiveDueAmountFor(installmentNo);
    final dueDateStr = _effectiveDueDateFor(installmentNo);
    final dueDate = DateTime.tryParse(dueDateStr);

    final instPayments = _payments.where((p) {
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
        final d = DateTime.tryParse(p['payment_date']?.toString() ?? '');
        if (d != null) completionDate = d;
      }
    }

    final remaining = (dueAmount - paidSum) > 0 ? (dueAmount - paidSum) : 0;
    final isComplete = dueAmount > 0 && paidSum >= dueAmount;

    int? daysLate;
    final now = DateTime.now();
    if (dueDate != null) {
      final ref = isComplete ? (completionDate ?? now) : now;
      final diffDays = ref.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
      if (diffDays > 0 && (!isComplete || (completionDate != null && completionDate!.isAfter(dueDate)))) {
        daysLate = diffDays;
      }
    }

    final isLateNow = !isComplete && daysLate != null && daysLate > 0;

    return _InstallmentCardData(
      installmentNo: installmentNo,
      dueAmount: dueAmount,
      dueDate: dueDateStr,
      paidSum: paidSum,
      remaining: remaining,
      paymentsCount: count,
      completionDate: completionDate == null ? '' : DateFormat('yyyy-MM-dd').format(completionDate!),
      daysLate: daysLate,
      isLateNow: isLateNow,
      isComplete: isComplete,
    );
  }

  String _formatIqd(dynamic amount) {
    if (amount == null) return '0 د.ع';
    final num? parsed = (amount is num) ? amount : num.tryParse(amount.toString().replaceAll(',', '').replaceAll('د.ع', '').trim());
    if (parsed == null) return '0 د.ع';
    final fmt = NumberFormat('#,###');
    return '${fmt.format(parsed)} د.ع';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: const Text('تفاصيل الطالب'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFEC619)))
          : RefreshIndicator(
              onRefresh: _load,
              color: const Color(0xFFFEC619),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildDiscountSection(),
                    const SizedBox(height: 16),
                    _buildInstallmentsSection(),
                    const SizedBox(height: 16),
                    _buildNotesSection(),
                  ],
                ),
              ),
            ),
    );
  }

  int _totalBeforeDiscount() {
    int sum = 0;
    for (final inst in _installments) {
      final a = (inst['amount'] is int) ? inst['amount'] as int : int.tryParse(inst['amount']?.toString() ?? '') ?? 0;
      sum += a;
    }
    return sum;
  }

  int _totalAfterDiscount() {
    int sum = 0;
    for (final inst in _installments) {
      final n = (inst['installment_no'] is int)
          ? inst['installment_no'] as int
          : int.tryParse(inst['installment_no']?.toString() ?? '') ?? 0;
      if (n <= 0) continue;
      sum += _effectiveDueAmountFor(n);
    }
    return sum;
  }

  Future<void> _openDiscountEditDialog() async {
    if (_installments.isEmpty) return;

    final installmentNos = _installments
        .map((r) => (r['installment_no'] is int) ? r['installment_no'] as int : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0)
        .where((n) => n > 0)
        .toList()
      ..sort();

    final reasonCtrl = TextEditingController(text: _discountReason);
    final Map<int, TextEditingController> amountCtrls = {};
    final Map<int, TextEditingController> dueCtrls = {};

    for (final n in installmentNos) {
      amountCtrls[n] = TextEditingController(text: _effectiveDueAmountFor(n).toString());
      dueCtrls[n] = TextEditingController(text: _effectiveDueDateFor(n));
    }

    bool saving = false;

    Future<void> save(StateSetter setLocalState) async {
      if (saving) return;
      setLocalState(() {
        saving = true;
      });

      try {
        bool anyAmountChanged = false;
        for (final n in installmentNos) {
          final baseAmount = _baseAmountFor(n);
          final enteredAmount = int.tryParse(amountCtrls[n]!.text.trim()) ?? 0;
          if (enteredAmount > 0 && enteredAmount != baseAmount) {
            anyAmountChanged = true;
            break;
          }
        }

        if (!anyAmountChanged) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن حفظ سبب التخفيض بدون تعديل مبالغ الدفعات')),
          );
          return;
        }

        for (final n in installmentNos) {
          final baseAmount = _baseAmountFor(n);
          final baseDue = _baseDueFor(n).trim();

          final enteredAmount = int.tryParse(amountCtrls[n]!.text.trim()) ?? 0;
          final enteredDue = dueCtrls[n]!.text.trim();

          final amountDiffers = enteredAmount > 0 && enteredAmount != baseAmount;
          final dueDiffers = enteredDue.isNotEmpty && enteredDue != baseDue;

          if (amountDiffers || dueDiffers) {
            await _dbHelper.upsertStudentTuitionOverride(
              studentId: widget.studentId,
              planId: widget.planId,
              installmentNo: n,
              amount: enteredAmount,
              dueDate: enteredDue,
              reason: null,
            );
          } else {
            await _dbHelper.deleteStudentTuitionOverride(
              studentId: widget.studentId,
              planId: widget.planId,
              installmentNo: n,
            );
          }
        }

        await _dbHelper.upsertStudentPlanDiscountReason(
          studentId: widget.studentId,
          planId: widget.planId,
          reason: reasonCtrl.text.trim(),
        );

        if (!mounted) return;
        Navigator.pop(context);
        await _load();
      } finally {
        if (mounted) {
          setLocalState(() {
            saving = false;
          });
        }
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF2A2A2A),
              title: const Text('تعديل التخفيض', style: TextStyle(color: Color(0xFFFEC619))),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: reasonCtrl,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'سبب التخفيض',
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
                      const SizedBox(height: 12),
                      ...installmentNos.map((n) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.18)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('الدفعة $n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: amountCtrls[n],
                                      keyboardType: TextInputType.number,
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'المبلغ',
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
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: TextField(
                                      controller: dueCtrls[n],
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'تاريخ الاستحقاق (YYYY-MM-DD)',
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
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: saving ? null : () => save(setLocalState),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                  child: Text(
                    saving ? 'جارِ الحفظ...' : 'حفظ',
                    style: const TextStyle(color: Color(0xFF1A1A1A)),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDiscountSection() {
    final before = _totalBeforeDiscount();
    final after = _totalAfterDiscount();
    final hasDiscount = after != before || _discountReason.trim().isNotEmpty || _overridesByInstallment.isNotEmpty;

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
          Row(
            children: [
              const Text(
                'التخفيض',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _openDiscountEditDialog,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFEC619)),
                child: const Text('تعديل', style: TextStyle(color: Color(0xFF1A1A1A))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _kv('قبل التخفيض', _formatIqd(before))),
              Expanded(child: _kv('بعد التخفيض', _formatIqd(after))),
              Expanded(child: _kv('فرق التخفيض', _formatIqd(before - after))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasDiscount ? 'سبب التخفيض: ${_discountReason.trim().isEmpty ? '-' : _discountReason.trim()}' : 'لا يوجد تخفيض',
            style: TextStyle(color: Colors.grey.shade300),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final s = _student;
    final name = s?.name ?? '';

    Widget avatar = Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFEC619), width: 2),
      ),
      child: const CircleAvatar(
        backgroundColor: Color(0xFF2A2A2A),
        child: Icon(Icons.person, color: Colors.grey, size: 54),
      ),
    );

    if (s != null && s.photoPath != null && s.photoPath!.trim().isNotEmpty && File(s.photoPath!).existsSync()) {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFEC619), width: 2),
        ),
        child: ClipOval(
          child: Image.file(
            File(s.photoPath!),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (s != null && (s.photo ?? '').trim().isNotEmpty) {
      avatar = Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFEC619), width: 2),
        ),
        child: ClipOval(
          child: Image.network(
            s.photo!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const CircleAvatar(
                backgroundColor: Color(0xFF2A2A2A),
                child: Icon(Icons.person, color: Colors.grey, size: 54),
              );
            },
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEC619).withOpacity(0.22)),
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFFFEC619),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الخطة: ${widget.planId}',
                  style: TextStyle(color: Colors.grey.shade400),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallmentsSection() {
    final installmentNos = _installments
        .map((r) => (r['installment_no'] is int) ? r['installment_no'] as int : int.tryParse(r['installment_no']?.toString() ?? '') ?? 0)
        .where((n) => n > 0)
        .toList()
      ..sort();

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
            'حالات الدفعات',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (installmentNos.isEmpty)
            const Text('لا توجد دفعات', style: TextStyle(color: Colors.grey)),
          if (installmentNos.isNotEmpty)
            ...installmentNos.map((n) {
              final d = _computeInstallment(n);
              final Color accent = d.isLateNow
                  ? Colors.redAccent
                  : d.isComplete
                      ? Colors.green
                      : Colors.grey;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.85)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'الدفعة $n',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: accent.withOpacity(0.85)),
                          ),
                          child: Text(
                            d.isLateNow
                                ? 'متأخر'
                                : d.isComplete
                                    ? 'مكتمل'
                                    : 'غير مكتمل',
                            style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('آخر تاريخ للسداد: ${d.dueDate}', style: TextStyle(color: Colors.grey.shade300)),
                    Text(
                      'تاريخ اكتمال الدفع: ${d.completionDate.isEmpty ? '-' : d.completionDate}',
                      style: TextStyle(color: Colors.grey.shade300),
                    ),
                    if (d.daysLate != null && d.daysLate! > 0)
                      Text('عدد أيام التأخير: ${d.daysLate}', style: const TextStyle(color: Colors.redAccent)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _kv('سعر الدفعة', _formatIqd(d.dueAmount)),
                        ),
                        Expanded(
                          child: _kv('المدفوع', _formatIqd(d.paidSum)),
                        ),
                        Expanded(
                          child: _kv('المتبقي', _formatIqd(d.remaining)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _kv('عدد مرات الدفع', d.paymentsCount.toString()),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _InstallmentCardData {
  final int installmentNo;
  final int dueAmount;
  final String dueDate;
  final int paidSum;
  final int remaining;
  final int paymentsCount;
  final String completionDate;
  final int? daysLate;
  final bool isLateNow;
  final bool isComplete;

  const _InstallmentCardData({
    required this.installmentNo,
    required this.dueAmount,
    required this.dueDate,
    required this.paidSum,
    required this.remaining,
    required this.paymentsCount,
    required this.completionDate,
    required this.daysLate,
    required this.isLateNow,
    required this.isComplete,
  });
}

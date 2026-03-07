import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../../database/database_helper.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';

/// Helper class for financial exports in messaging screen
class FinancialExportsHelper {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isInRange(DateTime dt, DateTime? startDate, DateTime? endDate) {
    if (startDate != null) {
      final s = DateTime(startDate.year, startDate.month, startDate.day);
      if (dt.isBefore(s)) return false;
    }
    if (endDate != null) {
      final e = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      if (dt.isAfter(e)) return false;
    }
    return true;
  }

  DateTime? _tryParseDate(dynamic raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s.replaceAll('/', '-'));
  }

  Future<_StudentTuitionSummary> _buildStudentTuitionSummary({
    required StudentModel student,
    required ClassModel studentClass,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final sid = student.id;
    final cid = studentClass.id;
    if (sid == null || cid == null) {
      return const _StudentTuitionSummary.empty();
    }

    final plans = await _dbHelper.getClassTuitionPlans(cid);
    final planIds = plans
        .map((p) => (p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0)
        .where((id) => id > 0)
        .toList();

    if (planIds.isEmpty) {
      return const _StudentTuitionSummary.empty();
    }

    final planNameById = <int, String>{
      for (final p in plans)
        ((p['id'] is int) ? p['id'] as int : int.tryParse(p['id']?.toString() ?? '') ?? 0): (p['name']?.toString() ?? ''),
    };

    final installmentsByPlanId = <int, List<Map<String, dynamic>>>{};
    for (final pid in planIds) {
      installmentsByPlanId[pid] = await _dbHelper.getTuitionPlanInstallments(pid);
    }

    final overridesByPlanStudent = await _dbHelper.getStudentTuitionOverridesMapForPlans(
      studentIds: <int>[sid],
      planIds: planIds,
    );

    final allPayments = <Map<String, dynamic>>[];
    final paidByPlanInstallment = <int, Map<int, int>>{};
    for (final pid in planIds) {
      final payments = await _dbHelper.getTuitionPaymentsForStudentPlan(
        studentId: sid,
        planId: pid,
      );

      final filteredPayments = payments.where((p) {
        if (startDate == null && endDate == null) return true;
        final dt = _tryParseDate(p['payment_date']);
        if (dt == null) return true;
        return _isInRange(dt, startDate, endDate);
      }).toList();

      allPayments.addAll(filteredPayments.map((e) => {...e, 'plan_id': pid}));
      final byInst = <int, int>{};
      for (final p in filteredPayments) {
        final ino = (p['installment_no'] is int)
            ? p['installment_no'] as int
            : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
        final amt = (p['paid_amount'] is int)
            ? p['paid_amount'] as int
            : int.tryParse(p['paid_amount']?.toString() ?? '') ?? 0;
        if (ino > 0) {
          byInst[ino] = (byInst[ino] ?? 0) + amt;
        }
      }
      paidByPlanInstallment[pid] = byInst;
    }

    int totalDue = 0;
    int totalPaid = 0;
    int totalRemaining = 0;

    final rows = <Map<String, dynamic>>[];
    final lateRows = <Map<String, dynamic>>[];
    final now = DateTime.now();

    for (final pid in planIds) {
      final planName = planNameById[pid] ?? '';
      final inst = installmentsByPlanId[pid] ?? const <Map<String, dynamic>>[];
      final paidByInst = paidByPlanInstallment[pid] ?? const <int, int>{};
      for (final t in inst) {
        final installmentNo = (t['installment_no'] is int)
            ? t['installment_no'] as int
            : int.tryParse(t['installment_no']?.toString() ?? '') ?? 0;
        if (installmentNo <= 0) continue;

        final override = overridesByPlanStudent[pid]?[sid]?[installmentNo];
        final rawAmount = override?['amount'] ?? t['amount'];
        final due = (rawAmount is int) ? rawAmount : int.tryParse(rawAmount?.toString() ?? '') ?? 0;
        if (due <= 0) continue;

        final dueDateStr = (override?['due_date'] ?? t['due_date'] ?? '').toString();

        if (startDate != null || endDate != null) {
          final dueDt = _tryParseDate(dueDateStr);
          if (dueDt != null && !_isInRange(dueDt, startDate, endDate)) {
            continue;
          }
        }

        final paid = paidByInst[installmentNo] ?? 0;
        final remaining = (due - paid).clamp(0, 1 << 30);

        totalDue += due;
        totalPaid += paid;
        totalRemaining += remaining;

        DateTime? dueDate;
        if (dueDateStr.trim().isNotEmpty) {
          dueDate = DateTime.tryParse(dueDateStr.replaceAll('/', '-'));
        }
        final daysLate = (dueDate == null)
            ? null
            : now.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
        final isLate = dueDate != null && (daysLate != null && daysLate > 0) && remaining > 0;

        final row = {
          'planId': pid,
          'planName': planName,
          'installmentNo': installmentNo,
          'dueDate': dueDateStr,
          'due': due,
          'paid': paid,
          'remaining': remaining,
          'daysLate': daysLate,
        };
        rows.add(row);
        if (isLate) {
          lateRows.add(row);
        }
      }
    }

    rows.sort((a, b) {
      final pa = a['planName']?.toString() ?? '';
      final pb = b['planName']?.toString() ?? '';
      final c = pa.compareTo(pb);
      if (c != 0) return c;
      final ia = a['installmentNo'] as int? ?? 0;
      final ib = b['installmentNo'] as int? ?? 0;
      return ia.compareTo(ib);
    });

    lateRows.sort((a, b) {
      final da = a['daysLate'] as int? ?? 0;
      final db = b['daysLate'] as int? ?? 0;
      return db.compareTo(da);
    });

    allPayments.sort((a, b) {
      final da = a['payment_date']?.toString() ?? '';
      final db = b['payment_date']?.toString() ?? '';
      final c = da.compareTo(db);
      if (c != 0) return c;
      final ia = (a['id'] is int) ? a['id'] as int : int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final ib = (b['id'] is int) ? b['id'] as int : int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return ia.compareTo(ib);
    });

    return _StudentTuitionSummary(
      totalDue: totalDue,
      totalPaid: totalPaid,
      totalRemaining: totalRemaining,
      installmentsRows: rows,
      lateRows: lateRows,
      payments: allPayments,
      planNameById: planNameById,
    );
  }

  /// Export financial data for a specific student
  Future<String?> exportFinancialDataForStudent(
    BuildContext context, {
    required StudentModel student,
    required ClassModel studentClass,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
          fontFallback: [pw.Font.helvetica()],
        ),
      );

      final tuition = await _buildStudentTuitionSummary(
        student: student,
        studentClass: studentClass,
        startDate: startDate,
        endDate: endDate,
      );

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'البيانات المالية',
                    style: pw.TextStyle(font: arabicBold, fontSize: 18, color: PdfColor.fromInt(0xFF000000)),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'اسم الطالب: ${student.name}',
                    style: pw.TextStyle(font: arabicFont, fontSize: 11, color: PdfColor.fromInt(0xFF555555)),
                  ),
                  pw.Text(
                    'الفصل: ${studentClass.name}',
                    style: pw.TextStyle(font: arabicFont, fontSize: 11, color: PdfColor.fromInt(0xFF555555)),
                  ),
                  pw.Text(
                    'الموقع: ${student.location ?? studentClass.subject}',
                    style: pw.TextStyle(font: arabicFont, fontSize: 11, color: PdfColor.fromInt(0xFF555555)),
                  ),
                  pw.Text(
                    'التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
                    style: pw.TextStyle(font: arabicFont, fontSize: 11, color: PdfColor.fromInt(0xFF555555)),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 1),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('القسط الكلي', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                              pw.SizedBox(height: 4),
                              pw.Text('${tuition.totalDue} د.ع'),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 1),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('إجمالي المدفوعات', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                              pw.SizedBox(height: 4),
                              pw.Text('${tuition.totalPaid} د.ع'),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 8),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(10),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColor.fromInt(0xFFCCCCCC), width: 1),
                            borderRadius: pw.BorderRadius.circular(8),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text('المبلغ المتبقي', style: pw.TextStyle(font: arabicBold, fontSize: 12)),
                              pw.SizedBox(height: 4),
                              pw.Text('${tuition.totalRemaining} د.ع'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  if (tuition.installmentsRows.isNotEmpty) ...[
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC)),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(1),
                        2: const pw.FlexColumnWidth(1),
                        3: const pw.FlexColumnWidth(1),
                        4: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0x33FEC619)),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('القسط', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('الدفعة', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('المستحق', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('المدفوع', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('المتبقي', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                          ],
                        ),
                        ...tuition.installmentsRows.map<pw.TableRow>((r) {
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(r['planName']?.toString() ?? '', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(r['installmentNo']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(r['due']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(r['paid']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(r['remaining']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                            ],
                          );
                        }).toList(),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      );

      final fileName = 'البيانات_المالية_${student.name}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      final bytes = await pdfDoc.save();
      
      print('PDF generated, size: ${bytes.length} bytes');
      
      // Save to temporary directory using a more reliable method
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      
      try {
        // Create file and write bytes in one operation
        final file = await File(filePath).writeAsBytes(bytes, flush: true);
        
        // Verify file was written correctly
        final fileSize = await file.length();
        print('PDF saved to: $filePath');
        print('Final file size: $fileSize bytes');
        
        if (fileSize > 0 && fileSize == bytes.length) {
          print('File verification passed');
          return filePath;
        } else {
          print('Error: File size mismatch or empty file');
          // Try alternative method
          await file.writeAsBytes(bytes, mode: FileMode.write, flush: true);
          final retrySize = await file.length();
          if (retrySize > 0) {
            print('File saved on retry, size: $retrySize bytes');
            return filePath;
          }
          return null;
        }
      } catch (e) {
        print('Error writing file: $e');
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Export late payments for a specific student
  Future<String?> exportLatePaymentsForStudent(
    BuildContext context, {
    required StudentModel student,
    required ClassModel studentClass,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
          fontFallback: [pw.Font.helvetica()],
        ),
      );

      final tuition = await _buildStudentTuitionSummary(
        student: student,
        studentClass: studentClass,
        startDate: startDate,
        endDate: endDate,
      );

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'حالة التأخر في الدفع',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFFFEC619),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('اسم الطالب: ${student.name}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('الفصل: ${studentClass.name}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('الموقع: ${student.location ?? studentClass.subject}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 12),
                  pw.Text(tuition.lateRows.isEmpty ? 'لا يوجد تأخير في الدفع' : 'الدفعات المتأخرة:', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 12),
                  if (tuition.lateRows.isNotEmpty)
                    pw.Table(
                      border: pw.TableBorder.all(color: const PdfColor(0.35, 0.35, 0.35), width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(1.5),
                        2: const pw.FlexColumnWidth(1.5),
                        3: const pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A1A)),
                          children: [
                            _buildHeaderCell('القسط / الدفعة', arabicBold),
                            _buildHeaderCell('المبلغ المتبقي', arabicBold),
                            _buildHeaderCell('تاريخ الاستحقاق', arabicBold),
                            _buildHeaderCell('أيام التأخير', arabicBold),
                          ],
                        ),
                        ...tuition.lateRows.map(
                          (r) => pw.TableRow(
                            children: [
                              _buildCell('${r['planName']?.toString() ?? ''} - ${r['installmentNo']?.toString() ?? ''}', arabicFont),
                              _buildCell(r['remaining']?.toString() ?? '0', arabicFont),
                              _buildCell(r['dueDate']?.toString() ?? '', arabicFont),
                              _buildCell(r['daysLate']?.toString() ?? '0', arabicFont),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        ),
      );

      final fileName = 'التأخر_في_الدفع_${student.name}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      final bytes = await pdfDoc.save();
      
      print('PDF generated, size: ${bytes.length} bytes');
      
      // Save to temporary directory using a more reliable method
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      
      try {
        // Create file and write bytes in one operation
        final file = await File(filePath).writeAsBytes(bytes, flush: true);
        
        // Verify file was written correctly
        final fileSize = await file.length();
        print('PDF saved to: $filePath');
        print('Final file size: $fileSize bytes');
        
        if (fileSize > 0 && fileSize == bytes.length) {
          print('File verification passed');
          return filePath;
        } else {
          print('Error: File size mismatch or empty file');
          // Try alternative method
          await file.writeAsBytes(bytes, mode: FileMode.write, flush: true);
          final retrySize = await file.length();
          if (retrySize > 0) {
            print('File saved on retry, size: $retrySize bytes');
            return filePath;
          }
          return null;
        }
      } catch (e) {
        print('Error writing file: $e');
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// Export payment history for a specific student
  Future<String?> exportPaymentHistoryForStudent(
    BuildContext context, {
    required StudentModel student,
    required ClassModel studentClass,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBold,
          fontFallback: [pw.Font.helvetica()],
        ),
      );

      final tuition = await _buildStudentTuitionSummary(
        student: student,
        studentClass: studentClass,
        startDate: startDate,
        endDate: endDate,
      );

      final payments = tuition.payments;

      pdfDoc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'سجل الدفعات',
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFFFEC619),
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('اسم الطالب: ${student.name}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('الفصل: ${studentClass.name}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('الموقع: ${student.location ?? studentClass.subject}', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 16),
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColor.fromInt(0xFF333333)),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(30),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(1.5),
                      3: const pw.FlexColumnWidth(1.5),
                      4: const pw.FlexColumnWidth(1.5),
                      5: const pw.FlexColumnWidth(1.5),
                    },
                    children: [
                      pw.TableRow(
                        decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF2A2A2A)),
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الرقم', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الكورس', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('القسط', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('المبلغ المدفوع', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('تاريخ الدفع', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('ملاحظات', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                          ),
                        ],
                      ),
                      ...List.generate(payments.length, (index) {
                        final p = payments[index];
                        final pid = (p['plan_id'] is int)
                            ? p['plan_id'] as int
                            : int.tryParse(p['plan_id']?.toString() ?? '') ?? 0;
                        final planName = tuition.planNameById[pid] ?? '';
                        final installmentNo = (p['installment_no'] is int)
                            ? p['installment_no'] as int
                            : int.tryParse(p['installment_no']?.toString() ?? '') ?? 0;
                        final paidAmount = (p['paid_amount'] is int)
                            ? p['paid_amount'] as int
                            : int.tryParse(p['paid_amount']?.toString() ?? '') ?? 0;
                        return pw.TableRow(
                          children: [
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(planName, style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text('دفعة $installmentNo', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text('$paidAmount', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['payment_date']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['notes']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      );

      final fileName = 'سجل_الدفعات_${student.name}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      final bytes = await pdfDoc.save();
      
      print('PDF generated, size: ${bytes.length} bytes');
      
      // Save to temporary directory using a more reliable method
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      
      try {
        // Create file and write bytes in one operation
        final file = await File(filePath).writeAsBytes(bytes, flush: true);
        
        // Verify file was written correctly
        final fileSize = await file.length();
        print('PDF saved to: $filePath');
        print('Final file size: $fileSize bytes');
        
        if (fileSize > 0 && fileSize == bytes.length) {
          print('File verification passed');
          return filePath;
        } else {
          print('Error: File size mismatch or empty file');
          // Try alternative method
          await file.writeAsBytes(bytes, mode: FileMode.write, flush: true);
          final retrySize = await file.length();
          if (retrySize > 0) {
            print('File saved on retry, size: $retrySize bytes');
            return filePath;
          }
          return null;
        }
      } catch (e) {
        print('Error writing file: $e');
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  pw.Widget _buildHeaderCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: 9,
          color: PdfColor.fromInt(0xFFFEC619),
        ),
      ),
    );
  }

  pw.Widget _buildCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontSize: 8,
          color: PdfColor.fromInt(0xFF000000),
        ),
      ),
    );
  }
}

class _StudentTuitionSummary {
  final int totalDue;
  final int totalPaid;
  final int totalRemaining;
  final List<Map<String, dynamic>> installmentsRows;
  final List<Map<String, dynamic>> lateRows;
  final List<Map<String, dynamic>> payments;
  final Map<int, String> planNameById;

  const _StudentTuitionSummary({
    required this.totalDue,
    required this.totalPaid,
    required this.totalRemaining,
    required this.installmentsRows,
    required this.lateRows,
    required this.payments,
    required this.planNameById,
  });

  const _StudentTuitionSummary.empty()
      : totalDue = 0,
        totalPaid = 0,
        totalRemaining = 0,
        installmentsRows = const <Map<String, dynamic>>[],
        lateRows = const <Map<String, dynamic>>[],
        payments = const <Map<String, dynamic>>[],
        planNameById = const <int, String>{};
}

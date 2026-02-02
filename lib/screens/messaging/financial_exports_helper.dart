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

  /// Export financial data for a specific student
  Future<String?> exportFinancialDataForStudent(
    BuildContext context, {
    required StudentModel student,
    required ClassModel studentClass,
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

      // Get student's financial data
      final studentData = await _getStudentFinancialData(student, studentClass);

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
                              pw.Text('${studentData['totalDue']} د.ع'),
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
                              pw.Text('${studentData['totalPaid']} د.ع'),
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
                              pw.Text('${studentData['totalRemaining']} د.ع'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 14),
                  if (studentData['courses'].isNotEmpty) ...[
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFCCCCCC)),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(1),
                        2: const pw.FlexColumnWidth(1),
                        3: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(color: PdfColor.fromInt(0x33FEC619)),
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('الكورس', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('القسط', style: pw.TextStyle(font: arabicBold, fontSize: 10)),
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
                        ...studentData['courses'].map<pw.TableRow>((course) {
                          return pw.TableRow(
                            children: [
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(course['courseName']?.toString() ?? '', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(course['due']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(course['paid']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(8),
                                child: pw.Text(course['remaining']?.toString() ?? '0', style: pw.TextStyle(font: arabicFont, fontSize: 9)),
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

      // Get student's late payment data
      final lateData = await _getStudentLatePaymentData(student, studentClass);

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
                  pw.Text(lateData['courses'].isEmpty ? 'لا يوجد تأخير في الدفع' : 'الكورسات المتأخرة:', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 12),
                  if (lateData['courses'].isNotEmpty)
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
                            _buildHeaderCell('الكورس', arabicBold),
                            _buildHeaderCell('المبلغ المتبقي', arabicBold),
                            _buildHeaderCell('تاريخ الاستحقاق', arabicBold),
                            _buildHeaderCell('أيام التأخير', arabicBold),
                          ],
                        ),
                        ...lateData['courses'].map(
                          (r) => pw.TableRow(
                            children: [
                              _buildCell(r['courseName']?.toString() ?? '', arabicFont),
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

      // Get student's payment history
      final payments = await _dbHelper.getAllInstallmentsWithDetails(
        locationFilter: student.location ?? studentClass.subject,
        classIdFilter: studentClass.id,
      );

      // Filter payments for this student only
      final studentPayments = payments.where((p) => p['student_id'] == student.id).toList();

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
                      ...List.generate(studentPayments.length, (index) {
                        final p = studentPayments[index];
                        return pw.TableRow(
                          children: [
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['course_name']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['installment_name']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['amount']?.toString() ?? '0', style: const pw.TextStyle(fontSize: 10))),
                            pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['date']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
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

  Future<Map<String, dynamic>> _getStudentFinancialData(StudentModel student, ClassModel studentClass) async {
    final courses = await _dbHelper.getCourses();
    final studentCourses = courses.where((c) => (c['location']?.toString() ?? '') == (student.location ?? studentClass.subject)).toList();
    
    int totalDue = 0;
    int totalPaid = 0;
    int totalRemaining = 0;
    final courseDetails = <Map<String, dynamic>>[];

    for (final course in studentCourses) {
      final courseId = course['id']?.toString() ?? '';
      if (courseId.isEmpty) continue;

      // Get enabled price for this student/class/course
      final db = await _dbHelper.database;
      final priceRows = await db.query(
        'class_course_prices',
        columns: ['amount'],
        where: 'class_id = ? AND course_id = ? AND enabled = 1',
        whereArgs: [studentClass.id, courseId],
        limit: 1,
      );

      if (priceRows.isEmpty) continue;
      final due = priceRows.first['amount'] as int? ?? 0;
      if (due <= 0) continue;

      final paid = await _dbHelper.getTotalPaidByStudentAndCourse(
        studentId: student.id!,
        courseId: courseId,
      );
      final remaining = (due - paid).clamp(0, 1 << 30);

      totalDue += due;
      totalPaid += paid;
      totalRemaining += remaining;

      courseDetails.add({
        'courseName': course['name']?.toString() ?? '',
        'due': due,
        'paid': paid,
        'remaining': remaining,
      });
    }

    return {
      'totalDue': totalDue,
      'totalPaid': totalPaid,
      'totalRemaining': totalRemaining,
      'courses': courseDetails,
    };
  }

  Future<Map<String, dynamic>> _getStudentLatePaymentData(StudentModel student, ClassModel studentClass) async {
    final courses = await _dbHelper.getCourses();
    final studentCourses = courses.where((c) => (c['location']?.toString() ?? '') == (student.location ?? studentClass.subject)).toList();
    
    final dueDates = await _dbHelper.getAllCourseDueDates();
    final now = DateTime.now();
    final lateCourses = <Map<String, dynamic>>[];

    for (final course in studentCourses) {
      final courseId = course['id']?.toString() ?? '';
      if (courseId.isEmpty) continue;

      // Get enabled price for this student/class/course
      final db = await _dbHelper.database;
      final priceRows = await db.query(
        'class_course_prices',
        columns: ['amount'],
        where: 'class_id = ? AND course_id = ? AND enabled = 1',
        whereArgs: [studentClass.id, courseId],
        limit: 1,
      );

      if (priceRows.isEmpty) continue;
      final due = priceRows.first['amount'] as int? ?? 0;
      if (due <= 0) continue;

      final paid = await _dbHelper.getTotalPaidByStudentAndCourse(
        studentId: student.id!,
        courseId: courseId,
      );
      final remaining = (due - paid).clamp(0, 1 << 30);

      // Check if late
      final dueKey = '${studentClass.id}|$courseId';
      final dueDateStr = dueDates[dueKey];
      DateTime? dueDate;
      if (dueDateStr != null) {
        dueDate = DateTime.tryParse(dueDateStr);
      }
      
      final daysLate = (dueDate == null)
          ? null
          : now.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
      final isLate = dueDate != null && (daysLate != null && daysLate > 0) && remaining > 0;

      if (isLate) {
        lateCourses.add({
          'courseName': course['name']?.toString() ?? '',
          'remaining': remaining,
          'dueDate': dueDateStr ?? '',
          'daysLate': daysLate ?? 0,
        });
      }
    }

    return {
      'courses': lateCourses,
    };
  }
}

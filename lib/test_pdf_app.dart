import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() {
  runApp(const TestPdfApp());
}

class TestPdfApp extends StatelessWidget {
  const TestPdfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Test Arabic PDF',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const TestPdfScreen(),
    );
  }
}

class TestPdfScreen extends StatefulWidget {
  const TestPdfScreen({super.key});

  @override
  State<TestPdfScreen> createState() => _TestPdfScreenState();
}

class _TestPdfScreenState extends State<TestPdfScreen> {
  bool _isLoading = false;

  Future<void> _generateTestPDF() async {
    setState(() {
      _isLoading = true;
    });

    print('Step 1: Starting PDF generation...');
    
    try {
      print('Step 2: Creating PDF document...');
      final pdf = pw.Document();
      
      print('Step 3: Loading Arabic font from assets...');
      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      print('Arabic font loaded successfully!');

      print('Step 4: Building PDF content...');
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // العنوان العلوي
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'تقرير الحضور',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'الفصل: اختبار',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 14,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      'المحاضرة: اختبار',
                      style: pw.TextStyle(
                        font: arabicFont,
                        fontSize: 12,
                        color: PdfColors.grey300,
                      ),
                    ),
                  ],
                ),
              ),
              
              pw.SizedBox(height: 20),
              
              // الإحصائيات
              pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.green200),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            'الحاضرين',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.green700,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '25',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 20,
                              color: PdfColors.green,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 10),
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(12),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.red50,
                        borderRadius: pw.BorderRadius.circular(8),
                        border: pw.Border.all(color: PdfColors.red200),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            'الغياب',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 12,
                              color: PdfColors.red700,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            '3',
                            style: pw.TextStyle(
                              font: arabicFont,
                              fontSize: 20,
                              color: PdfColors.red,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              pw.SizedBox(height: 20),
              
              // الجدول الرئيسي
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 1),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1), // الرقم
                  1: const pw.FlexColumnWidth(3), // اسم الطالب
                  2: const pw.FlexColumnWidth(2), // رقم الطالب
                  3: const pw.FlexColumnWidth(1.5), // الحالة
                },
                children: [
                  // عنوان الأعمدة
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue),
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'رقم',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'اسم الطالب',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'رقم الطالب',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'الحالة',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 12,
                            color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  // بيانات الطلاب
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey50),
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '1',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'أحمد محمد علي',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '2023001',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'حاضر',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                            color: PdfColors.green,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.white),
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '2',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'محمد عبدالله سالم',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          '2023002',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          'غائب',
                          style: pw.TextStyle(
                            font: arabicFont,
                            fontSize: 10,
                            color: PdfColors.red,
                            fontWeight: pw.FontWeight.bold,
                          ),
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      print('Step 5: Saving PDF to file...');
      final output = await getTemporaryDirectory();
      final file = File('${output.path}/test_arabic_pdf.pdf');
      await file.writeAsBytes(await pdf.save());
      print('PDF saved to: ${file.path}');

      print('Step 6: Opening PDF...');
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'test_arabic_pdf.pdf',
      );
      
      print('PDF generation completed successfully!');
      
    } catch (e, stackTrace) {
      print('Error generating PDF: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test Arabic PDF'),
        backgroundColor: Colors.blue,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.picture_as_pdf,
              size: 100,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              'Test Arabic PDF Generation',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This will test Arabic text rendering in PDF',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 30),
            if (_isLoading)
              const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 10),
                  Text('Generating PDF...'),
                ],
              )
            else
              ElevatedButton(
                onPressed: _generateTestPDF,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Generate Test PDF'),
              ),
          ],
        ),
      ),
    );
  }
}

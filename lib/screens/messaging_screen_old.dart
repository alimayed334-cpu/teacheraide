import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;
import '../providers/class_provider.dart';
import '../providers/student_provider.dart';
import '../providers/attendance_provider.dart';
import '../providers/exam_provider.dart';
import '../models/student_model.dart';
import '../models/class_model.dart';
import '../models/attendance_model.dart';
import '../models/exam_model.dart';
import '../models/grade_model.dart';
import '../services/google_drive_service.dart';
import '../database/database_helper.dart';
import 'students/student_attendance_pdf.dart';
import 'exports/export_files_screen.dart';
import 'package:intl/intl.dart';

class MessagingScreen extends StatefulWidget {
  const MessagingScreen({super.key});

  @override
  State<MessagingScreen> createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  int? selectedClassId;
  String selectedSortOption = 'معدل';
  String selectedFile = 'no_file';
  String messageText = '';
  List<String> selectedMethods = [];
  String selectedRecipient = 'طالب'; // خيار الإرسال المحدد
  Set<int> selectedStudents = {}; // لتتبع الطلاب المحددين
  String? selectedFilePath; // مسار الملف المختار
  final TextEditingController messageController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  // قائمة الملفات المتاحة للتصدير (مع خيار لا يوجد ملف)
  final List<Map<String, String>> availableFiles = [
    {'id': 'no_file', 'name': 'لا يوجد ملف', 'icon': '🚫'},
    {'id': 'student_info', 'name': 'معلومات الطالب', 'icon': '👤'},
    {'id': 'attendance_summary', 'name': 'ملخص الحضور', 'icon': '📊'},
    {'id': 'detailed_attendance', 'name': 'الحضور التفصيلي', 'icon': '📋'},
    {'id': 'exam_attendance', 'name': 'حضور الامتحانات', 'icon': '📝'},
    {'id': 'exams', 'name': 'الامتحانات', 'icon': '🎯'},
    {'id': 'final_grade', 'name': 'الدرجة النهائية', 'icon': '🏆'},
    {'id': 'student_summary', 'name': 'ملخص الطالب', 'icon': '📄'},
    {'id': 'detailed_statistics', 'name': 'احصائيات الطالب التفصيلية', 'icon': '📈'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      if (classProvider.classes.isNotEmpty && selectedClassId == null) {
        setState(() {
          selectedClassId = classProvider.classes.first.id;
        });
      }
    });
  }

  @override
  void dispose() {
    messageController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // دالة إنشاء ملف PDF حسب النوع المحدد (مع خيار لا يوجد ملف)
  Future<Uint8List?> _generatePDFBytes(String fileType, StudentModel student) async {
    if (fileType == 'no_file') {
      return null; // لا يوجد ملف للإرسال
    }
    
    try {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      final classModel = classProvider.classes.firstWhere((c) => c.id == student.classId);
      
      switch (fileType) {
        case 'student_info':
          return await _generateStudentInfoBytes(student, classModel);
        case 'attendance_summary':
          return await _generateAttendanceSummaryBytes(student, classModel);
        case 'detailed_attendance':
          return await _generateDetailedAttendanceBytes(student, classModel);
        case 'exam_attendance':
          return await _generateExamAttendanceBytes(student, classModel);
        case 'exams':
          return await _generateExamsBytes(student, classModel);
        case 'final_grade':
          return await _generateFinalGradeBytes(student, classModel);
        case 'student_summary':
          return await _generateStudentSummaryBytes(student, classModel);
        case 'detailed_statistics':
          return await _generateDetailedStatisticsBytes(student, classModel);
        default:
          return await _generateStudentInfoBytes(student, classModel);
      }
    } catch (e) {
      print('Error generating PDF: $e');
      return null;
    }
  }

  // دالة اختيار الملف من الجهاز
  Future<String?> pickFileFromDevice() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );

    if (result == null) return null;

    return result.files.single.path;
  }

  // دالة الإرسال المباشر مع الملف
  Future<void> sendWhatsAppWithFile(String message, String filePath) async {
    try {
      await Share.shareXFiles(
        [XFile(filePath)],
        text: message,
      );
    } catch (e) {
      print('Error sharing file: $e');
      _showErrorDialog('فشل في مشاركة الملف: $e');
    }
  }

  Future<String?> _uploadBytesToCloud(Uint8List fileBytes, String fileName) async {
    try {
      // استخدام Google Drive API للرفع المباشر
      final driveService = GoogleDriveService();
      
      // Initialize the service
      await driveService.initialize();
      
      // Check if signed in, if not sign in
      if (!driveService.isSignedIn) {
        final signedIn = await driveService.signIn();
        if (!signedIn) {
          print('Failed to sign in to Google Drive, falling back to temp.sh');
          // Fallback to temp.sh for Windows
          return await _uploadBytesToTempSh(fileBytes, fileName);
        }
      }

      // Upload file to Google Drive
      final fileId = await driveService.uploadBytesToGoogleDrive(
        fileBytes,
        fileName,
        shareWithAnyone: true,
      );

      if (fileId != null) {
        // Get direct download link
        final directLink = driveService.getDirectLink(fileId);
        return directLink;
      }
      
      // Fallback to temp.sh if Google Drive fails
      print('Google Drive upload failed, falling back to temp.sh');
      return await _uploadBytesToTempSh(fileBytes, fileName);
    } catch (e) {
      print('Error uploading file to Google Drive: $e');
      // Fallback to temp.sh on error
      return await _uploadBytesToTempSh(fileBytes, fileName);
    }
  }

  // Fallback method using temp.sh for bytes
  Future<String?> _uploadBytesToTempSh(Uint8List fileBytes, String fileName) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://temp.sh/upload'),
      );
      
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: fileName),
      );
      
      var response = await request.send();
      
      if (response.statusCode == 200) {
        var responseData = await http.Response.fromStream(response);
        final url = _extractUrlFromResponse(responseData.body);
        return url;
      }
    } catch (e) {
      print('Error uploading file to temp.sh: $e');
    }
    return null;
  }

  // Fallback method using temp.sh
  Future<String?> _uploadToTempSh(File file) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('https://temp.sh/upload'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('file', file.path),
      );
      
      var response = await request.send();
      
      if (response.statusCode == 200) {
        var responseData = await http.Response.fromStream(response);
        final url = _extractUrlFromResponse(responseData.body);
        return url;
      }
    } catch (e) {
      print('Error uploading file to temp.sh: $e');
    }
    return null;
  }

  // استخراج الرابط من استجابة خدمة الرفع
  String? _extractUrlFromResponse(String responseBody) {
    try {
      final regex = RegExp(r'https?://[^\s"]+');
      final match = regex.firstMatch(responseBody);
      return match?.group(0);
    } catch (e) {
      print('Error extracting URL: $e');
      return null;
    }
  }

  // دالة ترميز النص لواتساب
  String _encodeForWhatsApp(String text) {
    return Uri.encodeComponent(text);
  }

  // دالة عرض رسالة خطأ
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('خطأ'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  // الحصول على رقم هاتف الطالب
  String _getStudentPhoneNumber(StudentModel student, String recipientType) {
    switch (recipientType) {
      case 'طالب':
        return student.phone ?? '';
      case 'ولي الأمر 1':
        return student.parentPhone ?? '';
      case 'ولي الأمر 2':
        return student.parentPhone ?? '';
      default:
        return student.phone ?? '';
    }
  }

  // دالة إنشاء PDF معلومات الطالب (نسخة طبق الأصل من export_files_screen)
  Future<Uint8List> _generateStudentInfoBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    
    try {
      // تحميل الخطوط العربية
      final ttf = await PdfGoogleFonts.cairoRegular();
      final ttfBold = await PdfGoogleFonts.cairoBold();

      final pdf = pw.Document();
      final className = classModel.name;
      
      pdf.addPage(
        pw.MultiPage(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return [
              // العنوان
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      className,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'معلومات الطلاب',
                      style: pw.TextStyle(fontSize: 18, font: ttfBold, color: PdfColors.white),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // جدول الطلاب
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey),
                children: [
                  // رأس الجدول
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.blue),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('رقم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الإيميل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('اسم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('رقم ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('إيميل ولي الأمر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  // بيانات الطالب
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.phone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.email ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.primaryGuardian?.name ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.primaryGuardian?.phone ?? student.parentPhone ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(student.primaryGuardian?.email ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );
      
      final bytes = await pdf.save();
      return bytes;
    } catch (e) {
      print('Error: $e');
      rethrow;
    }
  }

  // دالة إنشاء PDF ملخص الحضور (تبسيط)
  Future<Uint8List> _generateAttendanceSummaryBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    final attendances = await _dbHelper.getAttendanceByStudent(student.id!);
    final presentCount = attendances.where((a) => a.status == AttendanceStatus.present).length;
    final absentCount = attendances.where((a) => a.status == AttendanceStatus.absent).length;
    final lateCount = attendances.where((a) => a.status == AttendanceStatus.late).length;
    final totalAttendance = attendances.length;
    
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ملخص الحضور - ${student.name}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Table.fromTextArray(
                        context: context,
                        data: <List<String>>[
                          ['الحالة', 'العدد', 'النسبة المئوية'],
                          ['حاضر', '$presentCount', totalAttendance > 0 ? '${(presentCount / totalAttendance * 100).toStringAsFixed(1)}%' : '0%'],
                          ['غائب', '$absentCount', totalAttendance > 0 ? '${(absentCount / totalAttendance * 100).toStringAsFixed(1)}%' : '0%'],
                          ['متأخر', '$lateCount', totalAttendance > 0 ? '${(lateCount / totalAttendance * 100).toStringAsFixed(1)}%' : '0%'],
                          ['الإجمالي', '$totalAttendance', '100%'],
                        ],
                        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold),
                        cellStyle: pw.TextStyle(font: arabicFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  // دوال إنشاء باقي أنواع الملفات (تبسيط)
  Future<Uint8List> _generateDetailedAttendanceBytes(StudentModel student, ClassModel classModel) async {
    // إنشاء PDF للحضور التفصيلي يدوياً بدلاً من StudentReportPDF
    final _dbHelper = DatabaseHelper();
    final attendances = await _dbHelper.getAttendanceByStudent(student.id!);
    
    final pdf = pw.Document();
    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                // العنوان
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.green100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        classModel.name,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'الحضور التفصيلي',
                        style: pw.TextStyle(
                          fontSize: 14,
                          font: ttf,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                
                // جدول الحضور
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey),
                  children: [
                    // رأس الجدول
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('الحالة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    // بيانات الحضور
                    ...attendances.map((att) {
                      return pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(DateFormat('d/M/yyyy').format(att.date), style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                              att.status == AttendanceStatus.present ? 'حاضر' :
                              att.status == AttendanceStatus.absent ? 'غائب' :
                              att.status == AttendanceStatus.late ? 'متأخر' : 'غير معروف',
                              style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          ),
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
    
    final bytes = await pdf.save();
    return bytes;
  }

  Future<Uint8List> _generateExamAttendanceBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    final exams = await _dbHelper.getExamsByClass(student.classId);
    final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
    
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.orange100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'حضور الامتحانات - ${student.name}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Table.fromTextArray(
                        context: context,
                        data: <List<String>>[
                          ['عنوان الامتحان', 'التاريخ', 'الحالة', 'الدرجة'],
                          ...exams.map((exam) {
                            final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
                            final status = grade != null ? 'حاضر' : 'غائب';
                            final score = grade?.score ?? 0;
                            return [
                              exam.title,
                              DateFormat('d/M/yyyy').format(exam.date),
                              status,
                              '$score',
                            ];
                          }),
                        ],
                        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold),
                        cellStyle: pw.TextStyle(font: arabicFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  Future<Uint8List> _generateExamsBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    final exams = await _dbHelper.getExamsByClass(student.classId);
    
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.purple100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'امتحانات الطالب - ${student.name}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Table.fromTextArray(
                        context: context,
                        data: <List<String>>[
                          ['عنوان الامتحان', 'التاريخ', 'الدرجة القصوى'],
                          ...exams.map((exam) => [
                            exam.title,
                            DateFormat('d/M/yyyy').format(exam.date),
                            '${exam.maxScore}',
                          ]),
                        ],
                        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold),
                        cellStyle: pw.TextStyle(font: arabicFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  Future<Uint8List> _generateFinalGradeBytes(StudentModel student, ClassModel classModel) async {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final average = await studentProvider.getStudentAverage(student.id!);
    
    final pdf = pw.Document();
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.all(16),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.red100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'الدرجة النهائية - ${student.name}',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text(
                        'المعدل النهائي: ${average.toStringAsFixed(2)}%',
                        style: pw.TextStyle(fontSize: 16, font: ttfBold),
                      ),
                      pw.Text(
                        'الفصل: ${classModel.name}',
                        style: pw.TextStyle(fontSize: 14, font: arabicFont),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  // دالة إنشاء PDF ملخص الطالب (نسخة من export_files_screen لطالب واحد)
  Future<Uint8List> _generateStudentSummaryBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    
    final lectures = await _dbHelper.getLecturesByClass(student.classId);
    final exams = await _dbHelper.getExamsByClass(student.classId);
    
    int absent = 0, missingExams = 0;
    double totalGrades = 0, maxGrades = 0;
    
    // حساب الغيابات
    for (var lecture in lectures) {
      final att = await _dbHelper.getAttendanceByStudentAndLecture(studentId: student.id!, lectureId: lecture.id!);
      if (att?.status.toString().contains('absent') == true) absent++;
    }
    
    // حساب الامتحانات الغائبة والدرجات
    final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
    for (var exam in exams) {
      final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
      if (grade == null) {
        missingExams++;
      } else {
        totalGrades += grade.score;
        maxGrades += exam.maxScore;
      }
    }
    
    final gradePercent = maxGrades > 0 ? ((totalGrades / maxGrades) * 100).toStringAsFixed(1) : '0.0';
    
    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                // العنوان
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.pink100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        classModel.name,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'ملخص الطالب',
                        style: pw.TextStyle(
                          fontSize: 14,
                          font: ttf,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                
                // جدول ملخص الطالب
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey),
                  children: [
                    // رأس الجدول
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('البيانات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('القيمة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    // بيانات الطالب
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('اسم الطالب', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('عدد الغيابات', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$absent', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('الامتحانات الغائبة', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$missingExams', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('المعدل', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$gradePercent%', style: pw.TextStyle(font: ttfBold, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  // دالة إنشاء PDF الإحصائيات التفصيلية (نسخة من export_files_screen لطالب واحد)
  Future<Uint8List> _generateDetailedStatisticsBytes(StudentModel student, ClassModel classModel) async {
    final _dbHelper = DatabaseHelper();
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    
    final lectures = await _dbHelper.getLecturesByClass(student.classId);
    final exams = await _dbHelper.getExamsByClass(student.classId);
    
    int absent = 0, present = 0, late = 0, missingExams = 0;
    double totalGrades = 0, maxGrades = 0;
    
    // حساب الحضور
    for (var lecture in lectures) {
      final att = await _dbHelper.getAttendanceByStudentAndLecture(studentId: student.id!, lectureId: lecture.id!);
      if (att?.status == AttendanceStatus.absent) {
        absent++;
      } else if (att?.status == AttendanceStatus.present) {
        present++;
      } else if (att?.status == AttendanceStatus.late) {
        late++;
      }
    }
    
    // حساب الامتحانات الغائبة والدرجات
    final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
    for (var exam in exams) {
      final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
      if (grade == null) {
        missingExams++;
      } else {
        totalGrades += grade.score;
        maxGrades += exam.maxScore;
      }
    }
    
    final gradePercent = maxGrades > 0 ? ((totalGrades / maxGrades) * 100).toStringAsFixed(1) : '0.0';
    final attendanceRate = lectures.isNotEmpty ? ((present + late) / lectures.length * 100).toStringAsFixed(1) : '0.0';
    
    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                // العنوان
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.indigo100,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        classModel.name,
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          font: ttfBold,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'الإحصائيات التفصيلية',
                        style: pw.TextStyle(
                          fontSize: 14,
                          font: ttf,
                        ),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 10),
                
                // جدول الإحصائيات
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey),
                  children: [
                    // رأس الجدول
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.blue),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('البيانات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('القيمة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    // بيانات الطالب
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('اسم الطالب', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('إجمالي المحاضرات', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${lectures.length}', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('عدد الحضور', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$present', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('عدد الغياب', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$absent', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('عدد التأخير', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$late', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('نسبة الحضور', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$attendanceRate%', style: pw.TextStyle(font: ttfBold, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('عدد الامتحانات', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('${exams.length}', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('الامتحانات الغائبة', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$missingExams', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('المعدل النهائي', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('$gradePercent%', style: pw.TextStyle(font: ttfBold, fontSize: 8), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    
    final bytes = await pdf.save();
    return bytes;
  }

  List<StudentModel> getFilteredStudents() {
    final studentProvider = Provider.of<StudentProvider>(context, listen: false);
    final attendanceProvider = Provider.of<AttendanceProvider>(context, listen: false);
    final examProvider = Provider.of<ExamProvider>(context, listen: false);
    
    if (selectedClassId == null) return [];
    
    // تحميل الطلاب للفصل المحدد
    studentProvider.loadStudentsByClass(selectedClassId!);
    List<StudentModel> students = studentProvider.students;
    
    // تطبيق البحث
    if (searchController.text.isNotEmpty) {
      students = students.where((student) => 
        student.name.toLowerCase().contains(searchController.text.toLowerCase()) ||
        student.id.toString().contains(searchController.text.toLowerCase())
      ).toList();
    }
    
    // تطبيق الترتيب
    switch (selectedSortOption) {
      case 'معدل':
        students.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'نسبة حضور من محاضرات':
        // ترتيب حسب اسم الطالب مؤقتاً
        students.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'نسبة غياب من امتحانات':
        // ترتيب حسب اسم الطالب مؤقتاً
        students.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'حضور':
        // ترتيب حسب اسم الطالب مؤقتاً
        students.sort((a, b) => a.name.compareTo(b.name));
        break;
    }
    
    return students;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'المراسلة',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // شريط تغيير الفصل والبحث والتصنيف
            _buildTopBar(),
            const SizedBox(height: 16),
            // المحتوى الرئيسي
            Expanded(
              child: Row(
                children: [
                  // قائمة الطلاب
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD700), width: 1),
                      ),
                      child: _buildStudentsList(),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // قسم الرسالة
                  Expanded(
                    flex: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD700), width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: _buildMessageSection(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Column(
      children: [
        // شريط تغيير الفصل
        Consumer<ClassProvider>(
          builder: (context, classProvider, child) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: Row(
                children: [
                  const Icon(Icons.class_, color: Color(0xFFDAA520)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButton<String>(
                      value: selectedClassId?.toString(),
                      hint: const Text('اختر الفصل', style: TextStyle(color: Colors.grey)),
                      dropdownColor: const Color(0xFF3D3D3D),
                      style: const TextStyle(color: Colors.white),
                      items: classProvider.classes.map((ClassModel classModel) {
                        return DropdownMenuItem<String>(
                          value: classModel.id.toString(),
                          child: Text(classModel.name),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            selectedClassId = int.tryParse(newValue);
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        // شريط البحث والتصنيف
        Row(
          children: [
            // حقل البحث
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D3D),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFD700), width: 1),
                ),
                child: TextField(
                  controller: searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'البحث عن طالب...',
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.search, color: Color(0xFFDAA520)),
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            // قائمة التصنيف
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3D3D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 1),
              ),
              child: DropdownButton<String>(
                value: selectedSortOption,
                dropdownColor: const Color(0xFF3D3D3D),
                style: const TextStyle(color: Colors.white),
                items: const [
                  DropdownMenuItem(value: 'معدل', child: Text('معدل')),
                  DropdownMenuItem(value: 'نسبة حضور', child: Text('نسبة حضور')),
                  DropdownMenuItem(value: 'نسبة غياب', child: Text('نسبة غياب')),
                ],
                onChanged: (String? newValue) {
                  setState(() {
                    selectedSortOption = newValue!;
                  });
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStudentsList() {
    final students = getFilteredStudents();
    final studentProvider = Provider.of<StudentProvider>(context);
    final attendanceProvider = Provider.of<AttendanceProvider>(context);
    final examProvider = Provider.of<ExamProvider>(context);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: students.length,
        itemBuilder: (context, index) {
          final student = students[index];
          
          // جلب البيانات الحقيقية من قاعدة البيانات
          Future<double> averageFuture = studentProvider.getStudentAverage(student.id!);
          Future<Map<String, int>> attendanceStatsFuture = studentProvider.getStudentAttendanceStats(student.id!);
          
          return FutureBuilder(
            future: Future.wait([averageFuture, attendanceStatsFuture]),
            builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
              double average = 0.0;
              int lectureAttendance = 0;
              int lectureAbsence = 0;
              int examAttendance = 0;
              int examAbsence = 0;
              
              if (snapshot.hasData) {
                average = snapshot.data![0] as double;
                final stats = snapshot.data![1] as Map<String, int>;
                lectureAttendance = stats['present'] ?? 0;
                lectureAbsence = stats['absent'] ?? 0;
                examAttendance = stats['present'] ?? 0; // مؤقتاً
                examAbsence = stats['absent'] ?? 0; // مؤقتاً
              }
              
              final phoneNumber = student.phone ?? student.parentPhone ?? 'لا يوجد';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D3D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3), width: 1),
                ),
                child: Row(
                  children: [
                    // معلومات الطالب
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // تحديد حجم النصوص بناءً على عرض الحاوية
                          final fontSize = constraints.maxWidth < 300 ? 10.0 : 
                                         constraints.maxWidth < 400 ? 11.0 : 
                                         constraints.maxWidth < 500 ? 12.0 : 14.0;
                          final chipFontSize = constraints.maxWidth < 300 ? 8.0 : 
                                              constraints.maxWidth < 350 ? 9.0 : 
                                              constraints.maxWidth < 450 ? 10.0 : 12.0;
                          final nameFontSize = fontSize + 2;
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // اسم الطالب
                              Text(
                                student.name,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: nameFontSize,
                                ),
                                maxLines: constraints.maxWidth < 250 ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: constraints.maxWidth < 300 ? 2 : 4),
                              
                              // جميع المعلومات في صف واحد باستخدام Wrap
                              Wrap(
                                spacing: 2,
                                runSpacing: 2,
                                children: [
                                  _buildInfoChip('معدل: ${average.toStringAsFixed(1)}', Colors.blue, chipFontSize),
                                  _buildInfoChip('غياب امتحانات: $examAbsence', Colors.red, chipFontSize),
                                  _buildInfoChip('غياب محاضرات: $lectureAbsence', Colors.orange, chipFontSize),
                                  _buildInfoChip('حضور محاضرات: $lectureAttendance', Colors.green, chipFontSize),
                                  _buildInfoChip('حضور امتحانات: $examAttendance', Colors.purple, chipFontSize),
                                  _buildInfoChip('هاتف: $phoneNumber', Colors.grey, chipFontSize),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // خانة الاختيار
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selectedStudents.contains(student.id!) 
                              ? const Color(0xFFFFD700) 
                              : Colors.grey.withOpacity(0.5),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                        color: selectedStudents.contains(student.id!) 
                            ? const Color(0xFFFFD700).withOpacity(0.2) 
                            : Colors.transparent,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () {
                            setState(() {
                              if (selectedStudents.contains(student.id!)) {
                                selectedStudents.remove(student.id!);
                              } else {
                                selectedStudents.add(student.id!);
                              }
                            });
                          },
                          child: selectedStudents.contains(student.id!)
                              ? const Icon(Icons.check, size: 16, color: Color(0xFFFFD700))
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            },
          );
  }

  Widget _buildInfoChip(String text, Color color, [double? fontSize]) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: fontSize != null && fontSize < 10 ? 4 : 6, 
        vertical: fontSize != null && fontSize < 10 ? 2 : 3
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(fontSize != null && fontSize < 10 ? 8 : 12),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: fontSize ?? 12,
          fontWeight: FontWeight.w500,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildMessageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // اختيار الملف
        _buildFileSelector(),
        const SizedBox(height: 16),
        // خيارات الإرسال على اليسار
        _buildRecipientOptions(),
        const SizedBox(height: 16),
        // مربع الرسالة
        _buildMessageField(),
        const SizedBox(height: 16),
        // خيارات الإرسال
        _buildSendOptions(),
        const SizedBox(height: 16),
        // زر الإرسال
        _buildSendButton(),
      ],
    );
  }

  Widget _buildFileSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختيار الملف',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // قائمة الملفات المتاحة
          DropdownButtonFormField<String>(
            value: selectedFile,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.grey[800],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey[600]!),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFFD700)),
              ),
            ),
            dropdownColor: Colors.grey[800],
            style: const TextStyle(color: Colors.white),
            items: availableFiles.map((file) {
              return DropdownMenuItem<String>(
                value: file['id'],
                child: Row(
                  children: [
                    Text(
                      file['icon']!,
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        file['name']!,
                        style: const TextStyle(color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                selectedFile = newValue ?? 'no_file';
                // إذا تم اختيار ملف جديد، قم بإعادة تعيين selectedFilePath
                selectedFilePath = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientOptions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إرسال إلى',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          // خيارات الإرسال (4 خيارات فقط)
          Row(
            children: [
              Expanded(
                child: _buildRecipientOption(
                  title: 'الطالب',
                  value: 'طالب',
                  icon: Icons.person,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildRecipientOption(
                  title: 'ولي الأمر 1',
                  value: 'ولي الأمر 1',
                  icon: Icons.family_restroom,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildRecipientOption(
                  title: 'ولي الأمر 2',
                  value: 'ولي الأمر 2',
                  icon: Icons.family_restroom,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildRecipientOption(
                  title: 'جميع الطلاب',
                  value: 'جميع الطلاب',
                  icon: Icons.group,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecipientOption({
    required String title,
    required String value,
    required IconData icon,
  }) {
    final isSelected = selectedRecipient == value;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedRecipient = value;
        });
      },
      child: Container(
        width: double.infinity, // جعل العرض كامل لاستيعاب النص
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700).withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFFD700) : Colors.grey.withOpacity(0.5),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFFFD700) : Colors.grey,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFFD700) : Colors.white,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageField() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF3D3D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الرسالة',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 120,
            child: TextField(
              controller: messageController,
              style: const TextStyle(color: Colors.white),
              maxLines: null,
              expands: true,
              decoration: InputDecoration(
                hintText: 'اكتب رسالتك هنا...',
                hintStyle: const TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFFD700)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFFFD700)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFDAA520)),
                ),
              ),
              onChanged: (value) {
                messageText = value;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendOptions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // تحديد حجم النصوص والمسافات بناءً على عرض الحاوية
        final titleFontSize = constraints.maxWidth < 300 ? 12.0 : 
                            constraints.maxWidth < 400 ? 14.0 : 16.0;
        final optionFontSize = constraints.maxWidth < 300 ? 10.0 : 
                              constraints.maxWidth < 400 ? 11.0 : 12.0;
        final spacing = constraints.maxWidth < 300 ? 6.0 : 
                       constraints.maxWidth < 400 ? 8.0 : 12.0;
        final runSpacing = constraints.maxWidth < 300 ? 4.0 : 
                          constraints.maxWidth < 400 ? 6.0 : 8.0;
        
        return Container(
          padding: EdgeInsets.all(constraints.maxWidth < 300 ? 8 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFF3D3D3D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFD700), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'الإرسال عن طريق',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: titleFontSize,
                ),
              ),
              SizedBox(height: constraints.maxWidth < 300 ? 6 : 12),
              Wrap(
                spacing: spacing,
                runSpacing: runSpacing,
                children: [
                  _buildMethodOption('SMS', 'sms', optionFontSize),
                  _buildMethodOption('EMAIL', 'email', optionFontSize),
                  _buildMethodOption('WHATSUP', 'whatsapp', optionFontSize),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMethodOption(String title, String value, [double? fontSize]) {
    final isSelected = selectedMethods.contains(value);
    final optionFontSize = fontSize ?? 12.0;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedMethods.remove(value);
          } else {
            selectedMethods.add(value);
          }
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: optionFontSize < 11 ? 8 : 16, 
          vertical: optionFontSize < 11 ? 4 : 8
        ),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFD700) : const Color(0xFFFFF8DC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFDAA520) : const Color(0xFFFFD700),
            width: 1,
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.black,
            fontWeight: FontWeight.w500,
            fontSize: optionFontSize,
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // تحديد حجم الزر بناءً على عرض الحاوية
        final buttonHeight = constraints.maxWidth < 300 ? 35.0 : 
                           constraints.maxWidth < 400 ? 40.0 : 50.0;
        final fontSize = constraints.maxWidth < 300 ? 12.0 : 
                        constraints.maxWidth < 400 ? 14.0 : 16.0;
        
        return Container(
          width: double.infinity,
          height: buttonHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFFFFD700), const Color(0xFFDAA520)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _sendWhatsAppMessage();
              },
              child: Center(
                child: Text(
                  constraints.maxWidth < 300 ? 'إرسال' : 'إرسال الرسالة',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: fontSize,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // الدالة الرئيسية لإرسال رسالة واتساب
  Future<void> _sendWhatsAppMessage() async {
    // التحقق من اختيار الطلاب
    if (selectedStudents.isEmpty) {
      _showErrorDialog('يرجى اختيار طالب واحد على الأقل');
      return;
    }

    // التحقق من نص الرسالة
    if (messageController.text.trim().isEmpty) {
      _showErrorDialog('يرجى كتابة رسالة');
      return;
    }

    // التحقق من اختيار طريقة الإرسال
    if (!selectedMethods.contains('whatsapp')) {
      _showErrorDialog('يرجى اختيار واتساب كطريقة إرسال');
      return;
    }

    // التحقق من اختيار الملف من القائمة
    if (selectedFile == 'no_file' || selectedFile == 'اختر الملف') {
      _showErrorDialog('يرجى اختيار ملف من القائمة');
      return;
    }

    // عرض مؤشر التحميل
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('جاري إرسال الرسالة...'),
          ],
        ),
      ),
    );

    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      final students = studentProvider.students.where((s) => selectedStudents.contains(s.id)).toList();

      for (final student in students) {
        // التحقق من وجود رقم هاتف
        final phoneNumber = _getStudentPhoneNumber(student, selectedRecipient);
        
        if (phoneNumber.isEmpty && selectedMethods.contains('واتساب')) {
          _showErrorDialog('الطالب ${student.name} ليس لديه رقم هاتف للإرسال عبر واتساب');
          continue; // تخطي هذا الطالب
        }

        if (phoneNumber.isEmpty) {
          continue; // تخطي الطلاب الذين ليس لديهم أرقام هواتف
        }

        // تنظيف الرقم وإزالة الرموز غير المرغوب فيها
        String cleanPhone = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
        
        // التأكد من أن الرقم يبدأ برمز الدولة العراقي
        if (!cleanPhone.startsWith('+')) {
          if (cleanPhone.startsWith('00')) {
            cleanPhone = '+964' + cleanPhone.substring(2);
          } else if (cleanPhone.startsWith('07')) {
            // الأرقام العراقية تبدأ بـ 07
            cleanPhone = '+964' + cleanPhone.substring(1);
          } else if (cleanPhone.startsWith('964')) {
            cleanPhone = '+' + cleanPhone;
          } else {
            cleanPhone = '+964' + cleanPhone;
          }
        }

        // إنشاء الملف المطلوب بناءً على الاختيار من القائمة
        Uint8List? pdfBytes;
        String fileName = '';
        
        // فقط إذا تم اختيار ملف من القائمة (لا اختيار خارجي)
        if (selectedFile != 'no_file') {
          pdfBytes = await _generatePDFBytes(selectedFile, student);
          fileName = '${selectedFile}_${student.name}.pdf';
          
          if (pdfBytes == null) {
            _showErrorDialog('فشل في إنشاء الملف للطالب: ${student.name}');
            continue;
          }
        }

        String fileUrl = '';
        
        // رفع الملف للسحابة إذا تم اختياره من القائمة
        if (pdfBytes != null) {
          fileUrl = await _uploadBytesToCloud(pdfBytes, fileName) ?? '';
          if (fileUrl.isEmpty) {
            _showErrorDialog('فشل في رفع الملف للطالب: ${student.name}');
            continue;
          }
        }

        // تكوين الرسالة النهائية
        String finalMessage = messageController.text.trim();
        if (fileUrl.isNotEmpty && !fileUrl.startsWith('تم إرفاق')) {
          finalMessage += '\n\nرابط الملف:\n$fileUrl';
        } else if (fileUrl.startsWith('تم إرفاق')) {
          finalMessage += '\n\n$fileUrl';
        }

        // ترميز الرسالة
        final encodedMessage = _encodeForWhatsApp(finalMessage);

        // إنشاء رابط واتساب
        final whatsappUrl = 'https://wa.me/${cleanPhone.substring(1)}?text=$encodedMessage';

        // فتح واتساب
        final uri = Uri.parse(whatsappUrl);
        
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          
          // انتظار قليلاً بين كل رسالة وأخرى
          await Future.delayed(Duration(seconds: 2));
        } else {
          _showErrorDialog('لا يمكن فتح واتساب. يرجى التأكد من تثبيت التطبيق');
        }
      }

      // إغلاق مؤشر التحميل
      Navigator.pop(context);
      
      // عرض رسالة نجاح
      _showSuccessDialog('تم إرسال الرسائل بنجاح');
      
    } catch (e) {
      // إغلاق مؤشر التحميل
      Navigator.pop(context);
      
      // عرض رسالة خطأ
      _showErrorDialog('حدث خطأ أثناء الإرسال: $e');
    }
  }

  // دالة عرض رسالة نجاح
  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('نجاح', style: TextStyle(color: Colors.green)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('موافق'),
          ),
        ],
      ),
    );
  }
}

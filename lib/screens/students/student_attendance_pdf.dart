import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../models/student_model.dart';
import '../../models/attendance_model.dart';
import '../../models/class_model.dart';
import '../../theme/app_theme.dart';
import '../../models/grade_model.dart';
import '../../models/exam_model.dart';
import '../../database/database_helper.dart';

class StudentReportPDF {
  static Future<void> generatePDF({
    required BuildContext context,
    required StudentModel student,
    required ClassModel? classModel,
    String reportType = 'attendance', // 'attendance', 'exams', 'notes'
  }) async {
    final _dbHelper = DatabaseHelper();

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('جاري إنشاء ملف PDF...'),
          ],
        ),
      ),
    );

    try {
      final pdf = pw.Document();
      
      // Load fonts
      final arabicFont = await PdfGoogleFonts.notoNaskhArabicRegular();
      final symbolsFont = await PdfGoogleFonts.notoSansSymbols2Regular();
      
      // Load attendance data
      final attendances = await _dbHelper.getAttendanceByStudent(student.id!);
      final presentCount = attendances.where((a) => a.status == AttendanceStatus.present).length;
      final absentCount = attendances.where((a) => a.status == AttendanceStatus.absent).length;
      final lateCount = attendances.where((a) => a.status == AttendanceStatus.late).length;
      final expelledCount = attendances.where((a) => a.status == AttendanceStatus.expelled).length;
      final excusedCount = attendances.where((a) => a.status == AttendanceStatus.excused).length;
      final totalAttendance = attendances.length;
      
      // Load exam data
      final exams = await _dbHelper.getExamsByClass(student.classId);
      final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
      Map<String, double> grades = {};
      double totalScore = 0.0;
      int examCount = 0;
      
      // Calculate percentage instead of total score
      double totalPercentage = 0.0;
      int validExams = 0;
      
      for (final exam in exams) {
        final GradeModel? grade = studentGrades.cast<GradeModel?>().firstWhere(
          (g) => g?.examName == exam.title,
          orElse: () => null,
        );

        final statusRaw = (grade?.status ?? '').trim();

        // تخزين الدرجات فقط عندما تكون هناك درجة فعلية
        if (grade != null) {
          grades[exam.title] = grade.score.toDouble();
        }

        // تجاهل المعفئ/المؤجل من المعدل (كأن الامتحان غير موجود)
        if (statusRaw == 'معفئ' || statusRaw == 'مؤجل' || statusRaw == 'معفئ او مؤجل') {
          continue;
        }

        // لا نضيف للمعدل إلا الامتحانات الحاضرة (نفس منطق التطبيق)
        if (statusRaw.isEmpty || statusRaw == 'حاضر') {
          if (exam.maxScore > 0) {
            final score = grade?.score ?? 0.0;
            totalPercentage += (score / exam.maxScore) * 100;
            validExams++;
          }
        }
      }
      
      final averagePercentage = validExams > 0 ? totalPercentage / validExams : 0.0;

      // Calculate attendance percentages
      final presentPercentage = totalAttendance > 0 ? (presentCount / totalAttendance * 100).toStringAsFixed(1) : '0.0';
      final absentPercentage = totalAttendance > 0 ? (absentCount / totalAttendance * 100).toStringAsFixed(1) : '0.0';
      final latePercentage = totalAttendance > 0 ? (lateCount / totalAttendance * 100).toStringAsFixed(1) : '0.0';
      final expelledPercentage = totalAttendance > 0 ? (expelledCount / totalAttendance * 100).toStringAsFixed(1) : '0.0';
      final excusedPercentage = totalAttendance > 0 ? (excusedCount / totalAttendance * 100).toStringAsFixed(1) : '0.0';

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
                  // Header with student info
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber100,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${student.name} - ${classModel?.name ?? ""}',
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'معدل الطالب: ${averagePercentage.toStringAsFixed(2)}%',
                          style: pw.TextStyle(
                            fontSize: 16,
                            font: arabicFont,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // Attendance Section with new design
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'جدول الحضور',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        
                        // New attendance table design like the image
                        pw.Table(
                          border: pw.TableBorder.all(color: PdfColors.grey400),
                          columnWidths: {
                            0: const pw.FixedColumnWidth(100), // Month
                            1: const pw.FixedColumnWidth(80), // Day
                            2: const pw.FixedColumnWidth(80), // Status
                          },
                          children: [
                            // Header row
                            pw.TableRow(
                              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                              children: [
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('الشهر', 
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: arabicFont, fontFallback: [symbolsFont]),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('اليوم', 
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: arabicFont, fontFallback: [symbolsFont]),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.all(8),
                                  child: pw.Text('الحالة', 
                                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: arabicFont, fontFallback: [symbolsFont]),
                                    textAlign: pw.TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                            // Data rows
                            ...attendances.map((attendance) {
                              final month = DateFormat('MMMM', 'ar').format(attendance.date);
                              final day = DateFormat('d', 'en').format(attendance.date); // English numbers
                              final status = _getAttendanceStatusText(attendance.status);
                              
                              return pw.TableRow(
                                children: [
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text(month, 
                                      style: pw.TextStyle(font: arabicFont, fontFallback: [symbolsFont]),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text(day, 
                                      style: pw.TextStyle(font: arabicFont, fontFallback: [symbolsFont]),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ),
                                  pw.Padding(
                                    padding: const pw.EdgeInsets.all(8),
                                    child: pw.Text(status, 
                                      style: pw.TextStyle(font: arabicFont, fontFallback: [symbolsFont]),
                                      textAlign: pw.TextAlign.center,
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                        pw.SizedBox(height: 16),
                        
                        // Statistics table
                        pw.Text(
                          'إحصائيات الحضور',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Table.fromTextArray(
                          context: context,
                          data: <List<String>>[
                            ['الحالة', 'العدد', 'النسبة'],
                            ['حاضر', '$presentCount', (presentPercentage + '%').toString()],
                            ['غائب', '$absentCount', (absentPercentage + '%').toString()],
                            ['متأخر', '$lateCount', (latePercentage + '%').toString()],
                            ['مجاز', '$excusedCount', (excusedPercentage + '%').toString()],
                            ['مطرود', '$expelledCount', (expelledPercentage + '%').toString()],
                          ],
                          headerStyle: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                          ),
                          cellStyle: pw.TextStyle(
                            font: arabicFont,
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  
                  // Exams Section
                  pw.Container(
                    padding: const pw.EdgeInsets.all(16),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'جدول الامتحانات',
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                            fontFallback: [symbolsFont],
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        pw.Table.fromTextArray(
                          context: context,
                          data: <List<String>>[
                            ['التاريخ', 'عنوان الامتحان', 'الحالة', 'الدرجة', 'النسبة'],
                            ...exams.map((exam) {
                              final GradeModel? grade = studentGrades.cast<GradeModel?>().firstWhere(
                                (g) => g?.examName == exam.title,
                                orElse: () => null,
                              );

                              final status = (grade?.status ?? '').trim();

                              final resolvedStatus = (status == 'معفئ' || status == 'مؤجل' || status == 'معفئ او مؤجل')
                                  ? 'معفئ او مؤجل'
                                  : (status.isEmpty ? 'حاضر' : status);

                              final score = grade?.score.toInt() ?? 0;
                              final date = DateFormat('d/M/yyyy', 'en').format(exam.date); // English numbers

                              final bool showScore = resolvedStatus == 'حاضر';
                              final String scoreText = showScore ? '$score' : '';
                              final String percentageText = showScore
                                  ? (exam.maxScore > 0 ? (score / exam.maxScore * 100).toStringAsFixed(1) : '0.0')
                                  : '';
                              return [
                                date,
                                exam.title,
                                resolvedStatus,
                                scoreText,
                                percentageText.isEmpty ? '' : (percentageText + '%').toString(),
                              ];
                            }),
                          ],
                          headerStyle: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            font: arabicFont,
                          ),
                          cellStyle: pw.TextStyle(
                            font: arabicFont,
                          ),
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
      
      // Close loading dialog
      Navigator.pop(context);

      // Share/open PDF directly without print dialog
      await Printing.sharePdf(
        bytes: await pdf.save(),
        filename: 'تقرير_${student.name}.pdf',
      );

    } catch (e) {
      // Close loading dialog
      Navigator.pop(context);
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إنشاء الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  static String _getAttendanceStatusText(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'مطرود';
      case AttendanceStatus.excused:
        return 'مجاز';
      default:
        return '';
    }
  }

  static String _getAttendanceSymbol(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.present:
        return 'P'; // Present
      case AttendanceStatus.absent:
        return 'A'; // Absent
      case AttendanceStatus.late:
        return 'TU'; // Tardy/Unexcused
      case AttendanceStatus.expelled:
        return 'E'; // Expelled
      case AttendanceStatus.excused:
        return 'EX'; // Excused
      default:
        return '';
    }
  }
}

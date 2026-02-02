# دوال التصدير الإضافية التي يجب إضافتها

## ملاحظة مهمة
هذه الدوال جاهزة للإضافة في ملف `export_files_screen.dart` قبل دالة `_exportFile()`

## 1. دالة تصدير الامتحانات (_exportExams)

```dart
Future<void> _exportExams() async {
  if (_currentClass == null) return;

  if (_dateOption == 'custom' && (_startDate == null || _endDate == null)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('يرجى تحديد تاريخ البدء والنهاية'), backgroundColor: Colors.orange),
    );
    return;
  }

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(color: Colors.green), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')],
        ),
      ),
    );

    final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
    if (students.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange));
      return;
    }

    final allExams = await _dbHelper.getExamsByClass(_currentClass!.id!);
    List<ExamModel> exams;
    if (_dateOption == 'custom' && _startDate != null && _endDate != null) {
      exams = allExams.where((exam) =>
        exam.date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
        exam.date.isBefore(_endDate!.add(const Duration(days: 1)))
      ).toList();
    } else {
      exams = allExams;
    }

    if (exams.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد امتحانات'), backgroundColor: Colors.orange));
      return;
    }

    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    final className = _currentClass!.name;

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.green100, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(
                children: [
                  pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(height: 4),
                  pw.Text('الامتحانات', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 10), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المعدل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 10), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    ...exams.map((exam) => pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Column(
                        children: [
                          pw.Text(exam.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                          pw.Text('${exam.date.day}/${exam.date.month}', style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ],
                      ),
                    )).toList(),
                  ],
                ),
                ...await Future.wait(students.map((student) async {
                  double totalScore = 0;
                  double totalMaxScore = 0;
                  List<pw.Widget> examScores = [];

                  for (var exam in exams) {
                    final grades = await _dbHelper.getGradesByStudent(student.id!);
                    final grade = grades.where((g) => g.examName == exam.title).firstOrNull;
                    
                    if (grade != null) {
                      totalScore += grade.score;
                      totalMaxScore += grade.maxScore;
                      examScores.add(pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${grade.score.toStringAsFixed(0)}/${grade.maxScore.toStringAsFixed(0)}', style: pw.TextStyle(font: ttf, fontSize: 9), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)));
                    } else {
                      examScores.add(pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('-', style: pw.TextStyle(font: ttf, fontSize: 9), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)));
                    }
                  }

                  final average = totalMaxScore > 0 ? ((totalScore / totalMaxScore) * 100).toStringAsFixed(1) : '0.0';

                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 9), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$average%', style: pw.TextStyle(font: ttf, fontSize: 9), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      ...examScores,
                    ],
                  );
                })).toList(),
              ],
            ),
          ];
        },
      ),
    );

    Navigator.pop(context);
    final fileName = '${className}_الامتحانات.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green),
    );
  } catch (e) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
  }
}
```

## 2. دالة تصدير الدرجة النهائية (_exportFinalGrades)

```dart
Future<void> _exportFinalGrades() async {
  if (_currentClass == null) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(color: Colors.teal), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')],
        ),
      ),
    );

    final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
    if (students.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange));
      return;
    }

    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    final className = _currentClass!.name;

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.teal100, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(
                children: [
                  pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(height: 4),
                  pw.Text('الدرجة النهائية', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('المعدل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('المجموع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                  ],
                ),
                ...await Future.wait(students.map((student) async {
                  final grades = await _dbHelper.getGradesByStudent(student.id!);
                  double totalScore = 0;
                  double totalMaxScore = 0;

                  for (var grade in grades) {
                    totalScore += grade.score;
                    totalMaxScore += grade.maxScore;
                  }

                  final average = totalMaxScore > 0 ? ((totalScore / totalMaxScore) * 100).toStringAsFixed(1) : '0.0';

                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$average%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${totalScore.toStringAsFixed(0)}/${totalMaxScore.toStringAsFixed(0)}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    ],
                  );
                })).toList(),
              ],
            ),
          ];
        },
      ),
    );

    Navigator.pop(context);
    final fileName = '${className}_الدرجة_النهائية.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green),
    );
  } catch (e) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
  }
}
```

## 3. دالة تصدير ملاحظات الفصول (_exportClassNotes)

```dart
Future<void> _exportClassNotes() async {
  if (_currentClass == null) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(color: Colors.indigo), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')],
        ),
      ),
    );

    final lectures = await _dbHelper.getLecturesByClass(_currentClass!.id!);
    final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
    final notes = await _dbHelper.getNotesByClass(_currentClass!.id!);
    
    Map<String, NoteModel> notesMap = {};
    for (final note in notes) {
      final key = '${note.itemType}_${note.itemId}';
      notesMap[key] = note;
    }

    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    final className = _currentClass!.name;

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.indigo100, borderRadius: pw.BorderRadius.circular(5)),
              child: pw.Text('ملاحظات: $className', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
            ),
            pw.SizedBox(height: 20),
            if (lectures.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text('المحاضرات', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                    ],
                  ),
                  ...lectures.map((lecture) {
                    final key = 'lecture_${lecture.id}';
                    final note = notesMap[key];
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(lecture.title, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${lecture.date.day}/${lecture.date.month}/${lecture.date.year}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(note?.content ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                      ],
                    );
                  }).toList(),
                ],
              ),
              pw.SizedBox(height: 20),
            ],
            if (exams.isNotEmpty) ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text('الامتحانات', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl),
              ),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
                    ],
                  ),
                  ...exams.map((exam) {
                    final key = 'exam_${exam.id}';
                    final note = notesMap[key];
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(exam.title, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${exam.date.day}/${exam.date.month}/${exam.date.year}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(note?.content ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ],
          ];
        },
      ),
    );

    Navigator.pop(context);
    final fileName = '${className}_ملاحظات_الفصول.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green),
    );
  } catch (e) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
  }
}
```

## 4. دالة تصدير ملخص الطالب (_exportStudentSummary)

```dart
Future<void> _exportStudentSummary() async {
  if (_currentClass == null) return;

  try {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(color: Colors.pink), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')],
        ),
      ),
    );

    final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
    if (students.isEmpty) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange));
      return;
    }

    final ttf = await PdfGoogleFonts.cairoRegular();
    final ttfBold = await PdfGoogleFonts.cairoBold();
    final pdf = pw.Document();
    final className = _currentClass!.name;

    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(color: PdfColors.pink100, borderRadius: pw.BorderRadius.circular(8)),
              child: pw.Column(
                children: [
                  pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                  pw.SizedBox(height: 4),
                  pw.Text('ملخص الطلاب', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الاسم', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الغيابات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('امتحانات غائبة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('المعدل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                  ],
                ),
                ...await Future.wait(students.map((student) async {
                  final lectures = await _dbHelper.getLecturesByClass(_currentClass!.id!);
                  int absences = 0;
                  for (var lecture in lectures) {
                    final attendance = await _dbHelper.getAttendanceByStudentAndLecture(student.id!, lecture.id!);
                    if (attendance?.status == AttendanceStatus.absent) absences++;
                  }

                  final grades = await _dbHelper.getGradesByStudent(student.id!);
                  final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
                  int missedExams = exams.length - grades.length;

                  double totalScore = 0;
                  double totalMaxScore = 0;
                  for (var grade in grades) {
                    totalScore += grade.score;
                    totalMaxScore += grade.maxScore;
                  }
                  final average = totalMaxScore > 0 ? ((totalScore / totalMaxScore) * 100).toStringAsFixed(1) : '0.0';

                  return pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$absences', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$missedExams', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$average%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
                    ],
                  );
                })).toList(),
              ],
            ),
          ];
        },
      ),
    );

    Navigator.pop(context);
    final fileName = '${className}_ملخص_الطلاب.pdf';
    await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green),
    );
  } catch (e) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
  }
}
```

## 5. تحديث دالة _exportFile

استبدل دالة `_exportFile` بهذا الكود:

```dart
Future<void> _exportFile() async {
  switch (_selectedFileType) {
    case 'student_info':
      await _exportStudentInfo();
      break;
    case 'attendance_summary':
      await _exportAttendanceSummary();
      break;
    case 'attendance_detailed':
      await _exportAttendanceDetailed();
      break;
    case 'exams':
      await _exportExams();
      break;
    case 'final_grades':
      await _exportFinalGrades();
      break;
    case 'class_notes':
      await _exportClassNotes();
      break;
    case 'student_summary':
      await _exportStudentSummary();
      break;
  }
}
```

## ملاحظات مهمة:
1. أضف هذه الدوال قبل دالة `_exportFile()` في ملف `export_files_screen.dart`
2. تأكد من أن جميع الاستيرادات موجودة في أعلى الملف
3. جميع الدوال جاهزة للعمل وتستخدم نفس نمط الكود الموجود
4. أسماء الملفات تتبع النمط: `اسم_الفصل_نوع_الملف.pdf`

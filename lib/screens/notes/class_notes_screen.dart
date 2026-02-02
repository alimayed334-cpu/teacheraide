import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/class_model.dart';
import '../../models/lecture_model.dart';
import '../../models/exam_model.dart';
import '../../models/note_model.dart';
import '../../database/database_helper.dart';
import '../../services/google_drive_service.dart';

class ClassNotesScreen extends StatefulWidget {
  final ClassModel classModel;

  const ClassNotesScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<ClassNotesScreen> createState() => _ClassNotesScreenState();
}

class _ClassNotesScreenState extends State<ClassNotesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<LectureModel> _lectures = [];
  List<ExamModel> _exams = [];
  Map<String, NoteModel> _notes = {};
  String? _copiedNote;
  bool _isLoading = true;
  List<ClassModel> _allClasses = [];
  ClassModel? _currentClass;

  @override
  void initState() {
    super.initState();
    _currentClass = widget.classModel;
    _loadData();
    _loadAllClasses();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final classId = _currentClass?.id ?? widget.classModel.id!;
      // تحميل المحاضرات والامتحانات
      _lectures = await _dbHelper.getLecturesByClass(classId);
      _exams = await _dbHelper.getExamsByClass(classId);
      
      // تحميل الملاحظات
      final notes = await _dbHelper.getNotesByClass(classId);
      _notes = {};
      for (final note in notes) {
        final key = '${note.itemType}_${note.itemId}';
        _notes[key] = note;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadAllClasses() async {
    try {
      _allClasses = await _dbHelper.getAllClasses();
      setState(() {});
    } catch (e) {
      print('خطأ في تحميل الفصول: $e');
    }
  }

  Future<void> _switchToClass(ClassModel newClass) async {
    if (newClass.id == _currentClass?.id) return;
    
    setState(() {
      _currentClass = newClass;
      _isLoading = true;
    });
    
    try {
      // تحميل بيانات الفصل الجديد
      _lectures = await _dbHelper.getLecturesByClass(newClass.id!);
      _exams = await _dbHelper.getExamsByClass(newClass.id!);
      
      // تحميل الملاحظات
      final notes = await _dbHelper.getNotesByClass(newClass.id!);
      _notes = {};
      for (final note in notes) {
        final key = '${note.itemType}_${note.itemId}';
        _notes[key] = note;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل بيانات الفصل: $e')),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }


  Future<void> _saveNote(String itemType, int itemId, String content) async {
    try {
      final key = '${itemType}_$itemId';
      final existingNote = _notes[key];
      
      if (existingNote != null) {
        // تحديث الملاحظة الموجودة
        final updatedNote = existingNote.copyWith(
          content: content,
          updatedAt: DateTime.now(),
        );
        await _dbHelper.updateNote(updatedNote);
        setState(() => _notes[key] = updatedNote);
      } else {
        // إضافة ملاحظة جديدة
        final newNote = NoteModel(
          classId: _currentClass?.id ?? widget.classModel.id!,
          itemType: itemType,
          itemId: itemId,
          content: content,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final id = await _dbHelper.insertNote(newNote);
        setState(() => _notes[key] = newNote.copyWith(id: id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الملاحظة: $e')),
        );
      }
    }
  }

  Future<void> _deleteNote(String itemType, int itemId) async {
    try {
      final key = '${itemType}_$itemId';
      final note = _notes[key];
      
      if (note != null && note.id != null) {
        await _dbHelper.deleteNote(note.id!);
        setState(() => _notes.remove(key));
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم حذف الملاحظة'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حذف الملاحظة: $e')),
        );
      }
    }
  }

  void _showNoteDialog(String itemType, int itemId, String title, String currentNote) {
    final controller = TextEditingController(text: currentNote);
    bool isLoading = false;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(
                itemType == 'lecture' ? Icons.school : Icons.assignment,
                color: itemType == 'lecture' ? Colors.blue : Colors.green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ملاحظة: $title',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'اكتب ملاحظتك هنا...',
                  border: const OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: itemType == 'lecture' ? Colors.blue : Colors.green,
                      width: 2,
                    ),
                  ),
                  counterText: '${controller.text.length}/500',
                ),
                onChanged: (value) {
                  setState(() {}); // لتحديث العداد
                },
              ),
              if (controller.text.length > 400)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'تحذير: اقتربت من الحد الأقصى للنص',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (controller.text.trim().isEmpty && currentNote.isNotEmpty) {
                  // تأكيد حذف الملاحظة
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد الحذف'),
                      content: const Text('هل تريد حذف هذه الملاحظة؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('حذف'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }
                
                setState(() => isLoading = true);
                try {
                  await _saveNote(itemType, itemId, controller.text.trim());
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          controller.text.trim().isEmpty 
                            ? 'تم حذف الملاحظة' 
                            : 'تم حفظ الملاحظة بنجاح'
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  setState(() => isLoading = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ في حفظ الملاحظة: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteOptions(String itemType, int itemId, String title) {
    final key = '${itemType}_$itemId';
    final note = _notes[key];
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('تعديل الملاحظة'),
              onTap: () {
                Navigator.pop(context);
                _showNoteDialog(itemType, itemId, title, note?.content ?? '');
              },
            ),
            if (note != null && note.content.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.green),
                title: const Text('نسخ الملاحظة'),
                onTap: () {
                  setState(() => _copiedNote = note.content);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم نسخ الملاحظة'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
            if (_copiedNote != null)
              ListTile(
                leading: const Icon(Icons.paste, color: Colors.orange),
                title: const Text('لصق الملاحظة'),
                onTap: () async {
                  Navigator.pop(context);
                  await _saveNote(itemType, itemId, _copiedNote!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('تم لصق الملاحظة'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                },
              ),
            if (note != null && note.content.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('حذف الملاحظة'),
                onTap: () async {
                  Navigator.pop(context);
                  // عرض تأكيد الحذف
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('تأكيد الحذف'),
                      content: const Text('هل أنت متأكد من حذف هذه الملاحظة؟'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('إلغاء'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('حذف'),
                        ),
                      ],
                    ),
                  );
                  
                  if (confirm == true) {
                    await _deleteNote(itemType, itemId);
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showShareDialog(NoteModel note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('مشاركة الملاحظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.copy, color: Colors.blue),
              title: Text('نسخ النص'),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: note.content));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم نسخ الملاحظة')),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.share, color: Colors.green),
              title: Text('مشاركة عبر التطبيقات'),
              onTap: () {
                Navigator.pop(context);
                Share.share(note.content);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadAndShareToGoogleDrive(File file, String fileName, Uint8List pdfBytes) async {
    try {
      final driveService = GoogleDriveService();
      
      // Initialize the service
      await driveService.initialize();
      
      // Check if signed in, if not sign in
      if (!driveService.isSignedIn) {
        final signedIn = await driveService.signIn();
        if (!signedIn) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('فشل تسجيل الدخول إلى Google Drive'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      // Upload file to Google Drive
      final fileId = await driveService.uploadBytesToGoogleDrive(
        pdfBytes,
        fileName,
        shareWithAnyone: true,
      );

      if (fileId != null) {
        // Get shareable link
        final shareableLink = driveService.getShareableLink(fileId);
        
        if (shareableLink != null && mounted) {
          // Show dialog with sharing options
          _showGoogleDriveShareDialog(fileName, shareableLink);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('فشل رفع الملف إلى Google Drive'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error uploading to Google Drive: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء الرفع إلى Google Drive'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showGoogleDriveShareDialog(String fileName, String shareableLink) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cloud_upload, color: Colors.blue),
            SizedBox(width: 8),
            Text('تم رفع الملف بنجاح'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('اسم الملف: $fileName'),
            SizedBox(height: 8),
            Text('رابط المشاركة:'),
            Container(
              margin: EdgeInsets.symmetric(vertical: 8),
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: SelectableText(
                shareableLink,
                style: TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'يمكنك الآن مشاركة هذا الرابط مباشرة عبر WhatsApp.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: shareableLink));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تم نسخ الرابط')),
              );
            },
            child: Text('نسخ الرابط'),
          ),
          ElevatedButton(
            onPressed: () async {
              await Share.share(shareableLink, subject: fileName);
              Navigator.pop(context);
            },
            child: Text('مشاركة'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(String itemType, int itemId, String title, DateTime date) {
    final key = '${itemType}_$itemId';
    final note = _notes[key];
    final hasNote = note != null && note.content.isNotEmpty;
    final isLecture = itemType == 'lecture';
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: hasNote 
            ? (isLecture 
                ? [Colors.blue.withOpacity(0.12), Colors.blue.withOpacity(0.06)]
                : [Colors.green.withOpacity(0.12), Colors.green.withOpacity(0.06)])
            : [Colors.grey.withOpacity(0.15), Colors.grey.withOpacity(0.08)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: Colors.grey.withOpacity(0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showNoteDialog(itemType, itemId, title, note?.content ?? ''),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isLecture 
                          ? Colors.blue.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLecture ? Icons.school : Icons.assignment,
                        color: isLecture ? Colors.blue : Colors.green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${date.day}/${date.month}/${date.year}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _showNoteOptions(itemType, itemId, title),
                      tooltip: 'خيارات الملاحظة',
                    ),
                  ],
                ),
                if (hasNote) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      note!.content,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.25),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.add_comment,
                          color: Colors.grey[500],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'اضغط لإضافة ملاحظة...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _generatePDF() async {
    try {
      // إظهار مؤشر التحميل مع رسالة
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'جاري إنشاء ملف PDF...',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );

      // Load NotoSansArabic fonts from assets - best Arabic support
      final fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));

      final pdf = pw.Document();
      final className = _currentClass?.name ?? widget.classModel.name;
      
      pdf.addPage(
        pw.Page(
          textDirection: pw.TextDirection.rtl,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          theme: pw.ThemeData.withFont(
            base: fontRegular,
            bold: fontBold,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'ملخص الطالب',
                          style: pw.TextStyle(
                            fontSize: 24,
                            fontWeight: pw.FontWeight.bold,
                            font: fontBold,
                          ),
                          textDirection: pw.TextDirection.rtl,
                        ),
                        pw.SizedBox(height: 8),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.end,
                          children: [
                            pw.Text(
                              'جميع الطلاب',
                              style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                font: fontBold,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                            pw.SizedBox(width: 16),
                            pw.Text(
                              className,
                              style: pw.TextStyle(
                                fontSize: 18,
                                color: PdfColors.grey700,
                                font: fontBold,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ],
                        ),
                      ],
                    ),
                    pw.Text(
                      DateFormat('dd/MM/yyyy').format(DateTime.now()),
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
                
                // قسم المحاضرات
                if (_lectures.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'المحاضرات',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: fontBold),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  
                  // جدول المحاضرات
                  pw.Table(
                    border: pw.TableBorder.all(),
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                        ],
                      ),
                      // بيانات المحاضرات
                      ..._lectures.map((lecture) {
                        final key = 'lecture_${lecture.id}';
                        final note = _notes[key];
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(lecture.title, style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('${lecture.date.day}/${lecture.date.month}/${lecture.date.year}', style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(note?.content ?? 'لا توجد ملاحظات', style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],
                
                // قسم الامتحانات
                if (_exams.isNotEmpty) ...[
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      'الامتحانات',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: fontBold),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ),
                  pw.SizedBox(height: 10),
                  
                  // جدول الامتحانات
                  pw.Table(
                    border: pw.TableBorder.all(),
                    children: [
                      // رأس الجدول
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8),
                            child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: fontBold), textDirection: pw.TextDirection.rtl),
                          ),
                        ],
                      ),
                      // بيانات الامتحانات
                      ..._exams.map((exam) {
                        final key = 'exam_${exam.id}';
                        final note = _notes[key];
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(exam.title, style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('${exam.date.day}/${exam.date.month}/${exam.date.year}', style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text(note?.content ?? 'لا توجد ملاحظات', style: pw.TextStyle(font: fontRegular), textDirection: pw.TextDirection.rtl),
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),
                ],
                
                // رسالة في حالة عدم وجود بيانات
                if (_lectures.isEmpty && _exams.isEmpty)
                  pw.Center(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(20),
                      child: pw.Text(
                        'لا توجد محاضرات أو امتحانات في هذا الفصل',
                        style: pw.TextStyle(color: PdfColors.grey, font: fontRegular),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );

      // إخفاء مؤشر التحميل
      if (mounted) Navigator.pop(context);

      // إنشاء اسم الملف بالعربية
      final now = DateTime.now();
      final dateStr = '${now.day}-${now.month}-${now.year}';
      final fileName = 'ملاحظات_${className}_$dateStr.pdf';
      
      // حفظ الملف مباشرة
      final output = await getApplicationDocumentsDirectory();
      final file = File('${output.path}/$fileName');
      await file.writeAsBytes(await pdf.save());
      
      // الرفع إلى Google Drive والمشاركة
      await _uploadAndShareToGoogleDrive(file, fileName, await pdf.save());

      // إظهار رسالة نجاح
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('تم إنشاء ورفع ملف PDF بنجاح: $fileName'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      // إخفاء مؤشر التحميل في حالة الخطأ
      if (mounted) Navigator.pop(context);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إنشاء PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<ClassModel>(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.class_, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${_currentClass?.name ?? widget.classModel.name}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down, color: Colors.green, size: 20),
              ],
            ),
          ),
          offset: const Offset(0, 40),
          itemBuilder: (context) => _allClasses.map((classModel) {
            final isSelected = classModel.id == _currentClass?.id;
            return PopupMenuItem<ClassModel>(
              value: classModel,
              height: 60, // تكبير ارتفاع العنصر
              child: Container(
                width: 280, // تكبير عرض القائمة
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.green.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10), // تكبير الأيقونة
                      decoration: BoxDecoration(
                        color: isSelected 
                          ? Colors.green.withOpacity(0.2)
                          : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.class_,
                        color: isSelected ? Colors.green : Colors.grey[600],
                        size: 22, // تكبير حجم الأيقونة
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        classModel.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.green[700] : null,
                          fontSize: 16, // تكبير حجم النص
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.check, 
                          color: Colors.white, 
                          size: 16, // تكبير أيقونة التحديد
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
          onSelected: (ClassModel classModel) {
            _switchToClass(classModel);
          },
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(left: 8),
            child: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: const Icon(
                  Icons.picture_as_pdf,
                  color: Colors.red,
                  size: 20,
                ),
              ),
              onPressed: _generatePDF,
              tooltip: 'تصدير PDF',
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                children: [
                  // قسم المحاضرات
                  if (_lectures.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.school, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'المحاضرات (${_lectures.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._lectures.map((lecture) => _buildNoteCard(
                      'lecture',
                      lecture.id!,
                      lecture.title,
                      lecture.date,
                    )).toList(),
                    const SizedBox(height: 16),
                  ],
                  
                  // قسم الامتحانات
                  if (_exams.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.assignment, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'الامتحانات (${_exams.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._exams.map((exam) => _buildNoteCard(
                      'exam',
                      exam.id!,
                      exam.title,
                      exam.date,
                    )).toList(),
                  ],
                  
                  // رسالة عدم وجود بيانات
                  if (_lectures.isEmpty && _exams.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'لا توجد محاضرات أو امتحانات في هذا الفصل',
                              style: TextStyle(color: Colors.grey, fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 20), // مساحة بسيطة في الأسفل
                ],
              ),
            ),
    );
  }

  Widget _buildNavItem(String title, IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? Colors.blue.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: isActive ? Colors.blue : Colors.grey[400],
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: isActive ? Colors.blue : Colors.grey[400],
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

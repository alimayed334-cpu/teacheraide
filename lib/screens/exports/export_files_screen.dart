import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/lecture_model.dart';
import '../../models/attendance_model.dart';
import '../../models/exam_model.dart';
import '../../models/grade_model.dart';
import '../../models/note_model.dart';
import '../../database/database_helper.dart';

class ExportFilesScreen extends StatefulWidget {
  final ClassModel classModel;

  const ExportFilesScreen({
    super.key,
    required this.classModel,
  });

  @override
  State<ExportFilesScreen> createState() => _ExportFilesScreenState();
}

class _ExportFilesScreenState extends State<ExportFilesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ClassModel> _allClasses = [];
  ClassModel? _currentClass;

  // خيارات تصدير التقارير المالية
  List<String> _financeExportLocations = [];
  List<ClassModel> _financeExportClasses = [];
  String _financeSelectedLocation = 'اختر موقع';
  String _financeSelectedClassId = 'all';
  
  // نوع الملف المحدد
  String _selectedFileType = 'student_info'; // student_info, attendance_summary, attendance_detailed, exam_attendance, exams, final_grades, class_notes, student_summary, financial_data, late_payments, payment_history
  
  // خيارات معلومات الطالب
  String _studentInfoNameOption = 'name'; // name, id, both
  
  // خيارات التاريخ (لجميع الخيارات ما عدا معلومات الطالب)
  String _dateOption = 'all'; // all, custom
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _currentClass = widget.classModel;
    _loadAllClasses();
    _loadFinanceExportFilters();
  }

  Future<void> _loadAllClasses() async {
    try {
      _allClasses = await _dbHelper.getAllClasses();
      setState(() {});
    } catch (e) {
      print('خطأ في تحميل الفصول: $e');
    }
  }

  Future<void> _loadFinanceExportFilters() async {
    try {
      final allCourses = await _dbHelper.getCourses();
      final allClasses = await _dbHelper.getAllClasses();

      final courseLocations = allCourses
          .map((c) => c['location']?.toString() ?? '')
          .where((s) => s.trim().isNotEmpty)
          .toSet();

      // في هذا المشروع: موقع الفصل محفوظ في classes.subject
      final classLocations = allClasses
          .map((c) => c.subject)
          .where((s) => s.trim().isNotEmpty)
          .toSet();

      final locations = courseLocations.intersection(classLocations).toList()..sort();

      if (!mounted) return;
      setState(() {
        _financeExportLocations = locations;
        if (_financeExportLocations.isNotEmpty) {
          _financeSelectedLocation = _financeExportLocations.first;
        }
      });

      await _reloadFinanceClassesForSelectedLocation();
    } catch (e) {
      // تجاهل
    }
  }

  Future<void> _reloadFinanceClassesForSelectedLocation() async {
    final loc = _financeSelectedLocation;
    if (loc.isEmpty || loc == 'اختر موقع') {
      if (!mounted) return;
      setState(() {
        _financeExportClasses = [];
        _financeSelectedClassId = 'all';
      });
      return;
    }

    final allClasses = await _dbHelper.getAllClasses();
    final classes = allClasses.where((c) => (c.subject) == loc).toList();
    classes.sort((a, b) => a.name.compareTo(b.name));

    if (!mounted) return;
    setState(() {
      _financeExportClasses = classes;
      _financeSelectedClassId = 'all';
    });
  }

  bool _fileTypeUsesDateFilter(String t) {
    switch (t) {
      case 'attendance_summary':
      case 'attendance_detailed':
      case 'exam_attendance':
      case 'exams':
      case 'final_grades':
      case 'class_notes':
      case 'student_summary':
        return true;
      default:
        return false;
    }
  }

  bool _fileTypeUsesFinanceFilters(String t) {
    switch (t) {
      case 'financial_data':
      case 'late_payments':
      case 'payment_history':
        return true;
      default:
        return false;
    }
  }

  Widget _buildFinanceExportFilters() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.location_on, color: Colors.green),
            title: const Text('الموقع'),
            trailing: DropdownButton<String>(
              value: _financeSelectedLocation == 'اختر موقع' && _financeExportLocations.isNotEmpty
                  ? _financeExportLocations.first
                  : (_financeExportLocations.contains(_financeSelectedLocation)
                      ? _financeSelectedLocation
                      : (_financeExportLocations.isNotEmpty ? _financeExportLocations.first : 'اختر موقع')),
              items: _financeExportLocations
                  .map(
                    (l) => DropdownMenuItem<String>(
                      value: l,
                      child: Text(l),
                    ),
                  )
                  .toList(),
              onChanged: (val) async {
                if (val == null) return;
                setState(() {
                  _financeSelectedLocation = val;
                });
                await _reloadFinanceClassesForSelectedLocation();
              },
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.class_, color: Colors.green),
            title: const Text('الفصل'),
            trailing: DropdownButton<String>(
              value: _financeSelectedClassId,
              items: [
                const DropdownMenuItem<String>(
                  value: 'all',
                  child: Text('جميع الفصول'),
                ),
                ..._financeExportClasses.map(
                  (c) => DropdownMenuItem<String>(
                    value: c.id?.toString() ?? '',
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _financeSelectedClassId = val;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getSelectedFinanceClassTitle() {
    final classId = _financeSelectedClassId;
    if (classId == 'all') return 'جميع الفصول';
    try {
      final c = _financeExportClasses.firstWhere((e) => e.id?.toString() == classId);
      return c.name;
    } catch (_) {
      return classId;
    }
  }

  Future<void> _switchToClass(ClassModel newClass) async {
    if (newClass.id == _currentClass?.id) return;
    
    setState(() {
      _currentClass = newClass;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم التبديل إلى فصل: ${newClass.name}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showClassSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // العنوان
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.class_, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'اختر الفصل (${_allClasses.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // قائمة الفصول
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _allClasses.length,
                itemBuilder: (context, index) {
                  final classModel = _allClasses[index];
                  final isSelected = _currentClass?.id == classModel.id;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected ? Colors.green : Colors.grey.withOpacity(0.3),
                        width: isSelected ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      color: isSelected ? Colors.green.withOpacity(0.1) : null,
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.class_,
                        color: isSelected ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        classModel.name,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.green : null,
                        ),
                      ),
                      subtitle: Text('${classModel.subject} - ${classModel.year}'),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _switchToClass(classModel);
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showStudentInfoNameOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'اختر طريقة عرض الاسم',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              RadioListTile<String>(
                title: const Text('الاسم فقط'),
                value: 'name',
                groupValue: _studentInfoNameOption,
                activeColor: Colors.green,
                onChanged: (value) {
                  setState(() => _studentInfoNameOption = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('ID فقط'),
                value: 'id',
                groupValue: _studentInfoNameOption,
                activeColor: Colors.green,
                onChanged: (value) {
                  setState(() => _studentInfoNameOption = value!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('الاسم و ID'),
                value: 'both',
                groupValue: _studentInfoNameOption,
                activeColor: Colors.green,
                onChanged: (value) {
                  setState(() => _studentInfoNameOption = value!);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileTypeSelector() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.description, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  'نوع الملف',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // معلومات الطالب
          _buildFileTypeOption(
            'student_info',
            'معلومات الطالب',
            Icons.person,
            Colors.blue,
          ),
          
          // ملخص الحضور
          _buildFileTypeOption(
            'attendance_summary',
            'ملخص الحضور',
            Icons.summarize,
            Colors.orange,
          ),
          
          // الحضور التفصيلي
          _buildFileTypeOption(
            'attendance_detailed',
            'الحضور التفصيلي',
            Icons.calendar_month,
            Colors.purple,
          ),
          
          // حضور الامتحانات
          _buildFileTypeOption(
            'exam_attendance',
            'حضور الامتحانات',
            Icons.fact_check,
            Colors.deepPurple,
          ),
          
          // الامتحانات
          _buildFileTypeOption(
            'exams',
            'الامتحانات',
            Icons.assignment,
            Colors.green,
          ),
          
          // الدرجة النهائية
          _buildFileTypeOption(
            'final_grades',
            'الدرجة النهائية',
            Icons.grade,
            Colors.teal,
          ),
          
          // ملاحظات الفصول
          _buildFileTypeOption(
            'class_notes',
            'ملاحظات الفصول',
            Icons.note_alt,
            Colors.indigo,
          ),
          
          // ملخص الطالب
          _buildFileTypeOption(
            'student_summary',
            'ملخص الطالب',
            Icons.summarize_outlined,
            Colors.pink,
          ),

          // البيانات المالية (نفس إدارة الأقساط)
          _buildFileTypeOption(
            'financial_data',
            'البيانات المالية',
            Icons.account_balance_wallet,
            Colors.green,
          ),

          // الطلاب المتأخرين بالدفع
          _buildFileTypeOption(
            'late_payments',
            'الطلاب المتأخرين بالدفع',
            Icons.warning_amber_rounded,
            Colors.red,
          ),

          // سجل الدفعات
          _buildFileTypeOption(
            'payment_history',
            'سجل الدفعات',
            Icons.receipt_long,
            Colors.amber,
          ),
        ],
      ),
    );
  }

  Widget _buildFileTypeOption(String value, String title, IconData icon, Color color) {
    final isSelected = _selectedFileType == value;
    
    return InkWell(
      onTap: () => setState(() => _selectedFileType = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : null,
          border: Border(
            bottom: BorderSide(color: Colors.grey.withOpacity(0.2)),
          ),
        ),
        child: Row(
          children: [
            Radio<String>(
              value: value,
              groupValue: _selectedFileType,
              activeColor: color,
              onChanged: (val) => setState(() => _selectedFileType = val!),
            ),
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentInfoOptions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.badge, color: Colors.blue),
            title: const Text('الاسم'),
            subtitle: Text(_getStudentInfoNameOptionText()),
            trailing: const Icon(Icons.arrow_drop_down),
            onTap: _showStudentInfoNameOptions,
          ),
        ],
      ),
    );
  }

  String _getStudentInfoNameOptionText() {
    switch (_studentInfoNameOption) {
      case 'name':
        return 'الاسم فقط';
      case 'id':
        return 'ID فقط';
      case 'both':
        return 'الاسم و ID';
      default:
        return '';
    }
  }

  Widget _buildDateFilterOptions() {
    // تحديد اللون حسب نوع الملف
    Color filterColor = Colors.orange;
    String titleText = 'تحديد التاريخ';
    String allOptionText = 'الكل';
    
    switch (_selectedFileType) {
      case 'attendance_summary':
      case 'attendance_detailed':
        filterColor = Colors.orange;
        allOptionText = 'كل المحاضرات';
        break;
      case 'exams':
      case 'final_grades':
        filterColor = Colors.green;
        allOptionText = 'كل الامتحانات';
        break;
      case 'student_summary':
        filterColor = Colors.pink;
        allOptionText = 'كل الفترة';
        break;
      case 'class_notes':
        filterColor = Colors.indigo;
        allOptionText = 'كل الملاحظات';
        break;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: filterColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: filterColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.date_range, color: filterColor),
                const SizedBox(width: 8),
                Text(
                  titleText,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          RadioListTile<String>(
            title: Text(allOptionText),
            value: 'all',
            groupValue: _dateOption,
            activeColor: filterColor,
            onChanged: (value) {
              setState(() {
                _dateOption = value!;
                _startDate = null;
                _endDate = null;
              });
            },
          ),
          RadioListTile<String>(
            title: const Text('تاريخ محدد'),
            value: 'custom',
            groupValue: _dateOption,
            activeColor: filterColor,
            onChanged: (value) {
              setState(() => _dateOption = value!);
            },
          ),
          if (_dateOption == 'custom') ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // تاريخ البدء
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _startDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _startDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.orange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('من تاريخ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _startDate != null
                                      ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                                      : 'اختر تاريخ البدء',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // تاريخ النهاية
                  InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: _startDate ?? DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, color: Colors.orange, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('إلى تاريخ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                Text(
                                  _endDate != null
                                      ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                                      : 'اختر تاريخ النهاية',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _exportStudentInfo() async {
    if (_currentClass == null) return;

    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.blue),
              SizedBox(height: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      // تحميل الطلاب
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      
      if (students.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد طلاب في هذا الفصل'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // تحميل الخطوط العربية
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
              // العنوان
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      className,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'معلومات الطلاب',
                      style: pw.TextStyle(fontSize: 18, font: ttf),
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
                  // بيانات الطلاب
                  ...students.map((student) {
                    return pw.TableRow(
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
                          child: pw.Text(student.primaryGuardian?.email ?? student.parentEmail ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ];
          },
        ),
      );

      // إخفاء مؤشر التحميل
      Navigator.pop(context);

      // اسم الملف
      final fileName = '${className}_معلومات_الطلاب.pdf';
      
      // حفظ وفتح الملف
      await Printing.sharePdf(
        bytes: await pdf.save(), 
        filename: fileName,
      );

      // رسالة نجاح
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('تم إنشاء الملف: $fileName')),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إنشاء الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportAttendanceSummary() async {
    if (_currentClass == null) return;

    // التحقق من التواريخ في حالة التاريخ المحدد
    if (_dateOption == 'custom') {
      if (_startDate == null || _endDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('يرجى تحديد تاريخ البدء والنهاية'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    try {
      // إظهار مؤشر التحميل
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.orange),
              SizedBox(height: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      // تحميل الطلاب
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      
      if (students.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد طلاب في هذا الفصل'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // تحميل المحاضرات
      final allLectures = await _dbHelper.getLecturesByClass(_currentClass!.id!);
      
      // تصفية المحاضرات حسب التاريخ
      List<LectureModel> lectures;
      if (_dateOption == 'custom' && _startDate != null && _endDate != null) {
        lectures = allLectures.where((lecture) {
          return lecture.date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
                 lecture.date.isBefore(_endDate!.add(const Duration(days: 1)));
        }).toList();
      } else {
        lectures = allLectures;
      }

      if (lectures.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد محاضرات في الفترة المحددة'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // حساب إحصائيات الحضور لكل طالب
      Map<int, Map<String, int>> attendanceStats = {};
      
      for (var student in students) {
        int present = 0, absent = 0, late = 0, expelled = 0, excused = 0;
        
        for (var lecture in lectures) {
          final attendance = await _dbHelper.getAttendanceByStudentAndLecture(
            studentId: student.id!,
            lectureId: lecture.id!,
          );
          
          if (attendance != null) {
            switch (attendance.status) {
              case AttendanceStatus.present:
                present++;
                break;
              case AttendanceStatus.absent:
                absent++;
                break;
              case AttendanceStatus.late:
                late++;
                break;
              case AttendanceStatus.expelled:
                expelled++;
                break;
              case AttendanceStatus.excused:
                excused++;
                break;
            }
          }
        }
        
        attendanceStats[student.id!] = {
          'present': present,
          'absent': absent,
          'late': late,
          'expelled': expelled,
          'excused': excused,
          'total': lectures.length,
        };
      }

      // تحميل الخطوط العربية
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
              // العنوان
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.orange100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      className,
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'ملخص الحضور',
                      style: pw.TextStyle(fontSize: 18, font: ttf),
                      textAlign: pw.TextAlign.center,
                      textDirection: pw.TextDirection.rtl,
                    ),
                    if (_dateOption == 'custom') ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'من ${_startDate!.day}/${_startDate!.month}/${_startDate!.year} إلى ${_endDate!.day}/${_endDate!.month}/${_endDate!.year}',
                        style: pw.TextStyle(fontSize: 14, font: ttf),
                        textAlign: pw.TextAlign.center,
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              
              // جدول ملخص الحضور
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
                        child: pw.Text('عدد المحاضرات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الحضور', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الغياب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('التأخر', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('مجاز', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('الطرد', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('النسبة %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                      ),
                    ],
                  ),
                  // بيانات الطلاب
                  ...students.map((student) {
                    final stats = attendanceStats[student.id!]!;
                    final percentage = stats['total']! > 0 
                        ? ((stats['present']! / stats['total']!) * 100).toStringAsFixed(1)
                        : '0.0';
                    
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['total']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['present']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['absent']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['late']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['excused']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('${stats['expelled']}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8),
                          child: pw.Text('$percentage%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
                        ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ];
          },
        ),
      );

      // إخفاء مؤشر التحميل
      Navigator.pop(context);

      // اسم الملف
      final fileName = '${className}_ملخص_الحضور.pdf';
      
      // حفظ وفتح الملف
      await Printing.sharePdf(
        bytes: await pdf.save(), 
        filename: fileName,
      );

      // رسالة نجاح
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('تم إنشاء الملف: $fileName')),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في إنشاء الملف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _exportAttendanceDetailed() async {
    if (_currentClass == null) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.purple), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      if (students.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange)); return; }
      final lectures = await _dbHelper.getLecturesByClass(_currentClass!.id!);
      if (lectures.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد محاضرات'), backgroundColor: Colors.orange)); return; }
      
      // ترتيب المحاضرات حسب التاريخ
      lectures.sort((a, b) => a.date.compareTo(b.date));
      
      // تنظيم المحاضرات حسب الأشهر
      Map<String, List<LectureModel>> lecturesByMonth = {};
      for (var lecture in lectures) {
        final monthKey = '${lecture.date.year}-${lecture.date.month.toString().padLeft(2, '0')}';
        if (!lecturesByMonth.containsKey(monthKey)) { lecturesByMonth[monthKey] = []; }
        lecturesByMonth[monthKey]!.add(lecture);
      }
      final sortedMonths = lecturesByMonth.keys.toList()..sort();
      
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document(); final className = _currentClass!.name;
      
      // إنشاء رأس الجدول
      List<pw.Widget> headerCells = [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
      ];
      
      // إضافة أعمدة الأيام مع أسماء الأشهر
      final monthNames = {'01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr', '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug', '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec'};
      for (var monthKey in sortedMonths) {
        final parts = monthKey.split('-');
        final monthAbbr = monthNames[parts[1]] ?? '';
        final monthLectures = lecturesByMonth[monthKey]!;
        for (var lecture in monthLectures) {
          headerCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Column(children: [
            pw.Text(monthAbbr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 7, color: PdfColors.white), textAlign: pw.TextAlign.center),
            pw.Text('${lecture.date.day}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 8, color: PdfColors.white), textAlign: pw.TextAlign.center),
          ])));
        }
      }
      
      // إنشاء صفوف الطلاب
      List<pw.TableRow> tableRows = [pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: headerCells)];
      
      for (var student in students) {
        List<pw.Widget> rowCells = [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        ];
        
        for (var lecture in lectures) {
          final attendance = await _dbHelper.getAttendanceByStudentAndLecture(studentId: student.id!, lectureId: lecture.id!);
          String statusText = '-';
          PdfColor textColor = PdfColors.black;
          if (attendance != null) {
            switch (attendance.status) {
              case AttendanceStatus.present: statusText = 'حاضر'; textColor = PdfColors.green; break;
              case AttendanceStatus.absent: statusText = 'غائب'; textColor = PdfColors.red; break;
              case AttendanceStatus.late: statusText = 'متأخر'; textColor = PdfColors.orange; break;
              case AttendanceStatus.expelled: statusText = 'مطرود'; textColor = PdfColors.purple; break;
              case AttendanceStatus.excused: statusText = 'مجاز'; textColor = PdfColors.black; break;
            }
          }
          rowCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(statusText, style: pw.TextStyle(font: ttf, fontSize: 7, color: textColor), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)));
        }
        tableRows.add(pw.TableRow(children: rowCells));
      }
      
      pdf.addPage(pw.MultiPage(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4.landscape, build: (pw.Context context) => [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.blue100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(children: [pw.Text(className, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl), pw.SizedBox(height: 4), pw.Text('الحضور التفصيلي', style: pw.TextStyle(fontSize: 14, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)])),
        pw.SizedBox(height: 10),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: tableRows),
      ]));
      
      Navigator.pop(context); final fileName = '${className}_الحضور_التفصيلي.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportExamAttendance() async {
    if (_currentClass == null) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.deepPurple), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      if (students.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange)); return; }
      final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
      if (exams.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد امتحانات'), backgroundColor: Colors.orange)); return; }
      
      // ترتيب الامتحانات حسب التاريخ
      exams.sort((a, b) => a.date.compareTo(b.date));
      
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold();
      final pdf = pw.Document(); final className = _currentClass!.name;
      
      // إنشاء رأس الجدول
      final monthNames = {'01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr', '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug', '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec'};
      List<pw.Widget> headerCells = [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
      ];
      
      // إضافة أعمدة الامتحانات مع التواريخ
      for (var exam in exams) {
        final monthAbbr = monthNames['${exam.date.month.toString().padLeft(2, '0')}'] ?? '';
        headerCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Column(children: [
          pw.Text(exam.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 7, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
          pw.Text('$monthAbbr ${exam.date.day}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 6, color: PdfColors.white), textAlign: pw.TextAlign.center),
        ])));
      }
      
      // إنشاء صفوف الطلاب
      List<pw.TableRow> tableRows = [pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: headerCells)];
      
      for (var student in students) {
        List<pw.Widget> rowCells = [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        ];
        
        for (var exam in exams) {
          final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
          final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
          
          String statusText = '-';
          PdfColor textColor = PdfColors.black;
          
          if (grade != null) {
            final statusRaw = (grade.status ?? '').trim();

            if (statusRaw == 'معفئ' || statusRaw == 'مؤجل' || statusRaw == 'معفئ او مؤجل') {
              statusText = 'معفئ او مؤجل';
              textColor = PdfColors.blue;
            } else if (statusRaw == 'غائب' || grade.notes?.contains('غائب') == true) {
              statusText = 'غائب';
              textColor = PdfColors.red;
            } else if (statusRaw == 'غش' || grade.notes?.contains('غش') == true) {
              statusText = 'غش';
              textColor = PdfColors.orange;
            } else if (statusRaw == 'مفقودة' || grade.notes?.contains('مفقودة') == true) {
              statusText = 'مفقودة';
              textColor = PdfColors.purple;
            } else if (statusRaw == 'طرد' || grade.notes?.contains('طرد') == true) {
              statusText = 'طرد';
              textColor = PdfColors.deepOrange;
            } else {
              statusText = 'حاضر';
              textColor = PdfColors.green;
            }
          }
          
          rowCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(statusText, style: pw.TextStyle(font: ttf, fontSize: 7, color: textColor), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)));
        }
        tableRows.add(pw.TableRow(children: rowCells));
      }
      
      pdf.addPage(pw.MultiPage(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4.landscape, build: (pw.Context context) => [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.purple100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(children: [pw.Text(className, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl), pw.SizedBox(height: 4), pw.Text('حضور الامتحانات', style: pw.TextStyle(fontSize: 14, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)])),
        pw.SizedBox(height: 10),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: tableRows),
      ]));
      
      Navigator.pop(context); final fileName = '${className}_حضور_الامتحانات.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportExams() async {
    if (_currentClass == null) return;
    if (_dateOption == 'custom' && (_startDate == null || _endDate == null)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى تحديد تاريخ البدء والنهاية'), backgroundColor: Colors.orange)); return; }
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.green), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      if (students.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange)); return; }
      final allExams = await _dbHelper.getExamsByClass(_currentClass!.id!);
      List<ExamModel> exams = _dateOption == 'custom' && _startDate != null && _endDate != null ? allExams.where((e) => e.date.isAfter(_startDate!.subtract(const Duration(days: 1))) && e.date.isBefore(_endDate!.add(const Duration(days: 1)))).toList() : allExams;
      if (exams.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد امتحانات'), backgroundColor: Colors.orange)); return; }
      exams.sort((a, b) => a.date.compareTo(b.date));
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold(); final pdf = pw.Document(); final className = _currentClass!.name;
      
      // إنشاء رأس الجدول
      final monthNames = {'01': 'Jan', '02': 'Feb', '03': 'Mar', '04': 'Apr', '05': 'May', '06': 'Jun', '07': 'Jul', '08': 'Aug', '09': 'Sep', '10': 'Oct', '11': 'Nov', '12': 'Dec'};
      List<pw.Widget> headerCells = [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المعدل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
      ];
      
      for (var exam in exams) {
        final monthAbbr = monthNames['${exam.date.month.toString().padLeft(2, '0')}'] ?? '';
        headerCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Column(children: [
          pw.Text(exam.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 7, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center),
          pw.Text('$monthAbbr ${exam.date.day}', style: pw.TextStyle(font: ttf, fontSize: 6, color: PdfColors.white), textAlign: pw.TextAlign.center),
          pw.Text('${exam.maxScore.toInt()} pts', style: pw.TextStyle(font: ttf, fontSize: 6, color: PdfColors.white), textAlign: pw.TextAlign.center),
        ])));

        headerCells.add(
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text(
              'الحالة',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                font: ttfBold,
                fontSize: 8,
                color: PdfColors.white,
              ),
              textDirection: pw.TextDirection.rtl,
              textAlign: pw.TextAlign.center,
            ),
          ),
        );
      }
      
      List<pw.TableRow> tableRows = [pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: headerCells)];
      
      for (var student in students) {
        final studentGrades = await _dbHelper.getGradesByStudent(student.id!);
        double totalGrades = 0, maxGrades = 0;
        for (var exam in exams) {
          final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
          final statusText = grade?.status?.trim() ?? 'حاضر';
          if (grade != null && statusText == 'حاضر') {
            totalGrades += grade.score;
            maxGrades += exam.maxScore;
          }
        }
        final finalPercent = maxGrades > 0 ? ((totalGrades / maxGrades) * 100).toStringAsFixed(1) : '0.0';
        
        List<pw.Widget> rowCells = [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$finalPercent%', style: pw.TextStyle(font: ttfBold, fontSize: 8), textAlign: pw.TextAlign.center)),
        ];
        
        for (var exam in exams) {
          final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull;
          final statusText = grade?.status?.trim() ?? 'حاضر';

          String txt;
          if (grade == null) {
            txt = '-';
          } else if (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل') {
            txt = '';
          } else {
            txt = '${grade.score.toInt()}';
          }

          PdfColor textColor = PdfColors.black;
          if (grade != null && txt.isNotEmpty) {
            final percent = (grade.score / exam.maxScore) * 100;
            if (percent >= 85) textColor = PdfColors.green;
            else if (percent >= 70) textColor = PdfColors.black;
            else if (percent >= 50) textColor = PdfColors.orange;
            else textColor = PdfColors.red;
          }
          rowCells.add(pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(txt, style: pw.TextStyle(font: ttf, fontSize: 8, color: textColor), textAlign: pw.TextAlign.center)));

          rowCells.add(
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(
                grade == null
                    ? '-'
                    : (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل')
                        ? 'معفئ او مؤجل'
                        : statusText,
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 8,
                  color: (grade != null && (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل'))
                      ? PdfColors.blue
                      : PdfColors.black,
                ),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center,
              ),
            ),
          );
        }
        tableRows.add(pw.TableRow(children: rowCells));
      }
      
      pdf.addPage(pw.MultiPage(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4.landscape, build: (pw.Context context) => [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.blue100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(children: [pw.Text(className, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl), pw.SizedBox(height: 4), pw.Text('درجات الامتحانات', style: pw.TextStyle(fontSize: 14, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)])),
        pw.SizedBox(height: 10),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: tableRows),
      ]));
      
      Navigator.pop(context); final fileName = '${className}_الامتحانات.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportFinalGrades() async {
    if (_currentClass == null) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.teal), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      if (students.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange)); return; }
      final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold(); final pdf = pw.Document(); final className = _currentClass!.name;
      List<pw.TableRow> tableRows = [pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('ID', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('مجموع الدرجات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('النسبة %', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center))])];
      for (var student in students) { double totalGrades = 0, maxGrades = 0; final studentGrades = await _dbHelper.getGradesByStudent(student.id!); for (var exam in exams) { final grade = studentGrades.where((g) => g.examName == exam.title).firstOrNull; final statusText = grade?.status?.trim() ?? 'حاضر'; if (grade != null && statusText != 'معفئ' && statusText != 'مؤجل' && statusText != 'معفئ او مؤجل') { totalGrades += grade.score; maxGrades += exam.maxScore; }} final percent = maxGrades > 0 ? ((totalGrades / maxGrades) * 100).toStringAsFixed(1) : '0.0'; tableRows.add(pw.TableRow(children: [pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.name, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(student.studentId ?? '-', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${totalGrades.toStringAsFixed(1)} / ${maxGrades.toStringAsFixed(1)}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)), pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('$percent%', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center))])); }
      pdf.addPage(pw.MultiPage(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4, build: (pw.Context context) => [pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(12), decoration: pw.BoxDecoration(color: PdfColors.teal100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(children: [pw.Text(className, style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl), pw.SizedBox(height: 4), pw.Text('الدرجات النهائية', style: pw.TextStyle(fontSize: 18, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)])), pw.SizedBox(height: 20), pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: tableRows)]));
      Navigator.pop(context); final fileName = '${className}_مجموع_الدرجات.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportClassNotes() async {
    if (_currentClass == null) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.indigo), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final allNotes = await _dbHelper.getNotesByClass(_currentClass!.id!);
      final lectures = await _dbHelper.getLecturesByClass(_currentClass!.id!); final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold(); final pdf = pw.Document(); final className = _currentClass!.name;
      
      // إنشاء خريطة للملاحظات
      Map<String, NoteModel> notesMap = {};
      for (var note in allNotes) {
        final key = '${note.itemType}_${note.itemId}';
        notesMap[key] = note;
      }
      
      pdf.addPage(pw.Page(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4, build: (pw.Context context) {
        return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          // العنوان
          pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(5)), child: pw.Text('ملاحظات الفصل: $className', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)),
          pw.SizedBox(height: 20),
          
          // قسم المحاضرات
          if (lectures.isNotEmpty) ...[
            pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: PdfColors.blue50, borderRadius: pw.BorderRadius.circular(3)), child: pw.Text('المحاضرات', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
            pw.SizedBox(height: 10),
            pw.Table(border: pw.TableBorder.all(), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: [
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
              ]),
              ...lectures.map((lecture) {
                final key = 'lecture_${lecture.id}';
                final note = notesMap[key];
                return pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(lecture.title, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${lecture.date.day}/${lecture.date.month}/${lecture.date.year}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(note?.content ?? 'لا توجد ملاحظات', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                ]);
              }).toList(),
            ]),
            pw.SizedBox(height: 20),
          ],
          
          // قسم الامتحانات
          if (exams.isNotEmpty) ...[
            pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(8), decoration: pw.BoxDecoration(color: PdfColors.green50, borderRadius: pw.BorderRadius.circular(3)), child: pw.Text('الامتحانات', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textDirection: pw.TextDirection.rtl)),
            pw.SizedBox(height: 10),
            pw.Table(border: pw.TableBorder.all(), children: [
              pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: [
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('العنوان', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('التاريخ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
                pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('الملاحظات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, color: PdfColors.white), textDirection: pw.TextDirection.rtl)),
              ]),
              ...exams.map((exam) {
                final key = 'exam_${exam.id}';
                final note = notesMap[key];
                return pw.TableRow(children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(exam.title, style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${exam.date.day}/${exam.date.month}/${exam.date.year}', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                  pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(note?.content ?? 'لا توجد ملاحظات', style: pw.TextStyle(font: ttf), textDirection: pw.TextDirection.rtl)),
                ]);
              }).toList(),
            ]),
          ],
          
          // رسالة في حالة عدم وجود بيانات
          if (lectures.isEmpty && exams.isEmpty) pw.Center(child: pw.Container(padding: const pw.EdgeInsets.all(20), child: pw.Text('لا توجد محاضرات أو امتحانات في هذا الفصل', style: pw.TextStyle(color: PdfColors.grey, font: ttf), textDirection: pw.TextDirection.rtl))),
        ]);
      }));
      
      Navigator.pop(context); final fileName = '${className}_الملاحظات.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportStudentSummary() async {
    if (_currentClass == null) return;
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const AlertDialog(content: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(color: Colors.pink), SizedBox(height: 16), Text('جاري إنشاء ملف PDF...')])));
      final students = await _dbHelper.getStudentsByClass(_currentClass!.id!);
      if (students.isEmpty) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد طلاب'), backgroundColor: Colors.orange)); return; }
      final lectures = await _dbHelper.getLecturesByClass(_currentClass!.id!); final exams = await _dbHelper.getExamsByClass(_currentClass!.id!);
      final ttf = await PdfGoogleFonts.cairoRegular(); final ttfBold = await PdfGoogleFonts.cairoBold(); final pdf = pw.Document(); final className = _currentClass!.name;
      
      // إنشاء رأس الجدول
      List<pw.Widget> headerCells = [
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('اسم الطالب', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('عدد الغيابات', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('الامتحانات الغائبة', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 8, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('المعدل', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, font: ttfBold, fontSize: 9, color: PdfColors.white), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
      ];
      
      List<pw.TableRow> tableRows = [pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.blue), children: headerCells)];
      
      int studentNum = 1;
      for (var student in students) {
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
            final statusText = grade.status?.trim() ?? 'حاضر';
            if (statusText == 'معفئ' || statusText == 'مؤجل' || statusText == 'معفئ او مؤجل') {
              continue;
            }
            totalGrades += grade.score;
            maxGrades += exam.maxScore;
          }
        }
        
        final gradePercent = maxGrades > 0 ? ((totalGrades / maxGrades) * 100).toStringAsFixed(1) : '0.0';
        
        List<pw.Widget> rowCells = [
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$studentNum', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(student.name, style: pw.TextStyle(font: ttf, fontSize: 8), textDirection: pw.TextDirection.rtl, textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$absent', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$missingExams', style: pw.TextStyle(font: ttf, fontSize: 8), textAlign: pw.TextAlign.center)),
          pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$gradePercent%', style: pw.TextStyle(font: ttfBold, fontSize: 8), textAlign: pw.TextAlign.center)),
        ];
        
        tableRows.add(pw.TableRow(children: rowCells));
        studentNum++;
      }
      
      pdf.addPage(pw.MultiPage(textDirection: pw.TextDirection.rtl, pageFormat: PdfPageFormat.a4, build: (pw.Context context) => [
        pw.Container(width: double.infinity, padding: const pw.EdgeInsets.all(10), decoration: pw.BoxDecoration(color: PdfColors.blue100, borderRadius: pw.BorderRadius.circular(8)), child: pw.Column(children: [pw.Text(className, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, font: ttfBold), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl), pw.SizedBox(height: 4), pw.Text('ملخص الطلاب', style: pw.TextStyle(fontSize: 14, font: ttf), textAlign: pw.TextAlign.center, textDirection: pw.TextDirection.rtl)])),
        pw.SizedBox(height: 10),
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey), children: tableRows),
      ]));
      
      Navigator.pop(context); final fileName = '${className}_ملخص_الطلاب.pdf'; await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [const Icon(Icons.check_circle, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('تم إنشاء: $fileName'))]), backgroundColor: Colors.green));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red)); }
  }

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
      case 'exam_attendance':
        await _exportExamAttendance();
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
      case 'financial_data':
        await _exportFinancialData();
        break;
      case 'late_payments':
        await _exportLatePaymentsFinancial();
        break;
      case 'payment_history':
        await _exportPaymentHistoryFinancial();
        break;
    }
  }

  Future<List<Map<String, dynamic>>> _getStudentsForFinanceExport({
    required String location,
    required String classId,
  }) async {
    final students = await _dbHelper.getAllStudents();
    final classes = await _dbHelper.getAllClasses();
    final classById = {for (final c in classes) (c.id?.toString() ?? ''): c};

    final filtered = students.where((s) {
      final c = classById[s.classId?.toString() ?? ''];
      final effectiveLoc = (s.location?.trim().isNotEmpty == true)
          ? (s.location ?? '')
          : (c?.subject ?? '');

      final matchesLocation = effectiveLoc == location;
      final matchesClass = classId == 'all' || (s.classId?.toString() ?? '') == classId;
      return matchesLocation && matchesClass;
    }).toList();

    return filtered
        .map((s) {
          final c = classById[s.classId?.toString() ?? ''];
          return {
            'id': s.id,
            'name': s.name,
            'class_id': s.classId,
            'class_name': c?.name ?? '',
            'location': (s.location?.trim().isNotEmpty == true) ? s.location : (c?.subject ?? ''),
          };
        })
        .toList();
  }

  Future<Map<String, int>> _getEnabledDueByClassForLocation({
    required String location,
    required List<int> classIds,
  }) async {
    if (classIds.isEmpty) return <String, int>{};
    final db = await _dbHelper.database;
    final placeholders = List.filled(classIds.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT ccp.class_id as class_id,
             COALESCE(SUM(ccp.amount), 0) as total_due
      FROM class_course_prices ccp
      INNER JOIN courses ON courses.id = ccp.course_id
      WHERE ccp.enabled = 1
        AND courses.location = ?
        AND ccp.class_id IN ($placeholders)
      GROUP BY ccp.class_id
      ''',
      [location, ...classIds],
    );

    final map = <String, int>{};
    for (final r in rows) {
      final cid = r['class_id']?.toString() ?? '';
      final t = r['total_due'];
      final total = (t is int) ? t : (t is num) ? t.toInt() : int.tryParse(t?.toString() ?? '') ?? 0;
      if (cid.isNotEmpty) map[cid] = total;
    }
    return map;
  }

  Future<void> _exportFinancialData() async {
    if (_financeExportLocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد مواقع متاحة للتصدير')),
      );
      return;
    }

    final location = _financeSelectedLocation;
    if (location.isEmpty || location == 'اختر موقع') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الموقع')),
      );
      return;
    }

    final classId = _financeSelectedClassId;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.green),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final students = await _getStudentsForFinanceExport(location: location, classId: classId);
      if (students.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد طلاب ضمن هذا الاختيار')),
        );
        return;
      }

      final studentIds = students.map((s) => s['id'] as int).toList();
      final classIds = students.map((s) => (s['class_id'] as int?) ?? 0).where((e) => e > 0).toSet().toList();

      final dueByClass = await _getEnabledDueByClassForLocation(location: location, classIds: classIds);
      final paidByStudent = await _dbHelper.getTotalPaidByStudentIdsForLocation(
        studentIds: studentIds,
        location: location,
      );

      int totalDue = 0;
      int totalPaid = 0;
      int totalRemaining = 0;

      final rows = <Map<String, dynamic>>[];
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final sid = s['id'] as int;
        final cid = (s['class_id'] as int?)?.toString() ?? '';
        final due = dueByClass[cid] ?? 0;
        final paid = paidByStudent[sid] ?? 0;
        final remaining = (due - paid).clamp(0, 1 << 30);
        totalDue += due;
        totalPaid += paid;
        totalRemaining += remaining;
        rows.add({
          'index': i + 1,
          'studentName': s['name']?.toString() ?? '',
          'location': s['location']?.toString() ?? '',
          'due': due,
          'paid': paid,
          'remaining': remaining,
        });
      }

      final arabicFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'),
      );
      final arabicBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'),
      );

      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      );

      final classTitle = _getSelectedFinanceClassTitle();

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
                    'الموقع: $location',
                    style: pw.TextStyle(font: arabicFont, fontSize: 11, color: PdfColor.fromInt(0xFF555555)),
                  ),
                  pw.Text(
                    'الفصل: $classTitle',
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
                              pw.Text('$totalDue د.ع'),
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
                              pw.Text('$totalPaid د.ع'),
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
                              pw.Text('$totalRemaining د.ع'),
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
                      ...rows.map((r) {
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
                              child: pw.Text('${r['due'] ?? 0} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('${r['paid'] ?? 0} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(6),
                              child: pw.Text('${r['remaining'] ?? 0} د.ع', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
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

      Navigator.pop(context);
      final fileName = 'البيانات_المالية_${location}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: await pdfDoc.save(), filename: fileName);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportLatePaymentsFinancial() async {
    final location = _financeSelectedLocation;
    if (location.isEmpty || location == 'اختر موقع') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الموقع')),
      );
      return;
    }
    final classId = _financeSelectedClassId;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.red),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final students = await _getStudentsForFinanceExport(location: location, classId: classId);
      final courses = (await _dbHelper.getCourses())
          .where((c) => (c['location']?.toString() ?? '') == location)
          .toList();

      final dueDates = await _dbHelper.getAllCourseDueDates();
      final now = DateTime.now();

      final rows = <Map<String, dynamic>>[];
      int idx = 0;

      for (final s in students) {
        final sid = s['id'] as int;
        final studentClassId = (s['class_id'] as int?)?.toString() ?? '';
        if (studentClassId.isEmpty) continue;

        bool isLateAny = false;
        int totalPaid = 0;
        int totalRemaining = 0;
        final perCourse = <String, Map<String, dynamic>>{};

        for (final c in courses) {
          final courseId = c['id']?.toString() ?? '';
          if (courseId.isEmpty) continue;

          // اقرأ السعر المفعّل لهذا الفصل/الكورس
          final db = await _dbHelper.database;
          final priceRows = await db.query(
            'class_course_prices',
            columns: ['amount', 'enabled'],
            where: 'class_id = ? AND course_id = ?',
            whereArgs: [studentClassId, courseId],
            limit: 1,
          );
          if (priceRows.isEmpty) continue;
          final enabled = (priceRows.first['enabled']?.toString() ?? '0') == '1';
          if (!enabled) continue;

          final amount = priceRows.first['amount'];
          final due = (amount is int) ? amount : int.tryParse(amount?.toString() ?? '') ?? 0;
          if (due <= 0) continue;

          final paid = await _dbHelper.getTotalPaidByStudentAndCourse(
            studentId: sid,
            courseId: courseId,
          );
          final remaining = (due - paid).clamp(0, 1 << 30);
          totalPaid += paid;
          totalRemaining += remaining;

          final dueKey = '$studentClassId|$courseId';
          final dueDateStr = dueDates[dueKey];
          DateTime? dueDate;
          if (dueDateStr != null) {
            dueDate = DateTime.tryParse(dueDateStr);
          }
          final daysLate = (dueDate == null)
              ? null
              : now.difference(DateTime(dueDate.year, dueDate.month, dueDate.day)).inDays;
          final isLate = dueDate != null && (daysLate != null && daysLate > 0) && remaining > 0;
          if (isLate) isLateAny = true;

          perCourse[courseId] = {
            'daysLate': daysLate,
            'remaining': remaining,
            'dueDate': dueDate != null 
                ? DateFormat('yyyy-MM-dd').format(dueDate)
                : '',
          };
        }

        if (!isLateAny) continue;
        idx++;
        // Compute max days late across all courses for this student
        int maxDaysLate = 0;
        for (final entry in perCourse.values) {
          final days = entry['daysLate'] as int?;
          if (days != null && days > maxDaysLate) maxDaysLate = days;
        }
        rows.add({
          'index': idx,
          'studentName': s['name']?.toString() ?? '',
          'className': s['class_name']?.toString() ?? '',
          'location': s['location']?.toString() ?? '',
          'totalPaid': totalPaid,
          'totalRemaining': totalRemaining,
          'daysLate': maxDaysLate,
        });
      }

      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final arabicBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
      final fallbackFont = pw.Font.helvetica();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      );

      final classTitle = _getSelectedFinanceClassTitle();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
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
                    color: PdfColor.fromInt(0xFF000000),
                  ),
                ),
              );
            }

            return pw.Directionality(
              textDirection: pw.TextDirection.rtl,
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
                  pw.Text('الموقع: $location', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('الفصل: $classTitle', style: const pw.TextStyle(fontSize: 12)),
                  pw.Text('التاريخ: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 12),
                  pw.Text(rows.isEmpty ? 'لا توجد بيانات' : 'عدد السجلات: ${rows.length}', style: const pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 12),
                  if (rows.isNotEmpty)
                    pw.Table(
                      border: pw.TableBorder.all(color: const PdfColor(0.35, 0.35, 0.35), width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2.0),
                        1: const pw.FlexColumnWidth(1.4),
                        2: const pw.FlexColumnWidth(1.2),
                        3: const pw.FlexColumnWidth(1.4),
                        4: const pw.FlexColumnWidth(1.4),
                        5: const pw.FlexColumnWidth(1.2),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1A1A1A)),
                          children: [
                            headerCell('اسم الطالب'),
                            headerCell('الفصل'),
                            headerCell('الموقع'),
                            headerCell('إجمالي المدفوعات'),
                            headerCell('المبلغ المتبقي الكلي'),
                            headerCell('عدد أيام التأخير'),
                          ],
                        ),
                        ...rows.map(
                          (r) => pw.TableRow(
                            children: [
                              cell(r['studentName']?.toString() ?? ''),
                              cell(r['className']?.toString() ?? ''),
                              cell(r['location']?.toString() ?? ''),
                              cell(r['totalPaid']?.toString() ?? '0'),
                              cell(r['totalRemaining']?.toString() ?? '0'),
                              cell(r['daysLate']?.toString() ?? '0'),
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

      Navigator.pop(context);
      final fileName = 'المتأخرين_بالدفع_${location}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _exportPaymentHistoryFinancial() async {
    final location = _financeSelectedLocation;
    if (location.isEmpty || location == 'اختر موقع') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار الموقع')),
      );
      return;
    }

    final classId = _financeSelectedClassId;
    final classIdInt = (classId == 'all') ? null : int.tryParse(classId);

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: Colors.amber),
              SizedBox(width: 16),
              Text('جاري إنشاء ملف PDF...'),
            ],
          ),
        ),
      );

      final payments = await _dbHelper.getAllInstallmentsWithDetails(
        locationFilter: location,
        classIdFilter: classIdInt,
      );

      if (payments.isEmpty) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد دفعات ضمن هذا الاختيار')),
        );
        return;
      }

      final arabicFont = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Regular.ttf'));
      final arabicBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansArabic-Bold.ttf'));
      final fallbackFont = pw.Font.helvetica();

      final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
      );

      final classTitle = _getSelectedFinanceClassTitle();

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
                      'سجل الدفعات',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFFFEC619),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text('الموقع: $location', style: const pw.TextStyle(fontSize: 12)),
                    pw.Text('الفصل: $classTitle', style: const pw.TextStyle(fontSize: 12)),
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
                              child: pw.Text('اسم الطالب', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
                            ),
                            pw.Container(
                              padding: const pw.EdgeInsets.all(8),
                              child: pw.Text('الفصل', style: pw.TextStyle(font: arabicBold, color: PdfColor.fromInt(0xFFFEC619))),
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
                          ],
                        ),
                        ...List.generate(payments.length, (index) {
                          final p = payments[index];
                          return pw.TableRow(
                            children: [
                              pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text('${index + 1}', style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['student_name']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['class_name']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['amount']?.toString() ?? '0', style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(8), child: pw.Text(p['date']?.toString() ?? '', style: const pw.TextStyle(fontSize: 10))),
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

      Navigator.pop(context);
      final fileName = 'سجل_الدفعات_${location}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.pdf';
      await Printing.sharePdf(bytes: await doc.save(), filename: fileName);
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في إنشاء الملف: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showClassSelector,
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
                  _currentClass?.name ?? 'اختر فصل',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down, color: Colors.green),
              ],
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            
            // نوع الملف
            _buildFileTypeSelector(),
            
            // خيارات معلومات الطالب
            if (_selectedFileType == 'student_info')
              _buildStudentInfoOptions(),
            
            // خيارات تحديد التاريخ (لجميع الخيارات ما عدا معلومات الطالب)
            if (_fileTypeUsesDateFilter(_selectedFileType))
              _buildDateFilterOptions(),

            // فلاتر التقارير المالية
            if (_fileTypeUsesFinanceFilters(_selectedFileType))
              _buildFinanceExportFilters(),
            
            const SizedBox(height: 24),
            
            // زر التصدير
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _exportFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.file_download, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'تصدير الملف',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

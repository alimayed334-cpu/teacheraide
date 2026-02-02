import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../../models/class_model.dart';
import '../../models/student_model.dart';
import '../../models/note_model.dart';
import '../../database/database_helper.dart';
import '../../providers/class_provider.dart';
import '../../providers/student_provider.dart';
import '../../theme/app_theme.dart';

enum NoteType { good, bad, normal }

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
  List<StudentModel> _students = [];
  Map<String, List<NoteModel>> _studentNotes = {};
  String? _selectedDateFilter = 'كل التواريخ';
  DateTime? _startDate;
  DateTime? _endDate;
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
      
      // تحميل الطلاب
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.loadStudentsByClass(classId);
      _students = studentProvider.students;
      
      // تحميل الملاحظات
      await _loadStudentNotes();
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStudentNotes() async {
    _studentNotes.clear();
    
    for (final student in _students) {
      try {
        final notes = await _dbHelper.getNotesByStudent(student.id!);
        final filteredNotes = _getFilteredNotes(notes);
        
        if (filteredNotes.isNotEmpty) {
          _studentNotes[student.id.toString()] = filteredNotes;
        }
      } catch (e) {
        print('Error loading notes for student ${student.id}: $e');
      }
    }
  }

  List<NoteModel> _getFilteredNotes(List<NoteModel> notes) {
    if (_selectedDateFilter == 'كل التواريخ') {
      return notes;
    } else if (_selectedDateFilter == 'اليوم') {
      final today = DateTime.now();
      return notes.where((note) {
        final noteDate = DateTime(note.date.year, note.date.month, note.date.day);
        final todayDate = DateTime(today.year, today.month, today.day);
        return noteDate.isAtSameMomentAs(todayDate);
      }).toList();
    } else if (_selectedDateFilter == 'هذا الأسبوع') {
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      return notes.where((note) {
        return note.date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
               note.date.isBefore(weekEnd.add(const Duration(days: 1)));
      }).toList();
    } else if (_selectedDateFilter == 'هذا الشهر') {
      final now = DateTime.now();
      return notes.where((note) {
        return note.date.year == now.year && note.date.month == now.month;
      }).toList();
    } else if (_selectedDateFilter == 'تاريخ محدد' && _startDate != null && _endDate != null) {
      return notes.where((note) {
        return note.date.isAfter(_startDate!.subtract(const Duration(days: 1))) &&
               note.date.isBefore(_endDate!.add(const Duration(days: 1)));
      }).toList();
    }
    
    return notes;
  }

  Future<void> _loadAllClasses() async {
    try {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      await classProvider.loadClasses();
      _allClasses = classProvider.classes;
    } catch (e) {
      print('Error loading classes: $e');
    }
  }

  Map<NoteType, int> _getNoteStatistics() {
    final stats = {NoteType.good: 0, NoteType.bad: 0, NoteType.normal: 0};
    
    for (final notesList in _studentNotes.values) {
      for (final note in notesList) {
        final type = _getNoteType(note);
        stats[type] = (stats[type] ?? 0) + 1;
      }
    }
    
    return stats;
  }

  NoteType _getNoteType(NoteModel note) {
    if (note.type == 'good') return NoteType.good;
    if (note.type == 'bad') return NoteType.bad;
    return NoteType.normal;
  }

  Color _getNoteColor(NoteType type) {
    switch (type) {
      case NoteType.good:
        return Colors.green;
      case NoteType.bad:
        return Colors.red;
      case NoteType.normal:
        return Colors.white;
    }
  }

  String _getNoteTypeText(NoteType type) {
    switch (type) {
      case NoteType.good:
        return 'جيدة';
      case NoteType.bad:
        return 'سيئة';
      case NoteType.normal:
        return 'عادية';
    }
  }

  void _showDateFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختر فترة التاريخ', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  title: const Text('كل التواريخ', style: TextStyle(color: Colors.white)),
                  value: 'كل التواريخ',
                  groupValue: _selectedDateFilter,
                  onChanged: (value) {
                    setState(() => _selectedDateFilter = value);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('اليوم', style: TextStyle(color: Colors.white)),
                  value: 'اليوم',
                  groupValue: _selectedDateFilter,
                  onChanged: (value) {
                    setState(() => _selectedDateFilter = value);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('هذا الأسبوع', style: TextStyle(color: Colors.white)),
                  value: 'هذا الأسبوع',
                  groupValue: _selectedDateFilter,
                  onChanged: (value) {
                    setState(() => _selectedDateFilter = value);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('هذا الشهر', style: TextStyle(color: Colors.white)),
                  value: 'هذا الشهر',
                  groupValue: _selectedDateFilter,
                  onChanged: (value) {
                    setState(() => _selectedDateFilter = value);
                  },
                ),
                RadioListTile<String>(
                  title: const Text('تاريخ محدد', style: TextStyle(color: Colors.white)),
                  value: 'تاريخ محدد',
                  groupValue: _selectedDateFilter,
                  onChanged: (value) {
                    setState(() => _selectedDateFilter = value);
                  },
                ),
                if (_selectedDateFilter == 'تاريخ محدد') ...[
                  const SizedBox(height: 16),
                  ListTile(
                    title: Text(
                      'من: ${_startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : 'اختر'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: Colors.amber),
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
                  ),
                  ListTile(
                    title: Text(
                      'إلى: ${_endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : 'اختر'}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    trailing: const Icon(Icons.calendar_today, color: Colors.amber),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: _endDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (date != null) {
                        setState(() => _endDate = date);
                      }
                    },
                  ),
                ],
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _selectedDateFilter = _selectedDateFilter;
              });
              _applyDateFilter();
            },
            child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _applyDateFilter() {
    _loadStudentNotes();
  }

  void _showAddNoteOptions(StudentModel student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('اختر نوع الملاحظة', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('ملاحظة جيدة', style: TextStyle(color: Colors.green)),
              onTap: () {
                Navigator.pop(context);
                _showAddNoteDialog(student, NoteType.good);
              },
            ),
            ListTile(
              title: const Text('ملاحظة سيئة', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showAddNoteDialog(student, NoteType.bad);
              },
            ),
            ListTile(
              title: const Text('ملاحظة عادية', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showAddNoteDialog(student, NoteType.normal);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddNoteDialog(StudentModel student, NoteType type) {
    final controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('إضافة ملاحظة ${_getNoteTypeText(type)}', style: TextStyle(color: _getNoteColor(type))),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'اكتب الملاحظة هنا...',
            hintStyle: TextStyle(color: Colors.white70),
            border: OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final note = NoteModel(
                  studentId: student.id!,
                  note: controller.text.trim(),
                  date: DateTime.now(),
                  type: type.name,
                );
                
                await _dbHelper.insertNote(note);
                _loadStudentNotes();
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showNoteOptions(NoteModel note, StudentModel student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('خيارات الملاحظة', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('تعديل الملاحظة', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showEditNoteDialog(note, student);
              },
            ),
            ListTile(
              title: const Text('حذف الملاحظة', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteNote(note);
              },
            ),
            ListTile(
              title: const Text('تغيير التاريخ', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showChangeDateDialog(note, student);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditNoteDialog(NoteModel note, StudentModel student) {
    final controller = TextEditingController(text: note.note);
    NoteType currentType = _getNoteType(note);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('تعديل الملاحظة', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'اكتب الملاحظة هنا...',
                hintStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white54),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            const Text('نوع الملاحظة:', style: TextStyle(color: Colors.white)),
            DropdownButton<NoteType>(
              value: currentType,
              items: NoteType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(
                    _getNoteTypeText(type),
                    style: TextStyle(color: _getNoteColor(type)),
                  ),
                );
              }).toList(),
              onChanged: (value) {
                currentType = value!;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final updatedNote = note.copyWith(
                  note: controller.text.trim(),
                  type: currentType.name,
                );
                
                await _dbHelper.updateNote(updatedNote);
                _loadStudentNotes();
                Navigator.pop(context);
              }
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _showChangeDateDialog(NoteModel note, StudentModel student) {
    DateTime selectedDate = note.date;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('تغيير تاريخ الملاحظة', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('yyyy-MM-dd').format(selectedDate),
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (date != null) {
                      setState(() => selectedDate = date);
                    }
                  },
                  child: const Text('اختر تاريخ'),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () async {
              final updatedNote = note.copyWith(date: selectedDate);
              await _dbHelper.updateNote(updatedNote);
              _loadStudentNotes();
              Navigator.pop(context);
            },
            child: const Text('حفظ', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _deleteNote(NoteModel note) async {
    await _dbHelper.deleteNote(note.id!);
    _loadStudentNotes();
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentClass?.name ?? widget.classModel.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<ClassModel>(
            icon: const Icon(Icons.class_, color: Colors.white),
            itemBuilder: (context) {
              return _allClasses.map((classModel) {
                return PopupMenuItem<ClassModel>(
                  value: classModel,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: _currentClass?.id == classModel.id ? Colors.green : Colors.grey,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          classModel.name,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: (ClassModel selectedClass) {
              setState(() {
                _currentClass = selectedClass;
              });
              _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
            onPressed: _exportToPDF,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : Column(
              children: [
                // Note statistics
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber, width: 2.0),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'إحصائيات الملاحظات',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatItem('جيدة', Colors.green, _getNoteStatistics()[NoteType.good] ?? 0),
                          _buildStatItem('سيئة', Colors.red, _getNoteStatistics()[NoteType.bad] ?? 0),
                          _buildStatItem('عادية', Colors.white, _getNoteStatistics()[NoteType.normal] ?? 0),
                        ],
                      ),
                    ],
                  ),
                ),
                // Students list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      final student = _students[index];
                      final studentNotes = _studentNotes[student.id.toString()] ?? [];
                      
                      return Column(
                        children: [
                          // Student header
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    student.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => _showAddNoteOptions(student),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.black,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Notes list
                          if (studentNotes.isNotEmpty)
                            ...studentNotes.map((note) => _buildNoteCard(note, student)),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String label, Color color, int count) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color),
          ),
          child: Text(
            count.toString(),
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildNoteCard(NoteModel note, StudentModel student) {
    final noteType = _getNoteType(note);
    final noteColor = _getNoteColor(noteType);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: noteColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note.note,
                  style: TextStyle(
                    color: noteColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(note.date),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: noteColor, size: 20),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Text('تعديل', style: TextStyle(color: Colors.white)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('حذف', style: TextStyle(color: Colors.red)),
              ),
              const PopupMenuItem(
                value: 'change_date',
                child: Text('تغيير التاريخ', style: TextStyle(color: Colors.white)),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _showEditNoteDialog(note, student);
                  break;
                case 'delete':
                  _deleteNote(note);
                  break;
                case 'change_date':
                  _showChangeDateDialog(note, student);
                  break;
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _exportToPDF() async {
    // Implementation for PDF export
  }
}

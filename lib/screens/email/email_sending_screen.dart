import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/student_model.dart';
import '../../models/email_service.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';

class EmailSendingScreen extends StatefulWidget {
  final String? attachmentPath;
  final String? attachmentName;
  final String? defaultSubject;
  final String? defaultMessage;
  final List<int>? preselectedStudentIds;

  const EmailSendingScreen({
    Key? key,
    this.attachmentPath,
    this.attachmentName,
    this.defaultSubject,
    this.defaultMessage,
    this.preselectedStudentIds,
  }) : super(key: key);

  @override
  State<EmailSendingScreen> createState() => _EmailSendingScreenState();
}

class _EmailSendingScreenState extends State<EmailSendingScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _searchController = TextEditingController();
  
  List<StudentModel> _allStudents = [];
  List<StudentModel> _filteredStudents = [];
  Set<int> _selectedStudentIds = {};
  bool _isLoading = false;
  bool _isSending = false;
  String? _selectedClassId;
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    setState(() => _isLoading = true);
    
    try {
      // Load students
      _allStudents = await Provider.of<StudentProvider>(context, listen: false).getAllStudents();
      
      // Set preselected students if provided
      if (widget.preselectedStudentIds != null) {
        _selectedStudentIds = Set.from(widget.preselectedStudentIds!);
      }
      
      // Set default values
      if (widget.defaultSubject != null) {
        _subjectController.text = widget.defaultSubject!;
      }
      if (widget.defaultMessage != null) {
        _messageController.text = widget.defaultMessage!;
      }
      
      _filteredStudents = _allStudents;
    } catch (e) {
      _showErrorSnackBar('حدث خطأ أثناء تحميل البيانات: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _filterStudents(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredStudents = _allStudents;
      } else {
        _filteredStudents = _allStudents.where((student) {
          return student.name.toLowerCase().contains(query.toLowerCase()) ||
                 (student.studentId?.toLowerCase().contains(query.toLowerCase()) ?? false) ||
                 (student.email?.toLowerCase().contains(query.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  void _filterByClass(String? classId) {
    setState(() {
      _selectedClassId = classId;
      if (classId == null || classId == 'all') {
        _filteredStudents = _allStudents;
      } else {
        _filteredStudents = _allStudents.where((student) => student.classId.toString() == classId).toList();
      }
      _filterStudents(_searchController.text);
    });
  }

  void _toggleStudentSelection(int studentId) {
    setState(() {
      if (_selectedStudentIds.contains(studentId)) {
        _selectedStudentIds.remove(studentId);
      } else {
        _selectedStudentIds.add(studentId);
      }
      _updateSelectAllState();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      _selectAll = !_selectAll;
      if (_selectAll) {
        _selectedStudentIds = _filteredStudents
            .where((student) => student.hasEmail())
            .map((student) => student.id!)
            .toSet();
      } else {
        _selectedStudentIds.clear();
      }
    });
  }

  void _updateSelectAllState() {
    final emailStudents = _filteredStudents.where((student) => student.hasEmail()).toList();
    _selectAll = emailStudents.isNotEmpty && 
                emailStudents.every((student) => _selectedStudentIds.contains(student.id!));
  }

  List<StudentModel> get _selectedStudents {
    return _allStudents.where((student) => _selectedStudentIds.contains(student.id!)).toList();
  }

  Future<void> _sendEmails() async {
    if (_selectedStudents.isEmpty) {
      _showErrorSnackBar('الرجاء اختيار طالب واحد على الأقل');
      return;
    }

    if (_subjectController.text.trim().isEmpty) {
      _showErrorSnackBar('الرجاء إدخال الموضوع');
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      _showErrorSnackBar('الرجاء إدخال الرسالة');
      return;
    }

    if (widget.attachmentPath == null) {
      _showErrorSnackBar('لا يوجد ملف مرفق');
      return;
    }

    setState(() => _isSending = true);

    try {
      int successCount = 0;
      int failCount = 0;
      
      for (StudentModel student in _selectedStudents) {
        final emails = student.getNotificationEmailAddresses();
        
        if (emails.isEmpty) {
          failCount++;
          continue;
        }

        final success = await EmailService.sendEmailToMultipleRecipients(
          recipientEmails: emails,
          subject: _subjectController.text.trim(),
          message: _messageController.text.trim(),
          attachmentPath: widget.attachmentPath!,
          attachmentName: widget.attachmentName,
        );

        if (success) {
          successCount++;
        } else {
          failCount++;
        }

        // Small delay between emails
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (successCount > 0) {
        _showSuccessSnackBar('تم إرسال الإيميل بنجاح إلى $successCount طالب${failCount > 0 ? ' (فشل إرسال إلى $failCount)' : ''}');
        
        // Go back after successful sending
        if (failCount == 0) {
          Navigator.of(context).pop(true);
        }
      } else {
        _showErrorSnackBar('فشل إرسال جميع الإيميلات');
      }
    } catch (e) {
      _showErrorSnackBar('حدث خطأ أثناء الإرسال: $e');
    } finally {
      setState(() => _isSending = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D44),
        title: const Text(
          'إرسال إيميل',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: _isSending ? null : _sendEmails,
            child: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'إرسال',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildEmailContent(),
                _buildStudentSelection(),
              ],
            ),
    );
  }

  Widget _buildEmailContent() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D44),
        border: Border(bottom: BorderSide(color: Color(0xFF3D3D5C), width: 1)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _subjectController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'الموضوع',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            style: const TextStyle(color: Colors.white),
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'الرسالة',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
          ),
          if (widget.attachmentPath != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.attach_file, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.attachmentName ?? 'ملف مرفق',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentSelection() {
    return Expanded(
      child: Column(
        children: [
          _buildFilters(),
          _buildSelectionHeader(),
          Expanded(child: _buildStudentList()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Consumer<ClassProvider>(
            builder: (context, classProvider, child) {
              return DropdownButtonFormField<String>(
                value: _selectedClassId,
                decoration: const InputDecoration(
                  labelText: 'اختر الفصل',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.blue),
                  ),
                ),
                dropdownColor: const Color(0xFF2D2D44),
                style: const TextStyle(color: Colors.white),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('جميع الفصول')),
                  ...classProvider.classes.map((cls) => DropdownMenuItem(
                    value: cls.id.toString(),
                    child: Text(cls.name),
                  )),
                ],
                onChanged: _filterByClass,
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'البحث عن طالب',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue),
              ),
            ),
            onChanged: _filterStudents,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF2D2D44),
        border: Border(bottom: BorderSide(color: Color(0xFF3D3D5C), width: 1)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _selectAll,
            onChanged: (value) => _toggleSelectAll(),
            activeColor: Colors.blue,
          ),
          const Text(
            'تحديد الكل',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          Text(
            'المحددون: ${_selectedStudents.length}',
            style: const TextStyle(color: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentList() {
    final emailStudents = _filteredStudents.where((student) => student.hasEmail()).toList();
    
    if (emailStudents.isEmpty) {
      return const Center(
        child: Text(
          'لا يوجد طلاب لديهم إيميل',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: emailStudents.length,
      itemBuilder: (context, index) {
        final student = emailStudents[index];
        final isSelected = _selectedStudentIds.contains(student.id!);
        final emails = student.getNotificationEmailAddresses();
        
        return CheckboxListTile(
          value: isSelected,
          onChanged: (value) => _toggleStudentSelection(student.id!),
          activeColor: Colors.blue,
          title: Text(
            student.getEmailDisplayName(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (emails.isNotEmpty)
                Text(
                  emails.join(', '),
                  style: const TextStyle(color: Colors.blue, fontSize: 12),
                ),
              if (student.primaryGuardian?.name != null)
                Text(
                  'ولي الأمر: ${student.primaryGuardian!.name}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
            ],
          ),
          secondary: CircleAvatar(
            backgroundColor: isSelected ? Colors.blue : Colors.grey,
            child: Text(
              student.name.isNotEmpty ? student.name[0].toUpperCase() : 'S',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_picker_helper.dart';
import '../../database/database_helper.dart';

class AddStudentScreen extends StatefulWidget {
  final ClassModel? selectedClass;
  final StudentModel? student;

  const AddStudentScreen({
    super.key,
    this.selectedClass,
    this.student,
  });

  @override
  State<AddStudentScreen> createState() => _AddStudentScreenState();
}

class _AddStudentScreenState extends State<AddStudentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  
  // Primary Guardian Controllers
  final _primaryGuardianNameController = TextEditingController();
  final _primaryGuardianPhoneController = TextEditingController();
  final _primaryGuardianEmailController = TextEditingController();
  
  // Secondary Guardian Controllers
  final _secondaryGuardianNameController = TextEditingController();
  final _secondaryGuardianPhoneController = TextEditingController();
  final _secondaryGuardianEmailController = TextEditingController();
  
  int? _selectedClassId;
  DateTime? _birthDate;
  bool _isLoading = false;
  bool _hasPrimaryGuardian = false;
  bool _hasSecondaryGuardian = false;
  List<String> _primaryGuardianNotifications = [];
  List<String> _secondaryGuardianNotifications = [];
  List<String> _selectedNotificationMethods = [];
  
  // Photo related variables
  String? _photoPath;

  final DatabaseHelper _dbHelper = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _selectedClassId = widget.selectedClass?.id;
    
    if (widget.student != null) {
      final student = widget.student!;
      _nameController.text = student.name;
      _studentIdController.text = student.studentId ?? '';
      _emailController.text = student.email ?? '';
      _phoneController.text = student.phone ?? '';
      _locationController.text = student.location ?? '';
      _birthDate = student.birthDate;
      _photoPath = student.photoPath; // Load existing photo
      
      // للتعديل، استخدم فصل الطالب الحالي ولا تسمح بتغييره
      if (widget.student != null) {
        _selectedClassId = widget.student!.classId;
      }
      
      // Load guardian information
      if (student.primaryGuardian != null) {
        _hasPrimaryGuardian = true;
        _primaryGuardianNameController.text = student.primaryGuardian!.name;
        _primaryGuardianPhoneController.text = student.primaryGuardian!.phone ?? '';
        _primaryGuardianEmailController.text = student.primaryGuardian!.email ?? '';
        _primaryGuardianNotifications = List.from(student.primaryGuardian!.notificationMethods);
      }
      
      if (student.secondaryGuardian != null) {
        _hasSecondaryGuardian = true;
        _secondaryGuardianNameController.text = student.secondaryGuardian!.name;
        _secondaryGuardianPhoneController.text = student.secondaryGuardian!.phone ?? '';
        _secondaryGuardianEmailController.text = student.secondaryGuardian!.email ?? '';
        _secondaryGuardianNotifications = List.from(student.secondaryGuardian!.notificationMethods);
      }
    } else {
      // إضافة جديدة: توليد ID تلقائي وعرضه
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshAutoStudentId();
      });
    }
  }

  Future<void> _refreshAutoStudentId() async {
    final next = await _dbHelper.getNextStudentSerial();
    if (!mounted) return;
    setState(() {
      _studentIdController.text = next.toString();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _primaryGuardianNameController.dispose();
    _primaryGuardianPhoneController.dispose();
    _primaryGuardianEmailController.dispose();
    _secondaryGuardianNameController.dispose();
    _secondaryGuardianPhoneController.dispose();
    _secondaryGuardianEmailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.student != null;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'تعديل بيانات الطالب' : 'إضافة طالب جديد',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBasicInfoSection(),
              const SizedBox(height: 24),
              _buildPrimaryGuardianSection(),
              const SizedBox(height: 24),
              _buildSecondaryGuardianSection(),
              const SizedBox(height: 32),
              _buildSaveButton(isEditing),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'المعلومات الأساسية',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            enabled: true,
            decoration: const InputDecoration(
              labelText: 'اسم الطالب',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.person, color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
              fillColor: Color(0xFF2A2A2A),
              filled: true,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'يرجى إدخال اسم الطالب';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Photo Section
          Container(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'صورة الطالب',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey.shade700,
                        backgroundImage: _photoPath != null
                            ? FileImage(File(_photoPath!)) as ImageProvider
                            : null,
                        child: _photoPath == null
                            ? const Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.grey,
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'اضغط لإضافة أو تغيير الصورة',
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _studentIdController,
            style: const TextStyle(color: Colors.white),
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'ID الطالب',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.badge, color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
              fillColor: Color(0xFF2A2A2A),
              filled: true,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today, color: Colors.white),
            title: Text(
              _birthDate != null 
                  ? 'تاريخ الميلاد: ${DateFormat('dd/MM/yyyy').format(_birthDate!)}'
                  : 'تاريخ الميلاد',
              style: const TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _birthDate ?? DateTime.now().subtract(const Duration(days: 6570)),
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
              );
              if (date != null) {
                setState(() {
                  _birthDate = date;
                });
              }
            },
          ),
          // إظهار الفصل فقط للإضافة، وليس للتعديل
          if (widget.student == null) ...[
            const SizedBox(height: 16),
            Consumer<ClassProvider>(
              builder: (context, classProvider, child) {
                return DropdownButtonFormField<int>(
                  value: _selectedClassId,
                  style: const TextStyle(color: Colors.white),
                  dropdownColor: const Color(0xFF1A1A1A),
                  decoration: const InputDecoration(
                    labelText: 'الفصل',
                    labelStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.class_, color: Colors.white),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.primaryColor),
                    ),
                  ),
                  items: classProvider.classes.map((classModel) {
                    return DropdownMenuItem<int>(
                      value: classModel.id,
                      child: Text('${classModel.name} - ${classModel.subject}'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedClassId = value;
                    });
                    _refreshAutoStudentId();
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'يرجى اختيار الفصل';
                    }
                    return null;
                  },
                );
              },
            ),
          ],
          // عرض الفصل الحالي للتعديل (للقراءة فقط)
          if (widget.student != null) ...[
            const SizedBox(height: 16),
            Consumer<ClassProvider>(
              builder: (context, classProvider, child) {
                final currentClass = classProvider.getClassById(widget.student!.classId);
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.class_, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        'الفصل: ${currentClass?.name ?? 'فصل غير محدد'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            style: const TextStyle(color: Colors.white),
            enabled: true,
            decoration: const InputDecoration(
              labelText: 'الإيميل (اختياري)',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.email, color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
              fillColor: Color(0xFF2A2A2A),
              filled: true,
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            style: const TextStyle(color: Colors.white),
            enabled: true,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف (اختياري)',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.phone, color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
              fillColor: Color(0xFF2A2A2A),
              filled: true,
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _locationController,
            style: const TextStyle(color: Colors.white),
            enabled: true,
            decoration: const InputDecoration(
              labelText: 'موقع الطالب (اختياري)',
              labelStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.location_on_outlined, color: Colors.white),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: AppTheme.primaryColor),
              ),
              fillColor: Color(0xFF2A2A2A),
              filled: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(bool isEditing) {
    return Container(
      width: double.infinity,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _saveStudent(isEditing),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(
                color: Colors.black,
                strokeWidth: 2,
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isEditing ? Icons.update : Icons.save,
                    color: Colors.black,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? 'تحديث البيانات' : 'حفظ الطالب',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _saveStudent(bool isEditing) async {
    if (!_formKey.currentState!.validate() || _selectedClassId == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      
      // Create guardian objects if needed
      GuardianModel? primaryGuardian;
      if (_hasPrimaryGuardian && _primaryGuardianNameController.text.trim().isNotEmpty) {
        primaryGuardian = GuardianModel(
          name: _primaryGuardianNameController.text.trim(),
          phone: _primaryGuardianPhoneController.text.trim().isEmpty 
              ? null 
              : _primaryGuardianPhoneController.text.trim(),
          email: _primaryGuardianEmailController.text.trim().isEmpty 
              ? null 
              : _primaryGuardianEmailController.text.trim(),
          notificationMethods: [],
        );
      }

      GuardianModel? secondaryGuardian;
      if (_hasSecondaryGuardian && _secondaryGuardianNameController.text.trim().isNotEmpty) {
        secondaryGuardian = GuardianModel(
          name: _secondaryGuardianNameController.text.trim(),
          phone: _secondaryGuardianPhoneController.text.trim().isEmpty 
              ? null 
              : _secondaryGuardianPhoneController.text.trim(),
          email: _secondaryGuardianEmailController.text.trim().isEmpty 
              ? null 
              : _secondaryGuardianEmailController.text.trim(),
          notificationMethods: [],
        );
      }

      bool success;
      if (isEditing) {
        // للتعديل، استخدم الفصل الحالي للطالب
        final currentClassId = widget.student!.classId;
        success = await studentProvider.updateStudent(
          widget.student!.copyWith(
            name: _nameController.text.trim(),
            studentId: _studentIdController.text.trim().isEmpty 
                ? null 
                : _studentIdController.text.trim(),
            classId: currentClassId, // لا تغيير الفصل عند التعديل
            email: _emailController.text.trim().isEmpty 
                ? null 
                : _emailController.text.trim(),
            phone: _phoneController.text.trim().isEmpty 
                ? null 
                : _phoneController.text.trim(),
            location: _locationController.text.trim().isEmpty 
                ? null 
                : _locationController.text.trim(),
            birthDate: _birthDate,
            photoPath: _photoPath, // Add photo path
            primaryGuardian: primaryGuardian,
            secondaryGuardian: secondaryGuardian,
            updatedAt: DateTime.now(),
          ),
        );
      } else {
        success = await studentProvider.addStudent(
          classId: _selectedClassId!,
          name: _nameController.text.trim(),
          studentId: _studentIdController.text.trim().isEmpty 
              ? null 
              : _studentIdController.text.trim(),
          email: _emailController.text.trim().isEmpty 
              ? null 
              : _emailController.text.trim(),
          phone: _phoneController.text.trim().isEmpty 
              ? null 
              : _phoneController.text.trim(),
          location: _locationController.text.trim().isEmpty 
              ? null 
              : _locationController.text.trim(),
          birthDate: _birthDate,
          photoPath: _photoPath, // Add photo path
          primaryGuardian: primaryGuardian,
          secondaryGuardian: secondaryGuardian,
        );
      }

      if (success && mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEditing ? 'تم تحديث بيانات الطالب بنجاح' : 'تم إضافة الطالب بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء حفظ البيانات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildPrimaryGuardianSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ولي الأمر الأول',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: _hasPrimaryGuardian,
                onChanged: (value) {
                  setState(() {
                    _hasPrimaryGuardian = value;
                    if (!value) {
                      _primaryGuardianNameController.clear();
                      _primaryGuardianPhoneController.clear();
                      _primaryGuardianEmailController.clear();
                    }
                  });
                },
                activeColor: const Color(0xFFFFD700),
                activeTrackColor: const Color(0xFFFFD700).withOpacity(0.3),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
              ),
            ],
          ),
          if (_hasPrimaryGuardian) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _primaryGuardianNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم ولي الأمر',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.person_outline, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              validator: _hasPrimaryGuardian ? (value) {
                if (value == null || value.isEmpty) {
                  return 'يرجى إدخال اسم ولي الأمر';
                }
                return null;
              } : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _primaryGuardianPhoneController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.phone, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _primaryGuardianEmailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الإيميل',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.email, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecondaryGuardianSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade700, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ولي الأمر الثاني',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: _hasSecondaryGuardian,
                onChanged: (value) {
                  setState(() {
                    _hasSecondaryGuardian = value;
                    if (!value) {
                      _secondaryGuardianNameController.clear();
                      _secondaryGuardianPhoneController.clear();
                      _secondaryGuardianEmailController.clear();
                    }
                  });
                },
                activeColor: const Color(0xFFFFD700),
                activeTrackColor: const Color(0xFFFFD700).withOpacity(0.3),
                inactiveThumbColor: Colors.grey,
                inactiveTrackColor: Colors.grey.withOpacity(0.3),
              ),
            ],
          ),
          if (_hasSecondaryGuardian) ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _secondaryGuardianNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'اسم ولي الأمر الثاني',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.person_outline, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              validator: _hasSecondaryGuardian ? (value) {
                if (value == null || value.isEmpty) {
                  return 'يرجى إدخال اسم ولي الأمر الثاني';
                }
                return null;
              } : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secondaryGuardianPhoneController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.phone, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _secondaryGuardianEmailController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'الإيميل',
                labelStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.email, color: Colors.white),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppTheme.primaryColor),
                ),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ],
      ),
    );
  }


  Future<void> _pickImage() async {
    try {
      final imageFile = await ImagePickerHelper.pickImage(context);
      if (imageFile != null) {
        setState(() {
          _photoPath = imageFile;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اختيار الصورة: $e')),
        );
      }
    }
  }


}

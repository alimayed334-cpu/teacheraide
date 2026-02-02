import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import '../../theme/app_theme.dart';
import '../../database/database_helper.dart';
import '../../utils/image_picker_helper.dart';
import '../../services/unified_student_status_service.dart';
import '../../widgets/student_status_indicator.dart';
import 'add_student_screen.dart';
import 'student_details_screen.dart';
import 'student_assignments_screen.dart';
import 'student_attendance_screen.dart';
import '../messaging/messaging_screen.dart';

class StudentsScreen extends StatefulWidget {
  final ClassModel? classModel;
  
  const StudentsScreen({super.key, this.classModel});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  ClassModel? _selectedClass;

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.classModel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudents();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadStudents() {
    if (_selectedClass != null) {
      Provider.of<StudentProvider>(context, listen: false)
          .loadStudentsByClass(_selectedClass!.id!);
    } else {
      Provider.of<StudentProvider>(context, listen: false).loadAllStudents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedClass != null 
            ? 'طلاب ${_selectedClass!.name}' 
            : 'جميع الطلاب',
            style: const TextStyle(),),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showClassFilter(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط البحث والفلترة
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'البحث في الطلاب...',
                    prefixIcon: Icon(Icons.search),
                    hintStyle: TextStyle(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
                if (_selectedClass != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.class_, size: 16, color: AppTheme.primaryColor),
                        const SizedBox(width: 4),
                        Text(
                          _selectedClass!.name,
                          style: GoogleFonts.cairo(
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedClass = null;
                            });
                            _loadStudents();
                          },
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // قائمة الطلاب
          Expanded(
            child: Consumer<StudentProvider>(
              builder: (context, studentProvider, child) {
                if (studentProvider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (studentProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: AppTheme.errorColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          studentProvider.error!,
                          style: GoogleFonts.cairo(
                            color: AppTheme.errorColor,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadStudents,
                          child: Text(
                            'إعادة المحاولة',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final students = _searchQuery.isEmpty
                    ? studentProvider.students
                    : studentProvider.searchStudents(_searchQuery);

                if (students.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.people,
                          size: 64,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا يوجد طلاب',
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _selectedClass != null 
                              ? 'لا يوجد طلاب في هذا الفصل'
                              : 'ابدأ بإضافة طلاب جدد',
                          style: GoogleFonts.cairo(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => _showAddStudentDialog(context),
                          icon: const Icon(Icons.add),
                          label: Text(
                            'إضافة طالب',
                            style: GoogleFonts.cairo(),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final student = students[index];
                    return _StudentCard(
                      student: student,
                      onTap: () => _showStudentDetails(context, student),
                      onEdit: () => _showEditStudentDialog(context, student),
                      onDelete: () => _showDeleteConfirmation(context, student),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddStudentDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showClassFilter(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('اختر الفصل', style: GoogleFonts.cairo()),
        content: Consumer<ClassProvider>(
          builder: (context, classProvider, child) {
            if (classProvider.classes.isEmpty) {
              return Text('لا توجد فصول متاحة', style: GoogleFonts.cairo());
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<ClassModel?>(
                  title: Text('جميع الفصول', style: GoogleFonts.cairo()),
                  value: null,
                  selected: _selectedClass == null,
                  toggleable: true,
                ),
                ...classProvider.classes.map((classModel) => RadioListTile<ClassModel?>(
                  title: Text(classModel.name, style: GoogleFonts.cairo()),
                  subtitle: Text(classModel.subject, style: GoogleFonts.cairo()),
                  value: classModel,
                  selected: _selectedClass == classModel,
                  toggleable: true,
                )),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  void _showAddStudentDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddStudentScreen(
          selectedClass: _selectedClass,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadStudents();
      }
    });
  }

  void _showEditStudentDialog(BuildContext context, StudentModel student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddStudentScreen(
          student: student,
          selectedClass: _selectedClass,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadStudents();
      }
    });
  }

  void _showStudentDetails(BuildContext context, StudentModel student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentDetailsScreen(student: student),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, StudentModel student) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد الحذف', style: GoogleFonts.cairo()),
        content: Text('هل أنت متأكد من حذف الطالب "${student.name}"؟', style: GoogleFonts.cairo()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final studentProvider = Provider.of<StudentProvider>(context, listen: false);
              final studentId = student.id;
              if (studentId == null) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تعذر حذف الطالب: معرف غير صالح', style: GoogleFonts.cairo())),
                );
                return;
              }
              final success = await studentProvider.deleteStudent(studentId);
              if (!context.mounted) return;
              if (success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('تم حذف الطالب بنجاح', style: GoogleFonts.cairo())),
                );
              } else {
                final msg = studentProvider.error ?? 'حدث خطأ في حذف الطلاب';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(msg, style: GoogleFonts.cairo())),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: Text('حذف', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}

class _StudentCard extends StatefulWidget {
  final StudentModel student;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StudentCard({
    required this.student,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isHovered = false;
  bool _isExcellent = false;
  bool _isAtRisk = false;

  @override
  void initState() {
    super.initState();
    _checkStudentStatus();
  }

  /// تحديث صورة الطالب في قاعدة البيانات
  Future<void> _updateStudentPhoto(int studentId, String? photoPath) async {
    try {
      final dbHelper = DatabaseHelper();
      
      // جلب بيانات الطالب الحالية
      final students = await dbHelper.getStudentsByClass(widget.student.classId);
      final currentStudent = students.firstWhere((s) => s.id == studentId);
      
      // تحديث الصورة مع حذف الصورة القديمة إذا وجدت
      if (currentStudent.photoPath != null && photoPath == null) {
        await ImagePickerHelper.deleteLocalImage(currentStudent.photoPath);
      }
      
      // تحديث الطالب بالصورة الجديدة
      final updatedStudent = currentStudent.copyWith(photoPath: photoPath);
      await dbHelper.updateStudent(updatedStudent);
      
      // تحديث الواجهة
      if (mounted) {
        setState(() {
          // تحديث الحالة المحلية للطالب
          widget.student.copyWith(photoPath: photoPath);
        });
        
        // إعادة تحميل قائمة الطلاب
        _loadStudents();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(photoPath != null ? 'تم تحديث صورة الطالب بنجاح' : 'تم حذف الصورة بنجاح'),
            backgroundColor: photoPath != null ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تحديث الصورة: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// معالجة إضافة/تغيير الصورة
  Future<void> _handlePhotoAction() async {
    if (widget.student.photoPath != null) {
      // عرض الخيارات: تغيير الصورة أو عرض الصورة
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('خيارات الصورة', style: GoogleFonts.cairo()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera, color: Colors.blue),
                title: Text('تغيير الصورة', style: GoogleFonts.cairo()),
                onTap: () async {
                  Navigator.pop(context);
                  final String? imagePath = await ImagePickerHelper.pickImage(context);
                  if (imagePath != null) {
                    await _updateStudentPhoto(widget.student.id!, imagePath);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.zoom_in, color: Colors.green),
                title: Text('عرض الصورة', style: GoogleFonts.cairo()),
                onTap: () {
                  Navigator.pop(context);
                  showImageViewer(context, widget.student.photoPath!);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text('حذف الصورة', style: GoogleFonts.cairo()),
                onTap: () async {
                  Navigator.pop(context);
                  await _updateStudentPhoto(widget.student.id!, null);
                },
              ),
            ],
          ),
        ),
      );
    } else {
      // اختيار صورة جديدة مباشرة
      final String? imagePath = await ImagePickerHelper.pickImage(context);
      if (imagePath != null) {
        await _updateStudentPhoto(widget.student.id!, imagePath);
      }
    }
  }

  /// إعادة تحميل قائمة الطلاب
  void _loadStudents() {
    if (widget.student.classId != 0) {
      Provider.of<StudentProvider>(context, listen: false)
          .loadStudentsByClass(widget.student.classId);
    } else {
      Provider.of<StudentProvider>(context, listen: false).loadAllStudents();
    }
  }

  Future<void> _checkStudentStatus() async {
    try {
      final classId = (widget.student.classId != 0) ? widget.student.classId : null;
      final status = await UnifiedStudentStatusService.checkStudentStatus(
        widget.student,
        classId: classId,
      );

      if (!mounted) return;
      setState(() {
        _isExcellent = status['isExcellent'] ?? false;
        _isAtRisk = status['isAtRisk'] ?? false;
      });
    } catch (e) {
      print('Error checking student status: $e');
    }
  }

  void _navigateToAssignments(BuildContext context, StudentModel student) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentAssignmentsScreen(
          student: student,
        ),
      ),
    );
  }

  void _navigateToAttendance(BuildContext context, StudentModel student) {
    final classModel = Provider.of<ClassProvider>(context, listen: false)
        .getClassById(student.classId);
    if (classModel != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StudentAttendanceScreen(
            student: student,
            classModel: classModel,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    print('Building StudentCard for ${widget.student.name}');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() {
            _isHovered = true;
          });
        },
        onExit: (_) {
          setState(() {
            _isHovered = false;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: _isHovered ? Colors.amber.withValues(alpha: 0.05) : Colors.transparent,
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(16),
            splashColor: Colors.amber.withValues(alpha: 0.3),
            highlightColor: Colors.amber.withValues(alpha: 0.1),
            child: Padding(
              // تقريب الدائرة والاسم قدر الإمكان من الطرف الأيسر
              padding: const EdgeInsets.only(left: 0, right: 4, top: 8, bottom: 8),
              child: Row(
                children: [
                  // الصورة + الاسم في الطرف الأيسر وتأخذ أكبر مساحة ممكنة
                  Expanded(
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            if (widget.student.photoPath != null) {
                              // عرض الصورة المكبرة
                              showImageViewer(context, widget.student.photoPath!);
                            } else {
                              // اختيار صورة جديدة
                              final String? imagePath = await ImagePickerHelper.pickImage(context);
                              if (imagePath != null) {
                                // تحديث بيانات الطالب مع الصورة الجديدة
                                await _updateStudentPhoto(widget.student.id!, imagePath);
                              }
                            }
                          },
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: widget.student.photoPath != null 
                                    ? Colors.transparent
                                    : AppTheme.primaryColor.withValues(alpha: 0.1),
                                backgroundImage: widget.student.photoPath != null
                                    ? FileImage(File(widget.student.photoPath!)) as ImageProvider
                                    : widget.student.photo != null
                                        ? NetworkImage(widget.student.photo!)
                                        : null,
                                child: widget.student.photoPath == null && widget.student.photo == null
                                    ? Text(
                                        widget.student.name.isNotEmpty
                                            ? widget.student.name.substring(0, 1).toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryColor,
                                        ),
                                      )
                                    : null,
                              ),
                              // أيقونة الكاميرا عند عدم وجود صورة
                              if (widget.student.photoPath == null && widget.student.photo == null)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              // أيقونة تكبير عند وجود صورة
                              if (widget.student.photoPath != null || widget.student.photo != null)
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.zoom_in,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // اسم الطالب
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // اسم الطالب في سطر واحد
                              Row(
                                children: [
                                  StudentStatusIndicator(student: widget.student),
                                  const SizedBox(width: 8),
                                  // اسم الطالب
                                  Expanded(
                                    child: Text(
                                      widget.student.name,
                                      style: GoogleFonts.cairo(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'الرقم: ${widget.student.studentId ?? 'غير محدد'}',
                                style: GoogleFonts.cairo(
                                  color: AppTheme.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (widget.student.email != null && widget.student.email!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.student.email!,
                                  style: GoogleFonts.cairo(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // أيقونة الحضور
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.check_circle_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () {
                        _navigateToAttendance(context, widget.student);
                      },
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // أيقونة الواجبات
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.assignment,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () {
                        _navigateToAssignments(context, widget.student);
                      },
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'view',
                        child: Row(
                          children: [
                            const Icon(Icons.visibility, size: 18),
                            const SizedBox(width: 6),
                            Text('عرض', style: GoogleFonts.cairo()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'photo',
                        child: Row(
                          children: [
                            Icon(
                              widget.student.photoPath != null ? Icons.photo_camera : Icons.add_photo_alternate,
                              size: 18,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.student.photoPath != null ? 'تغيير الصورة' : 'إضافة صورة',
                              style: GoogleFonts.cairo(),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'messaging',
                        child: Row(
                          children: [
                            const Icon(Icons.message, size: 18, color: Colors.amber),
                            const SizedBox(width: 6),
                            Text('المراسلة', style: GoogleFonts.cairo()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            const Icon(Icons.edit, size: 18),
                            const SizedBox(width: 6),
                            Text('تعديل', style: GoogleFonts.cairo()),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(Icons.delete, size: 18),
                            const SizedBox(width: 6),
                            Text('حذف', style: GoogleFonts.cairo()),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'view':
                          widget.onTap();
                          break;
                        case 'photo':
                          _handlePhotoAction();
                          break;
                        case 'messaging':
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MessagingScreen(),
                            ),
                          );
                          break;
                        case 'edit':
                          widget.onEdit();
                          break;
                        case 'delete':
                          widget.onDelete();
                          break;
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StudentDetailsSheet extends StatelessWidget {
  final StudentModel student;
  final ScrollController scrollController;

  const _StudentDetailsSheet({
    required this.student,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
                backgroundImage: student.photo != null ? NetworkImage(student.photo!) : null,
                child: student.photo == null
                    ? Text(
                        student.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryColor,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      student.name,
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'الرقم الجامعي: ${student.studentId}',
                      style: GoogleFonts.cairo(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                _DetailSection(
                  title: 'معلومات الاتصال',
                  children: [
                    if (student.email != null)
                      _DetailItem(
                        icon: Icons.email,
                        label: 'البريد الإلكتروني',
                        value: student.email!,
                      ),
                    if (student.phone != null)
                      _DetailItem(
                        icon: Icons.phone,
                        label: 'رقم الهاتف',
                        value: student.phone!,
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _DetailSection(
                  title: 'المعلومات الأكاديمية',
                  children: [
                    const _DetailItem(
                      icon: Icons.class_,
                      label: 'الفصل',
                      value: 'غير محدد', // TODO: جلب اسم الفصل
                    ),
                    _DetailItem(
                      icon: Icons.calendar_today,
                      label: 'تاريخ التسجيل',
                      value: '${student.createdAt.day}/${student.createdAt.month}/${student.createdAt.year}',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const _DetailSection(
                  title: 'الإجراءات',
                  children: [
                    _ActionItem(
                      icon: Icons.assessment,
                      label: 'عرض سجل الدرجات',
                      color: AppTheme.primaryColor,
                    ),
                    _ActionItem(
                      icon: Icons.how_to_reg,
                      label: 'سجل الحضور والغياب',
                      color: AppTheme.successColor,
                    ),
                    _ActionItem(
                      icon: Icons.analytics,
                      label: 'تقرير أداء الطالب',
                      color: AppTheme.secondaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.cairo(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _DetailItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(width: 12),
          Text(
            '$label:',
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.cairo(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(label, style: GoogleFonts.cairo()),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            // TODO: تنفيذ الإجراءات
            Navigator.pop(context);
          },
        ),
      ),
    );
  }
}

class _AddEditStudentDialog extends StatefulWidget {
  final StudentModel? student;
  final ClassModel? selectedClass;
  final VoidCallback onSave;

  const _AddEditStudentDialog({
    this.student,
    this.selectedClass,
    required this.onSave,
  });

  @override
  State<_AddEditStudentDialog> createState() => _AddEditStudentDialogState();
}

class _AddEditStudentDialogState extends State<_AddEditStudentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _studentIdController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _photoController;
  ClassModel? _selectedClass;

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.selectedClass;
    _nameController = TextEditingController(text: widget.student?.name ?? '');
    _studentIdController = TextEditingController(text: widget.student?.studentId ?? '');
    _emailController = TextEditingController(text: widget.student?.email ?? '');
    _phoneController = TextEditingController(text: widget.student?.phone ?? '');
    _photoController = TextEditingController(text: widget.student?.photo ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.student != null;

    return AlertDialog(
      title: Text(isEditing ? 'تعديل بيانات الطالب' : 'إضافة طالب جديد'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم الطالب',
                    hintText: 'أدخل اسم الطالب الكامل',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال اسم الطالب';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _studentIdController,
                  decoration: const InputDecoration(
                    labelText: 'الرقم الجامعي',
                    hintText: 'أدخل الرقم الجامعي أو الكود',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'يرجى إدخال الرقم الجامعي';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Consumer<ClassProvider>(
                  builder: (context, classProvider, child) {
                    if (classProvider.classes.isEmpty) {
                      return const Text(
                        'لا توجد فصول متاحة. يرجى إضافة فصل أولاً.',
                        style: TextStyle(color: AppTheme.errorColor),
                      );
                    }

                    return DropdownButtonFormField<ClassModel>(
                      initialValue: _selectedClass,
                      decoration: const InputDecoration(
                        labelText: 'الفصل',
                        hintText: 'اختر الفصل',
                      ),
                      items: classProvider.classes.map((classModel) {
                        return DropdownMenuItem(
                          value: classModel,
                          child: Text('${classModel.name} - ${classModel.subject}'),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedClass = value;
                        });
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'البريد الإلكتروني (اختياري)',
                    hintText: 'أدخل البريد الإلكتروني',
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف (اختياري)',
                    hintText: 'أدخل رقم الهاتف',
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _photoController,
                  decoration: const InputDecoration(
                    labelText: 'رابط الصورة (اختياري)',
                    hintText: 'أدخل رابط صورة الطالب',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('إلغاء', style: GoogleFonts.cairo()),
        ),
        Consumer<StudentProvider>(
          builder: (context, studentProvider, child) {
            return ElevatedButton(
              onPressed: studentProvider.isLoading ? null : () async {
                if (_formKey.currentState!.validate() && _selectedClass != null) {
                  bool success;
                  
                  if (isEditing) {
                    success = await studentProvider.updateStudent(
                      widget.student!.copyWith(
                        name: _nameController.text.trim(),
                        studentId: _studentIdController.text.trim(),
                        classId: _selectedClass!.id!,
                        email: _emailController.text.trim().isEmpty 
                            ? null 
                            : _emailController.text.trim(),
                        phone: _phoneController.text.trim().isEmpty 
                            ? null 
                            : _phoneController.text.trim(),
                        photo: _photoController.text.trim().isEmpty 
                            ? null 
                            : _photoController.text.trim(),
                      ),
                    );
                  } else {
                    success = await studentProvider.addStudent(
                      classId: _selectedClass!.id!,
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
                      photo: _photoController.text.trim().isEmpty 
                          ? null 
                          : _photoController.text.trim(),
                    );
                  }

                  if (success && context.mounted) {
                    Navigator.pop(context);
                    widget.onSave();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEditing ? 'تم تحديث بيانات الطالب بنجاح' : 'تم إضافة الطالب بنجاح'),
                      ),
                    );
                  }
                }
              },
              child: studentProvider.isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEditing ? 'تحديث' : 'إضافة'),
            );
          },
        ),
      ],
    );
  }
}

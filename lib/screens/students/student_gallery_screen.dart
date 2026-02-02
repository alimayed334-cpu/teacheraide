import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import '../../models/student_model.dart';
import '../../models/class_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/class_provider.dart';
import 'student_quiz_screen.dart';
import 'student_assignments_screen.dart';

class StudentGalleryScreen extends StatefulWidget {
  final int classId;

  const StudentGalleryScreen({
    super.key,
    required this.classId,
  });

  @override
  State<StudentGalleryScreen> createState() => _StudentGalleryScreenState();
}

class _StudentGalleryScreenState extends State<StudentGalleryScreen> {
  List<StudentModel> students = [];
  bool isLoading = true;
  ClassModel? currentClass;

  static const Color _bgGray = Color(0xFF2D2D2D);
  static const Color _panelBlack = Color(0xFF0D0D0D);
  static const Color _dividerGray = Color(0xFF404040);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadClassAndStudents();
      }
    });
  }

  Future<void> _loadClassAndStudents() async {
    try {
      final classProvider = Provider.of<ClassProvider>(context, listen: false);
      currentClass = classProvider.getClassById(widget.classId);
      
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.loadStudentsByClass(widget.classId);
      setState(() {
        students = studentProvider.students;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _panelBlack,
        foregroundColor: Colors.white,
        title: const Text('معرض الصور'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StudentQuizScreen(classId: widget.classId),
                ),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.yellow),
            child: const Text('اختبار'),
          ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.yellow,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: GestureDetector(
                    onTap: () => _showClassSelectionDialog(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentClass?.name ?? 'Class ${widget.classId}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_drop_down,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1, thickness: 1, color: _dividerGray),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: students.length,
                      itemBuilder: (context, index) {
                        final student = students[index];
                        return _buildStudentItem(student);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildStudentItem(StudentModel student) {
    final String? assetPhotoPath = student.photo is String ? student.photo as String : null;
    final ImageProvider<Object>? avatarImage = student.photoPath != null
        ? FileImage(File(student.photoPath!)) as ImageProvider<Object>
        : (assetPhotoPath != null
            ? AssetImage(assetPhotoPath) as ImageProvider<Object>
            : null);

    return Container(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 72,
            backgroundImage: avatarImage,
            backgroundColor: _panelBlack,
            child: avatarImage == null
                ? const Icon(Icons.person, size: 54, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              student.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClassSelectionDialog() {
    final classProvider = Provider.of<ClassProvider>(context, listen: false);
    final classes = classProvider.classes;
    
    if (classes.isEmpty) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: _panelBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxHeight: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'اختر الفصل',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final classItem = classes[index];
                      final isSelected = classItem.id == widget.classId;
                      
                      return InkWell(
                        onTap: () {
                          Navigator.pop(context);
                          if (classItem.id != widget.classId) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (context) => StudentGalleryScreen(
                                  classId: classItem.id!,
                                ),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected 
                                ? Colors.yellow.withOpacity(0.2)
                                : _bgGray,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: Colors.yellow, width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      classItem.name,
                                      style: TextStyle(
                                        color: isSelected 
                                            ? Colors.yellow
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${classItem.subject} - ${classItem.year}',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.yellow,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('إلغاء'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

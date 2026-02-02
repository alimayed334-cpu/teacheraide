import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/student_model.dart';
import '../../providers/student_provider.dart';

class StudentQuizScreen extends StatefulWidget {
  final int classId;

  const StudentQuizScreen({
    super.key,
    required this.classId,
  });

  @override
  State<StudentQuizScreen> createState() => _StudentQuizScreenState();
}

class _StudentQuizScreenState extends State<StudentQuizScreen> {
  List<StudentModel> _students = <StudentModel>[];
  bool _isLoading = true;

  int _currentIndex = 0;
  bool _isNameRevealed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadStudents();
      }
    });
  }

  Future<void> _loadStudents() async {
    try {
      final studentProvider = Provider.of<StudentProvider>(context, listen: false);
      await studentProvider.loadStudentsByClass(widget.classId);

      if (!mounted) return;
      setState(() {
        _students = studentProvider.students;
        _isLoading = false;
        _currentIndex = 0;
        _isNameRevealed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _revealName() {
    setState(() {
      _isNameRevealed = true;
    });
  }

  void _nextStudent() {
    if (_currentIndex >= _students.length) return;

    setState(() {
      _currentIndex++;
      _isNameRevealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isFinished = !_isLoading && (_students.isEmpty || _currentIndex >= _students.length);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('QUIZ'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.yellow,
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: isFinished
                    ? const Text(
                        'انتهت الصور',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      )
                    : _buildQuizContent(context),
              ),
            ),
    );
  }

  Widget _buildQuizContent(BuildContext context) {
    final student = _students[_currentIndex];

    final String? assetPhotoPath = student.photo is String ? student.photo as String : null;
    final ImageProvider<Object>? avatarImage = student.photoPath != null
        ? FileImage(File(student.photoPath!)) as ImageProvider<Object>
        : (assetPhotoPath != null
            ? AssetImage(assetPhotoPath) as ImageProvider<Object>
            : null);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 90,
          backgroundImage: avatarImage,
          backgroundColor: const Color(0xFF2D2D2D),
          child: avatarImage == null
              ? const Icon(Icons.person, size: 90, color: Colors.white)
              : null,
        ),
        const SizedBox(height: 16),
        if (_isNameRevealed) ...[
          Text(
            student.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          const SizedBox(height: 30),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _revealName,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
              ),
              child: const Text('كشف الاسم'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _nextStudent,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellow,
                foregroundColor: Colors.black,
              ),
              child: const Text('التالي'),
            ),
          ],
        ),
      ],
    );
  }
}

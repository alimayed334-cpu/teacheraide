import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student_model.dart';
import '../database/database_helper.dart';
import '../services/unified_student_status_service.dart';
import '../../models/grade_model.dart';
import '../../models/exam_model.dart';
import '../../models/attendance_model.dart';
import '../../providers/student_provider.dart';
import '../../providers/grade_provider.dart';

class StudentStatusIndicator extends StatelessWidget {
  final StudentModel student;

  const StudentStatusIndicator({Key? key, required this.student}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer2<StudentProvider, GradeProvider>(
      builder: (context, studentProvider, gradeProvider, child) {
        // نستخدم عدّادات التحديث لإجبار FutureBuilder على إعادة الحساب عند تغيير البيانات
        return FutureBuilder<Map<String, bool>>(
          key: ValueKey('${studentProvider.updateCounter}_${gradeProvider.updateCounter}'),
          future: _checkStudentStatus(),
          builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(width: 20, height: 20);
        }
        
        final isExcellent = snapshot.data?['isExcellent'] ?? false;
        final isAtRisk = snapshot.data?['isAtRisk'] ?? false;

        if (!isExcellent && !isAtRisk) {
          return const SizedBox(width: 20, height: 20);
        }

        final children = <Widget>[];
        if (isExcellent) {
          // نجمة صفراء مصغرة مع تأثيرات بصرية
          children.add(
            Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.yellow.withOpacity(0.15),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.yellow.withOpacity(0.3),
                    blurRadius: 1,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.star,
                color: Colors.yellow,
                size: 13,
                shadows: [
                  Shadow(
                    color: Colors.orange,
                    blurRadius: 1,
                    offset: Offset(0.5, 0.5),
                  ),
                ],
              ),
            ),
          );
        }

        if (isAtRisk) {
          if (children.isNotEmpty) {
            children.add(const SizedBox(width: 2));
          }
          // نقطة حمراء مصغرة مع تأثيرات بصرية
          children.add(
            Container(
              width: 6,
              height: 6,
              margin: EdgeInsets.zero,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.4),
                    blurRadius: 2,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
            ),
          );
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: children,
        );
          },
        );
      },
    );
  }

  Future<Map<String, bool>> _checkStudentStatus() async {
    // استخدام الخدمة الموحدة فقط
    final classId = (student.classId != 0) ? student.classId : null;
    return await UnifiedStudentStatusService.checkStudentStatus(
      student,
      classId: classId,
    );
  }
}

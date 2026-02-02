import 'package:flutter/material.dart';
import '../../models/class_model.dart';

class ExamsScreen extends StatefulWidget {
  final ClassModel classModel;

  const ExamsScreen({super.key, required this.classModel});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: Text('امتحانات ${widget.classModel.name}'),
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.quiz_outlined,
              size: 100,
              color: Colors.yellow[600],
            ),
            const SizedBox(height: 20),
            Text(
              'شاشة الامتحانات',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'قريباً مع جميع التحسينات الجديدة',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.yellow[600]!, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    '✅ تم إصلاح مشكلة النظام بنجاح',
                    style: TextStyle(
                      color: Colors.green[400],
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '✅ Flutter يعمل بشكل مثالي',
                    style: TextStyle(
                      color: Colors.green[400],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '🔧 جاري العمل على الواجهة المحسنة',
                    style: TextStyle(
                      color: Colors.yellow[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('إضافة امتحان - قريباً مع جميع التحسينات!'),
              backgroundColor: Colors.yellow[600],
            ),
          );
        },
        backgroundColor: Colors.yellow[600],
        child: const Icon(
          Icons.add,
          color: Colors.black,
          size: 28,
        ),
        tooltip: 'إضافة امتحان',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

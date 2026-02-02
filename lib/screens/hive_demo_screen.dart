import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/hive_student.dart';
import '../models/hive_exam.dart';
import '../services/hive_service.dart';
import 'hive_main_screen.dart';

/// شاشة تجريبية لإضافة بيانات تجريبية واختبار النظام
class HiveDemoScreen extends StatefulWidget {
  const HiveDemoScreen({super.key});

  @override
  State<HiveDemoScreen> createState() => _HiveDemoScreenState();
}

class _HiveDemoScreenState extends State<HiveDemoScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تجربة نظام Hive'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Card(
              color: Colors.blue,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Icon(Icons.science, size: 48, color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'شاشة تجريبية',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'اختبر نظام Hive بإضافة بيانات تجريبية',
                      style: TextStyle(color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // معلومات الحالة الحالية
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'الحالة الحالية:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatChip(
                          'الطلاب',
                          HiveService.getStudentsCount().toString(),
                          Colors.blue,
                        ),
                        _buildStatChip(
                          'الامتحانات',
                          HiveService.getExamsCount().toString(),
                          Colors.green,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // أزرار الإجراءات
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _addSampleData,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_circle),
              label: const Text('إضافة بيانات تجريبية'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HiveMainScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.dashboard),
              label: const Text('فتح لوحة التحكم'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _confirmClearData,
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text(
                'حذف جميع البيانات',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                side: const BorderSide(color: Colors.red),
              ),
            ),
            
            const Spacer(),
            
            // معلومات إضافية
            const Card(
              color: Colors.amber,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.black87),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'البيانات التجريبية تحتوي على 5 طلاب مع امتحانات متنوعة',
                        style: TextStyle(color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(String label, String value, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      label: Text(label),
    );
  }

  Future<void> _addSampleData() async {
    setState(() => _isLoading = true);

    try {
      // إنشاء 5 طلاب تجريبيين
      final students = [
        HiveStudent(
          id: const Uuid().v4(),
          name: 'أحمد محمد علي',
          age: 15,
          grade: 'الصف التاسع',
          phoneNumber: '0501234567',
          parentPhone: '0507654321',
          address: 'الرياض، حي النخيل',
          createdAt: DateTime.now(),
        ),
        HiveStudent(
          id: const Uuid().v4(),
          name: 'فاطمة عبدالله',
          age: 14,
          grade: 'الصف الثامن',
          phoneNumber: '0509876543',
          parentPhone: '0503456789',
          address: 'جدة، حي الصفا',
          createdAt: DateTime.now(),
        ),
        HiveStudent(
          id: const Uuid().v4(),
          name: 'خالد سعد',
          age: 16,
          grade: 'الصف العاشر',
          phoneNumber: '0502345678',
          parentPhone: '0508765432',
          address: 'الدمام، حي الفيصلية',
          createdAt: DateTime.now(),
        ),
        HiveStudent(
          id: const Uuid().v4(),
          name: 'نورة حسن',
          age: 15,
          grade: 'الصف التاسع',
          phoneNumber: '0506543210',
          parentPhone: '0501234098',
          address: 'مكة، حي العزيزية',
          createdAt: DateTime.now(),
        ),
        HiveStudent(
          id: const Uuid().v4(),
          name: 'عمر يوسف',
          age: 14,
          grade: 'الصف الثامن',
          phoneNumber: '0504567890',
          parentPhone: '0509870123',
          address: 'المدينة، حي السلام',
          createdAt: DateTime.now(),
        ),
      ];

      // حفظ الطلاب
      for (var student in students) {
        await HiveService.addStudent(student);
      }

      // إضافة امتحانات لكل طالب
      final subjects = ['الرياضيات', 'العلوم', 'اللغة العربية', 'اللغة الإنجليزية', 'التاريخ'];
      final examTypes = ['شهري', 'نصفي', 'نهائي'];

      for (var student in students) {
        // إضافة 3-5 امتحانات لكل طالب
        final examCount = 3 + (student.age % 3);
        
        for (int i = 0; i < examCount; i++) {
          final subject = subjects[i % subjects.length];
          final examType = examTypes[i % examTypes.length];
          
          // درجات عشوائية بناءً على اسم الطالب (للحصول على نتائج متنوعة)
          final baseScore = 50 + (student.name.length % 40);
          final score = (baseScore + (i * 5)).toDouble();
          
          final exam = HiveExam(
            id: const Uuid().v4(),
            studentId: student.id,
            subject: subject,
            score: score > 100 ? 100 : score,
            maxScore: 100,
            date: DateTime.now().subtract(Duration(days: i * 15)),
            examType: examType,
            notes: i == 0 ? 'امتحان ممتاز' : null,
            createdAt: DateTime.now(),
          );

          await HiveService.addExam(exam);
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم إضافة ${students.length} طلاب مع امتحاناتهم بنجاح! ✓',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );

        // الانتقال تلقائيًا للوحة التحكم
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const HiveMainScreen(),
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmClearData() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('تأكيد الحذف'),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من حذف جميع البيانات؟\n'
          'لا يمكن التراجع عن هذا الإجراء!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await HiveService.clearAllData();
              if (context.mounted) {
                Navigator.pop(context);
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف جميع البيانات'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}

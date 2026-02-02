import 'package:flutter/material.dart';
import '../services/hive_service.dart';
import 'hive_students_screen.dart';
import 'hive_exams_screen.dart';

class HiveMainScreen extends StatelessWidget {
  const HiveMainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نظام Hive المحلي 🔥'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // بطاقة معلومات
            Card(
              color: Colors.blue.withValues(alpha: 0.1),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Icon(Icons.storage, size: 48, color: Colors.blue),
                    const SizedBox(height: 8),
                    const Text(
                      'قاعدة بيانات محلية سريعة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'تخزين البيانات محليًا بدون إنترنت',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // إحصائيات سريعة
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    'الطلاب',
                    HiveService.getStudentsCount().toString(),
                    Icons.people,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    context,
                    'الامتحانات',
                    HiveService.getExamsCount().toString(),
                    Icons.assignment,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // أزرار التنقل
            _buildNavigationButton(
              context,
              'إدارة الطلاب',
              'عرض وإضافة وتعديل الطلاب',
              Icons.people,
              Colors.blue,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HiveStudentsScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildNavigationButton(
              context,
              'إدارة الامتحانات',
              'عرض وتصفية الامتحانات',
              Icons.assignment,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HiveExamsScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _buildNavigationButton(
              context,
              'أفضل الطلاب',
              'عرض الطلاب المتفوقين',
              Icons.emoji_events,
              Colors.orange,
              () => _showTopStudents(context),
            ),
            
            const Spacer(),
            
            // زر حذف البيانات
            OutlinedButton.icon(
              onPressed: () => _confirmClearData(context),
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              label: const Text(
                'حذف جميع البيانات',
                style: TextStyle(color: Colors.red),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationButton(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _showTopStudents(BuildContext context) {
    final topStudents = HiveService.getTopStudents(limit: 10);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.orange),
            SizedBox(width: 8),
            Text('أفضل 10 طلاب'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: topStudents.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text(
                      'لا توجد بيانات كافية',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: topStudents.length,
                  itemBuilder: (context, index) {
                    final data = topStudents[index];
                    final student = data['student'];
                    final average = data['average'] as double;
                    
                    // أيقونة الميدالية للمراكز الثلاثة الأولى
                    Widget? medal;
                    if (index == 0) {
                      medal = const Icon(Icons.emoji_events, color: Colors.amber, size: 28);
                    } else if (index == 1) {
                      medal = const Icon(Icons.emoji_events, color: Colors.grey, size: 24);
                    } else if (index == 2) {
                      medal = const Icon(Icons.emoji_events, color: Colors.brown, size: 20);
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: medal ?? CircleAvatar(
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          student.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text('الصف: ${student.grade}'),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${average.toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _confirmClearData(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('تحذير'),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من حذف جميع البيانات؟\n\n'
          'سيتم حذف:\n'
          '• جميع الطلاب\n'
          '• جميع الامتحانات\n\n'
          'هذا الإجراء لا يمكن التراجع عنه!',
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم حذف جميع البيانات بنجاح'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
  }
}

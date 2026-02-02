# 🚀 كيفية الوصول إلى نظام Hive

## الطريقة السريعة - للتجربة الفورية

### 1. من أي صفحة في التطبيق، أضف هذا الكود:

```dart
import 'package:flutter/material.dart';
import 'screens/hive_demo_screen.dart';

// في أي مكان تريد إضافة زر للوصول:
FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
    );
  },
  child: const Icon(Icons.science),
  tooltip: 'تجربة Hive',
)
```

### 2. أو أضف في Drawer/Menu:

```dart
ListTile(
  leading: const Icon(Icons.storage),
  title: const Text('نظام Hive'),
  subtitle: const Text('قاعدة بيانات محلية'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
    );
  },
)
```

---

## الطريقة المباشرة - تعديل الصفحة الرئيسية

### إذا كنت تريد الوصول المباشر من الصفحة الرئيسية:

1. افتح الصفحة الرئيسية للتطبيق (مثلاً `home_screen.dart` أو `dashboard_screen.dart`)

2. أضف import في الأعلى:
```dart
import 'screens/hive_demo_screen.dart';
// أو
import 'screens/hive_main_screen.dart';
```

3. أضف بطاقة أو زر في الواجهة:
```dart
Card(
  child: ListTile(
    leading: const Icon(Icons.storage, color: Colors.blue),
    title: const Text('نظام Hive 🔥'),
    subtitle: const Text('قاعدة بيانات محلية للطلاب والامتحانات'),
    trailing: const Icon(Icons.arrow_forward_ios),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
      );
    },
  ),
)
```

---

## الطريقة البرمجية - الاستخدام المباشر

### إذا كنت تريد استخدام Hive مباشرة في الكود:

```dart
import 'services/hive_service.dart';
import 'models/hive_student.dart';
import 'models/hive_exam.dart';
import 'package:uuid/uuid.dart';

// إضافة طالب
final student = HiveStudent(
  id: const Uuid().v4(),
  name: 'أحمد محمد',
  age: 15,
  grade: 'الصف التاسع',
  createdAt: DateTime.now(),
);
await HiveService.addStudent(student);

// إضافة امتحان
final exam = HiveExam(
  id: const Uuid().v4(),
  studentId: student.id,
  subject: 'الرياضيات',
  score: 85,
  maxScore: 100,
  date: DateTime.now(),
  createdAt: DateTime.now(),
);
await HiveService.addExam(exam);

// الحصول على جميع الطلاب
final students = HiveService.getAllStudents();

// الحصول على معدل طالب
final average = HiveService.getStudentAverage(student.id);
```

---

## مثال كامل - إضافة في الصفحة الرئيسية

### إذا كانت لديك صفحة رئيسية مثل `HomeScreen`:

```dart
import 'package:flutter/material.dart';
import 'screens/hive_demo_screen.dart';
import 'screens/hive_main_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مساعد المعلم')),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        children: [
          // ... البطاقات الموجودة ...
          
          // بطاقة Hive الجديدة
          _buildCard(
            context,
            'نظام Hive 🔥',
            'قاعدة بيانات محلية',
            Icons.storage,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(subtitle, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
```

---

## الشاشات المتاحة

### 1. HiveDemoScreen (للتجربة)
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
);
```
- إضافة بيانات تجريبية
- اختبار النظام
- عرض الإحصائيات

### 2. HiveMainScreen (لوحة التحكم)
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const HiveMainScreen()),
);
```
- إدارة الطلاب والامتحانات
- عرض الإحصائيات
- أفضل الطلاب

### 3. HiveStudentsScreen (إدارة الطلاب)
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const HiveStudentsScreen()),
);
```

### 4. HiveExamsScreen (إدارة الامتحانات)
```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const HiveExamsScreen()),
);
```

---

## نصيحة سريعة 💡

**للتجربة الفورية:**
1. شغل التطبيق
2. أضف هذا الكود في أي صفحة:
```dart
FloatingActionButton(
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const HiveDemoScreen()),
    );
  },
  child: const Icon(Icons.science),
)
```
3. اضغط الزر
4. اضغط "إضافة بيانات تجريبية"
5. استمتع! 🎉

---

## الملفات المهمة

- `HIVE_GUIDE.md` - دليل شامل
- `HIVE_IMPLEMENTATION_SUMMARY.md` - ملخص التطبيق
- `lib/services/hive_service.dart` - جميع الوظائف
- `lib/screens/hive_demo_screen.dart` - شاشة التجربة

**جاهز للاستخدام! 🚀**

# 🔥 دليل استخدام نظام Hive في Teacher Aide Pro

## 📋 نظرة عامة

تم تطبيق نظام **Hive** كقاعدة بيانات محلية سريعة وخفيفة لتخزين بيانات الطلاب والامتحانات. Hive يوفر:

✅ **تخزين محلي** - لا يحتاج إنترنت  
⚡ **سرعة عالية** - أسرع من SQLite  
📦 **سهولة الاستخدام** - API بسيط وواضح  
🔄 **تحديثات تلقائية** - واجهة تتحدث تلقائيًا عند تغيير البيانات  
💾 **حفظ دائم** - البيانات تبقى حتى بعد إغلاق التطبيق

---

## 🏗️ البنية المعمارية

### 1. الموديلات (Models)

#### `HiveStudent` - موديل الطالب
```dart
@HiveType(typeId: 0)
class HiveStudent extends HiveObject {
  String id;              // معرف فريد
  String name;            // الاسم
  int age;                // العمر
  String grade;           // الصف
  String? classId;        // معرف الفصل (اختياري)
  String? phoneNumber;    // رقم الهاتف (اختياري)
  String? parentPhone;    // هاتف ولي الأمر (اختياري)
  String? address;        // العنوان (اختياري)
  String? imageUrl;       // صورة الطالب (اختياري)
  DateTime createdAt;     // تاريخ الإنشاء
  DateTime? updatedAt;    // تاريخ آخر تحديث
  List<String> examIds;   // قائمة معرفات الامتحانات
}
```

#### `HiveExam` - موديل الامتحان
```dart
@HiveType(typeId: 1)
class HiveExam extends HiveObject {
  String id;              // معرف فريد
  String studentId;       // معرف الطالب
  String subject;         // المادة
  double score;           // الدرجة المحصلة
  double maxScore;        // الدرجة الكاملة
  DateTime date;          // تاريخ الامتحان
  String? notes;          // ملاحظات (اختياري)
  String? examType;       // نوع الامتحان (شهري، نصفي، نهائي)
  DateTime createdAt;     // تاريخ الإنشاء
  DateTime? updatedAt;    // تاريخ آخر تحديث
}
```

### 2. الخدمات (Services)

#### `HiveService` - خدمة إدارة Hive

يوفر جميع العمليات المطلوبة للتعامل مع البيانات:

**عمليات الطلاب:**
- `addStudent()` - إضافة طالب جديد
- `updateStudent()` - تحديث بيانات طالب
- `deleteStudent()` - حذف طالب (وجميع امتحاناته)
- `getStudent()` - الحصول على طالب بالمعرف
- `getAllStudents()` - الحصول على جميع الطلاب
- `searchStudents()` - البحث عن طلاب
- `getStudentsByGrade()` - طلاب حسب الصف
- `getStudentsByClass()` - طلاب حسب الفصل

**عمليات الامتحانات:**
- `addExam()` - إضافة امتحان جديد
- `updateExam()` - تحديث امتحان
- `deleteExam()` - حذف امتحان
- `getExam()` - الحصول على امتحان بالمعرف
- `getAllExams()` - الحصول على جميع الامتحانات
- `getExamsByStudentId()` - امتحانات طالب معين
- `getExamsBySubject()` - امتحانات حسب المادة
- `getStudentExamsBySubject()` - امتحانات طالب في مادة معينة

**الإحصائيات:**
- `getStudentAverage()` - معدل الطالب العام
- `getStudentSubjectAverage()` - معدل الطالب في مادة
- `getTopStudents()` - أفضل الطلاب
- `getStudentsCount()` - عدد الطلاب
- `getExamsCount()` - عدد الامتحانات

### 3. الواجهات (Screens)

#### `HiveMainScreen` - الشاشة الرئيسية
- عرض إحصائيات سريعة
- التنقل إلى إدارة الطلاب والامتحانات
- عرض أفضل الطلاب
- خيار حذف جميع البيانات

#### `HiveStudentsScreen` - إدارة الطلاب
- عرض قائمة الطلاب
- البحث عن طلاب
- إضافة/تعديل/حذف طالب
- عرض إحصائيات كل طالب
- الانتقال لصفحة تفاصيل الطالب

#### `HiveStudentDetailsScreen` - تفاصيل الطالب
- عرض معلومات الطالب الكاملة
- عرض إحصائيات الطالب
- إدارة امتحانات الطالب
- إضافة/تعديل/حذف امتحان

#### `HiveExamsScreen` - إدارة الامتحانات
- عرض جميع الامتحانات مجمعة حسب المادة
- تصفية حسب المادة أو الطالب
- عرض تفاصيل كل امتحان

---

## 🚀 كيفية الاستخدام

### 1. التهيئة الأولية

تم تهيئة Hive تلقائيًا في `main.dart`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة قاعدة البيانات
  await initializeDatabase();
  
  // تهيئة Hive
  await HiveService.init();
  
  runApp(const TeacherAideApp());
}
```

### 2. الوصول إلى الشاشة الرئيسية

من أي مكان في التطبيق:

```dart
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const HiveMainScreen()),
);
```

### 3. أمثلة على الاستخدام

#### إضافة طالب جديد:
```dart
final student = HiveStudent(
  id: const Uuid().v4(),
  name: 'أحمد محمد',
  age: 15,
  grade: 'الصف التاسع',
  phoneNumber: '0501234567',
  createdAt: DateTime.now(),
);

await HiveService.addStudent(student);
```

#### إضافة امتحان لطالب:
```dart
final exam = HiveExam(
  id: const Uuid().v4(),
  studentId: student.id,
  subject: 'الرياضيات',
  score: 85,
  maxScore: 100,
  date: DateTime.now(),
  examType: 'شهري',
  createdAt: DateTime.now(),
);

await HiveService.addExam(exam);
```

#### الحصول على معدل طالب:
```dart
final average = HiveService.getStudentAverage(studentId);
print('المعدل: ${average.toStringAsFixed(1)}%');
```

#### البحث عن طلاب:
```dart
final results = HiveService.searchStudents('أحمد');
```

---

## 📊 الميزات المتقدمة

### 1. التحديث التلقائي للواجهة

استخدام `ValueListenableBuilder` للتحديث التلقائي:

```dart
ValueListenableBuilder(
  valueListenable: HiveService.studentsBox.listenable(),
  builder: (context, Box<HiveStudent> box, _) {
    final students = box.values.toList();
    return ListView.builder(
      itemCount: students.length,
      itemBuilder: (context, index) {
        return ListTile(title: Text(students[index].name));
      },
    );
  },
)
```

### 2. الربط بين الطلاب والامتحانات

كل طالب يحتوي على قائمة `examIds` تربطه بامتحاناته:

```dart
// الحصول على امتحانات طالب
final exams = HiveService.getExamsByStudentId(studentId);

// عند حذف طالب، يتم حذف جميع امتحاناته تلقائيًا
await HiveService.deleteStudent(studentId);
```

### 3. الإحصائيات والتقارير

```dart
// أفضل 10 طلاب
final topStudents = HiveService.getTopStudents(limit: 10);

// معدل طالب في مادة معينة
final mathAverage = HiveService.getStudentSubjectAverage(
  studentId, 
  'الرياضيات'
);
```

---

## 🎨 التخصيص

### إضافة حقول جديدة للموديلات

1. أضف الحقل في الموديل مع `@HiveField`:
```dart
@HiveField(12)
String? newField;
```

2. شغل build_runner لتوليد الكود:
```bash
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### إضافة عمليات جديدة في HiveService

```dart
static List<HiveStudent> getStudentsByAge(int age) {
  return studentsBox.values
      .where((student) => student.age == age)
      .toList();
}
```

---

## ⚠️ ملاحظات مهمة

1. **المعرفات الفريدة**: استخدم `Uuid().v4()` لتوليد معرفات فريدة
2. **الحذف المتسلسل**: حذف طالب يحذف جميع امتحاناته تلقائيًا
3. **التحديثات**: استخدم `updatedAt` لتتبع التعديلات
4. **النسخ الاحتياطي**: لا يوجد نسخ احتياطي تلقائي، يمكن إضافة ميزة تصدير/استيراد لاحقًا

---

## 🔧 استكشاف الأخطاء

### مشكلة: البيانات لا تظهر
- تأكد من تهيئة Hive في `main.dart`
- تحقق من استخدام `ValueListenableBuilder`

### مشكلة: خطأ في build_runner
```bash
flutter clean
flutter pub get
flutter packages pub run build_runner build --delete-conflicting-outputs
```

### مشكلة: البيانات تختفي
- Hive يحفظ البيانات تلقائيًا
- تأكد من عدم استخدام `clearAllData()` بالخطأ

---

## 📚 موارد إضافية

- [Hive Documentation](https://docs.hivedb.dev/)
- [Flutter Hive Tutorial](https://pub.dev/packages/hive)
- [Hive Generator](https://pub.dev/packages/hive_generator)

---

## ✅ الخلاصة

نظام Hive الآن جاهز للاستخدام بالكامل! يمكنك:

✓ إضافة وإدارة الطلاب  
✓ إضافة وإدارة الامتحانات  
✓ ربط الامتحانات بالطلاب  
✓ عرض الإحصائيات والتقارير  
✓ البحث والتصفية  
✓ التحديث التلقائي للواجهة  

**جميع البيانات محفوظة محليًا ولا تحتاج إنترنت! 🎉**

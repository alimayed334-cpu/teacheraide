# مساعد المعلم - Teacher Aide Pro

تطبيق Flutter لإدارة الطلاب والفصول الدراسية باللغة العربية.

## الميزات الرئيسية

- ✅ إدارة الفصول الدراسية
- ✅ إدارة الطلاب
- ✅ تسجيل الحضور والغياب
- ✅ إدارة الدرجات والاختبارات
- ✅ التقارير والإحصائيات
- ✅ تصدير البيانات (PDF, Excel)
- ✅ واجهة عربية كاملة
- ✅ دعم الوضع الليلي
- ✅ قاعدة بيانات محلية SQLite

## المتطلباJ``bash
# تحقق من تثبيت Flutter
flutter doctor
```

### 2. Android Studio أو VS Code
- Android Studio مع Android SDK
- أو VS Code مع إضافات Flutter و Dart

### 3. Git
```bash
git --version
```

## التثبيت والتشغيل

### 1. استنساخ المشروع
```bash
git clone <repository-url>
cd teacher_aide_pro
```

### 2. تثبيت المكتبات
```bash
flutter pub get
```

### 3. تشغيل التطبيق
```bash
# للتشغيل على محاكي Android
flutter run

# للتشغيل على جهاز محدد
flutter devices
flutter run -d <device-id>
```

### 4. بناء التطبيق للإنتاج
```bash
# بناء APK
flutter build apk --release

# بناء App Bundle
flutter build appbundle --release
```

## بيانات التجربة

للتجربة السريعة، يمكنك استخدام:
- **البريد الإلكتروني**: teacher@example.com
- **كلمة المرور**: 123456

## هيكل المشروع

```
lib/
├── main.dart                 # نقطة البداية
├── theme/
│   └── app_theme.dart       # الثيم والألوان
├── models/                  # نماذج البيانات
│   ├── class_model.dart
│   ├── student_model.dart
│   ├── attendance_model.dart
│   └── grade_model.dart
├── database/
│   └── database_helper.dart # قاعدة البيانات
├── providers/               # إدارة الحالة
│   ├── auth_provider.dart
│   ├── class_provider.dart
│   ├── student_provider.dart
│   ├── attendance_provider.dart
│   └── grade_provider.dart
└── screens/                 # الشاشات
    ├── splash_screen.dart
    ├── auth/
    │   ├── login_screen.dart
    │   └── register_screen.dart
    ├── home/
    │   └── home_screen.dart
    ├── classes/
    │   └── classes_screen.dart
    ├── reports/
    │   └── reports_screen.dart
    └── settings/
        └── settings_screen.dart
```

## الألوان المستخدمة

- **اللون الأساسي**: #2C272B
- **اللون الثانوي**: #FEC619
- **لون الخلفية**: #F5F5F5
- **لون النجاح**: #38A169
- **لون الخطأ**: #E53E3E
- **لون التحذير**: #D69E2E

## المكتبات المستخدمة

- `flutter`: إطار العمل الأساسي
- `provider`: إدارة الحالة
- `sqflite`: قاعدة البيانات المحلية
- `shared_preferences`: التخزين المحلي
- `pdf`: إنشاء ملفات PDF
- `excel`: إنشاء ملفات Excel
- `image_picker`: اختيار الصور
- `fl_chart`: الرسوم البيانية
- `intl`: التاريخ والوقت

## الحالة الحالية

### ✅ مكتمل
- إعداد المشروع الأساسي
- نماذج البيانات
- قاعدة البيانات
- الثيم والتصميم
- شاشة تسجيل الدخول والتسجيل
- الشاشة الرئيسية
- شاشة إدارة الفصول

### 🚧 قيد التطوير
- شاشة إدارة الطلاب
- شاشة الحضور والغياب
- شاشة الدرجات
- شاشة التقارير
- الإعدادات المتقدمة

### 📋 مخطط للمستقبل
- المزامنة السحابية
- الإشعارات
- النسخ الاحتياطي التلقائي
- دعم اللغة الإنجليزية
- تطبيق الويب

## المساهمة

نرحب بالمساهمات! يرجى:

1. عمل Fork للمشروع
2. إنشاء branch جديد للميزة
3. تنفيذ التغييرات
4. إرسال Pull Request

## الترخيص

هذا المشروع مرخص تحت رخصة MIT.

## الدعم

للحصول على الدعم أو الإبلاغ عن مشاكل:
- إنشاء Issue في GitHub
- التواصل عبر البريد الإلكتروني

---

**ملاحظة**: هذا التطبيق في مرحلة التطوير. بعض الميزات قد تكون غير مكتملة.

# إعداد Google Drive API لتطبيق مساعد المعلم

## الخطوات المطلوبة:

### 1. إنشاء مشروع في Google Cloud Console
1. اذهب إلى [Google Cloud Console](https://console.cloud.google.com/)
2. أنشئ مشروع جديد أو اختر مشروع موجود
3. فعّل **Google Drive API**:
   - من القائمة الجانبية اختر "APIs & Services" > "Library"
   - ابحث عن "Google Drive API"
   - اضغط على "Enable"

### 2. إعداد بيانات الاعتماد (Credentials)
1. من القائمة الجانبية اختر "APIs & Services" > "Credentials"
2. اضغط على "Create Credentials" > "OAuth client ID"
3. اختر "Web application"
4. أضف معلومات التطبيق:
   - **Name**: Teacher Aide Pro
   - **Authorized JavaScript origins**: `http://localhost`
   - **Authorized redirect URIs**: `http://localhost`

### 3. تحديث ملفات التطبيق

#### أ. إضافة ملف الاعتماد
أنشئ ملف `assets/credentials.json` وأضف بيانات الاعتماد التي حصلت عليها:

```json
{
  "web": {
    "client_id": "YOUR_CLIENT_ID_HERE",
    "client_secret": "YOUR_CLIENT_SECRET_HERE",
    "redirect_uris": ["http://localhost"],
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "token_uri": "https://oauth2.googleapis.com/token"
  }
}
```

#### ب. تحديث pubspec.yaml
تم إضافة المكتبات التالية:
- `google_sign_in: ^6.2.1`
- `googleapis: ^12.0.0`
- `googleapis_auth: ^1.4.1`
- `flutter_secure_storage: ^9.0.0`

#### ج. إضافة ملف الاعتماد إلى assets
أضف السطر التالي في قسم `assets` بملف `pubspec.yaml`:
```yaml
assets:
  - assets/credentials.json
```

### 4. استخدام الميزة في التطبيق
تم تحديث صفحة الملاحظات (`class_notes_screen.dart`) لتدعم:
- الرفع المباشر إلى Google Drive
- الحصول على رابط مشاركة مباشر
- مشاركة الرابط عبر WhatsApp

## كيف تعمل الميزة:
1. عند الضغط على زر PDF في صفحة الملاحظات
2. يتم إنشاء ملف PDF
3. يطلب التطبيق تسجيل الدخول إلى Google (مرة واحدة فقط)
4. يتم رفع الملف إلى Google Drive
5. يتم الحصول على رابط مشاركة عام
6. يمكن مشاركة الرابط مباشرة عبر WhatsApp

## ملاحظات هامة:
- يجب أن يكون المستخدم لديه حساب Google
- الملفات ترفع إلى Google Drive الخاص بالمستخدم
- الروابط تكون متاحة للجميع (public)
- يمكن إدارة الملفات من Google Drive

## الخطوات التالية:
1. إنشاء مشروع Google Cloud
2. تفعيل Google Drive API
3. إنشاء بيانات الاعتماد
4. إضافة ملف credentials.json
5. اختبار الميزة في التطبيق

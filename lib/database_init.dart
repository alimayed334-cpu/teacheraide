// ملف افتراضي للتهيئة
import 'database/database_helper.dart';

Future<void> initializeDatabase() async {
  // تهيئة قاعدة البيانات الافتراضية
  await DatabaseHelper().database;
}

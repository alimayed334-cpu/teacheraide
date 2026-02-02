// تهيئة قاعدة البيانات للويب
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite/sqflite.dart';

Future<void> initializeDatabase() async {
  // تهيئة sqflite للويب
  databaseFactory = databaseFactoryFfiWeb;
  print('تم تهيئة قاعدة البيانات للويب باستخدام sqflite_common_ffi_web');
}

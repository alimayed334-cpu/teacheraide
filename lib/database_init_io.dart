// تهيئة قاعدة البيانات لـ Windows/Linux/macOS/Android
import 'dart:io' show Platform;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'database/database_helper.dart';

Future<void> initializeDatabase() async {
  // تهيئة FFI فقط للـ Desktop (Windows, Linux, macOS)
  // Android و iOS يستخدمون sqflite العادي
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  
  // تهيئة قاعدة البيانات
  await DatabaseHelper().database;
}

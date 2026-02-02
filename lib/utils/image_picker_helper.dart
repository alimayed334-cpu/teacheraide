import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class ImagePickerHelper {
  static final ImagePicker _imagePicker = ImagePicker();

  /// اختيار صورة من المعرض أو File Picker حسب المنصة
  static Future<String?> pickImage(BuildContext context) async {
    try {
      // التحقق من الصلاحيات (Mobile فقط)
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        PermissionStatus status;
        if (Platform.isIOS) {
          status = await Permission.photos.request();
        } else {
          // Android: photos (Android 13+) أو storage (أقدم)
          status = await Permission.photos.request();
          if (status != PermissionStatus.granted) {
            status = await Permission.storage.request();
          }
        }

        if (status == PermissionStatus.permanentlyDenied) {
          _showErrorSnackBar(
            context,
            'يرجى السماح بصلاحية الصور من إعدادات الجهاز',
          );
          await openAppSettings();
          return null;
        }

        if (status != PermissionStatus.granted && status != PermissionStatus.limited) {
          _showErrorSnackBar(context, 'يرجى منح صلاحية الوصول للصور');
          return null;
        }
      }

      String? imagePath;

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // Desktop: استخدام File Picker
        imagePath = await _pickImageFromFilePicker(context);
      } else {
        // Mobile: استخدام ImagePicker
        imagePath = await _pickImageFromGallery(context);
      }

      if (imagePath != null) {
        // نسخ الصورة إلى مجلد التطبيق المحلي
        final localPath = await _copyImageToLocal(imagePath);
        return localPath;
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'حدث خطأ أثناء اختيار الصورة: $e');
      return null;
    }
  }

  /// اختيار صورة من المعرض (Mobile)
  static Future<String?> _pickImageFromGallery(BuildContext context) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, // جودة متوسطة لتقليل الحجم
        maxWidth: 800,    // أقصى عرض
        maxHeight: 800,   // أقصى ارتفاع
      );

      return pickedFile?.path;
    } catch (e) {
      _showErrorSnackBar(context, 'فشل اختيار الصورة من المعرض: $e');
      return null;
    }
  }

  /// اختيار صورة باستخدام File Picker (Desktop)
  static Future<String?> _pickImageFromFilePicker(BuildContext context) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return result.files.single.path!;
      }

      return null;
    } catch (e) {
      _showErrorSnackBar(context, 'فشل اختيار الصورة: $e');
      return null;
    }
  }

  /// نسخ الصورة إلى مجلد التخزين المحلي للتطبيق
  static Future<String?> _copyImageToLocal(String imagePath) async {
    try {
      final sourceFile = File(imagePath);
      
      // الحصول على مجلد التطبيق
      final appDir = await getApplicationSupportDirectory();
      final imagesDir = Directory(path.join(appDir.path, 'student_images'));
      
      // إنشاء المجلد إذا لم يكن موجوداً
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // إنشاء اسم فريد للصورة
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'student_${timestamp}${path.extension(imagePath)}';
      final localPath = path.join(imagesDir.path, fileName);

      // نسخ الملف
      await sourceFile.copy(localPath);

      print('📸 Image copied to: $localPath');
      return localPath;
    } catch (e) {
      print('❌ Error copying image: $e');
      return null;
    }
  }

  /// حذف الصورة المحلية
  static Future<bool> deleteLocalImage(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return true;

    try {
      final file = File(imagePath);
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Image deleted: $imagePath');
      }
      return true;
    } catch (e) {
      print('❌ Error deleting image: $e');
      return false;
    }
  }

  /// التحقق من وجود الصورة
  static Future<bool> imageExists(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return false;

    try {
      final file = File(imagePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  /// عرض رسالة خطأ
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

/// ودجت لعرض الصورة المكبرة
class ImageViewerDialog extends StatelessWidget {
  final String imagePath;

  const ImageViewerDialog({
    super.key,
    required this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // خلفية داكنة
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              color: Colors.black.withOpacity(0.9),
            ),
          ),
          // الصورة المكبرة
          Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                child: Image.file(
                  File(imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error, color: Colors.red, size: 50),
                          SizedBox(height: 10),
                          Text(
                            'لا يمكن عرض الصورة',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // زر الإغلاق
          Positioned(
            top: 40,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// عرض الصورة المكبرة
void showImageViewer(BuildContext context, String imagePath) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) => ImageViewerDialog(imagePath: imagePath),
  );
}

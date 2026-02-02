import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class FileAttachmentHelper {
  static const String _reportsDir = 'reports';
  static const String _attendanceDir = 'attendance';
  static const String _examsDir = 'exams';
  static const String _notesDir = 'notes';

  // Get app documents directory
  static Future<Directory> get _appDir async {
    return await getApplicationDocumentsDirectory();
  }

  // Get reports directory
  static Future<Directory> get _reportsDirectory async {
    final appDir = await _appDir;
    final reportsDir = Directory(path.join(appDir.path, _reportsDir));
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    return reportsDir;
  }

  // Get attendance reports directory
  static Future<Directory> get _attendanceDirectory async {
    final reportsDir = await _reportsDirectory;
    final attendanceDir = Directory(path.join(reportsDir.path, _attendanceDir));
    if (!await attendanceDir.exists()) {
      await attendanceDir.create(recursive: true);
    }
    return attendanceDir;
  }

  // Get exams reports directory
  static Future<Directory> get _examsDirectory async {
    final reportsDir = await _reportsDirectory;
    final examsDir = Directory(path.join(reportsDir.path, _examsDir));
    if (!await examsDir.exists()) {
      await examsDir.create(recursive: true);
    }
    return examsDir;
  }

  // Get notes reports directory
  static Future<Directory> get _notesDirectory async {
    final reportsDir = await _reportsDirectory;
    final notesDir = Directory(path.join(reportsDir.path, _notesDir));
    if (!await notesDir.exists()) {
      await notesDir.create(recursive: true);
    }
    return notesDir;
  }

  // Save attendance PDF report
  static Future<String> saveAttendanceReport({
    required String className,
    required String date,
    required List<int> bytes,
  }) async {
    final dir = await _attendanceDirectory;
    final fileName = 'attendance_${className}_$date.pdf';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Save exam PDF report
  static Future<String> saveExamReport({
    required String className,
    required String examTitle,
    required String date,
    required List<int> bytes,
  }) async {
    final dir = await _examsDirectory;
    final fileName = 'exam_${className}_${examTitle}_$date.pdf';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Save notes PDF report
  static Future<String> saveNotesReport({
    required String className,
    required String date,
    required List<int> bytes,
  }) async {
    final dir = await _notesDirectory;
    final fileName = 'notes_${className}_$date.pdf';
    final file = File(path.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    return file.path;
  }

  // Get all attendance reports
  static Future<List<FileInfo>> getAttendanceReports() async {
    final dir = await _attendanceDirectory;
    return await _getFilesInDirectory(dir);
  }

  // Get all exam reports
  static Future<List<FileInfo>> getExamReports() async {
    final dir = await _examsDirectory;
    return await _getFilesInDirectory(dir);
  }

  // Get all notes reports
  static Future<List<FileInfo>> getNotesReports() async {
    final dir = await _notesDirectory;
    return await _getFilesInDirectory(dir);
  }

  // Get all reports
  static Future<List<FileInfo>> getAllReports() async {
    final reportsDir = await _reportsDirectory;
    return await _getFilesInDirectory(reportsDir, recursive: true);
  }

  // Get files in directory
  static Future<List<FileInfo>> _getFilesInDirectory(Directory dir, {bool recursive = false}) async {
    if (!await dir.exists()) {
      return [];
    }

    final files = <FileInfo>[];
    await for (final entity in dir.list(recursive: recursive)) {
      if (entity is File && entity.path.endsWith('.pdf')) {
        final stat = await entity.stat();
        files.add(FileInfo(
          path: entity.path,
          name: path.basename(entity.path),
          size: stat.size,
          modified: stat.modified,
        ));
      }
    }
    
    // Sort by modified date (newest first)
    files.sort((a, b) => b.modified.compareTo(a.modified));
    return files;
  }

  // Delete file
  static Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Check if file exists
  static Future<bool> fileExists(String filePath) async {
    final file = File(filePath);
    return await file.exists();
  }

  // Get file size
  static Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final stat = await file.stat();
        return stat.size;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // Format file size
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // Clean old files (older than specified days)
  static Future<void> cleanOldFiles({int daysOld = 30}) async {
    try {
      final reportsDir = await _reportsDirectory;
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      
      await for (final entity in reportsDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoffDate)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      // Silent fail for cleanup
    }
  }
}

class FileInfo {
  final String path;
  final String name;
  final int size;
  final DateTime modified;

  FileInfo({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  String get formattedSize => FileAttachmentHelper.formatFileSize(size);
  
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(modified);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return 'منذ ${difference.inMinutes} دقيقة';
      }
      return 'منذ ${difference.inHours} ساعة';
    } else if (difference.inDays == 1) {
      return 'أمس';
    } else if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} أيام';
    } else {
      return '${modified.day}/${modified.month}/${modified.year}';
    }
  }

  String get type {
    if (name.endsWith('.pdf')) return 'PDF';
    return 'File';
  }
}

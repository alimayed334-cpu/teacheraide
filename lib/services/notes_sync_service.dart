import 'package:flutter/material.dart';
import 'package:teacher_aide_pro/models/student_note_model.dart';
import 'package:teacher_aide_pro/models/attendance_model.dart';
import 'package:teacher_aide_pro/database/database_helper.dart';
import 'package:intl/intl.dart';

class NotesSyncService {
  static final DatabaseHelper _dbHelper = DatabaseHelper();

  static Future<void> syncAttendanceToNotes() async {
    try {
      print('Starting sync from attendance to notes...');
      // مزامنة الملاحظات من جدول الحضور لجدول الملاحظات
      final attendanceRecords = await _dbHelper.getAllAttendance();
      
      for (var attendance in attendanceRecords) {
        if (attendance.notes != null && attendance.notes!.isNotEmpty) {
          // تحقق من وجود الملاحظة في جدول student_notes
          final existingNotes = await _dbHelper.getStudentNotesByStudent(attendance.studentId);
          final dateKey = DateFormat('yyyy-MM-dd').format(attendance.date);
          
          bool noteExists = existingNotes.any((note) => 
            note.date.contains(dateKey) && note.note == attendance.notes);
          
          if (!noteExists) {
            // إضافة الملاحظة كنوع "عادي"
            final newNote = StudentNoteModel(
              studentId: attendance.studentId,
              classId: attendance.classId,
              note: attendance.notes!,
              noteType: StudentNoteType.normal,
              date: dateKey,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            await _dbHelper.insertStudentNote(newNote);
            print('Synced attendance note to student notes for student ${attendance.studentId}');
          }
        }
      }
    } catch (e) {
      print('Error syncing attendance to notes: $e');
    }
  }

  static Future<void> syncNotesToAttendance() async {
    try {
      print('Starting sync from notes to attendance...');
      // مزامنة الملاحظات من جدول الملاحظات لجدول الحضور
      final classes = await _dbHelper.getAllClasses();
      
      for (var classModel in classes) {
        final studentNotes = await _dbHelper.getStudentNotesByClass(classModel.id!);
        
        for (var note in studentNotes) {
          // البحث عن سجل الحضور المطابق
          final attendanceRecords = await _dbHelper.getAttendanceByStudent(note.studentId);
          
          for (var attendance in attendanceRecords) {
            final attendanceDate = DateFormat('yyyy-MM-dd').format(attendance.date);
            
            if (attendanceDate == note.date) {
              // تحديث تعليق الحضور إذا كان فارغاً أو مختلفاً
              if (attendance.notes == null || attendance.notes != note.note) {
                final updatedAttendance = attendance.copyWith(notes: note.note);
                await _dbHelper.updateAttendance(updatedAttendance);
                print('Synced student note to attendance for student ${note.studentId}');
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Error syncing notes to attendance: $e');
    }
  }
}

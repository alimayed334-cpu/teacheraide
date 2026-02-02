import 'package:flutter/material.dart';

enum StudentNoteType {
  good('جيدة', Colors.green),
  bad('سيئة', Colors.red),
  normal('عادية', Colors.grey);

  const StudentNoteType(this.displayName, this.color);
  final String displayName;
  final Color color;
}

class StudentNoteModel {
  final int? id;
  final int studentId;
  final int classId;
  final String note;
  final StudentNoteType noteType;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  StudentNoteModel({
    this.id,
    required this.studentId,
    required this.classId,
    required this.note,
    required this.noteType,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'class_id': classId,
      'note': note,
      'note_type': noteType.name,
      'date': date.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory StudentNoteModel.fromMap(Map<String, dynamic> map) {
    return StudentNoteModel(
      id: map['id'],
      studentId: map['student_id'],
      classId: map['class_id'],
      note: map['note'],
      noteType: StudentNoteType.values.firstWhere(
        (type) => type.name == map['note_type'],
        orElse: () => StudentNoteType.normal,
      ),
      date: DateTime.parse(map['date']),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  StudentNoteModel copyWith({
    int? id,
    int? studentId,
    int? classId,
    String? note,
    StudentNoteType? noteType,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudentNoteModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classId: classId ?? this.classId,
      note: note ?? this.note,
      noteType: noteType ?? this.noteType,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'StudentNoteModel{id: $id, studentId: $studentId, note: $note, noteType: $noteType}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudentNoteModel &&
        other.id == id &&
        other.studentId == studentId &&
        other.classId == classId &&
        other.date == date;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        studentId.hashCode ^
        classId.hashCode ^
        date.hashCode;
  }
}

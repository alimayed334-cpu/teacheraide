enum AttendanceStatus {
  present,
  absent,
  late,
  expelled,
  excused,
}

class AttendanceModel {
  final int? id;
  final int studentId;
  final int? lectureId; // Add lecture ID to handle separate lectures on same date
  final DateTime date;
  final AttendanceStatus status;
  final String? notes;
  final DateTime createdAt;

  AttendanceModel({
    this.id,
    required this.studentId,
    this.lectureId,
    required this.date,
    required this.status,
    this.notes,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'lecture_id': lectureId,
      'date': date.toIso8601String().split('T')[0], // Store only date part
      'status': status.index,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    return AttendanceModel(
      id: map['id']?.toInt(),
      studentId: map['student_id']?.toInt() ?? 0,
      lectureId: map['lecture_id']?.toInt(),
      date: DateTime.parse(map['date']),
      status: AttendanceStatus.values[map['status'] ?? 0],
      notes: map['notes'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  AttendanceModel copyWith({
    int? id,
    int? studentId,
    int? lectureId,
    DateTime? date,
    AttendanceStatus? status,
    String? notes,
    DateTime? createdAt,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      lectureId: lectureId ?? this.lectureId,
      date: date ?? this.date,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  String get statusText {
    switch (status) {
      case AttendanceStatus.present:
        return 'حاضر';
      case AttendanceStatus.absent:
        return 'غائب';
      case AttendanceStatus.late:
        return 'متأخر';
      case AttendanceStatus.expelled:
        return 'مطرود';
      case AttendanceStatus.excused:
        return 'مجاز';
    }
  }

  String get statusEmoji {
    switch (status) {
      case AttendanceStatus.present:
        return '✅';
      case AttendanceStatus.absent:
        return '❌';
      case AttendanceStatus.late:
        return '⏰';
      case AttendanceStatus.expelled:
        return '🚫';
      case AttendanceStatus.excused:
        return '🟦';
    }
  }
}

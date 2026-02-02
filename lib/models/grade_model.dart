class GradeModel {
  final int? id;
  final int studentId;
  final String examName;
  final double score;
  final double maxScore;
  final DateTime examDate;
  final String? notes;
  final String? status;
  final DateTime createdAt;
  final DateTime updatedAt;

  GradeModel({
    this.id,
    required this.studentId,
    required this.examName,
    required this.score,
    required this.maxScore,
    required this.examDate,
    this.notes,
    this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'exam_name': examName,
      'score': score,
      'max_score': maxScore,
      'exam_date': examDate.toIso8601String().split('T')[0],
      'notes': notes,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory GradeModel.fromMap(Map<String, dynamic> map) {
    return GradeModel(
      id: map['id']?.toInt(),
      studentId: map['student_id']?.toInt() ?? 0,
      examName: map['exam_name'] ?? '',
      score: map['score']?.toDouble() ?? 0.0,
      maxScore: map['max_score']?.toDouble() ?? 0.0,
      examDate: DateTime.parse(map['exam_date']),
      notes: map['notes'],
      status: map['status'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  GradeModel copyWith({
    int? id,
    int? studentId,
    String? examName,
    double? score,
    double? maxScore,
    DateTime? examDate,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GradeModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      examName: examName ?? this.examName,
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      examDate: examDate ?? this.examDate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  double get percentage => maxScore > 0 ? (score / maxScore) * 100 : 0;

  String get gradeLevel {
    final percent = percentage;
    if (percent >= 90) return 'ممتاز';
    if (percent >= 80) return 'جيد جداً';
    if (percent >= 70) return 'جيد';
    if (percent >= 60) return 'مقبول';
    return 'ضعيف';
  }
}

class GradeInfo {
  final double obtainedMarks;
  final double totalMarks;
  final String? comment;
  final String? status;

  GradeInfo({
    required this.obtainedMarks,
    required this.totalMarks,
    this.comment,
    this.status,
  });
}

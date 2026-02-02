class ExamResultModel {
  final int? id;
  final int studentId;
  final int examId;
  final double score;
  final double totalScore;
  final String status; // present, absent, late, cheating, etc.
  final String? comment;
  final DateTime examDate;
  final String examName;

  ExamResultModel({
    this.id,
    required this.studentId,
    required this.examId,
    required this.score,
    required this.totalScore,
    this.status = 'present', 
    this.comment,
    required this.examDate,
    required this.examName,
  });

  // Convert a ExamResultModel into a Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'examId': examId,
      'score': score,
      'totalScore': totalScore,
      'status': status,
      'comment': comment,
      'examDate': examDate.toIso8601String(),
      'examName': examName,
    };
  }

  // Create a ExamResultModel from a Map
  factory ExamResultModel.fromMap(Map<String, dynamic> map) {
    return ExamResultModel(
      id: map['id'],
      studentId: map['studentId'],
      examId: map['examId'],
      score: map['score'] is int ? (map['score'] as int).toDouble() : map['score'],
      totalScore: map['totalScore'] is int ? (map['totalScore'] as int).toDouble() : map['totalScore'],
      status: map['status'] ?? 'present',
      comment: map['comment'],
      examDate: DateTime.parse(map['examDate']),
      examName: map['examName'],
    );
  }

  // Create a copy of the model with some updated fields
  ExamResultModel copyWith({
    int? id,
    int? studentId,
    int? examId,
    double? score,
    double? totalScore,
    String? status,
    String? comment,
    DateTime? examDate,
    String? examName,
  }) {
    return ExamResultModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      examId: examId ?? this.examId,
      score: score ?? this.score,
      totalScore: totalScore ?? this.totalScore,
      status: status ?? this.status,
      comment: comment ?? this.comment,
      examDate: examDate ?? this.examDate,
      examName: examName ?? this.examName,
    );
  }
}

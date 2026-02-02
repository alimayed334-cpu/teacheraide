class ExamModel {
  final int? id;
  final String title;
  final DateTime date;
  final double maxScore;
  final int classId;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExamModel({
    this.id,
    required this.title,
    required this.date,
    required this.maxScore,
    required this.classId,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  // تحويل من Map (من قاعدة البيانات)
  factory ExamModel.fromMap(Map<String, dynamic> map) {
    return ExamModel(
      id: map['id'] as int?,
      title: map['title'] as String,
      date: DateTime.parse(map['date'] as String),
      maxScore: (map['max_score'] as num).toDouble(),
      classId: map['class_id'] as int,
      description: map['description'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  // تحويل إلى Map (لقاعدة البيانات)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'date': date.toIso8601String(),
      'max_score': maxScore,
      'class_id': classId,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // نسخ مع تعديل بعض الخصائص
  ExamModel copyWith({
    int? id,
    String? title,
    DateTime? date,
    double? maxScore,
    int? classId,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ExamModel(
      id: id ?? this.id,
      title: title ?? this.title,
      date: date ?? this.date,
      maxScore: maxScore ?? this.maxScore,
      classId: classId ?? this.classId,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'ExamModel{id: $id, title: $title, date: $date, maxScore: $maxScore, classId: $classId}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ExamModel &&
        other.id == id &&
        other.title == title &&
        other.date == date &&
        other.maxScore == maxScore &&
        other.classId == classId;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        title.hashCode ^
        date.hashCode ^
        maxScore.hashCode ^
        classId.hashCode;
  }
}

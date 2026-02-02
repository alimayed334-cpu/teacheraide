class LectureModel {
  final int? id;
  final int classId; // ربط المحاضرة بالفصل
  final String title;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;

  LectureModel({
    this.id,
    required this.classId,
    required this.title,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'class_id': classId,
      'title': title,
      'date': date.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LectureModel.fromMap(Map<String, dynamic> map) {
    return LectureModel(
      id: map['id'],
      classId: map['class_id'],
      title: map['title'],
      date: DateTime.parse(map['date']),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  LectureModel copyWith({
    int? id,
    int? classId,
    String? title,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LectureModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      title: title ?? this.title,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

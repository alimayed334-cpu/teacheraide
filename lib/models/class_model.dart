class ClassModel {
  final int? id;
  final String name;
  final String subject;
  final String year;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  ClassModel({
    this.id,
    required this.name,
    required this.subject,
    required this.year,
    this.description,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'subject': subject,
      'year': year,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ClassModel.fromMap(Map<String, dynamic> map) {
    return ClassModel(
      id: map['id']?.toInt(),
      name: map['name'] ?? '',
      subject: map['subject'] ?? '',
      year: map['year'] ?? '',
      description: map['description'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  ClassModel copyWith({
    int? id,
    String? name,
    String? subject,
    String? year,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ClassModel(
      id: id ?? this.id,
      name: name ?? this.name,
      subject: subject ?? this.subject,
      year: year ?? this.year,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

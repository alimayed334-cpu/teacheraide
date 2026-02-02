class NoteModel {
  final int? id;
  final int classId;
  final String itemType; // 'lecture' أو 'exam'
  final int itemId; // معرف المحاضرة أو الامتحان
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  NoteModel({
    this.id,
    required this.classId,
    required this.itemType,
    required this.itemId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'class_id': classId,
      'item_type': itemType,
      'item_id': itemId,
      'content': content,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'],
      classId: map['class_id'],
      itemType: map['item_type'],
      itemId: map['item_id'],
      content: map['content'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  NoteModel copyWith({
    int? id,
    int? classId,
    String? itemType,
    int? itemId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      itemType: itemType ?? this.itemType,
      itemId: itemId ?? this.itemId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'NoteModel{id: $id, classId: $classId, itemType: $itemType, itemId: $itemId, content: $content}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is NoteModel &&
        other.id == id &&
        other.classId == classId &&
        other.itemType == itemType &&
        other.itemId == itemId;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        classId.hashCode ^
        itemType.hashCode ^
        itemId.hashCode;
  }
}

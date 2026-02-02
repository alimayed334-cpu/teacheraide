import 'package:hive/hive.dart';

part 'hive_student.g.dart';

@HiveType(typeId: 0)
class HiveStudent extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  int age;

  @HiveField(3)
  String grade;

  @HiveField(4)
  String? classId;

  @HiveField(5)
  String? phoneNumber;

  @HiveField(6)
  String? parentPhone;

  @HiveField(7)
  String? address;

  @HiveField(8)
  String? imageUrl;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  DateTime? updatedAt;

  @HiveField(11)
  List<String> examIds; // قائمة معرفات الامتحانات المرتبطة بالطالب

  HiveStudent({
    required this.id,
    required this.name,
    required this.age,
    required this.grade,
    this.classId,
    this.phoneNumber,
    this.parentPhone,
    this.address,
    this.imageUrl,
    required this.createdAt,
    this.updatedAt,
    List<String>? examIds,
  }) : examIds = examIds ?? [];

  // تحويل من Map
  factory HiveStudent.fromMap(Map<String, dynamic> map) {
    return HiveStudent(
      id: map['id'] as String,
      name: map['name'] as String,
      age: map['age'] as int,
      grade: map['grade'] as String,
      classId: map['classId'] as String?,
      phoneNumber: map['phoneNumber'] as String?,
      parentPhone: map['parentPhone'] as String?,
      address: map['address'] as String?,
      imageUrl: map['imageUrl'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt'] as String) 
          : null,
      examIds: map['examIds'] != null 
          ? List<String>.from(map['examIds'] as List) 
          : [],
    );
  }

  // تحويل إلى Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'age': age,
      'grade': grade,
      'classId': classId,
      'phoneNumber': phoneNumber,
      'parentPhone': parentPhone,
      'address': address,
      'imageUrl': imageUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'examIds': examIds,
    };
  }

  // نسخ مع تعديلات
  HiveStudent copyWith({
    String? id,
    String? name,
    int? age,
    String? grade,
    String? classId,
    String? phoneNumber,
    String? parentPhone,
    String? address,
    String? imageUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? examIds,
  }) {
    return HiveStudent(
      id: id ?? this.id,
      name: name ?? this.name,
      age: age ?? this.age,
      grade: grade ?? this.grade,
      classId: classId ?? this.classId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      parentPhone: parentPhone ?? this.parentPhone,
      address: address ?? this.address,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      examIds: examIds ?? this.examIds,
    );
  }
}

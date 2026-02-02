import 'package:hive/hive.dart';

part 'hive_exam.g.dart';

@HiveType(typeId: 1)
class HiveExam extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String studentId; // معرف الطالب المرتبط بالامتحان

  @HiveField(2)
  String subject; // المادة

  @HiveField(3)
  double score; // الدرجة

  @HiveField(4)
  double maxScore; // الدرجة الكاملة

  @HiveField(5)
  DateTime date; // تاريخ الامتحان

  @HiveField(6)
  String? notes; // ملاحظات

  @HiveField(7)
  String? examType; // نوع الامتحان (شهري، نصفي، نهائي)

  @HiveField(8)
  DateTime createdAt;

  @HiveField(9)
  DateTime? updatedAt;

  HiveExam({
    required this.id,
    required this.studentId,
    required this.subject,
    required this.score,
    required this.maxScore,
    required this.date,
    this.notes,
    this.examType,
    required this.createdAt,
    this.updatedAt,
  });

  // حساب النسبة المئوية
  double get percentage => (score / maxScore) * 100;

  // حالة النجاح/الرسوب
  bool get isPassed => percentage >= 50;

  // التقدير
  String get grade {
    if (percentage >= 90) return 'ممتاز';
    if (percentage >= 80) return 'جيد جداً';
    if (percentage >= 70) return 'جيد';
    if (percentage >= 60) return 'مقبول';
    if (percentage >= 50) return 'ضعيف';
    return 'راسب';
  }

  // تحويل من Map
  factory HiveExam.fromMap(Map<String, dynamic> map) {
    return HiveExam(
      id: map['id'] as String,
      studentId: map['studentId'] as String,
      subject: map['subject'] as String,
      score: (map['score'] as num).toDouble(),
      maxScore: (map['maxScore'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String),
      notes: map['notes'] as String?,
      examType: map['examType'] as String?,
      createdAt: DateTime.parse(map['createdAt'] as String),
      updatedAt: map['updatedAt'] != null 
          ? DateTime.parse(map['updatedAt'] as String) 
          : null,
    );
  }

  // تحويل إلى Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'subject': subject,
      'score': score,
      'maxScore': maxScore,
      'date': date.toIso8601String(),
      'notes': notes,
      'examType': examType,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  // نسخ مع تعديلات
  HiveExam copyWith({
    String? id,
    String? studentId,
    String? subject,
    double? score,
    double? maxScore,
    DateTime? date,
    String? notes,
    String? examType,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HiveExam(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      subject: subject ?? this.subject,
      score: score ?? this.score,
      maxScore: maxScore ?? this.maxScore,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      examType: examType ?? this.examType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

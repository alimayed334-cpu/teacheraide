class GuardianModel {
  final String name;
  final String? phone;
  final String? email;
  final List<String> notificationMethods; // ['email', 'sms', 'telegram']

  GuardianModel({
    required this.name,
    this.phone,
    this.email,
    this.notificationMethods = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'notification_methods': notificationMethods.join(','),
    };
  }

  factory GuardianModel.fromMap(Map<String, dynamic> map) {
    return GuardianModel(
      name: map['name'] ?? '',
      phone: map['phone'],
      email: map['email'],
      notificationMethods: map['notifications'] != null 
          ? (map['notifications'] as String).split(',').where((s) => s.isNotEmpty).toList()
          : map['notification_methods'] != null 
              ? (map['notification_methods'] as String).split(',').where((s) => s.isNotEmpty).toList()
              : [],
    );
  }

  GuardianModel copyWith({
    String? name,
    String? phone,
    String? email,
    List<String>? notificationMethods,
  }) {
    return GuardianModel(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notificationMethods: notificationMethods ?? this.notificationMethods,
    );
  }
}

class StudentModel {
  final int? id;
  final int classId;
  final String name;
  final String? photo;
  final String? photoPath; // مسار الصورة المحلية
  final String? notes;
  final String? parentPhone; // للتوافق مع النسخة القديمة
  final String? parentEmail; // للتوافق مع النسخة القديمة
  final String? studentId;
  final String? email;
  final String? phone;
  final String? location;
  final DateTime? birthDate;
  final GuardianModel? primaryGuardian;
  final GuardianModel? secondaryGuardian;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // حقول إحصائية للمراسلة
  final double? averageGrade;
  final int? attendedLectures;
  final int? absentLectures;
  final int? excusedLectures;
  final int? expelledLectures;
  final double? absencePercentage;
  final int? attendedExams;
  final int? absentExams;
  final int? exemptOrPostponedExams;
  final int? cheatingCount;
  final int? missingCount;

  StudentModel({
    this.id,
    required this.classId,
    required this.name,
    this.photo,
    this.photoPath,
    this.notes,
    this.parentPhone,
    this.parentEmail,
    this.studentId,
    this.email,
    this.phone,
    this.location,
    this.birthDate,
    this.primaryGuardian,
    this.secondaryGuardian,
    this.averageGrade,
    this.attendedLectures,
    this.absentLectures,
    this.excusedLectures,
    this.expelledLectures,
    this.absencePercentage,
    this.attendedExams,
    this.absentExams,
    this.exemptOrPostponedExams,
    this.cheatingCount,
    this.missingCount,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'id': id,
      'class_id': classId,
      'name': name,
      'photo': photo,
      'photo_path': photoPath,
      'notes': notes,
      'parent_phone': parentPhone,
      'parent_email': parentEmail,
      'student_id': studentId,
      'email': email,
      'phone': phone,
      'location': location,
      'birth_date': birthDate?.toIso8601String(),
      'average_grade': averageGrade,
      'attended_lectures': attendedLectures,
      'absent_lectures': absentLectures,
      'excused_lectures': excusedLectures,
      'expelled_lectures': expelledLectures,
      'absence_percentage': absencePercentage,
      'attended_exams': attendedExams,
      'absent_exams': absentExams,
      'exempt_or_postponed_exams': exemptOrPostponedExams,
      'cheating_count': cheatingCount,
      'missing_count': missingCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    // إضافة بيانات الوصي الأول إذا وجد
    if (primaryGuardian != null) {
      map['primary_guardian'] = _encodeGuardian(primaryGuardian!.toMap());
    }
    
    // إضافة بيانات الوصي الثاني إذا وجد
    if (secondaryGuardian != null) {
      map['secondary_guardian'] = _encodeGuardian(secondaryGuardian!.toMap());
    }

    return map;
  }
  
  static String _encodeGuardian(Map<String, dynamic> guardian) {
    // تحويل البيانات إلى نص JSON بسيط
    final parts = <String>[];
    if (guardian['name'] != null) parts.add('name:${guardian['name']}');
    if (guardian['phone'] != null) parts.add('phone:${guardian['phone']}');
    if (guardian['email'] != null) parts.add('email:${guardian['email']}');
    if (guardian['notification_methods'] != null && guardian['notification_methods'] is String) {
      parts.add('notifications:${guardian['notification_methods']}');
    }
    return parts.join('|');
  }
  
  static Map<String, dynamic>? _decodeGuardian(String? guardianData) {
    if (guardianData == null || guardianData.isEmpty) return null;
    
    final result = <String, dynamic>{};
    final parts = guardianData.split('|');
    
    for (final part in parts) {
      final keyValue = part.split(':');
      if (keyValue.length == 2) {
        final key = keyValue[0];
        final value = keyValue[1];
        result[key] = value;
      }
    }
    
    return result.isNotEmpty ? result : null;
  }

  factory StudentModel.fromMap(Map<String, dynamic> map) {
    return StudentModel(
      id: map['id']?.toInt(),
      classId: map['class_id']?.toInt() ?? 0,
      name: map['name'] ?? '',
      photo: map['photo'],
      photoPath: map['photo_path'],
      notes: map['notes'],
      parentPhone: map['parent_phone'],
      parentEmail: map['parent_email'],
      studentId: map['student_id'],
      email: map['email'],
      phone: map['phone'],
      location: map['location'],
      birthDate: map['birth_date'] != null ? DateTime.parse(map['birth_date']) : null,
      primaryGuardian: _decodeGuardian(map['primary_guardian']) != null 
          ? GuardianModel.fromMap(_decodeGuardian(map['primary_guardian'])!)
          : null,
      secondaryGuardian: _decodeGuardian(map['secondary_guardian']) != null 
          ? GuardianModel.fromMap(_decodeGuardian(map['secondary_guardian'])!)
          : null,
      averageGrade: map['average_grade']?.toDouble(),
      attendedLectures: map['attended_lectures']?.toInt(),
      absentLectures: map['absent_lectures']?.toInt(),
      excusedLectures: map['excused_lectures']?.toInt(),
      expelledLectures: map['expelled_lectures']?.toInt(),
      absencePercentage: map['absence_percentage']?.toDouble(),
      attendedExams: map['attended_exams']?.toInt(),
      absentExams: map['absent_exams']?.toInt(),
      exemptOrPostponedExams: map['exempt_or_postponed_exams']?.toInt(),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
    );
  }

  StudentModel copyWith({
    int? id,
    int? classId,
    String? name,
    String? photo,
    String? photoPath,
    String? notes,
    String? parentPhone,
    String? parentEmail,
    String? studentId,
    String? email,
    String? phone,
    String? location,
    DateTime? birthDate,
    GuardianModel? primaryGuardian,
    GuardianModel? secondaryGuardian,
    double? averageGrade,
    int? attendedLectures,
    int? absentLectures,
    int? excusedLectures,
    int? expelledLectures,
    double? absencePercentage,
    int? attendedExams,
    int? absentExams,
    int? exemptOrPostponedExams,
    int? cheatingCount,
    int? missingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StudentModel(
      id: id ?? this.id,
      classId: classId ?? this.classId,
      name: name ?? this.name,
      photo: photo ?? this.photo,
      photoPath: photoPath ?? this.photoPath,
      notes: notes ?? this.notes,
      parentPhone: parentPhone ?? this.parentPhone,
      parentEmail: parentEmail ?? this.parentEmail,
      studentId: studentId ?? this.studentId,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      location: location ?? this.location,
      birthDate: birthDate ?? this.birthDate,
      primaryGuardian: primaryGuardian ?? this.primaryGuardian,
      secondaryGuardian: secondaryGuardian ?? this.secondaryGuardian,
      averageGrade: averageGrade ?? this.averageGrade,
      attendedLectures: attendedLectures ?? this.attendedLectures,
      absentLectures: absentLectures ?? this.absentLectures,
      excusedLectures: excusedLectures ?? this.excusedLectures,
      expelledLectures: expelledLectures ?? this.expelledLectures,
      absencePercentage: absencePercentage ?? this.absencePercentage,
      attendedExams: attendedExams ?? this.attendedExams,
      absentExams: absentExams ?? this.absentExams,
      exemptOrPostponedExams: exemptOrPostponedExams ?? this.exemptOrPostponedExams,
      cheatingCount: cheatingCount ?? this.cheatingCount,
      missingCount: missingCount ?? this.missingCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Get all available email addresses for this student
  List<String> getEmailAddresses() {
    final emails = <String>[];
    
    // Student's own email
    if (email != null && email!.isNotEmpty) {
      emails.add(email!);
    }
    
    // Legacy parent email
    if (parentEmail != null && parentEmail!.isNotEmpty) {
      emails.add(parentEmail!);
    }
    
    // Primary guardian email
    if (primaryGuardian?.email != null && primaryGuardian!.email!.isNotEmpty) {
      emails.add(primaryGuardian!.email!);
    }
    
    // Secondary guardian email
    if (secondaryGuardian?.email != null && secondaryGuardian!.email!.isNotEmpty) {
      emails.add(secondaryGuardian!.email!);
    }
    
    return emails.toSet().toList(); // Remove duplicates
  }

  // Get email addresses that have email notifications enabled
  List<String> getNotificationEmailAddresses() {
    final emails = <String>[];
    
    // Check primary guardian notifications
    if (primaryGuardian?.email != null && 
        primaryGuardian!.email!.isNotEmpty &&
        primaryGuardian!.notificationMethods.contains('email')) {
      emails.add(primaryGuardian!.email!);
    }
    
    // Check secondary guardian notifications
    if (secondaryGuardian?.email != null && 
        secondaryGuardian!.email!.isNotEmpty &&
        secondaryGuardian!.notificationMethods.contains('email')) {
      emails.add(secondaryGuardian!.email!);
    }
    
    // Always include student's own email if available
    if (email != null && email!.isNotEmpty) {
      emails.add(email!);
    }
    
    return emails.toSet().toList(); // Remove duplicates
  }

  // Check if student has any email address
  bool hasEmail() {
    return getEmailAddresses().isNotEmpty;
  }

  // Get primary email address (first available)
  String? getPrimaryEmail() {
    final emails = getEmailAddresses();
    return emails.isNotEmpty ? emails.first : null;
  }

  // Get display name for email recipients
  String getEmailDisplayName() {
    if (studentId != null && studentId!.isNotEmpty) {
      return '$name ($studentId)';
    }
    return name;
  }
}

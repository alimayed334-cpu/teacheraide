class MessageModel {
  final String? id;
  final String studentId;
  final String classId;
  final String title;
  final String content;
  final String attachedFile;
  final List<String> sendMethods;
  final DateTime createdAt;
  final bool isSent;
  final DateTime? sentAt;

  MessageModel({
    this.id,
    required this.studentId,
    required this.classId,
    required this.title,
    required this.content,
    required this.attachedFile,
    required this.sendMethods,
    required this.createdAt,
    this.isSent = false,
    this.sentAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'student_id': studentId,
      'class_id': classId,
      'title': title,
      'content': content,
      'attached_file': attachedFile,
      'send_methods': sendMethods.join(','),
      'created_at': createdAt.toIso8601String(),
      'is_sent': isSent ? 1 : 0,
      'sent_at': sentAt?.toIso8601String(),
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'],
      studentId: map['student_id'] ?? '',
      classId: map['class_id'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      attachedFile: map['attached_file'] ?? '',
      sendMethods: map['send_methods'] != null 
          ? (map['send_methods'] as String).split(',')
          : [],
      createdAt: DateTime.parse(map['created_at']),
      isSent: map['is_sent'] == 1,
      sentAt: map['sent_at'] != null ? DateTime.parse(map['sent_at']) : null,
    );
  }

  MessageModel copyWith({
    String? id,
    String? studentId,
    String? classId,
    String? title,
    String? content,
    String? attachedFile,
    List<String>? sendMethods,
    DateTime? createdAt,
    bool? isSent,
    DateTime? sentAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      classId: classId ?? this.classId,
      title: title ?? this.title,
      content: content ?? this.content,
      attachedFile: attachedFile ?? this.attachedFile,
      sendMethods: sendMethods ?? this.sendMethods,
      createdAt: createdAt ?? this.createdAt,
      isSent: isSent ?? this.isSent,
      sentAt: sentAt ?? this.sentAt,
    );
  }
}

enum SendMessageMethod {
  sms('SMS', 'sms'),
  email('EMAIL', 'email'),
  whatsapp('WHATSUP', 'whatsapp');

  const SendMessageMethod(this.displayName, this.value);
  final String displayName;
  final String value;

  static SendMessageMethod fromValue(String value) {
    return SendMessageMethod.values.firstWhere(
      (method) => method.value == value,
      orElse: () => SendMessageMethod.email,
    );
  }
}

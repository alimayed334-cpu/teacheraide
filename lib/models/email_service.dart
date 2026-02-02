import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../config/email_config.dart';

class EmailService {
  static const String _senderEmail = EmailConfig.senderEmail;
  static const String _senderName = EmailConfig.senderName;
  static const String _appPassword = EmailConfig.appPassword;

  // Configure Gmail SMTP server
  static SmtpServer get _smtpServer => gmail(_senderEmail, _appPassword);

  
  // Send email with file attachment
  static Future<bool> sendEmailWithAttachment({
    required String recipientEmail,
    required String subject,
    required String message,
    required String attachmentPath,
    String? attachmentName,
    String? replyToEmail,
  }) async {
    try {
      print('Preparing email to: $recipientEmail');
      print('Attachment path: $attachmentPath');
      
      // Check if attachment file exists and is accessible
      final attachmentFile = File(attachmentPath);
      if (!await attachmentFile.exists()) {
        print('Error: Attachment file does not exist: $attachmentPath');
        return false;
      }
      
      final fileSize = await attachmentFile.length();
      print('Attachment file size: $fileSize bytes');
      
      if (fileSize == 0) {
        print('Error: Attachment file is empty');
        return false;
      }
      
      // Create email message
      final emailMessage = Message()
        ..from = Address(_senderEmail, _senderName)
        ..recipients.add(recipientEmail)
        ..subject = subject
        ..text = message;

      if (replyToEmail != null && replyToEmail.trim().isNotEmpty) {
        emailMessage.headers['Reply-To'] = replyToEmail.trim();
      }

      // Add attachment with proper MIME type
      final fileName = attachmentName ?? attachmentFile.path.split(Platform.pathSeparator).last;
      emailMessage.attachments.add(
        FileAttachment(
          attachmentFile,
          fileName: fileName,
        ),
      );
      
      print('Sending email...');
      
      // Send email
      await send(emailMessage, _smtpServer);
      
      print('Email sent successfully to $recipientEmail');
      return true;
    } catch (e) {
      print('Error sending email: $e');
      print('Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  // Send email to multiple recipients
  static Future<bool> sendEmailToMultipleRecipients({
    required List<String> recipientEmails,
    required String subject,
    required String message,
    required String attachmentPath,
    String? attachmentName,
  }) async {
    try {
      bool allSent = true;
      
      for (String email in recipientEmails) {
        final success = await sendEmailWithAttachment(
          recipientEmail: email,
          subject: subject,
          message: message,
          attachmentPath: attachmentPath,
          attachmentName: attachmentName,
        );
        
        if (!success) {
          allSent = false;
        }
        
        // Add delay between emails to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 100));
      }
      
      return allSent;
    } catch (e) {
      print('Error sending emails to multiple recipients: $e');
      return false;
    }
  }

  // Get app documents directory for storing files
  static Future<Directory> getAppDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  // Check if file exists and is accessible
  static Future<bool> isFileAccessible(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }

  // Validate email format
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  // Send text-only email without attachment
  static Future<bool> sendTextOnlyEmail({
    required String recipientEmail,
    required String subject,
    required String message,
    String? replyToEmail,
  }) async {
    try {
      // Create email message
      final emailMessage = Message()
        ..from = Address(_senderEmail, _senderName)
        ..recipients.add(recipientEmail)
        ..subject = subject
        ..text = message;

      if (replyToEmail != null && replyToEmail.trim().isNotEmpty) {
        emailMessage.headers['Reply-To'] = replyToEmail.trim();
      }

      // Send email
      await send(emailMessage, _smtpServer);
      return true;
    } catch (e) {
      print('Error sending text-only email: $e');
      return false;
    }
  }
}

class EmailAttachment {
  final String name;
  final String path;
  final String type;

  EmailAttachment({
    required this.name,
    required this.path,
    this.type = 'application/pdf',
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'path': path,
      'type': type,
    };
  }

  factory EmailAttachment.fromJson(Map<String, dynamic> json) {
    return EmailAttachment(
      name: json['name'],
      path: json['path'],
      type: json['type'] ?? 'application/pdf',
    );
  }
}

class EmailMessage {
  final List<String> recipients;
  final String subject;
  final String message;
  final EmailAttachment? attachment;

  EmailMessage({
    required this.recipients,
    required this.subject,
    required this.message,
    this.attachment,
  });

  Map<String, dynamic> toJson() {
    return {
      'recipients': recipients,
      'subject': subject,
      'message': message,
      'attachment': attachment?.toJson(),
    };
  }

  factory EmailMessage.fromJson(Map<String, dynamic> json) {
    return EmailMessage(
      recipients: List<String>.from(json['recipients']),
      subject: json['subject'],
      message: json['message'],
      attachment: json['attachment'] != null 
          ? EmailAttachment.fromJson(json['attachment'])
          : null,
    );
  }
}

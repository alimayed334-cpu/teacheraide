import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BotApiService {
  static const String _baseUrl = String.fromEnvironment(
    'BOT_API_BASE_URL',
    defaultValue: 'https://teacheraide-production.up.railway.app',
  );

  static Future<bool> upsertStudent({
    required String id,
    required String name,
    String? phone,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/upsert/student'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': id,
          'name': name,
          'phone': phone,
        }),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService upsertStudent error: $e');
      }
      return false;
    }
  }

  static Future<bool> upsertParent({
    required String phone,
    String? name,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/upsert/parent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'phone': phone,
          'name': name,
        }),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService upsertParent error: $e');
      }
      return false;
    }
  }

  static Future<bool> deleteStudent({required String id}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/delete/student'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService deleteStudent error: $e');
      }
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getTelegramGroups() async {
    try {
      final resp = await http.get(Uri.parse('$_baseUrl/groups'));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return [];
      final decoded = jsonDecode(resp.body);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService getTelegramGroups error: $e');
      }
      return [];
    }
  }

  static Future<bool> sendTelegramText({
    required dynamic chatId,
    required String text,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/send-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'chat_id': chatId, 'text': text}),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService sendTelegramText error: $e');
      }
      return false;
    }
  }

  static Future<bool> sendTelegramDocument({
    required dynamic chatId,
    required File file,
    String? caption,
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/send-document');
      final req = http.MultipartRequest('POST', uri);
      req.fields['chat_id'] = chatId.toString();
      if (caption != null && caption.trim().isNotEmpty) {
        req.fields['caption'] = caption.trim();
      }
      req.files.add(await http.MultipartFile.fromPath('document', file.path));
      final streamed = await req.send();
      return streamed.statusCode >= 200 && streamed.statusCode < 300;
    } catch (e) {
      if (kDebugMode) {
        print('BotApiService sendTelegramDocument error: $e');
      }
      return false;
    }
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BotApiService {
  static const String _baseUrl = String.fromEnvironment(
    'BOT_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5005',
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
}

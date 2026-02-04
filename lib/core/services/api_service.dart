import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

class ApiService {
  static String get _baseUrl => ApiConfig.baseUrl;

  // Analyze Tone
  Future<Map<String, dynamic>?> analyzeTone(
      String text, List<String> history) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/tone'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'conversation_history': history,
        }),
      );
      print("Tone API Response: ${response.body}");

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint("Tone API Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Tone API Exception: $e");
      return null;
    }
  }

  // Translate Message
  Future<Map<String, dynamic>?> translateMessage(
      String text, String targetLang) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/translate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'target_language': targetLang,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        debugPrint(
            "Translate API Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Translate API Exception: $e");
      return null;
    }
  }

  // Batch Translate
  Future<List<Map<String, dynamic>>?> translateBatch(
      List<Map<String, String>> items, String targetLang) async {
    debugPrint("Batch Translate skipped.");
    return null;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/translate-batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'target_language': targetLang,
          'items': items,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['translations']);
      } else {
        debugPrint(
            "Batch Translate API Error: ${response.statusCode} - ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("Batch Translate API Exception: $e");
      return null;
    }
  }
}

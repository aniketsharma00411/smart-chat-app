import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String get baseUrl {
    // For production builds with --dart-define, use String.fromEnvironment
    // For development, fall back to dotenv
    const dartDefineUrl = String.fromEnvironment('API_BASE_URL');
    if (dartDefineUrl.isNotEmpty) {
      return dartDefineUrl;
    }
    return dotenv.env['API_BASE_URL'] ?? "http://localhost:8080/api";
  }

  static String get socketUrl {
    // For production builds with --dart-define, use String.fromEnvironment
    // For development, fall back to dotenv
    const dartDefineUrl = String.fromEnvironment('BACKEND_URL');
    if (dartDefineUrl.isNotEmpty) {
      return dartDefineUrl;
    }
    return dotenv.env['BACKEND_URL'] ?? "ws://localhost:8080/ws/call";
  }
}

import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {
  static String get baseUrl {
    return dotenv.env['API_BASE_URL'] ?? "http://localhost:8080/api";
  }

  static String get socketUrl {
    return dotenv.env['BACKEND_URL'] ?? "ws://localhost:8080/ws/call";
  }
}

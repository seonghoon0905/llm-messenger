// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_style.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"username": username, "password": password}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {"success": false, "message": "서버 응답 오류"};
    } catch (e) {
      return {"success": false, "message": "네트워크 연결 실패: $e"};
    }
  }

  Future<String?> requestAnalysis(List<String> messages) async {
    return null;
  }
}

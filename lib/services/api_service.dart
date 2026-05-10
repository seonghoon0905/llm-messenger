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

  Future<Map<String, dynamic>> signup({
    required String userId,
    required String password,
    required String nickname,
    String statusMessage = '',
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/signup"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "password": password,
          "nickname": nickname,
          "status_message": statusMessage,
        }),
      );

      final payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        return payload;
      }
      return {
        "success": false,
        "message": payload["detail"] ?? payload["message"] ?? "회원가입 실패",
      };
    } catch (e) {
      return {"success": false, "message": "네트워크 연결 실패: $e"};
    }
  }

  Future<Map<String, dynamic>> createDirectRoom({
    required String userId,
    required String friendId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/rooms/direct"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "friend_id": friendId,
        }),
      );

      final payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200) {
        return payload;
      }
      return {
        "success": false,
        "message": payload["detail"] ?? payload["message"] ?? "1:1 채팅방 생성 실패",
      };
    } catch (e) {
      return {"success": false, "message": "네트워크 연결 실패: $e"};
    }
  }

  Future<Map<String, dynamic>> addFriend({
    required String userId,
    required String friendId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/friends/add"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "user_id": userId,
          "friend_id": friendId,
        }),
      );

      final payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode == 200) return payload;
      return {
        "success": false,
        "message": payload["detail"] ?? payload["message"] ?? "친구 추가 실패",
      };
    } catch (e) {
      return {"success": false, "message": "네트워크 연결 실패: $e"};
    }
  }

  Future<Map<String, dynamic>> removeFriend({
    required String userId,
    required String friendId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse("${AppStyle.baseUrl}/friends/remove"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": userId, "friend_id": friendId}),
      );
      if (response.statusCode == 200) return {"success": true};
      final payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      return {"success": false, "message": payload["detail"] ?? "친구 삭제 실패"};
    } catch (e) {
      return {"success": false, "message": "네트워크 연결 실패: $e"};
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriends(String userId) async {
    final response = await http.get(
      Uri.parse("${AppStyle.baseUrl}/users/$userId/friends"),
    );
    if (response.statusCode != 200) return [];
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final friends = payload['friends'] as List<dynamic>? ?? const [];
    return friends.whereType<Map<String, dynamic>>().toList();
  }

  Future<String?> requestAnalysis(List<String> messages) async {
    return null;
  }

  Future<Map<String, dynamic>> analyzeLeary({
    required List<Map<String, String>> messages,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/analyze-leary"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"messages": messages}),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {"dominance": 50.0, "affiliation": 50.0};
    } catch (e) {
      return {"dominance": 50.0, "affiliation": 50.0};
    }
  }

  Future<Map<String, dynamic>> deleteAccount(String userId) async {
    try {
      final response = await http.delete(
        Uri.parse("${AppStyle.baseUrl}/users/$userId"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) return {"success": true};
      final payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};
      return {
        "success": false,
        "message": payload["detail"] ?? payload["message"] ?? "계정 삭제 실패",
      };
    } catch (e) {
      return {"success": false, "message": "네트워크 오류: $e"};
    }
  }
}

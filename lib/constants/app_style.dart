import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class AppStyle {
  // --- [ Color Palette ] ---
  static const Color primaryBlue = Color(0xFF0055FF);
  static const Color backgroundGrey = Color(0xFFF5F7F9);
  static const Color myBubbleColor = primaryBlue;
  static const Color otherBubbleColor = Colors.white;
  static const Color inputBgColor = Color(0xFFEEEEEE);

  // --- [ Personality Stat Colors (Duolingo Style) ] ---
  static const Color statDominance = Color(0xFFFF9800); // 주도성: 오렌지
  static const Color statAffiliation = Color(0xFF4CAF50); // 친화성: 초록
  static const Color statOpenness = Color(0xFF2196F3); // 개방성: 파랑
  static const Color statStability = Color(0xFF9C27B0); // 정서안정: 보라
  static const Color characterBoxBg = Color(0xFFFFF8E1); // 캐릭터 배경 (연한 노랑)
  static const Color characterBoxText = Color(0xFFD4A017); // 캐릭터 텍스트 (진한 황금색)

  // --- [ Sizing & Spacing ] ---
  static const double borderRadius = 16.0;
  static const double cardRadius = 24.0; // 성격 분석 카드용 곡률
  static const double horizontalPadding = 16.0;
  static const double verticalPadding = 8.0;

  // --- [ Typography ] ---
  static const TextStyle chatTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.4,
    color: Colors.black87,
  );

  static const TextStyle myChatTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.4,
    color: Colors.white,
  );

  static const TextStyle appBarTitleStyle = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  // 새로운 타이틀 스타일 추가
  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: Colors.black87,
  );

  static String? myLoggedInId;
  static UserProfile? myProfile;
  static const String baseUrl = "http://192.168.1.4:8000";
  static const String serverIp = "192.168.1.4";
  static const String wsUrl = "ws://$serverIp:8000/ws";

  static WebSocketChannel? channel;
  static Stream<dynamic>? globalStream;

  static void connectSocket(String userId) {
    channel?.sink.close();

    final url = Uri.parse("$wsUrl/$userId");
    channel = WebSocketChannel.connect(url);
    globalStream = channel!.stream.asBroadcastStream();
    print("🌐 전역 소켓 연결 시도: $url");
  }

  static void disconnectSocket() {
    channel?.sink.close();
    channel = null;
    print("🔌 전역 소켓 연결 해제");
  }
}

import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class AppStyle {
  // --- [ Color Palette ] ---
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color primaryLight = Color(0xFFEFF6FF);
  static const Color primaryBlue = primary; // backward compat

  static const Color backgroundGrey = Color(0xFFF8F9FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3F4F6);
  static const Color chatBg = Color(0xFFECF0F6);

  static const Color myBubbleColor = primary;
  static const Color otherBubbleColor = Colors.white;
  static const Color inputBgColor = Color(0xFFF3F4F6);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  static const Color divider = Color(0xFFE5E7EB);
  static const Color border = Color(0xFFE5E7EB);
  static const Color online = Color(0xFF10B981);

  // --- [ Personality Stat Colors ] ---
  static const Color statDominance = Color(0xFFFF9800);
  static const Color statAffiliation = Color(0xFF4CAF50);
  static const Color statOpenness = Color(0xFF2196F3);
  static const Color statStability = Color(0xFF9C27B0);
  static const Color characterBoxBg = Color(0xFFFFF8E1);
  static const Color characterBoxText = Color(0xFFD4A017);

  // --- [ Sizing & Spacing ] ---
  static const double borderRadius = 18.0;
  static const double cardRadius = 20.0;
  static const double horizontalPadding = 16.0;
  static const double verticalPadding = 6.0;

  // --- [ Avatar Palette ] ---
  static const List<Color> avatarColors = [
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDC2626),
    Color(0xFFD97706),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
  ];

  static Color getAvatarColor(String name) {
    if (name.isEmpty) return avatarColors[0];
    final hash = name.codeUnits.fold(0, (a, b) => a + b);
    return avatarColors[hash % avatarColors.length];
  }

  static String getInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : '?';

  // --- [ Time Formatting ] ---
  static String formatMessageTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    if (h < 12) return '오전 ${h == 0 ? 12 : h}:$m';
    return '오후 ${h == 12 ? 12 : h - 12}:$m';
  }

  static String formatChatListTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(dt.year, dt.month, dt.day);
    if (dateOnly == today) return formatMessageTime(dt);
    if (dateOnly == yesterday) return '어제';
    if (now.difference(dt).inDays < 7) {
      const days = ['월', '화', '수', '목', '금', '토', '일'];
      return '${days[dt.weekday - 1]}요일';
    }
    return '${dt.month}/${dt.day}';
  }

  static String formatDateSeparator(DateTime dt) {
    const months = ['1월', '2월', '3월', '4월', '5월', '6월',
        '7월', '8월', '9월', '10월', '11월', '12월'];
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.year}년 ${months[dt.month - 1]} ${dt.day}일 ${days[dt.weekday - 1]}요일';
  }

  // --- [ Typography ] ---
  static const TextStyle chatTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.45,
    color: textPrimary,
  );

  static const TextStyle myChatTextStyle = TextStyle(
    fontSize: 15.0,
    height: 1.45,
    color: Colors.white,
  );

  static const TextStyle appBarTitleStyle = TextStyle(
    fontSize: 17.0,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle sectionTitleStyle = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  // --- [ Session & Connection ] ---
  static String? myLoggedInId;
  static UserProfile? myProfile;
  static String? currentOpenRoomId;
  static const String baseUrl = "http://127.0.0.1:8000";
  static const String serverIp = "127.0.0.1";
  static const String wsUrl = "ws://$serverIp:8000/ws";

  static final Map<String, String> roomRegisterModes = {};
  static bool autoFeedbackEnabled = true;

  static WebSocketChannel? channel;
  static Stream<dynamic>? globalStream;

  static void connectSocket(String userId) {
    channel?.sink.close();
    final url = Uri.parse("$wsUrl/$userId");
    channel = WebSocketChannel.connect(url);
    globalStream = channel!.stream.asBroadcastStream();
    debugPrint("🌐 전역 소켓 연결 시도: $url");
  }

  static void disconnectSocket() {
    channel?.sink.close();
    channel = null;
    debugPrint("🔌 전역 소켓 연결 해제");
  }
}

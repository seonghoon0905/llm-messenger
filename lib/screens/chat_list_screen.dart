import 'package:flutter/material.dart';
import 'dart:convert';
import '../services/db_helper.dart';
import '../models/chat_room.dart';
import '../constants/app_style.dart';
import '../screens/tabs/chat_list_tab.dart';
import 'package:http/http.dart' as http;

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<ChatRoom> _chatRooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _syncRoomsFromServer(); // 1. 서버와 동기화 (추가)
    _loadChatRooms(); // 2. 로컬 로드
    _initInviteSocket(); // 3. 소켓 감시
  }

  Future<void> _syncRoomsFromServer() async {
    try {
      final response = await http.get(
        Uri.parse(
          "http://${AppStyle.serverIp}:8000/users/${AppStyle.myLoggedInId}/rooms",
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List rooms = data['rooms'];

        for (var roomData in rooms) {
          final serverRoom = ChatRoom(
            id: roomData['room_id'],
            title: roomData['title'],
            relation: roomData['relation'],
            lastMessage: "채팅방에 참여했습니다.",
            lastMessageTime: DateTime.now(),
          );
          // 로컬 DB에 없으면 저장 (이미 있으면 무시하도록 DBHelper 구성)
          await DBHelper().insertChatRoom(serverRoom);
        }
        _loadChatRooms(); // 다시 로드해서 화면 갱신
      }
    } catch (e) {
      debugPrint("서버 동기화 실패: $e");
    }
  }

  // 📥 로컬 DB에서 채팅방 목록 가져오기
  Future<void> _loadChatRooms() async {
    final rooms = await DBHelper().getChatRooms();
    if (mounted) {
      setState(() {
        _chatRooms = rooms;
        _isLoading = false;
      });
    }
  }

  // 🔌 실시간 초대 소켓 리스너
  void _initInviteSocket() {
    // AppStyle 등에 static으로 저장된 채널을 사용하거나 여기서 연결
    AppStyle.channel?.stream.listen((message) async {
      final data = jsonDecode(message);

      if (data['type'] == 'INVITE_EVENT') {
        final newRoom = ChatRoom(
          id: data['room_id'],
          title: data['room_title'],
          relation: data['relation'] ?? "기타", // [수신]
          lastMessageTime: DateTime.now(),
          lastMessage: "${data['inviter_id']}님이 초대하셨습니다.",
        );

        await DBHelper().insertChatRoom(newRoom);
        _loadChatRooms();

        // 3. 알림 띄우기
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("${data['inviter_id']}님이 초대하셨습니다!")),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ChatListTab(
              // 자식 UI 컴포넌트 호출
              chatRooms: _chatRooms,
              onLongPress: (index) {
                // 길게 눌러서 삭제하는 로직 등
              },
              onReturnFromChat: _loadChatRooms,
            ),
    );
  }
}

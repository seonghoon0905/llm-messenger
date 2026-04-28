import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../constants/app_style.dart';
import '../widgets/chat_dialogs.dart';
import 'tabs/profile_tab.dart';
import 'tabs/chat_list_tab.dart';
import '../services/db_helper.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<ChatRoom> _chatRooms = [];
  StreamSubscription? _socketSubscription;

  @override
  void initState() {
    super.initState();
    if (AppStyle.myLoggedInId != null) {
      AppStyle.connectSocket(AppStyle.myLoggedInId!);
    }
    _initGlobalSocket();
    _syncRoomsFromServer().then((_) => _loadChatRooms());
  }

  Future<void> _syncRoomsFromServer() async {
    if (AppStyle.myLoggedInId == null) return;
    try {
      final response = await http.get(
        Uri.parse("${AppStyle.baseUrl}/users/${AppStyle.myLoggedInId}/rooms"),
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
            messages: [],
          );
          try {
            await DBHelper().insertChatRoom(serverRoom);
          } catch(e) {} // 이미 존재하면 무시
        }
      }
    } catch (e) {
      debugPrint("서버 동기화 실패: $e");
    }
  }

  void _initGlobalSocket() {
    if (AppStyle.globalStream != null) {
      _socketSubscription = AppStyle.globalStream!.listen((message) async {
        final data = jsonDecode(message);
        if (data['type'] == 'INVITE_EVENT') {
          final newRoom = ChatRoom(
            id: data['room_id'],
            title: data['room_title'],
            relation: data['relation'] ?? "기타",
            lastMessageTime: DateTime.now(),
            lastMessage: "${data['inviter_id']}님이 초대하셨습니다.",
            messages: [],
          );
          try {
            await DBHelper().insertChatRoom(newRoom);
          } catch(e) {}
          _loadChatRooms();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${data['inviter_id']}님이 초대하셨습니다!")),
            );
          }
        } else if (data['content'] != null && data['room_id'] != null) {
          // 일반 메시지 수신 시 DB 저장 및 목록 갱신
          final incomingMsg = Message(
            text: data['content'] ?? "",
            sender: data['sender_nickname'] ?? data['sender_id'] ?? "unknown",
            timestamp: DateTime.parse(data['timestamp'] ?? DateTime.now().toIso8601String()),
          );
          await DBHelper().insertMessage(data['room_id'], incomingMsg);
          _loadChatRooms(); // 목록의 최신 메시지 업데이트
        }
      });
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  // --- [ 로컬 데이터 로드 ] ---
  Future<void> _loadChatRooms() async {
    // 보안을 위해 로그인 아이디가 있을 때만 로컬 데이터를 보여줍니다.
    if (AppStyle.myLoggedInId == null) return;

    // 서버 API 호출 대신 로컬 DBHelper를 통해 데이터를 가져옵니다.
    final rooms = await DBHelper().getChatRooms();

    setState(() {
      _chatRooms.clear();
      _chatRooms.addAll(rooms);
      // 최신 메시지 시간 순으로 정렬 (선택 사항)
      _chatRooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  // --- [ 새 채팅방 생성 (로컬 전용) ] ---
  void _createNewChat(String title, String relation) async {
    final newRoom = ChatRoom(
      // 서버가 ID를 생성하지 않으므로 고유한 String ID를 직접 생성합니다.
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      relation: relation,
      lastMessageTime: DateTime.now(),
      messages: [],
    );

    try {
      // 로컬 DB에 저장
      await DBHelper().insertChatRoom(newRoom);

      // UI 갱신
      await _loadChatRooms();
    } catch (e) {
      debugPrint("방 생성 실패: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('데이터베이스 오류로 방을 생성할 수 없습니다.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 탭별 페이지 구성
    final List<Widget> pages = [
      const ProfileTab(),
      ChatListTab(
        chatRooms: _chatRooms,
        onLongPress: (index) => _showChatOptions(index),
        onReturnFromChat: () => _loadChatRooms(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'OPEN SW TEMP PROJECT',
          style: AppStyle.appBarTitleStyle,
        ),
        backgroundColor: AppStyle.primaryBlue,
        elevation: 2,
        centerTitle: true,
      ),
      body: pages[_selectedIndex],
      floatingActionButton: _selectedIndex == 1
          ? FloatingActionButton(
              onPressed: () => ChatDialogs.showCreateChatDialog(
                context: context,
                onCreate: (title, relation) => _createNewChat(title, relation),
              ),
              backgroundColor: AppStyle.primaryBlue,
              child: const Icon(Icons.add_comment, color: Colors.white),
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: AppStyle.primaryBlue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '채팅'),
        ],
      ),
    );
  }

  // --- [ 채팅방 옵션 (수정/삭제) ] ---
  void _showChatOptions(int index) {
    final room = _chatRooms[index];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppStyle.primaryBlue),
              title: const Text('채팅방 정보 수정'),
              onTap: () {
                Navigator.pop(context);
                ChatDialogs.showEditChatDialog(
                  context: context,
                  initialTitle: room.title,
                  initialRelation: room.relation,
                  onSave: (newTitle, newRelation) async {
                    // 메모리 데이터 업데이트
                    setState(() {
                      room.title = newTitle;
                      room.relation = newRelation;
                    });
                    // 로컬 DB 업데이트 (DBHelper에 updateChatRoom 구현 필요)
                    await DBHelper().updateChatRoom(room);
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('채팅방 삭제'),
              onTap: () {
                Navigator.pop(context);
                ChatDialogs.showDeleteDialog(
                  context: context,
                  onDelete: () async {
                    // 로컬 DB에서 삭제
                    await DBHelper().deleteChatRoom(room.id);
                    // 목록 새로고침
                    await _loadChatRooms();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('대화방이 삭제되었습니다.')),
                      );
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

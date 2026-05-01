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
          } catch (e) {
            debugPrint("방 존재: \$e");
          } // 이미 존재하면 무시
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
          } catch (e) {
            debugPrint("방 존재: \$e");
          }
          _loadChatRooms();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${data['inviter_id']}님이 초대하셨습니다!")),
            );
          }
        } else if (data['content'] != null && data['room_id'] != null) {
          // Save incoming message to DB and update list
          final incomingMsg = Message(
            text: data['content'] ?? "",
            sender: data['sender_nickname'] ?? data['sender_id'] ?? "unknown",
            timestamp: DateTime.parse(data['timestamp'] ?? DateTime.now().toIso8601String()),
          );
          await DBHelper().insertMessage(data['room_id'], incomingMsg);
          _loadChatRooms(); // Update UI list
        }
      });
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  // Load Local Data
  Future<void> _loadChatRooms() async {
    // Show local data only if user is logged in
    if (AppStyle.myLoggedInId == null) return;

    // Fetch from local DB
    final rooms = await DBHelper().getChatRooms();

    setState(() {
      _chatRooms.clear();
      _chatRooms.addAll(rooms);
      // Sort by recent message time
      _chatRooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  // Create New Chat Room (Local)
  void _createNewChat(String title, String relation) async {
    final newRoom = ChatRoom(
      // Generate unique string ID
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      relation: relation,
      lastMessageTime: DateTime.now(),
      messages: [],
    );

    try {
      // Save to local DB
      await DBHelper().insertChatRoom(newRoom);

      // Update UI
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
    // Tab pages
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

  // Chat Room Options (Edit/Delete)
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
                    // Update memory data
                    setState(() {
                      room.title = newTitle;
                      room.relation = newRelation;
                    });
                    // Update local DB
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
                    // Delete from local DB
                    await DBHelper().deleteChatRoom(room.id);
                    // Refresh list
                    await _loadChatRooms();

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('대화방이 삭제되었습니다.')),
                    );
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

import 'package:flutter/material.dart';
import '../models/chat_room.dart';
import '../constants/app_style.dart';
import '../widgets/chat_dialogs.dart';
import 'tabs/profile_tab.dart';
import 'tabs/chat_list_tab.dart';
import 'tabs/ai_settings_tab.dart';
import '../services/db_helper.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<ChatRoom> _chatRooms = [];

  @override
  void initState() {
    super.initState();
    _loadChatRooms(); // 앱 시작 시 DB 로드
  }

// DB에서 데이터 불러오기
  Future<void> _loadChatRooms() async {
    final rooms = await DBHelper().getChatRooms();
    setState(() {
      _chatRooms.clear();
      _chatRooms.addAll(rooms);
    });
  }

  void _createNewChat(String title, String relation) async {
    final newRoom = ChatRoom(
      id: DateTime.now().toString(),
      title: title,
      relation: relation,
      lastMessageTime: DateTime.now(),
      messages: [],
    );

    await DBHelper().insertChatRoom(newRoom);

    setState(() {
      _chatRooms.add(newRoom);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 현재 선택된 탭에 따라 보여줄 화면 결정
    final List<Widget> pages = [
      const ProfileTab(),
      ChatListTab(
        chatRooms: _chatRooms,
        onLongPress: (index) => _showChatOptions(index),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('OPEN SW TEMP PROJECT', style: AppStyle.appBarTitleStyle),
        backgroundColor: AppStyle.primaryBlue,
        elevation: 2,
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '프로필'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '채팅'),
        ],
      ),
    );
  }

  // _showChatOptions와 _showEditTitleDialog는 여기에 그대로 두거나 별도 믹스인으로 뺄 수 있습니다.
  void _showChatOptions(int index) {
    final room = _chatRooms[index];
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppStyle.primaryBlue),
              title: const Text('채팅방 정보 수정'),
              onTap: () {
                Navigator.pop(context);
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (context.mounted) {
                    ChatDialogs.showEditChatDialog(
                      context: context,
                      initialTitle: room.title,
                      initialRelation: room.relation,
                      onSave: (newTitle, newRelation) async {
                        setState(() {
                          room.title = newTitle;
                          room.relation = newRelation;
                        });
                        await DBHelper().updateChatRoom(room);
                      },
                    );
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('채팅방 삭제'),
              onTap: () {
                Navigator.pop(context); // BottomSheet 닫기
                ChatDialogs.showDeleteDialog(
                  context: context,
                  onDelete: () async {
                    // 1. DB에서 먼저 삭제 (비동기)
                    await DBHelper().deleteChatRoom(room.id);

                    // 2. 메모리(UI) 리스트에서 제거 후 화면 갱신
                    setState(() {
                      _chatRooms.removeAt(index);
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('채팅방이 삭제되었습니다.')),
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
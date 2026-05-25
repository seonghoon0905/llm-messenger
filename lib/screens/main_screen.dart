import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../constants/app_style.dart';
import '../widgets/chat_dialogs.dart';
import 'tabs/profile_tab.dart';
import 'tabs/chat_list_tab.dart';
import 'tabs/settings_tab.dart';
import '../services/db_helper.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<ChatRoom> _chatRooms = [];
  StreamSubscription? _socketSubscription;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    // WebSocket은 동기화 완료 후 연결해야 중복 삽입 경쟁 없음
    _syncInitialData().then((_) {
      if (!mounted) return;
      if (AppStyle.myLoggedInId != null) {
        AppStyle.connectSocket(AppStyle.myLoggedInId!);
      }
      _initGlobalSocket();
    });
  }

  Future<void> _syncInitialData() async {
    await _syncRoomsFromServer();
    await _syncFriendsFromServer();
    await _syncMissedMessages();
    await _loadChatRooms();
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
            relation: roomData['relation'] ?? '기타',
            lastMessage: "채팅방에 참여했습니다.",
            lastMessageTime: DateTime.now(),
          );
          // 기존 방 데이터(lastMessageTime 등)를 덮어쓰지 않음
          await DBHelper().insertChatRoomIfAbsent(serverRoom);
        }
      }
    } catch (e) {
      debugPrint("서버 동기화 실패: $e");
    }
  }

  Future<void> _syncMissedMessages() async {
    if (AppStyle.myLoggedInId == null) return;
    final myId = AppStyle.myLoggedInId!;
    final rooms = await DBHelper().getChatRooms();
    for (final room in rooms) {
      try {
        // 로컬 DB에서 가장 최근 메시지 타임스탬프 조회
        final localMessages = await DBHelper().getMessages(room.id);
        String? since;
        if (localMessages.isNotEmpty) {
          final latest = localMessages
              .map((m) => m.timestamp)
              .reduce((a, b) => a.isAfter(b) ? a : b);
          since = latest.toIso8601String();
        }

        final uri = since != null
            ? Uri.parse(
                "${AppStyle.baseUrl}/rooms/${room.id}/messages?since=${Uri.encodeComponent(since)}")
            : Uri.parse("${AppStyle.baseUrl}/rooms/${room.id}/messages");

        final response = await http.get(uri);
        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body);
        final serverMsgs = data['messages'] as List<dynamic>? ?? [];

        for (final raw in serverMsgs) {
          final senderId = raw['sender_id'] as String? ?? '';
          if (senderId == myId) continue; // 내가 보낸 메시지는 이미 로컬에 있음

          final msg = Message(
            text: raw['content'] as String? ?? '',
            sender: raw['sender_nickname'] as String? ?? senderId,
            timestamp: DateTime.tryParse(raw['timestamp'] as String? ?? '') ??
                DateTime.now(),
            isRead: false,
          );
          await DBHelper().insertMessageIfAbsent(room.id, msg);
          await DBHelper().upsertIncomingChatRoom(
            roomId: room.id,
            title: room.title,
            relation: room.relation,
            timestamp: msg.timestamp,
            incrementUnread: true,
          );
        }
      } catch (e) {
        debugPrint("누락 메시지 동기화 실패 (${room.id}): $e");
      }
    }
  }

  Future<void> _syncFriendsFromServer() async {
    if (AppStyle.myLoggedInId == null) return;
    try {
      final friends = await _apiService.fetchFriends(AppStyle.myLoggedInId!);
      for (final friend in friends) {
        await DBHelper().insertFriend(
          UserProfile(
            userId: friend['user_id'] as String? ?? '',
            name: friend['nickname'] as String? ?? friend['user_id'] as String? ?? '',
            statusMessage: friend['status_message'] as String? ?? "상태 메시지가 없습니다.",
          ),
        );
      }
    } catch (e) {
      debugPrint("친구 동기화 실패: $e");
    }
  }

  void _initGlobalSocket() {
    if (AppStyle.globalStream != null) {
      _socketSubscription = AppStyle.globalStream!.listen((message) async {
        final data = jsonDecode(message);
        if (data['type'] == 'INVITE_EVENT') {
          final myId = AppStyle.myLoggedInId ?? 'me';
          final inviterId = data['inviter_id'] as String? ?? '';
          final roomId = data['room_id'] as String;
          final newRoom = ChatRoom(
            id: roomId,
            title: data['room_title'],
            relation: data['relation'] ?? "기타",
            lastMessageTime: DateTime.now(),
            lastMessage: "$inviterId님이 초대하셨습니다.",
            memberIds: [myId, if (inviterId.isNotEmpty) inviterId],
          );
          await DBHelper().insertChatRoomIfAbsent(newRoom);
          // 기존 방이 있으면 초대자 추가
          final existing = await DBHelper().getChatRoomById(roomId);
          if (existing != null && inviterId.isNotEmpty && !existing.memberIds.contains(inviterId)) {
            final ids = [...existing.memberIds, inviterId];
            await DBHelper().updateRoomMembers(roomId, ids);
          }
          _loadChatRooms();
          if (mounted) {
            // 친구 DB에서 닉네임 조회, 없으면 ID 사용
            final friends = await DBHelper().getFriends();
            final inviterName = friends
                    .where((f) => f.userId == inviterId)
                    .map((f) => f.name)
                    .firstOrNull ??
                inviterId;
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("$inviterName님이 초대하셨습니다!")),
              );
            }
          }
        } else if (data['type'] == 'FRIEND_EVENT') {
          final friend = UserProfile(
            userId: data['user_id'] ?? '',
            name: data['nickname'] ?? data['user_id'] ?? '',
            statusMessage: data['status_message'] ?? "상태 메시지가 없습니다.",
          );
          await DBHelper().insertFriend(friend);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("${friend.name}님이 친구 목록에 추가되었습니다.")),
            );
          }
        } else if (data['type'] == 'EDIT_EVENT') {
          final roomId = data['room_id'] as String? ?? '';
          final msgTimestamp = data['msg_timestamp'] as String? ?? '';
          final newText = data['new_text'] as String? ?? '';
          if (roomId.isNotEmpty && msgTimestamp.isNotEmpty) {
            await DBHelper().editMessageByTimestamp(roomId, msgTimestamp, newText);
          }
        } else if (data['type'] == 'DELETE_EVENT') {
          final roomId = data['room_id'] as String? ?? '';
          final msgTimestamp = data['msg_timestamp'] as String? ?? '';
          if (roomId.isNotEmpty && msgTimestamp.isNotEmpty) {
            await DBHelper().deleteMessageByTimestamp(roomId, msgTimestamp);
          }
        } else if (data['type'] == 'MEMBER_JOINED') {
          final roomId = data['room_id'] as String? ?? '';
          final userId = data['user_id'] as String? ?? '';
          final nickname = data['nickname'] as String? ?? userId;
          if (roomId.isNotEmpty && userId.isNotEmpty) {
            final room = await DBHelper().getChatRoomById(roomId);
            if (room != null && !room.memberIds.contains(userId)) {
              await DBHelper().updateRoomMembers(roomId, [...room.memberIds, userId]);
            }
            // 채팅방이 열려 있으면 chat_screen.dart가 처리하므로 중복 삽입 방지
            if (AppStyle.currentOpenRoomId != roomId) {
              final sysMsg = Message(
                text: '$nickname님이 입장하셨습니다.',
                sender: '__system__',
                timestamp: DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now(),
              );
              await DBHelper().insertMessage(roomId, sysMsg);
            }
            _loadChatRooms();
          }
        } else if (data['content'] != null && data['room_id'] != null) {
          final roomId = data['room_id'] as String;
          final timestamp = DateTime.parse(
            data['timestamp'] ?? DateTime.now().toIso8601String(),
          );
          final shouldIncrementUnread = AppStyle.currentOpenRoomId != roomId;
          await DBHelper().upsertIncomingChatRoom(
            roomId: roomId,
            title: data['room_title'] ?? data['sender_nickname'] ?? data['sender_id'] ?? roomId,
            relation: data['relation'] ?? '기타',
            timestamp: timestamp,
            incrementUnread: shouldIncrementUnread,
          );
          // 채팅방이 열려 있으면 chat_screen.dart가 이미 메시지를 삽입하므로 중복 방지
          if (AppStyle.currentOpenRoomId != roomId) {
            final incomingMsg = Message(
              text: data['content'] ?? "",
              sender: data['sender_nickname'] ?? data['sender_id'] ?? "unknown",
              timestamp: timestamp,
            );
            await DBHelper().insertMessage(roomId, incomingMsg);
          }
          _loadChatRooms();
        }
      });
    }
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadChatRooms() async {
    if (AppStyle.myLoggedInId == null) return;
    final rooms = await DBHelper().getChatRooms();
    setState(() {
      _chatRooms.clear();
      _chatRooms.addAll(rooms);
      _chatRooms.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      ProfileTab(onRoomsChanged: _loadChatRooms),
      ChatListTab(
        chatRooms: _chatRooms,
        onLongPress: (index) => _showChatOptions(index),
        onReturnFromChat: () => _loadChatRooms(),
      ),
      SettingsTab(onLogout: _handleLogout),
    ];

    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      body: pages[_selectedIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppStyle.divider, width: 0.5)),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) =>
              setState(() => _selectedIndex = index),
          backgroundColor: AppStyle.surface,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          height: 64,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded, size: 24),
              selectedIcon: Icon(Icons.people_rounded, size: 24),
              label: '친구',
            ),
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded, size: 24),
              selectedIcon: Icon(Icons.chat_bubble_rounded, size: 24),
              label: '채팅',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined, size: 24),
              selectedIcon: Icon(Icons.settings_rounded, size: 24),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    AppStyle.disconnectSocket();
    AppStyle.globalStream = null;
    AppStyle.myLoggedInId = null;
    AppStyle.myProfile = null;
    await DBHelper.closeAndReset();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showChatOptions(int index) {
    final room = _chatRooms[index];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppStyle.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppStyle.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_rounded,
                      color: AppStyle.primary, size: 20),
                ),
                title: const Text('채팅방 정보 수정',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
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
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.exit_to_app_rounded,
                      color: Colors.orange, size: 20),
                ),
                title: const Text('채팅방 나가기',
                    style: TextStyle(
                        color: Colors.orange, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('채팅방 나가기',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      content: const Text('채팅방을 나가면 대화 내용이 모두 삭제됩니다.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final leavePacket = {
                              "type": "LEAVE",
                              "room_id": room.id,
                              "timestamp": DateTime.now().toIso8601String(),
                            };
                            AppStyle.channel?.sink
                                .add(jsonEncode(leavePacket));
                            await DBHelper().deleteChatRoom(room.id);
                            await _loadChatRooms();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('채팅방을 나갔습니다.')),
                            );
                          },
                          child: const Text('나가기',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                },
              ),
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.delete_rounded,
                      color: Colors.redAccent, size: 20),
                ),
                title: const Text('채팅방 삭제 (로컬)',
                    style: TextStyle(
                        color: Colors.redAccent, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  ChatDialogs.showDeleteDialog(
                    context: context,
                    onDelete: () async {
                      await DBHelper().deleteChatRoom(room.id);
                      await _loadChatRooms();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('대화방이 삭제되었습니다.')),
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

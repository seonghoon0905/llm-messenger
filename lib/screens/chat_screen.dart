import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../models/message.dart';
import '../models/chat_room.dart';
import '../models/user_profile.dart';
import '../widgets/profile_modal.dart';
import '../services/log_parser.dart';
import '../services/db_helper.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final ChatRoom chatRoom;
  const ChatScreen({super.key, required this.chatRoom});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription? _socketSubscription;
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _displayMessages = [];
  bool _isLoading = true;
  bool _isAiPanelOpen = false;
  List<UserProfile> _participants = [];

  @override
  void initState() {
    super.initState();
    _loadMessagesFromLocal().then((_) => _syncMessagesFromServer());
    _connectSocket();

    if (AppStyle.myProfile != null) {
      _participants.add(AppStyle.myProfile!);
    }
  }

  Future<void> _syncMessagesFromServer() async {
    try {
      final response = await http.get(Uri.parse("${AppStyle.baseUrl}/rooms/${widget.chatRoom.id}/messages"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final serverMsgs = data['messages'] as List;
          final localMsgs = await DBHelper().getMessages(widget.chatRoom.id);
          
          bool hasNew = false;
          for (var sm in serverMsgs) {
            final text = sm['content'];
            final isMyMessage = sm['sender_id'] == AppStyle.myLoggedInId;
            final sender = isMyMessage ? 'me' : (sm['sender_nickname'] ?? sm['sender_id']);
            final timestamp = sm['timestamp'];
            
            bool exists = localMsgs.any((m) => 
               m.text == text && m.sender == sender && m.timestamp.toIso8601String() == timestamp
            );
            
            if (!exists) {
              final newMsg = Message(
                 text: text ?? "", 
                 sender: sender ?? "unknown", 
                 timestamp: DateTime.parse(timestamp ?? DateTime.now().toIso8601String())
              );
              await DBHelper().insertMessage(widget.chatRoom.id, newMsg);
              hasNew = true;
            }
          }
          if (hasNew) {
            await _loadMessagesFromLocal();
          }
        }
      }
    } catch(e) {
      debugPrint("메시지 동기화 에러: $e");
    }
  }

  // 🔌 [소켓 수신 대기]
  void _connectSocket() {
    try {
      _socketSubscription = AppStyle.globalStream?.listen(
        (message) {
          final data = jsonDecode(message);

          if (data['type'] == 'INVITE_EVENT') return;
          if (data['room_id'] != null && data['room_id'] != widget.chatRoom.id) return;

          final incomingMsg = Message(
            text: data['content'] ?? "",
            sender: data['sender_nickname'] ?? data['sender_id'] ?? "unknown",
            timestamp: DateTime.parse(
              data['timestamp'] ?? DateTime.now().toIso8601String(),
            ),
          );

          // 로컬 DB 저장은 MainScreen의 전역 리스너에서 처리하므로 여기서는 생략
          // UI만 업데이트합니다.
          if (mounted) {
            setState(() {
              _displayMessages.insert(0, incomingMsg);
            });
          }
        },
        onError: (error) {
          debugPrint("소켓 에러: $error");
        },
      );
    } catch (e) {
      debugPrint("소켓 리스너 등록 실패: $e");
    }
  }

  // 📥 [로컬 메시지 로드]
  Future<void> _loadMessagesFromLocal() async {
    try {
      final messages = await DBHelper().getMessages(widget.chatRoom.id);
      if (mounted) {
        setState(() {
          _displayMessages = messages.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("로컬 메시지 로드 에러: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 📤 [메시지 전송 - 소켓 방식]
  void _handleSend() async {
    if (_controller.text.trim().isEmpty) return;

    final text = _controller.text.trim();
    final timestamp = DateTime.now();

    // 1. 소켓 패킷 생성 (서버 ConnectionManager의 수신 형식에 맞춤)
    final msgPacket = {
      "receiver_id": widget.chatRoom.id, // 채팅방 ID가 곧 상대방 ID인 경우
      "content": text,
      "timestamp": timestamp.toIso8601String(),
    };

    // 2. 서버로 소켓 전송
    AppStyle.channel?.sink.add(jsonEncode(msgPacket));

    // 3. 내 화면에 표시할 메시지 객체 생성
    final myMsg = Message(text: text, sender: 'me', timestamp: timestamp);

    // 4. 로컬 DB 저장
    await DBHelper().insertMessage(widget.chatRoom.id, myMsg);

    if (mounted) {
      setState(() {
        _displayMessages.insert(0, myMsg);
        _controller.clear();
      });
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // 👤 [프로필 조회]
  Future<void> _showProfile(String senderName) async {
    // 1. '나'의 프로필인 경우
    if (senderName == "me" || senderName == AppStyle.myLoggedInId) {
      if (context.mounted) {
        ProfileModal.show(
          context,
          AppStyle.myProfile ??
              UserProfile(
                userId: AppStyle.myLoggedInId ?? "unknown",
                name: AppStyle.myLoggedInId ?? "나",
                statusMessage: "정보를 불러오는 중...",
              ),
        );
      }
      return;
    }

    // 2. 친구인 경우 (로컬 DB에서 검색)
    try {
      final friends = await DBHelper().getFriends();
      final friend = friends.firstWhere(
        (f) => f.name == senderName,
        orElse: () => UserProfile(userId: senderName, name: senderName),
      );

      if (mounted) {
        ProfileModal.show(context, friend);
      }
    } catch (e) {
      debugPrint("프로필 조회 에러: $e");
    }
  }

  Future<void> _uploadKakaoLog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (result != null) {
      setState(() => _isLoading = true);
      try {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        String myName = AppStyle.myProfile?.name ?? "나";
        List<Message> parsedMsgs = LogParser.parseKakaoLog(content, myName);

        if (parsedMsgs.isEmpty) return;

        for (var msg in parsedMsgs) {
          await DBHelper().insertMessage(widget.chatRoom.id, msg);
        }
        await _loadMessagesFromLocal();
      } catch (e) {
        debugPrint("로그 업로드 에러: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showInviteDialog() async {
    final friends = await DBHelper().getFriends();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("친구 초대하기"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: friends.isEmpty
              ? const Center(child: Text("초대할 수 있는 친구가 없습니다."))
              : ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text(friend.name),
                      subtitle: Text("@${friend.userId}"),
                      onTap: () {
                        bool isAlreadyIn = _participants.any(
                          (p) => p.userId == friend.userId,
                        );

                        if (!isAlreadyIn) {
                          final timestamp = DateTime.now().toIso8601String();

                          setState(() {
                            _participants.add(friend);
                          });

                          // 💡 패킷을 하나로 합쳐서 한 번만 전송합니다.
                          final invitePacket = {
                            "type": "INVITE",
                            "room_id": widget.chatRoom.id,
                            "invitee_id": friend.userId,
                            "room_title": widget.chatRoom.title,
                            "relation":
                                widget.chatRoom.relation ?? "기타", // 관계 태그 포함
                            "timestamp": timestamp,
                          };

                          AppStyle.channel?.sink.add(jsonEncode(invitePacket));
                          debugPrint("✅ 초대 패킷 전송: $invitePacket");
                        }

                        Navigator.pop(ctx);
                        _showInviteSuccess(friend.name);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
        ],
      ),
    );
  }

  void _showInviteSuccess(String name) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$name님을 채팅방에 초대했습니다.")));
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- [ UI 빌드 부분 ] ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.inputBgColor,
      appBar: AppBar(
        title: Text(
          widget.chatRoom.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _uploadKakaoLog,
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: _buildChatDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: _displayMessages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageBubble(_displayMessages[index]),
                  ),
                ),
                _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(Message msg) {
    bool isMe = msg.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppStyle.verticalPadding),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => _showProfile(msg.sender),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey[300],
                child: Icon(Icons.person, color: Colors.grey[700], size: 20),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      msg.sender,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe
                        ? AppStyle.myBubbleColor
                        : AppStyle.otherBubbleColor,
                    borderRadius: BorderRadius.circular(AppStyle.borderRadius),
                  ),
                  child: Text(
                    msg.text,
                    style: isMe
                        ? AppStyle.myChatTextStyle
                        : AppStyle.chatTextStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isAiPanelOpen ? 130 : 0,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: _isAiPanelOpen
                ? [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ]
                : [],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              children: [
                _buildAiOptionButton(
                  "💬 대화 피드백 받기",
                  Icons.auto_awesome_motion,
                  () {},
                ),
                const SizedBox(height: 10),
                _buildAiOptionButton(
                  "✨ 자동 응답 생성",
                  Icons.psychology_outlined,
                  () {},
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.black12)),
          ),
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.auto_awesome,
                    color: _isAiPanelOpen ? AppStyle.primaryBlue : Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _isAiPanelOpen = !_isAiPanelOpen),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      fillColor: AppStyle.inputBgColor,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: AppStyle.primaryBlue,
                    child: Icon(
                      Icons.arrow_upward,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onPressed: _handleSend,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAiOptionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppStyle.primaryBlue.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppStyle.primaryBlue),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppStyle.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "대화 상대",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _participants.length,
                itemBuilder: (context, index) {
                  return _buildDrawerUserTile(_participants[index]);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add, color: AppStyle.primaryBlue),
              title: const Text(
                "대화 상대 초대",
                style: TextStyle(color: AppStyle.primaryBlue),
              ),
              onTap: _showInviteDialog,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerUserTile(UserProfile user) {
    return ListTile(
      leading: const CircleAvatar(
        radius: 15,
        backgroundColor: AppStyle.primaryBlue,
        child: Icon(Icons.person, size: 18, color: Colors.white), // 이모지 대신 아이콘
      ),
      title: Text(user.name, style: const TextStyle(fontSize: 14)),
    );
  }
}

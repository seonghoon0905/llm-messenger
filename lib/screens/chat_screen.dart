import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../models/message.dart';
import '../models/chat_room.dart';
import '../models/user_profile.dart';
import '../widgets/profile_modal.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_area.dart';
import '../widgets/chat_drawer.dart';
import '../services/log_parser.dart';
import '../services/db_helper.dart';
import '../services/llm_assist_service.dart';
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
  bool _isAssistLoading = false;
  String? _assistError;
  LlmAssistResponse? _assistResponse;
  final List<UserProfile> _participants = [];
  final LlmAssistService _llmAssistService = LlmAssistService();

  @override
  void initState() {
    super.initState();
    _loadMessagesFromLocal();
    _connectSocket();

    if (AppStyle.myProfile != null) {
      _participants.add(AppStyle.myProfile!);
    }
  }

  // Socket Listener
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

          // UI Update
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

  // Load Local Messages
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

  // Send Message via Socket
  void _handleSend() async {
    if (_controller.text.trim().isEmpty) return;

    final text = _controller.text.trim();
    final timestamp = DateTime.now();

    // 1. Create socket packet
    final msgPacket = {
      "receiver_id": widget.chatRoom.id, // Chat room ID
      "content": text,
      "timestamp": timestamp.toIso8601String(),
    };

    // 2. Send via socket
    AppStyle.channel?.sink.add(jsonEncode(msgPacket));

    // 3. Create message object for UI
    final myMsg = Message(text: text, sender: 'me', timestamp: timestamp);

    // 4. Save to local DB
    await DBHelper().insertMessage(widget.chatRoom.id, myMsg);

    if (mounted) {
      setState(() {
        _displayMessages.insert(0, myMsg);
        _controller.clear();
        _assistError = null;
        _assistResponse = null;
      });
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _requestFeedback() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty) {
      setState(() {
        _assistError = "먼저 초안을 입력해주세요.";
        _assistResponse = null;
      });
      return;
    }

    final recentMessages = _displayMessages.reversed
        .take(6)
        .map(
          (message) => AssistRecentMessage(
            role: message.isMe ? 'me' : 'partner',
            text: message.text,
          ),
        )
        .toList();

    final partnerLastMessage = _displayMessages
        .where((message) => !message.isMe)
        .map((message) => message.text)
        .cast<String?>()
        .firstWhere((text) => text != null, orElse: () => null) ??
        "";

    setState(() {
      _isAssistLoading = true;
      _assistError = null;
      _assistResponse = null;
    });

    try {
      final response = await _llmAssistService.requestFeedback(
        recentMessages: recentMessages,
        partnerLastMessage: partnerLastMessage,
        draft: draft,
      );
      if (!mounted) return;
      setState(() {
        _assistResponse = response;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assistError = "피드백을 불러오지 못했습니다: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          _isAssistLoading = false;
        });
      }
    }
  }

  void _applyRewrite() {
    final rewrite = _assistResponse?.rewrite;
    if (rewrite == null || rewrite.trim().isEmpty) return;
    _controller.text = rewrite;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {
      _assistError = null;
    });
  }

  // Show Profile
  Future<void> _showProfile(String senderName) async {
    // 1. If it's me
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

    // 2. If it's a friend (Search in local DB)
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

                          // Send single packet
                          final invitePacket = {
                            "type": "INVITE",
                            "room_id": widget.chatRoom.id,
                            "invitee_id": friend.userId,
                            "room_title": widget.chatRoom.title,
                            "relation": widget.chatRoom.relation,
                            "timestamp": timestamp,
                          };

                          AppStyle.channel?.sink.add(jsonEncode(invitePacket));
                          debugPrint("Invite packet sent: $invitePacket");
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

  // Build UI

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
      endDrawer: ChatDrawer(
        participants: _participants,
        onInvite: _showInviteDialog,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    itemCount: _displayMessages.length,
                    itemBuilder: (context, index) => ChatMessageBubble(
                      message: _displayMessages[index],
                      onShowProfile: _showProfile,
                    ),
                  ),
                ),
                ChatInputArea(
                  controller: _controller,
                  onSend: _handleSend,
                  onRequestFeedback: _requestFeedback,
                  onApplyRewrite: _applyRewrite,
                  isFeedbackLoading: _isAssistLoading,
                  feedbackError: _assistError,
                  feedbackResult: _assistResponse,
                ),
              ],
            ),
    );
  }

}

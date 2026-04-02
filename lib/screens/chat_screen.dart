import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/log_parser.dart';
import '../services/db_helper.dart';
import '../models/message.dart';
import '../models/chat_room.dart';
import '../models/user_profile.dart';
import '../constants/app_style.dart';
import '../widgets/profile_modal.dart';

class ChatScreen extends StatefulWidget {
  final ChatRoom chatRoom;

  const ChatScreen({super.key, required this.chatRoom});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _displayMessages = [];
  bool _isLoading = true;
  bool _isAiPanelOpen = false; // AI 패널 표시 여부

  // 임시 더미 사용자 데이터 (이성훈 외의 사람은 기본 프로필로 처리)
  final Map<String, UserProfile> _mockUsers = {
    "이성훈": UserProfile(
        name: "이성훈",
        avatar: "👨‍💻",
        statusMessage: "코딩 중...",
        isSharingPersonality: true,
        characterAction: "🙌",
        characterDesc: "협조적이고 주도적인 리더",
        personalityStats: {'dominance': 70.0, 'affiliation': 85.0}
    ),
  };

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final msgs = await DBHelper().getMessages(widget.chatRoom.id);
    setState(() {
      _displayMessages = msgs.reversed.toList();
      _isLoading = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() async {
    if (_controller.text
        .trim()
        .isEmpty) return;

    final newMessage = Message(
      text: _controller.text,
      sender: 'me',
    );

    await DBHelper().insertMessage(widget.chatRoom.id, newMessage);

    setState(() {
      _displayMessages.insert(0, newMessage);
    });
    _controller.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chatRoom.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: '카톡 로그 불러오기',
            onPressed: () async {
              // 네이티브 창 띄울 때 마우스 충돌 방지용 짧은 대기
              await Future.delayed(const Duration(milliseconds: 100));

              FilePickerResult? result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['txt'],
              );

              if (result != null) {
                setState(() => _isLoading = true);

                try {
                  File file = File(result.files.single.path!);
                  String content = await file.readAsString();

                  // ★ LogParser에 본인 이름 전달하여 'me'로 변환
                  List<Message> newMessages = LogParser.parseKakaoLog(
                      content, "이성훈");

                  for (var msg in newMessages) {
                    await DBHelper().insertMessage(widget.chatRoom.id, msg);
                  }

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(
                          '${newMessages.length}개의 메시지를 가져왔습니다!')),
                    );
                    _loadMessages();
                  }
                } catch (e) {
                  print("파일 읽기 에러: $e");
                } finally {
                  setState(() => _isLoading = false);
                }
              }
            },
          ),
        ],
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
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment
            .start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 상대방일 경우 프로필 아바타 표시 및 모달 연결
          if (!isMe) ...[
            GestureDetector(
              onTap: () {
                final user = _mockUsers[msg.sender] ?? UserProfile(
                  name: msg.sender,
                  avatar: "👤",
                  isSharingPersonality: false,
                );

                // 모달 띄울 때 마우스 충돌 방지
                Future.microtask(() {
                  if (context.mounted) ProfileModal.show(context, user);
                });
              },
              child: const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey,
                child: Icon(Icons.person, color: Colors.white, size: 20),
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
                    child: Text(msg.sender, style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? AppStyle.myBubbleColor : AppStyle
                        .otherBubbleColor,
                    borderRadius: BorderRadius.circular(AppStyle.borderRadius),
                  ),
                  child: Text(
                    msg.text,
                    style: isMe ? AppStyle.myChatTextStyle : AppStyle
                        .chatTextStyle,
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
        // --- [ 1. AI 에이전트 옵션 패널 ] ---
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: _isAiPanelOpen ? 130 : 0,
          // 높이를 적절히 조절
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: _isAiPanelOpen
                ? [
              BoxShadow(color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2))
            ]
                : [],
          ),
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Column(
              children: [
                _buildAiOptionButton(
                    "💬 대화 피드백 받기", Icons.auto_awesome_motion, () {
                  // TODO: 현재 입력된 텍스트(_controller.text) 분석 로직 연결
                  print("피드백 요청: ${_controller.text}");
                }),
                const SizedBox(height: 10),
                _buildAiOptionButton(
                    "✨ 자동 응답 생성", Icons.psychology_outlined, () {
                  // TODO: 상대방의 마지막 메시지 기반 응답 생성 로직 연결
                  print("자동 응답 생성 요청");
                }),
              ],
            ),
          ),
        ),

        // --- [ 2. 메시지 입력창 메인 영역 ] ---
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppStyle.horizontalPadding / 2,
            vertical: AppStyle.verticalPadding,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                offset: const Offset(0, -1),
                blurRadius: 4,
              ),
            ],
          ),
          child: SafeArea(
            child: Row(
              children: [
                const SizedBox(width: 8),
                // ★ AI 에이전트 실행 버튼 (별 아이콘)
                IconButton(
                  icon: Icon(
                    Icons.auto_awesome,
                    color: _isAiPanelOpen ? AppStyle.primaryBlue : Colors
                        .grey[600],
                    size: 26,
                  ),
                  onPressed: () =>
                      setState(() => _isAiPanelOpen = !_isAiPanelOpen),
                ),

                const SizedBox(width: 4),

                // 텍스트 필드
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: AppStyle.chatTextStyle,
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: AppStyle.chatTextStyle.copyWith(
                          color: Colors.grey),
                      fillColor: AppStyle.inputBgColor,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppStyle.horizontalPadding,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),

                const SizedBox(width: 4),

                // 전송 버튼 (종이비행기 또는 화살표)
                IconButton(
                  icon: const CircleAvatar(
                    backgroundColor: AppStyle.primaryBlue,
                    radius: 18,
                    child: Icon(
                        Icons.arrow_upward, color: Colors.white, size: 20),
                  ),
                  onPressed: _handleSend,
                ),
                const SizedBox(width: 4),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppStyle.primaryBlue.withOpacity(0.3)),
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
}
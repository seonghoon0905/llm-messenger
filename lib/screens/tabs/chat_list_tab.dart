import 'package:flutter/material.dart';
import '../../constants/app_style.dart';
import '../../models/chat_room.dart';
import '../../widgets/chat_list_tile.dart';
import '../chat_screen.dart';

class ChatListTab extends StatelessWidget {
  final List<ChatRoom> chatRooms;
  final Function(int) onLongPress;
  final VoidCallback onReturnFromChat;

  const ChatListTab({
    super.key,
    required this.chatRooms,
    required this.onLongPress,
    required this.onReturnFromChat,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: chatRooms.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.only(top: 8, bottom: 80),
                      itemCount: chatRooms.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 1),
                      itemBuilder: (context, index) {
                        final room = chatRooms[index];
                        return ChatListTile(
                          room: room,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChatScreen(chatRoom: room),
                              ),
                            );
                            onReturnFromChat();
                          },
                          onLongPress: () => onLongPress(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppStyle.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: const Row(
        children: [
          Text(
            '채팅',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppStyle.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppStyle.primaryLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 38,
              color: AppStyle.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '아직 대화방이 없어요',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppStyle.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '+ 버튼을 눌러 새 대화를 시작해보세요',
            style: TextStyle(
              fontSize: 14,
              color: AppStyle.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

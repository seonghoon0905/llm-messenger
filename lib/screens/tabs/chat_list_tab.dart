import 'package:flutter/material.dart';
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
    if (chatRooms.isEmpty) return _buildEmptyState();

    return ListView.separated(
      itemCount: chatRooms.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final room = chatRooms[index];
        return ChatListTile(
          room: room,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(chatRoom: room),
              ),
            );
            onReturnFromChat();
          },
          onLongPress: () => onLongPress(index),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            '아직 대화방이 없습니다.\n우측 하단 + 버튼을 눌러 시작하세요!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
        ],
      ),
    );
  }
}

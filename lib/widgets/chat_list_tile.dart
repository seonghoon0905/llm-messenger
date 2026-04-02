import 'package:flutter/material.dart';
import '../models/chat_room.dart';

class ChatListTile extends StatelessWidget {
  final ChatRoom room;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const ChatListTile({
    super.key,
    required this.room,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(
        child: Icon(Icons.person_outline),
      ),
      title: Text(
        room.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        room.messages.isEmpty ? '대화 내용이 없습니다.' : room.messages.last.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Spacer(),
          Text(
            room.relation,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
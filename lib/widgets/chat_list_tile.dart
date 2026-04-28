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
        backgroundColor: Colors.blueAccent,
        child: Icon(Icons.person, color: Colors.white),
      ),
      title: Text(
        room.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),

      subtitle: Text(
        (room.lastMessage == null || room.lastMessage!.isEmpty)
            ? '대화 내용이 없습니다.'
            : room.lastMessage!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, color: Colors.black54),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            room.relation,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

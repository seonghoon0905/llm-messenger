import 'package:flutter/material.dart';
import '../constants/app_style.dart';
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
    final avatarColor = AppStyle.getAvatarColor(room.title);
    final initial = AppStyle.getInitial(room.title);
    final timeStr = AppStyle.formatChatListTime(room.lastMessageTime);
    final hasUnread = room.unreadCount > 0;

    return Material(
      color: AppStyle.surface,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Flexible(
                                child: Text(
                                  room.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: hasUnread
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                    color: AppStyle.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (room.memberCount > 1) ...[
                                const SizedBox(width: 4),
                                Text(
                                  '${room.memberCount}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppStyle.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: hasUnread
                                ? AppStyle.primary
                                : AppStyle.textTertiary,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (room.lastMessage == null ||
                                    room.lastMessage!.isEmpty)
                                ? '대화 내용이 없습니다.'
                                : room.lastMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: hasUnread
                                  ? AppStyle.textPrimary
                                  : AppStyle.textSecondary,
                              fontWeight: hasUnread
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (hasUnread)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppStyle.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              room.unreadCount > 99
                                  ? '99+'
                                  : '${room.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

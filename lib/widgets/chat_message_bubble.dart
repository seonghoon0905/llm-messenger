import 'package:flutter/material.dart';
import '../models/message.dart';
import '../constants/app_style.dart';

class ChatMessageBubble extends StatelessWidget {
  final Message message;
  final void Function(String sender) onShowProfile;
  final void Function(Message msg) onLongPress;
  final void Function(Message msg, String emoji) onReact;
  final String searchQuery;
  final int participantCount;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onShowProfile,
    required this.onLongPress,
    required this.onReact,
    this.searchQuery = '',
    this.participantCount = 1,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;
    final timeStr = AppStyle.formatMessageTime(message.timestamp);
    final avatarColor = AppStyle.getAvatarColor(message.sender);
    final initial = AppStyle.getInitial(message.sender);

    return GestureDetector(
      onLongPress: message.isDeleted ? null : () => onLongPress(message),
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 60 : 12,
          right: isMe ? 12 : 60,
          top: 3,
          bottom: 3,
        ),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              GestureDetector(
                onTap: () => onShowProfile(message.sender),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: avatarColor,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        message.sender,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppStyle.textSecondary,
                        ),
                      ),
                    ),
                  // Reply reference
                  if (message.replyToText != null)
                    _buildReplyReference(isMe),
                  // Bubble + time row
                  Row(
                    mainAxisAlignment:
                        isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (isMe) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // 읽지 않은 참여자 수 (카톡 스타일)
                            Builder(builder: (context) {
                              final unread = message.isRead
                                  ? 0
                                  : (participantCount - 1).clamp(0, 99);
                              if (unread > 0) {
                                return Text(
                                  '$unread',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppStyle.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            }),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppStyle.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(child: _buildBubble(isMe)),
                      if (!isMe) ...[
                        const SizedBox(width: 6),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppStyle.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Reactions
                  if (message.reactions.isNotEmpty)
                    _buildReactions(isMe),
                ],
              ),
            ),
            if (isMe) const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(bool isMe) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: message.isDeleted
            ? AppStyle.surfaceVariant
            : (isMe ? AppStyle.myBubbleColor : AppStyle.otherBubbleColor),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.block_rounded,
                    size: 14, color: AppStyle.textTertiary),
                const SizedBox(width: 6),
                const Text(
                  '삭제된 메시지입니다.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppStyle.textTertiary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          else ...[
            _buildHighlightedText(message.displayText, isMe),
            if (message.editedText != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '(수정됨)',
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.6)
                        : AppStyle.textTertiary,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHighlightedText(String text, bool isMe) {
    final baseStyle = isMe ? AppStyle.myChatTextStyle : AppStyle.chatTextStyle;
    if (searchQuery.isEmpty) {
      return Text(text, style: baseStyle);
    }
    final lower = text.toLowerCase();
    final lowerQ = searchQuery.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;
    int idx;
    while ((idx = lower.indexOf(lowerQ, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + searchQuery.length),
        style: TextStyle(
          backgroundColor: Colors.yellow.withValues(alpha: 0.7),
          color: AppStyle.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + searchQuery.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return RichText(
      text: TextSpan(children: spans, style: baseStyle),
    );
  }

  Widget _buildReplyReference(bool isMe) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : AppStyle.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white70 : AppStyle.primary,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.replyToSender == 'me'
                ? '나'
                : (message.replyToSender ?? ''),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isMe ? Colors.white : AppStyle.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            message.replyToText ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.8)
                  : AppStyle.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactions(bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        children: message.reactions.entries.map((e) {
          final emoji = e.key;
          final count = e.value.length;
          final iReacted = e.value.contains(AppStyle.myLoggedInId ?? 'me');
          return GestureDetector(
            onTap: () => onReact(message, emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: iReacted ? AppStyle.primaryLight : AppStyle.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iReacted ? AppStyle.primary : AppStyle.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 3),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          iReacted ? AppStyle.primary : AppStyle.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          const Expanded(
              child: Divider(color: AppStyle.divider, thickness: 0.5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppStyle.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppStyle.divider),
              ),
              child: Text(
                AppStyle.formatDateSeparator(date),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppStyle.textTertiary,
                ),
              ),
            ),
          ),
          const Expanded(
              child: Divider(color: AppStyle.divider, thickness: 0.5)),
        ],
      ),
    );
  }
}

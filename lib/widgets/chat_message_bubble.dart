import 'package:flutter/material.dart';
import '../models/message.dart';
import '../constants/app_style.dart';

class ChatMessageBubble extends StatelessWidget {
  final Message message;
  final void Function(String) onShowProfile;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.onShowProfile,
  });

  @override
  Widget build(BuildContext context) {
    bool isMe = message.isMe;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppStyle.verticalPadding),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () => onShowProfile(message.sender),
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
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      message.sender,
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
                    message.text,
                    style: isMe ? AppStyle.myChatTextStyle : AppStyle.chatTextStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

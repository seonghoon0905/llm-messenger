import 'message.dart';

class ChatRoom {
  final String id;
  String title;
  String relation;
  DateTime lastMessageTime;
  String? lastMessage;
  int unreadCount;
  List<String> memberIds; // 참여자 user ID 목록

  ChatRoom({
    required this.id,
    required this.title,
    required this.relation,
    required this.lastMessageTime,
    this.lastMessage,
    this.unreadCount = 0,
    List<String>? memberIds,
    List<Message>? messages,
  }) : memberIds = memberIds ?? [];

  int get memberCount => memberIds.isEmpty ? 1 : memberIds.length;
}

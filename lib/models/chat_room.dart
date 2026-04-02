import 'message.dart';

class ChatRoom {
  final String id;
  String title;
  String relation; // 관계 필드 추가
  List<Message> messages;
  DateTime lastMessageTime;

  ChatRoom({
    required this.id,
    required this.title,
    required this.relation, // 필수 인자로 변경
    this.messages = const [],
    required this.lastMessageTime,
  });
}
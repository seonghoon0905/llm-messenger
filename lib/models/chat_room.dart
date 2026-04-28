import 'message.dart';

class ChatRoom {
  final String id;
  String title;
  String relation;
  DateTime lastMessageTime;
  String? lastMessage; // 이 필드가 있어야 목록에 표시됩니다!

  ChatRoom({
    required this.id,
    required this.title,
    required this.relation,
    required this.lastMessageTime,
    this.lastMessage, // 생성자 추가
    List<Message>? messages,
  });
}

import 'dart:convert';

class Message {
  final int? id;
  final String text;
  final String sender;
  final DateTime timestamp;
  bool isRead;
  final int? replyToId;
  final String? replyToText;
  final String? replyToSender;
  Map<String, List<String>> reactions;
  bool isDeleted;
  String? editedText;

  Message({
    this.id,
    required this.text,
    required this.sender,
    DateTime? timestamp,
    this.isRead = false,
    this.replyToId,
    this.replyToText,
    this.replyToSender,
    Map<String, List<String>>? reactions,
    this.isDeleted = false,
    this.editedText,
  })  : timestamp = timestamp ?? DateTime.now(),
        reactions = reactions ?? {};

  bool get isMe => sender == 'me';

  String get displayText {
    if (isDeleted) return '삭제된 메시지입니다.';
    return editedText ?? text;
  }

  Map<String, dynamic> toDbMap(String roomId) => {
        'roomId': roomId,
        'text': text,
        'sender': sender,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead ? 1 : 0,
        'replyToId': replyToId,
        'replyToText': replyToText,
        'replyToSender': replyToSender,
        'reactions': jsonEncode(reactions),
        'isDeleted': isDeleted ? 1 : 0,
        'editedText': editedText,
      };

  factory Message.fromMap(Map<String, dynamic> m) {
    Map<String, List<String>> reactions = {};
    try {
      final raw = m['reactions'];
      if (raw != null && raw.toString().isNotEmpty && raw.toString() != '{}') {
        final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
        reactions =
            decoded.map((k, v) => MapEntry(k, List<String>.from(v as List)));
      }
    } catch (_) {}

    return Message(
      id: m['id'] as int?,
      text: m['text'] as String,
      sender: m['sender'] as String,
      timestamp: DateTime.parse(m['timestamp'] as String),
      isRead: (m['isRead'] as int? ?? 0) == 1,
      replyToId: m['replyToId'] as int?,
      replyToText: m['replyToText'] as String?,
      replyToSender: m['replyToSender'] as String?,
      reactions: reactions,
      isDeleted: (m['isDeleted'] as int? ?? 0) == 1,
      editedText: m['editedText'] as String?,
    );
  }

  Message copyWith({
    int? id,
    bool? isRead,
    Map<String, List<String>>? reactions,
    bool? isDeleted,
    String? editedText,
  }) {
    return Message(
      id: id ?? this.id,
      text: text,
      sender: sender,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSender: replyToSender,
      reactions: reactions ?? Map.from(this.reactions),
      isDeleted: isDeleted ?? this.isDeleted,
      editedText: editedText ?? this.editedText,
    );
  }
}

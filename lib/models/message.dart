class Message {
  final String text;
  final String sender;
  final DateTime timestamp;

  Message({
    required this.text,
    required this.sender,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isMe => sender == 'me';
}
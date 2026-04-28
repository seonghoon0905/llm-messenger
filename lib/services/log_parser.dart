import '../models/message.dart';

class LogParser {
  static List<Message> parseKakaoLog(String rawText, String myName) {
    List<Message> parsedMessages = [];
    List<String> lines = rawText.split('\n');

    // 카톡 형식: [이름] [오전/오후 시간] 내용
    final regExp = RegExp(
      r'^\[(.+?)\]\s\[(오전|오후)\s([0-9]{1,2}:[0-9]{2})\]\s(.+)$',
    );

    for (var line in lines) {
      final match = regExp.firstMatch(line.trim());
      if (match != null) {
        String name = match.group(1)!;
        String amPm = match.group(2)!;
        String timeStr = match.group(3)!;
        String content = match.group(4)!;

        int hour = int.parse(timeStr.split(':')[0]);
        int minute = int.parse(timeStr.split(':')[1]);
        if (amPm == "오후" && hour < 12) hour += 12;
        if (amPm == "오전" && hour == 12) hour = 0;

        parsedMessages.add(
          Message(
            text: content,
            sender: name == myName ? 'me' : name,
            timestamp: DateTime(2026, 4, 2, hour, minute), // 현재 날짜 기준
          ),
        );
      }
    }
    return parsedMessages;
  }
}

// services/log_parser.dart
import '../models/message.dart';

class LogParser {
  // myName 파라미터 추가
  static List<Message> parseKakaoLog(String rawText, String myName) {
    List<Message> parsedMessages = [];
    List<String> lines = rawText.split('\n');

    final regExp = RegExp(r'^\[(.+?)\]\s\[(오전|오후)\s([0-9]{1,2}:[0-9]{2})\]\s(.+)$');

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

        parsedMessages.add(Message(
          text: content,
          // 카톡 로그의 이름이 내 이름과 같으면 'me'로 변환, 아니면 그대로 저장
          sender: name == myName ? 'me' : name,
          timestamp: DateTime(2026, 1, 1, hour, minute),
        ));
      }
    }
    return parsedMessages;
  }
}
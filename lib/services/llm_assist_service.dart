import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_style.dart';

class AssistRecentMessage {
  final String role;
  final String text;

  AssistRecentMessage({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class LlmAssistResponse {
  final bool shouldFeedback;
  final String? feedback;
  final String? reason;
  final String? rewrite;

  LlmAssistResponse({
    required this.shouldFeedback,
    required this.feedback,
    required this.reason,
    required this.rewrite,
  });

  factory LlmAssistResponse.fromJson(Map<String, dynamic> json) {
    return LlmAssistResponse(
      shouldFeedback: json['shouldFeedback'] == true,
      feedback: json['feedback'] as String?,
      reason: json['reason'] as String?,
      rewrite: json['rewrite'] as String?,
    );
  }
}

class LlmAssistService {
  Future<LlmAssistResponse> requestFeedback({
    required List<AssistRecentMessage> recentMessages,
    required String partnerLastMessage,
    required String draft,
  }) async {
    final response = await http.post(
      Uri.parse("${AppStyle.baseUrl}/llm-assist"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        'recentMessages': recentMessages.map((message) => message.toJson()).toList(),
        'partnerLastMessage': partnerLastMessage,
        'draft': draft,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("피드백 요청 실패: ${response.statusCode}");
    }

    return LlmAssistResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}

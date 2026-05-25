import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_style.dart';
import '../models/ai_analysis_models.dart';

class AiFeedbackRecentMessage {
  final String role;
  final String text;

  AiFeedbackRecentMessage({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class AiFeedbackResponse {
  final bool shouldFeedback;
  final String? feedback;
  final String? reason;
  final String? rewrite;

  AiFeedbackResponse({
    required this.shouldFeedback,
    required this.feedback,
    required this.reason,
    required this.rewrite,
  });

  factory AiFeedbackResponse.fromJson(Map<String, dynamic> json) {
    return AiFeedbackResponse(
      shouldFeedback: json['shouldFeedback'] == true,
      feedback: json['feedback'] as String?,
      reason: json['reason'] as String?,
      rewrite: json['rewrite'] as String?,
    );
  }
}

class AiFeedbackService {
  Future<AiAnalyzeDraftResponse> analyzeDraft({
    required List<AiFeedbackRecentMessage> recentMessages,
    required String partnerLastMessage,
    required String draft,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/analyze-draft"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'recentMessages': recentMessages.map((message) => message.toJson()).toList(),
          'partnerLastMessage': partnerLastMessage,
          'draft': draft,
        }),
      );

      final Map<String, dynamic> payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        final message = payload['detail'] ?? payload['error'] ?? "초안 분석 실패";
        throw Exception(message);
      }

      return AiAnalyzeDraftResponse.fromJson(payload);
    } catch (e) {
      throw Exception("초안 분석 중 오류가 발생했습니다: $e");
    }
  }

  Future<AiFeedbackResponse> requestFeedback({
    required List<AiFeedbackRecentMessage> recentMessages,
    required String partnerLastMessage,
    required String draft,
    Map<String, dynamic>? llmCandidatePayload,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/llm-assist"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'recentMessages': recentMessages.map((message) => message.toJson()).toList(),
          'partnerLastMessage': partnerLastMessage,
          'draft': draft,
          'llmCandidatePayload': llmCandidatePayload,
        }),
      );

      final Map<String, dynamic> payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        final message = payload['detail'] ?? payload['error'] ?? "피드백 요청 실패";
        throw Exception(message);
      }

      return AiFeedbackResponse.fromJson(payload);
    } catch (e) {
      throw Exception("AI 피드백 요청 중 오류가 발생했습니다: $e");
    }
  }

  Future<AiAutoReplyResponse> generateAutoReply({
    required List<AiFeedbackRecentMessage> recentMessages,
    required String partnerLastMessage,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/auto-reply"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'recentMessages': recentMessages.map((message) => message.toJson()).toList(),
          'partnerLastMessage': partnerLastMessage,
        }),
      );

      final Map<String, dynamic> payload = response.body.isNotEmpty
          ? jsonDecode(response.body) as Map<String, dynamic>
          : <String, dynamic>{};

      if (response.statusCode != 200) {
        final message = payload['detail'] ?? payload['error'] ?? "자동 응답 생성 실패";
        throw Exception(message);
      }

      return AiAutoReplyResponse.fromJson(payload);
    } catch (e) {
      throw Exception("자동 응답 생성 중 오류가 발생했습니다: $e");
    }
  }
}

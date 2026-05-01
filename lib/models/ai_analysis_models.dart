class AiRuleMatch {
  final String id;
  final String label;
  final bool matched;

  AiRuleMatch({
    required this.id,
    required this.label,
    required this.matched,
  });

  factory AiRuleMatch.fromJson(Map<String, dynamic> json) {
    return AiRuleMatch(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      matched: json['matched'] == true,
    );
  }
}

class AiAnalyzeDraftResponse {
  final bool shouldInvokeLlm;
  final List<AiRuleMatch> rules;
  final Map<String, dynamic> observedFeatures;
  final String message;

  AiAnalyzeDraftResponse({
    required this.shouldInvokeLlm,
    required this.rules,
    required this.observedFeatures,
    required this.message,
  });

  factory AiAnalyzeDraftResponse.fromJson(Map<String, dynamic> json) {
    final rulesJson = json['rules'] as List<dynamic>? ?? const [];
    return AiAnalyzeDraftResponse(
      shouldInvokeLlm: json['shouldInvokeLlm'] == true,
      rules: rulesJson
          .whereType<Map<String, dynamic>>()
          .map(AiRuleMatch.fromJson)
          .toList(),
      observedFeatures: json['observedFeatures'] as Map<String, dynamic>? ?? <String, dynamic>{},
      message: json['message'] as String? ?? '',
    );
  }
}

class AiAutoReplyResponse {
  final String reply;
  final String? reason;

  AiAutoReplyResponse({
    required this.reply,
    required this.reason,
  });

  factory AiAutoReplyResponse.fromJson(Map<String, dynamic> json) {
    return AiAutoReplyResponse(
      reply: json['reply'] as String? ?? '',
      reason: json['reason'] as String?,
    );
  }
}

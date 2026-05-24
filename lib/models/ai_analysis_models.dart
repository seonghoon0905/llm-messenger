class AiRuleMatch {
  final String id;
  final String label;
  final bool matched;
  final String severity;

  AiRuleMatch({
    required this.id,
    required this.label,
    required this.matched,
    required this.severity,
  });

  factory AiRuleMatch.fromJson(Map<String, dynamic> json) {
    return AiRuleMatch(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      matched: json['matched'] == true,
      severity: json['severity'] as String? ?? 'low',
    );
  }
}

class AiEmotionScores {
  final double distressScore;
  final double angerScore;
  final double burdenScore;
  final double warmthScore;
  final double neutralScore;
  final List<String> topEmotionLabels;
  final String source;

  AiEmotionScores({
    required this.distressScore,
    required this.angerScore,
    required this.burdenScore,
    required this.warmthScore,
    required this.neutralScore,
    required this.topEmotionLabels,
    required this.source,
  });

  factory AiEmotionScores.fromJson(Map<String, dynamic>? json) {
    final data = json ?? <String, dynamic>{};
    return AiEmotionScores(
      distressScore: (data['distressScore'] as num?)?.toDouble() ?? 0,
      angerScore: (data['angerScore'] as num?)?.toDouble() ?? 0,
      burdenScore: (data['burdenScore'] as num?)?.toDouble() ?? 0,
      warmthScore: (data['warmthScore'] as num?)?.toDouble() ?? 0,
      neutralScore: (data['neutralScore'] as num?)?.toDouble() ?? 0,
      topEmotionLabels: (data['topEmotionLabels'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      source: data['source'] as String? ?? 'unavailable',
    );
  }
}

class AiEmotionShift {
  final String direction;
  final String reason;
  final double scoreDelta;

  AiEmotionShift({
    required this.direction,
    required this.reason,
    required this.scoreDelta,
  });

  factory AiEmotionShift.fromJson(Map<String, dynamic>? json) {
    final data = json ?? <String, dynamic>{};
    return AiEmotionShift(
      direction: data['direction'] as String? ?? 'neutral',
      reason: data['reason'] as String? ?? '',
      scoreDelta: (data['scoreDelta'] as num?)?.toDouble() ?? 0,
    );
  }
}

class AiNegativeEmotionStreak {
  final int count;
  final bool active;
  final String reason;

  AiNegativeEmotionStreak({
    required this.count,
    required this.active,
    required this.reason,
  });

  factory AiNegativeEmotionStreak.fromJson(Map<String, dynamic>? json) {
    final data = json ?? <String, dynamic>{};
    return AiNegativeEmotionStreak(
      count: data['count'] as int? ?? 0,
      active: data['active'] == true,
      reason: data['reason'] as String? ?? '',
    );
  }
}

class AiLlmCandidatePayload {
  final Map<String, dynamic> raw;

  AiLlmCandidatePayload({required this.raw});

  factory AiLlmCandidatePayload.fromJson(Map<String, dynamic>? json) {
    return AiLlmCandidatePayload(raw: json ?? <String, dynamic>{});
  }
}

class AiAnalyzeDraftResponse {
  final AiEmotionScores partnerEmotionScores;
  final AiEmotionScores myDraftEmotionScores;
  final AiEmotionShift emotionShift;
  final AiNegativeEmotionStreak negativeEmotionStreak;
  final String partnerSpeechAct;
  final String mySpeechAct;
  final bool shouldInvokeLlm;
  final List<AiRuleMatch> thinGateReasons;
  final Map<String, dynamic> observedFeatures;
  final AiLlmCandidatePayload llmCandidatePayload;
  final String message;

  AiAnalyzeDraftResponse({
    required this.partnerEmotionScores,
    required this.myDraftEmotionScores,
    required this.emotionShift,
    required this.negativeEmotionStreak,
    required this.partnerSpeechAct,
    required this.mySpeechAct,
    required this.shouldInvokeLlm,
    required this.thinGateReasons,
    required this.observedFeatures,
    required this.llmCandidatePayload,
    required this.message,
  });

  factory AiAnalyzeDraftResponse.fromJson(Map<String, dynamic> json) {
    final rulesJson =
        (json['thinGateReasons'] as List<dynamic>? ?? json['rules'] as List<dynamic>? ?? const []);
    return AiAnalyzeDraftResponse(
      partnerEmotionScores: AiEmotionScores.fromJson(
        json['partnerEmotionScores'] as Map<String, dynamic>?,
      ),
      myDraftEmotionScores: AiEmotionScores.fromJson(
        json['myDraftEmotionScores'] as Map<String, dynamic>?,
      ),
      emotionShift: AiEmotionShift.fromJson(
        json['emotionShift'] as Map<String, dynamic>?,
      ),
      negativeEmotionStreak: AiNegativeEmotionStreak.fromJson(
        json['negativeEmotionStreak'] as Map<String, dynamic>?,
      ),
      partnerSpeechAct: json['partnerSpeechAct'] as String? ?? 'unknown',
      mySpeechAct: json['mySpeechAct'] as String? ?? 'unknown',
      shouldInvokeLlm: json['shouldInvokeLlm'] == true,
      thinGateReasons: rulesJson
          .whereType<Map<String, dynamic>>()
          .map(AiRuleMatch.fromJson)
          .toList(),
      observedFeatures:
          json['observedFeatures'] as Map<String, dynamic>? ?? <String, dynamic>{},
      llmCandidatePayload: AiLlmCandidatePayload.fromJson(
        json['llmCandidatePayload'] as Map<String, dynamic>?,
      ),
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

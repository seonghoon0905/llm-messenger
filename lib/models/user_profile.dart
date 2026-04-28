import 'dart:convert';

class UserProfile {
  final String userId;
  final String name;
  final String statusMessage;
  final bool isSharingPersonality;
  final Map<String, double>? personalityStats;
  final String? characterAction;
  final String? characterDesc;

  UserProfile({
    required this.userId,
    required this.name,
    this.statusMessage = "",
    this.isSharingPersonality = false,
    this.personalityStats,
    this.characterAction,
    this.characterDesc,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      userId: map['userId'] ?? '',
      name: map['nickname'] ?? '',
      statusMessage: map['statusMessage'] ?? "",
      isSharingPersonality: map['isSharingPersonality'] == 1,
      personalityStats: map['personalityStats'] != null
          ? Map<String, double>.from(jsonDecode(map['personalityStats']))
          : null,
      characterAction: map['characterAction'],
      characterDesc: map['characterDesc'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'nickname': name,
      'statusMessage': statusMessage,
      'isSharingPersonality': isSharingPersonality ? 1 : 0,
      'personalityStats': personalityStats != null
          ? jsonEncode(personalityStats)
          : null,
      'characterAction': characterAction,
      'characterDesc': characterDesc,
    };
  }
}

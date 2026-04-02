// models/user_profile.dart

class UserProfile {
  final String name;
  final String avatar;
  final String statusMessage;
  final bool isSharingPersonality;
  final Map<String, double>? personalityStats;
  final String? characterAction;
  final String? characterDesc;

  UserProfile({
    required this.name,
    this.avatar = "👤",
    this.statusMessage = "",
    this.isSharingPersonality = false,
    this.personalityStats,
    this.characterAction,
    this.characterDesc,
  });
}
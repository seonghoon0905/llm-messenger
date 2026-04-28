class Friend {
  final String id;
  final String name;
  final String profileImage;
  final String lastMessage;

  double dominance;
  double friendliness;
  String relationTag;

  Friend({
    required this.id,
    required this.name,
    this.profileImage = "",
    this.lastMessage = "",
    this.dominance = 0.5,
    this.friendliness = 0.5,
    this.relationTag = "분석 전",
  });
}
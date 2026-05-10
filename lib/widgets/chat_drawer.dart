import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../constants/app_style.dart';

class ChatDrawer extends StatelessWidget {
  final List<UserProfile> participants;
  final VoidCallback onInvite;

  const ChatDrawer({
    super.key,
    required this.participants,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppStyle.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "대화 상대",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppStyle.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${participants.length}명 참여 중",
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppStyle.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: AppStyle.divider, height: 1),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: participants.length,
                itemBuilder: (context, index) =>
                    _buildParticipantTile(participants[index]),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Divider(color: AppStyle.divider, height: 1),
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppStyle.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_rounded,
                    color: AppStyle.primary, size: 20),
              ),
              title: const Text(
                "대화 상대 초대",
                style: TextStyle(
                  color: AppStyle.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              onTap: onInvite,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipantTile(UserProfile user) {
    final avatarColor = AppStyle.getAvatarColor(user.name);
    final initial = AppStyle.getInitial(user.name);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: avatarColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            initial,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
      title: Text(
        user.name,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppStyle.textPrimary,
        ),
      ),
      subtitle: Text(
        "@${user.userId}",
        style: const TextStyle(
          fontSize: 12,
          color: AppStyle.textSecondary,
        ),
      ),
    );
  }
}

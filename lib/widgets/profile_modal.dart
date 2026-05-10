import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../models/user_profile.dart';

class ProfileModal {
  static void show(
    BuildContext context,
    UserProfile user, {
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        bool showSubProfile = false;

        return StatefulBuilder(
          builder: (context, setState) {
            final avatarColor = AppStyle.getAvatarColor(user.name);
            final initial = AppStyle.getInitial(user.name);

            return Container(
              decoration: const BoxDecoration(
                color: AppStyle.surface,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 24),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: avatarColor,
                        borderRadius: BorderRadius.circular(26),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppStyle.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "@${user.userId}",
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppStyle.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (user.statusMessage.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          user.statusMessage,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppStyle.textSecondary,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    // Action buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          if (actionLabel != null &&
                              onActionPressed != null) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  onActionPressed();
                                },
                                icon: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 18),
                                label: Text(actionLabel),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppStyle.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Personality profile button
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: user.isSharingPersonality
                                  ? () => setState(
                                      () => showSubProfile = !showSubProfile)
                                  : null,
                              icon: Icon(
                                user.isSharingPersonality
                                    ? (showSubProfile
                                        ? Icons.expand_less_rounded
                                        : Icons.insights_rounded)
                                    : Icons.lock_outline_rounded,
                                size: 18,
                              ),
                              label: Text(
                                user.isSharingPersonality
                                    ? (showSubProfile
                                        ? '성격 프로필 닫기'
                                        : '성격 프로필 보기')
                                    : '성격 프로필 비공개',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: user.isSharingPersonality
                                    ? const Color(0xFFFFFBEB)
                                    : AppStyle.surfaceVariant,
                                foregroundColor: user.isSharingPersonality
                                    ? AppStyle.characterBoxText
                                    : AppStyle.textTertiary,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: user.isSharingPersonality
                                        ? AppStyle.characterBoxText
                                            .withValues(alpha: 0.3)
                                        : AppStyle.border,
                                  ),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Personality stats
                    if (showSubProfile && user.personalityStats != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        margin:
                            const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppStyle.characterBoxText
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              user.characterAction ?? "🧐",
                              style: const TextStyle(fontSize: 44),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '"${user.characterDesc ?? ""}"',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppStyle.characterBoxText,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            _buildStatBar(
                              '지배성',
                              user.personalityStats!['dominance'] ?? 0,
                              Colors.orange,
                            ),
                            const SizedBox(height: 10),
                            _buildStatBar(
                              '친화성',
                              user.personalityStats!['affiliation'] ?? 0,
                              Colors.green,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _buildStatBar(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppStyle.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey[200],
              color: color,
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${value.toInt()}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppStyle.textSecondary,
          ),
        ),
      ],
    );
  }
}

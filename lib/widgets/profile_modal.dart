// widgets/profile_modal.dart
import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../constants/app_style.dart';

class ProfileModal {
  static void show(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // 내부 상태 변화(토글)를 위해 StatefulBuilder 사용
        bool showSubProfile = false;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.grey[200],
                    child: Text(user.avatar, style: const TextStyle(fontSize: 40)),
                  ),
                  const SizedBox(height: 16),
                  Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(user.statusMessage, style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: user.isSharingPersonality ? Colors.amber[300] : Colors.grey[300],
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: user.isSharingPersonality
                          ? () => setState(() => showSubProfile = !showSubProfile)
                          : null,
                      child: Text(
                        user.isSharingPersonality
                            ? (showSubProfile ? '성격 프로필 닫기 🔼' : '🌟 성격 프로필 보기 🔽')
                            : '🔒 성격 프로필 비공개',
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  // --- [ 서브 프로필 상세 (듀오링고 스타일) ] ---
                  if (showSubProfile && user.personalityStats != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber, width: 2),
                      ),
                      child: Column(
                        children: [
                          Text(user.characterAction ?? "🧐", style: const TextStyle(fontSize: 50)),
                          const SizedBox(height: 8),
                          Text('"${user.characterDesc ?? ""}"', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          _buildStatBar('지배성 (Dominance)', user.personalityStats!['dominance'] ?? 0, Colors.orange),
                          const SizedBox(height: 8),
                          _buildStatBar('친화성 (Affiliation)', user.personalityStats!['affiliation'] ?? 0, Colors.green),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
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
        SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value / 100,
              backgroundColor: Colors.grey[300],
              color: color,
              minHeight: 10,
            ),
          ),
        ),
      ],
    );
  }
}
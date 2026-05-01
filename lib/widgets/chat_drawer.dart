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
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Text(
                "대화 상대",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  return _buildDrawerUserTile(participants[index]);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add, color: AppStyle.primaryBlue),
              title: const Text(
                "대화 상대 초대",
                style: TextStyle(color: AppStyle.primaryBlue),
              ),
              onTap: onInvite,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerUserTile(UserProfile user) {
    return ListTile(
      leading: const CircleAvatar(
        radius: 15,
        backgroundColor: AppStyle.primaryBlue,
        child: Icon(Icons.person, size: 18, color: Colors.white),
      ),
      title: Text(user.name, style: const TextStyle(fontSize: 14)),
    );
  }
}

// screens/tabs/profile_tab.dart
import 'package:flutter/material.dart';
import '../../constants/app_style.dart';
import '../analysis_screen.dart'; // 분석 화면 임포트

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("프로필"), elevation: 0),
      body: ListView(
        children: [
          // 1. 내 프로필 섹션
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            leading: const CircleAvatar(radius: 35, child: Text("👨‍💻", style: TextStyle(fontSize: 30))),
            title: const Text("이성훈", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            subtitle: const Text("LLM 코칭 메신저 개발 중"),
          ),

          // 2. 성격 분석 리포트 진입 버튼 (핵심!)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: InkWell(
              onTap: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AnalysisScreen())
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppStyle.characterBoxBg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: AppStyle.characterBoxText.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Text("🌟", style: TextStyle(fontSize: 24)),
                    const SizedBox(width: 15),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("나의 성격 분석 리포트", style: TextStyle(fontWeight: FontWeight.bold, color: AppStyle.characterBoxText)),
                          Text("현재 대화 데이터를 기반으로 분석됨", style: TextStyle(fontSize: 12, color: AppStyle.characterBoxText)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: AppStyle.characterBoxText),
                  ],
                ),
              ),
            ),
          ),

          const Divider(thickness: 1, height: 30),

          // 3. 친구 목록 섹션
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text("친구 목록", style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          _buildFriendTile("김철수", "🤝", "오늘도 화이팅!"),
          _buildFriendTile("이영희", "🎨", "작업 중입니다."),
        ],
      ),
    );
  }

  Widget _buildFriendTile(String name, String emoji, String status) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: Colors.grey[200], child: Text(emoji)),
      title: Text(name),
      subtitle: Text(status),
      onTap: () { /* 친구 프로필 모달 등을 띄울 수 있음 */ },
    );
  }
}
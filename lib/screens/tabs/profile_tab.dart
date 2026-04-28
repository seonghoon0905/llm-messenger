import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../constants/app_style.dart';
import '../analysis_screen.dart';
import '../../models/user_profile.dart';
import '../../services/db_helper.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<UserProfile> _friends = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFriendsFromLocal();
  }

  // 📥 [로컬 DB에서 친구 목록 로드]
  Future<void> _loadFriendsFromLocal() async {
    try {
      final friends = await DBHelper().getFriends();
      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("친구 목록 로드 실패: $e");
      setState(() => _isLoading = false);
    }
  }

  // 💬 [스낵바 알림 함수]
  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ➕ [아이디 기반 친구 추가 다이얼로그]
  void _showAddFriendDialog() {
    final TextEditingController idController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("아이디로 친구 추가"),
        content: TextField(
          controller: idController,
          decoration: const InputDecoration(
            hintText: "추가할 친구의 아이디(ID) 입력",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () async {
              final searchId = idController.text.trim();
              if (searchId.isEmpty) return;

              try {
                // 서버에 유저 존재 여부 확인 (아이디 기반)
                final response = await http.get(
                  Uri.parse("${AppStyle.baseUrl}/users/search/$searchId"),
                );
                final data = jsonDecode(response.body);

                if (response.statusCode == 200 && data['success'] == true) {
                  final newFriend = UserProfile(
                    userId: data['user_id'], // 서버의 고유 ID
                    name: data['nickname'], // 서버의 닉네임
                    statusMessage: "새로 추가된 친구입니다.",
                  );

                  await DBHelper().insertFriend(newFriend);
                  await _loadFriendsFromLocal(); // 목록 새로고침

                  if (mounted) {
                    Navigator.pop(ctx);
                    _showSnackBar("${newFriend.name}님을 추가했습니다!");
                  }
                } else {
                  _showSnackBar(data['message'] ?? "사용자를 찾을 수 없거나 서버 오류입니다.");
                }
              } catch (e) {
                _showSnackBar("서버 통신 에러: $e");
              }
            },
            child: const Text("검색 및 추가"),
          ),
        ],
      ),
    );
  }

  // 🗑️ [친구 삭제 확인 다이얼로그]
  void _confirmDeleteFriend(UserProfile friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("친구 삭제"),
        content: Text("${friend.name}(${friend.userId})님을 삭제하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () async {
              await DBHelper().deleteFriend(friend.userId); // ID 기반 삭제
              await _loadFriendsFromLocal(); // 목록 새로고침
              if (mounted) {
                Navigator.pop(ctx);
                _showSnackBar("삭제되었습니다.");
              }
            },
            child: const Text("삭제", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("친구 관리"),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _showAddFriendDialog,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildMyProfile(),
                _buildAnalysisBanner(),
                const Divider(thickness: 1, height: 30),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  child: Text(
                    "친구 목록 (길게 눌러 삭제)",
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40.0),
                    child: Center(child: Text("추가된 친구가 없습니다.")),
                  )
                else
                  ..._friends
                      .map((friend) => _buildFriendTile(friend))
                      .toList(),
              ],
            ),
    );
  }

  void _showEditNicknameDialog() {
    final TextEditingController nameController = TextEditingController(
      text: AppStyle.myProfile?.name,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("닉네임 변경"),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: "새 닉네임",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) return;

              try {
                // 1. 서버 업데이트
                final response = await http.post(
                  Uri.parse("${AppStyle.baseUrl}/users/update_nickname"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "user_id": AppStyle.myLoggedInId,
                    "nickname": newName,
                  }),
                );

                if (response.statusCode == 200) {
                  // 2. 전역 세션(AppStyle) 업데이트
                  AppStyle.myProfile = UserProfile(
                    userId: AppStyle.myProfile!.userId,
                    name: newName,
                    statusMessage: AppStyle.myProfile!.statusMessage,
                  );

                  // 3. UI 갱신
                  setState(() {});
                  if (mounted) {
                    Navigator.pop(ctx);
                    _showSnackBar("닉네임이 변경되었습니다!");
                  }
                }
              } catch (e) {
                _showSnackBar("변경 실패: $e");
              }
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  void _showEditStatusDialog() {
    final TextEditingController statusController = TextEditingController(
      text: AppStyle.myProfile?.statusMessage,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("상태 메시지 변경"),
        content: TextField(
          controller: statusController,
          maxLines: 2, // 여러 줄 입력 가능하게
          decoration: const InputDecoration(
            hintText: "나의 상태를 표현해보세요",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newStatus = statusController.text.trim();
              try {
                final response = await http.post(
                  Uri.parse("${AppStyle.baseUrl}/users/update_status"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "user_id": AppStyle.myLoggedInId,
                    "status_message": newStatus,
                  }),
                );

                if (response.statusCode == 200) {
                  // 전역 세션 갱신 (기존 정보 복사 + 상태 메시지만 변경)
                  final current = AppStyle.myProfile!;
                  AppStyle.myProfile = UserProfile(
                    userId: current.userId,
                    name: current.name,
                    statusMessage: newStatus, // 새 상태 메시지 적용
                    isSharingPersonality: current.isSharingPersonality,
                    personalityStats: current.personalityStats,
                    characterAction: current.characterAction,
                    characterDesc: current.characterDesc,
                  );

                  setState(() {}); // UI 리프레시
                  if (mounted) {
                    Navigator.pop(ctx);
                    _showSnackBar("상태 메시지가 변경되었습니다.");
                  }
                }
              } catch (e) {
                _showSnackBar("변경 실패: $e");
              }
            },
            child: const Text("저장"),
          ),
        ],
      ),
    );
  }

  Widget _buildMyProfile() {
    final myProfile = AppStyle.myProfile;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      // 1. 아바타 영역 (생략되었던 부분 추가)
      leading: CircleAvatar(
        radius: 35,
        child: Icon(Icons.person, size: 30, color: Colors.grey[700]),
      ),
      title: InkWell(
        onTap: _showEditNicknameDialog,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  myProfile?.name ?? "사용자",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 14, color: Colors.grey),
              ],
            ),
            Text(
              "@${myProfile?.userId ?? 'unknown'}",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
      subtitle: InkWell(
        onTap: _showEditStatusDialog,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  myProfile?.statusMessage ?? "상태 메시지가 없습니다.",
                  style: TextStyle(color: Colors.blueGrey[600], fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnalysisBanner() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AnalysisScreen()),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppStyle.characterBoxBg,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: AppStyle.characterBoxText.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              const Text("🌟", style: TextStyle(fontSize: 24)),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "나의 성격 분석 리포트",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppStyle.characterBoxText,
                      ),
                    ),
                    Text(
                      "전체 대화 데이터를 기반으로 분석됨",
                      style: TextStyle(
                        fontSize: 12,
                        color: AppStyle.characterBoxText,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppStyle.characterBoxText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendTile(UserProfile friend) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppStyle.primaryBlue.withValues(alpha: 0.1),
        child: Icon(Icons.person, color: AppStyle.primaryBlue),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 친구 닉네임
          Text(
            friend.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          // 친구 아이디 (작게 표시)
          Text(
            "@${friend.userId}",
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      subtitle: Text(
        friend.statusMessage,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        // 상세 프로필 모달 연결
      },
      onLongPress: () => _confirmDeleteFriend(friend),
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../constants/app_style.dart';
import '../analysis_screen.dart';
import '../../models/user_profile.dart';
import '../../services/db_helper.dart';
import '../../services/api_service.dart';
import '../../models/chat_room.dart';
import '../chat_screen.dart';
import '../../widgets/profile_modal.dart';

class ProfileTab extends StatefulWidget {
  final VoidCallback? onRoomsChanged;

  const ProfileTab({super.key, this.onRoomsChanged});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  List<UserProfile> _friends = [];
  bool _isLoading = true;
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadFriendsFromLocal();
  }

  Future<void> _loadFriendsFromLocal() async {
    try {
      await _syncFriendsFromServer();
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

  Future<void> _syncFriendsFromServer() async {
    final myId = AppStyle.myLoggedInId;
    if (myId == null) return;
    final friends = await _apiService.fetchFriends(myId);
    for (final friend in friends) {
      await DBHelper().insertFriend(
        UserProfile(
          userId: friend['user_id'] as String? ?? '',
          name: friend['nickname'] as String? ??
              friend['user_id'] as String? ??
              '',
          statusMessage:
              friend['status_message'] as String? ?? "상태 메시지가 없습니다.",
        ),
      );
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  void _showAddFriendDialog() {
    final TextEditingController idController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("친구 추가",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: idController,
          decoration: const InputDecoration(
            hintText: "추가할 친구의 아이디(ID) 입력",
          ),
          autofocus: true,
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
              if (AppStyle.myLoggedInId == null) {
                _showSnackBar("로그인 정보가 없습니다.");
                return;
              }
              try {
                final response = await http.get(
                  Uri.parse(
                      "${AppStyle.baseUrl}/users/search/$searchId"),
                );
                final data = jsonDecode(response.body);
                if (response.statusCode == 200 && data['success'] == true) {
                  final addResult = await _apiService.addFriend(
                    userId: AppStyle.myLoggedInId!,
                    friendId: data['user_id'],
                  );
                  if (addResult['success'] != true) {
                    _showSnackBar(addResult['message'] ?? "친구 추가 실패");
                    return;
                  }
                  await _syncFriendsFromServer();
                  await _loadFriendsFromLocal();
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnackBar("${data['nickname']}님을 추가했습니다!");
                } else {
                  _showSnackBar(
                      data['message'] ?? "사용자를 찾을 수 없거나 서버 오류입니다.");
                }
              } catch (e) {
                _showSnackBar("서버 통신 에러: $e");
              }
            },
            child: const Text("추가"),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFriend(UserProfile friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("친구 삭제",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text("${friend.name}님을 친구 목록에서 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DBHelper().deleteFriend(friend.userId);
              if (AppStyle.myLoggedInId != null) {
                await _apiService.removeFriend(
                  userId: AppStyle.myLoggedInId!,
                  friendId: friend.userId,
                );
              }
              await _loadFriendsFromLocal();
              _showSnackBar("삭제되었습니다.");
            },
            child: const Text("삭제",
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _startDirectChat(UserProfile friend) async {
    final myId = AppStyle.myLoggedInId;
    if (myId == null) {
      _showSnackBar("로그인 정보가 없습니다.");
      return;
    }
    final result = await _apiService.createDirectRoom(
      userId: myId,
      friendId: friend.userId,
    );
    if (result['success'] != true) {
      _showSnackBar(result['message'] ?? "1:1 채팅방 생성에 실패했습니다.");
      return;
    }
    final room = ChatRoom(
      id: result['room_id'],
      title: result['title'] ?? friend.name,
      relation: result['relation'] ?? '기타',
      lastMessageTime: DateTime.now(),
      lastMessage: "대화를 시작해보세요.",
      memberIds: [myId, friend.userId],
    );
    await DBHelper().insertChatRoom(room);
    widget.onRoomsChanged?.call();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(chatRoom: room)),
    );
    widget.onRoomsChanged?.call();
  }

  void _showEditNicknameDialog() {
    final nameController = TextEditingController(
      text: AppStyle.myProfile?.name,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("닉네임 변경",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: "새 닉네임"),
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
                final response = await http.post(
                  Uri.parse("${AppStyle.baseUrl}/users/update_nickname"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "user_id": AppStyle.myLoggedInId,
                    "nickname": newName,
                  }),
                );
                if (response.statusCode == 200) {
                  AppStyle.myProfile = UserProfile(
                    userId: AppStyle.myProfile!.userId,
                    name: newName,
                    statusMessage: AppStyle.myProfile!.statusMessage,
                  );
                  setState(() {});
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnackBar("닉네임이 변경되었습니다!");
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
    final statusController = TextEditingController(
      text: AppStyle.myProfile?.statusMessage,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("상태 메시지 변경",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: statusController,
          maxLines: 2,
          autofocus: true,
          decoration: const InputDecoration(hintText: "나의 상태를 표현해보세요"),
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
                  final current = AppStyle.myProfile!;
                  AppStyle.myProfile = UserProfile(
                    userId: current.userId,
                    name: current.name,
                    statusMessage: newStatus,
                    isSharingPersonality: current.isSharingPersonality,
                    personalityStats: current.personalityStats,
                    characterAction: current.characterAction,
                    characterDesc: current.characterDesc,
                  );
                  setState(() {});
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  _showSnackBar("상태 메시지가 변경되었습니다.");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppStyle.primary))
            : CustomScrollView(
                slivers: [
                  // Header
                  SliverToBoxAdapter(child: _buildHeader()),
                  // My profile card
                  SliverToBoxAdapter(child: _buildMyProfileCard()),
                  // Analysis banner
                  SliverToBoxAdapter(child: _buildAnalysisBanner()),
                  // Friend list header
                  SliverToBoxAdapter(child: _buildFriendListHeader()),
                  // Friend list
                  _friends.isEmpty
                      ? SliverToBoxAdapter(child: _buildEmptyFriends())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) =>
                                _buildFriendTile(_friends[index]),
                            childCount: _friends.length,
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 32)),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppStyle.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '친구',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppStyle.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            onPressed: _showAddFriendDialog,
            icon: const Icon(Icons.person_add_rounded,
                color: AppStyle.primary, size: 22),
            tooltip: '친구 추가',
          ),
        ],
      ),
    );
  }

  Widget _buildMyProfileCard() {
    final myProfile = AppStyle.myProfile;
    final avatarColor =
        AppStyle.getAvatarColor(myProfile?.name ?? 'me');
    final initial = AppStyle.getInitial(myProfile?.name ?? 'M');

    return GestureDetector(
      onTap: () => ProfileModal.show(
        context,
        myProfile ?? UserProfile(userId: '?', name: '나', statusMessage: ''),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppStyle.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: avatarColor,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        myProfile?.name ?? "사용자",
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: AppStyle.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: _showEditNicknameDialog,
                        child: const Icon(Icons.edit_rounded,
                            size: 14, color: AppStyle.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "@${myProfile?.userId ?? 'unknown'}",
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppStyle.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _showEditStatusDialog,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            myProfile?.statusMessage ?? "상태 메시지를 설정해보세요",
                            style: TextStyle(
                              color: myProfile?.statusMessage != null
                                  ? AppStyle.textSecondary
                                  : AppStyle.textTertiary,
                              fontSize: 13,
                              fontStyle:
                                  myProfile?.statusMessage == null
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.edit_rounded,
                            size: 12, color: AppStyle.textTertiary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisBanner() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const AnalysisScreen()),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppStyle.primary,
              AppStyle.primary.withValues(alpha: 0.75),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppStyle.primary.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.insights_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "나의 성격 분석 리포트",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    "전체 대화 데이터 기반 분석",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendListHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: [
          const Text(
            "친구 목록",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppStyle.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppStyle.primaryLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${_friends.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppStyle.primary,
              ),
            ),
          ),
          const Spacer(),
          const Text(
            "길게 눌러 삭제",
            style: TextStyle(
              fontSize: 11,
              color: AppStyle.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFriends() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.people_outline_rounded,
                size: 48, color: AppStyle.textTertiary),
            SizedBox(height: 12),
            Text(
              "아직 친구가 없어요",
              style: TextStyle(
                color: AppStyle.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              "+ 버튼으로 친구를 추가해보세요",
              style: TextStyle(color: AppStyle.textTertiary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendTile(UserProfile friend) {
    final avatarColor = AppStyle.getAvatarColor(friend.name);
    final initial = AppStyle.getInitial(friend.name);

    return Material(
      color: AppStyle.surface,
      child: InkWell(
        onTap: () => ProfileModal.show(
          context,
          friend,
          actionLabel: '1:1 채팅',
          onActionPressed: () => _startDirectChat(friend),
        ),
        onLongPress: () => _confirmDeleteFriend(friend),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: avatarColor,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppStyle.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      friend.statusMessage.isNotEmpty
                          ? friend.statusMessage
                          : "@${friend.userId}",
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppStyle.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _startDirectChat(friend),
                icon: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppStyle.primary, size: 20),
                tooltip: '1:1 채팅',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

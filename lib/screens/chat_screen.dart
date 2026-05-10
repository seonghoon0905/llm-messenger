import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_style.dart';
import '../models/message.dart';
import '../models/chat_room.dart';
import '../models/user_profile.dart';
import '../models/ai_analysis_models.dart';
import '../widgets/profile_modal.dart';
import '../widgets/chat_message_bubble.dart';
import '../widgets/chat_input_area.dart';
import '../widgets/chat_drawer.dart';
import '../services/log_parser.dart';
import '../services/db_helper.dart';
import '../services/ai_feedback_service.dart';
import 'dart:convert';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final ChatRoom chatRoom;
  const ChatScreen({super.key, required this.chatRoom});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  StreamSubscription? _socketSubscription;
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message> _displayMessages = [];
  bool _isLoading = true;

  // AI assist state
  bool _isFeedbackLoading = false;
  bool _isAutoReplyLoading = false;
  String? _feedbackError;
  String? _autoReplyError;
  String? _feedbackText;
  String? _feedbackReason;
  String? _feedbackRewrite;
  String? _analysisSummary;
  String? _debugSummary;
  bool _shouldFeedback = false;
  late String _selectedRegisterMode;

  // New feature state
  bool _isSearching = false;
  String _searchQuery = '';
  Message? _replyingTo;

  final List<UserProfile> _participants = [];
  final AiFeedbackService _aiFeedbackService = AiFeedbackService();

  @override
  void initState() {
    super.initState();
    AppStyle.currentOpenRoomId = widget.chatRoom.id;
    _selectedRegisterMode = _resolveInitialRegisterMode();
    DBHelper().resetUnreadCount(widget.chatRoom.id);
    _loadMessagesFromLocal();
    _connectSocket();
    _loadParticipants();
  }

  Future<void> _loadParticipants() async {
    final myId = AppStyle.myLoggedInId ?? 'me';
    final room = await DBHelper().getChatRoomById(widget.chatRoom.id);
    final storedIds = room?.memberIds ?? [];

    // 내 ID가 없으면 추가
    var ids = storedIds.contains(myId) ? storedIds : [myId, ...storedIds];

    // DM 방(dm:id1:id2)이면 room ID에서 상대방 ID 추출해 보정
    if (widget.chatRoom.id.startsWith('dm:')) {
      final parts = widget.chatRoom.id.split(':');
      if (parts.length == 3) {
        final partnerId = parts[1] == myId ? parts[2] : parts[1];
        if (!ids.contains(partnerId)) {
          ids = [...ids, partnerId];
        }
      }
    }

    final friends = await DBHelper().getFriends();
    final friendMap = {for (var f in friends) f.userId: f};

    if (mounted) {
      setState(() {
        _participants.clear();
        for (final id in ids) {
          if (id == myId && AppStyle.myProfile != null) {
            _participants.add(AppStyle.myProfile!);
          } else if (friendMap.containsKey(id)) {
            _participants.add(friendMap[id]!);
          } else if (id != myId) {
            _participants.add(UserProfile(userId: id, name: id));
          }
        }
        // 최소 나 자신은 포함
        if (_participants.isEmpty && AppStyle.myProfile != null) {
          _participants.add(AppStyle.myProfile!);
        }
      });
      // storedIds와 달라졌으면 DB 갱신
      if (ids.length != storedIds.length ||
          ids.toSet().difference(storedIds.toSet()).isNotEmpty) {
        await DBHelper().updateRoomMembers(widget.chatRoom.id, ids);
        widget.chatRoom.memberIds
          ..clear()
          ..addAll(ids);
      }
    }
  }

  Future<void> _addMemberToRoom(String userId, String? nickname) async {
    final myId = AppStyle.myLoggedInId ?? 'me';
    final room = await DBHelper().getChatRoomById(widget.chatRoom.id);
    final ids = List<String>.from(room?.memberIds ?? [myId]);
    if (!ids.contains(userId)) {
      ids.add(userId);
      await DBHelper().updateRoomMembers(widget.chatRoom.id, ids);
      widget.chatRoom.memberIds
        ..clear()
        ..addAll(ids);
      if (mounted) {
        setState(() {
          final exists = _participants.any((p) => p.userId == userId);
          if (!exists) {
            _participants.add(UserProfile(
              userId: userId,
              name: nickname ?? userId,
            ));
          }
        });
      }
    }
  }

  void _connectSocket() {
    try {
      _socketSubscription = AppStyle.globalStream?.listen(
        (message) async {
          final data = jsonDecode(message);
          if (data['type'] == 'INVITE_EVENT') return;

          // 다른 멤버가 입장했을 때 시스템 메시지 표시
          if (data['type'] == 'MEMBER_JOINED') {
            if (data['room_id'] == widget.chatRoom.id) {
              final joinedId = data['user_id'] as String? ?? '';
              final nickname = data['nickname'] as String? ?? joinedId;
              final ts = DateTime.tryParse(data['timestamp'] ?? '') ?? DateTime.now();
              final sysMsg = Message(
                text: '$nickname님이 입장하셨습니다.',
                sender: '__system__',
                timestamp: ts,
                isRead: true,
              );
              final sysId = await DBHelper().insertMessage(widget.chatRoom.id, sysMsg);
              await _addMemberToRoom(joinedId, nickname);
              if (mounted) {
                setState(() => _displayMessages.insert(0, sysMsg.copyWith(id: sysId)));
              }
            }
            return;
          }

          if (data['room_id'] != null &&
              data['room_id'] != widget.chatRoom.id) {
            return;
          }
          final incomingMsg = Message(
            text: data['content'] ?? "",
            sender: data['sender_nickname'] ?? data['sender_id'] ?? "unknown",
            timestamp: DateTime.parse(
              data['timestamp'] ?? DateTime.now().toIso8601String(),
            ),
            isRead: true,
          );
          final msgId = await DBHelper().insertMessage(widget.chatRoom.id, incomingMsg);
          final incomingMsgWithId = incomingMsg.copyWith(id: msgId);
          if (mounted) {
            // Mark my sent messages as read (heuristic: if they replied, they read my messages)
            DBHelper().markMySentMessagesAsRead(widget.chatRoom.id);
            setState(() {
              _displayMessages.insert(0, incomingMsgWithId);
              for (int i = 0; i < _displayMessages.length; i++) {
                if (_displayMessages[i].isMe && !_displayMessages[i].isRead) {
                  _displayMessages[i] =
                      _displayMessages[i].copyWith(isRead: true);
                }
              }
            });
          }
        },
        onError: (error) => debugPrint("소켓 에러: $error"),
      );
    } catch (e) {
      debugPrint("소켓 리스너 등록 실패: $e");
    }
  }

  Future<void> _loadMessagesFromLocal() async {
    try {
      final messages = await DBHelper().getMessages(widget.chatRoom.id);
      await DBHelper().markRoomMessagesAsRead(widget.chatRoom.id);
      if (mounted) {
        setState(() {
          _displayMessages = messages.reversed.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("로컬 메시지 로드 에러: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateMessageInList(Message updated) {
    setState(() {
      final idx = _displayMessages.indexWhere((m) => m.id == updated.id);
      if (idx != -1) _displayMessages[idx] = updated;
    });
  }

  // ─── Send ─────────────────────────────────────────────────────────────────

  void _handleSend() async {
    if (_controller.text.trim().isEmpty) return;
    final text = _controller.text.trim();
    final timestamp = DateTime.now();

    final msgPacket = {
      "receiver_id": widget.chatRoom.id,
      "content": text,
      "timestamp": timestamp.toIso8601String(),
    };
    AppStyle.channel?.sink.add(jsonEncode(msgPacket));

    final myMsg = Message(
      text: text,
      sender: 'me',
      timestamp: timestamp,
      isRead: false,
      replyToId: _replyingTo?.id,
      replyToText: _replyingTo?.displayText,
      replyToSender: _replyingTo?.sender,
    );

    final id = await DBHelper().insertMessage(widget.chatRoom.id, myMsg);
    final myMsgWithId = myMsg.copyWith(id: id);

    // memberIds를 건드리지 않고 lastMessageTime만 갱신
    await DBHelper().updateRoomLastMessage(widget.chatRoom.id, timestamp);

    if (mounted) {
      setState(() {
        _displayMessages.insert(0, myMsgWithId);
        _setDraftTextProgrammatically('');
        _replyingTo = null;
        _clearFeedbackState();
      });
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  // ─── Message Actions ──────────────────────────────────────────────────────

  void _onMessageLongPress(Message msg) {
    if (!mounted) return;
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppStyle.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Quick emoji reactions
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: emojis.map((emoji) {
                  final iReacted = msg.reactions[emoji]
                          ?.contains(AppStyle.myLoggedInId ?? 'me') ==
                      true;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _onReact(msg, emoji);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: iReacted
                            ? AppStyle.primaryLight
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(emoji,
                          style: const TextStyle(fontSize: 26)),
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: AppStyle.divider, height: 1),
            _buildActionTile(
              ctx,
              icon: Icons.copy_rounded,
              label: '복사',
              onTap: () => _handleCopy(msg),
            ),
            _buildActionTile(
              ctx,
              icon: Icons.reply_rounded,
              label: '답장',
              onTap: () => _handleReply(msg),
            ),
            if (msg.isMe) ...[
              _buildActionTile(
                ctx,
                icon: Icons.edit_rounded,
                label: '수정',
                onTap: () => _handleEdit(msg),
              ),
              _buildActionTile(
                ctx,
                icon: Icons.delete_rounded,
                label: '삭제',
                color: Colors.redAccent,
                onTap: () => _handleDelete(msg),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color != null
              ? color.withValues(alpha: 0.1)
              : AppStyle.primaryLight,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon,
            color: color ?? AppStyle.primary, size: 19),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: color ?? AppStyle.textPrimary,
        ),
      ),
      onTap: () {
        Navigator.pop(ctx);
        onTap();
      },
    );
  }

  void _handleCopy(Message msg) {
    Clipboard.setData(ClipboardData(text: msg.displayText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메시지를 복사했습니다.')),
    );
  }

  void _handleReply(Message msg) {
    setState(() => _replyingTo = msg);
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  Future<void> _handleEdit(Message msg) async {
    if (msg.id == null) return;
    final ctrl = TextEditingController(text: msg.displayText);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메시지 수정',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration:
              const InputDecoration(hintText: '수정할 내용을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await DBHelper().editMessage(msg.id!, result);
      _updateMessageInList(msg.copyWith(editedText: result));
    }
  }

  Future<void> _handleDelete(Message msg) async {
    if (msg.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('메시지 삭제',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('이 메시지를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DBHelper().deleteMessage(msg.id!);
      _updateMessageInList(msg.copyWith(isDeleted: true));
    }
  }

  Future<void> _onReact(Message msg, String emoji) async {
    if (msg.id == null) return;
    final userId = AppStyle.myLoggedInId ?? 'me';
    final updated = Map<String, List<String>>.from(
      msg.reactions.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
    if (updated[emoji]?.contains(userId) == true) {
      updated[emoji]!.remove(userId);
      if (updated[emoji]!.isEmpty) updated.remove(emoji);
    } else {
      updated.putIfAbsent(emoji, () => []).add(userId);
    }
    await DBHelper().updateReactions(msg.id!, updated);
    _updateMessageInList(msg.copyWith(reactions: updated));
  }

  // ─── Search ───────────────────────────────────────────────────────────────

  List<Message> get _filteredMessages {
    if (_searchQuery.isEmpty) return _displayMessages;
    final q = _searchQuery.toLowerCase();
    return _displayMessages
        .where((m) =>
            m.displayText.toLowerCase().contains(q) && !m.isDeleted)
        .toList();
  }

  // ─── AI Assist ────────────────────────────────────────────────────────────

  void _clearFeedbackState() {
    _feedbackError = null;
    _feedbackText = null;
    _feedbackReason = null;
    _feedbackRewrite = null;
    _analysisSummary = null;
    _debugSummary = null;
    _shouldFeedback = false;
  }

  void _setDraftTextProgrammatically(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  List<AiFeedbackRecentMessage> _buildRecentMessages() {
    return _displayMessages.reversed
        .take(6)
        .map((m) => AiFeedbackRecentMessage(
              role: m.isMe ? 'me' : 'partner',
              text: m.displayText,
            ))
        .toList();
  }

  String _findPartnerLastMessage() {
    return _displayMessages
            .where((m) => !m.isMe && !m.isDeleted)
            .map((m) => m.displayText)
            .cast<String?>()
            .firstWhere((t) => t != null, orElse: () => null) ??
        "";
  }

  String _buildDebugSummary(AiAnalyzeDraftResponse r) {
    final matchedRules =
        r.thinGateReasons.where((x) => x.matched).map((x) => x.id).join(', ');
    final nluSource = r.observedFeatures['nluSource'] ?? 'unavailable';
    return "debug: shouldInvokeLlm=${r.shouldInvokeLlm}, "
        "rules=${matchedRules.isEmpty ? 'none' : matchedRules}, "
        "registerMode=${r.registerMode}, "
        "formalProb=${r.formalProb.toStringAsFixed(2)}, "
        "partnerSpeechAct=${r.partnerSpeechAct}, "
        "mySpeechAct=${r.mySpeechAct}, "
        "nluSource=$nluSource, "
        "partnerEmotionSource=${r.partnerEmotionScores.source}, "
        "myDraftEmotionSource=${r.myDraftEmotionScores.source}, "
        "partnerEmotion=[d=${r.partnerEmotionScores.distressScore.toStringAsFixed(2)}, "
        "a=${r.partnerEmotionScores.angerScore.toStringAsFixed(2)}, "
        "b=${r.partnerEmotionScores.burdenScore.toStringAsFixed(2)}, "
        "w=${r.partnerEmotionScores.warmthScore.toStringAsFixed(2)}], "
        "myDraftEmotion=[d=${r.myDraftEmotionScores.distressScore.toStringAsFixed(2)}, "
        "a=${r.myDraftEmotionScores.angerScore.toStringAsFixed(2)}, "
        "b=${r.myDraftEmotionScores.burdenScore.toStringAsFixed(2)}, "
        "w=${r.myDraftEmotionScores.warmthScore.toStringAsFixed(2)}], "
        "emotionShift=${r.emotionShift.direction}, "
        "negativeStreak=${r.negativeEmotionStreak.active}";
  }

  String _resolveInitialRegisterMode() {
    return AppStyle.roomRegisterModes[widget.chatRoom.id] ?? 'casual';
  }

  Future<void> _handleAiFeedback() async {
    final draft = _controller.text.trim();
    if (draft.isEmpty) {
      setState(() {
        _clearFeedbackState();
        _feedbackError = "먼저 초안을 입력해주세요.";
      });
      return;
    }
    final recentMessages = _buildRecentMessages();
    final partnerLastMessage = _findPartnerLastMessage();
    setState(() {
      _isFeedbackLoading = true;
      _autoReplyError = null;
      _clearFeedbackState();
    });
    try {
      final analyzeResponse = await _aiFeedbackService.analyzeDraft(
        recentMessages: recentMessages,
        partnerLastMessage: partnerLastMessage,
        draft: draft,
        registerMode: _selectedRegisterMode,
      );
      if (!mounted) return;
      if (!analyzeResponse.shouldInvokeLlm) {
        setState(() {
          _shouldFeedback = false;
          _analysisSummary = analyzeResponse.message.isNotEmpty
              ? analyzeResponse.message
              : "큰 문제는 감지되지 않았습니다.";
          if (kDebugMode) _debugSummary = _buildDebugSummary(analyzeResponse);
        });
        return;
      }
      final response = await _aiFeedbackService.requestFeedback(
        recentMessages: recentMessages,
        partnerLastMessage: partnerLastMessage,
        draft: draft,
        llmCandidatePayload: analyzeResponse.llmCandidatePayload.raw,
      );
      if (!mounted) return;
      setState(() {
        _shouldFeedback = response.shouldFeedback;
        _feedbackText = response.feedback;
        _feedbackReason = response.reason;
        _feedbackRewrite = response.rewrite;
        // GPT가 피드백 불필요로 판단했으면 Gate 메시지 대신 긍정 메시지로 덮음
        _analysisSummary = response.shouldFeedback
            ? analyzeResponse.message
            : "큰 문제는 감지되지 않았습니다.";
        if (kDebugMode) _debugSummary = _buildDebugSummary(analyzeResponse);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clearFeedbackState();
        _feedbackError = "피드백을 불러오지 못했습니다: $e";
      });
    } finally {
      if (mounted) setState(() => _isFeedbackLoading = false);
    }
  }

  Future<void> _handleAutoReply() async {
    final recentMessages = _buildRecentMessages();
    final partnerLastMessage = _findPartnerLastMessage();
    setState(() {
      _isAutoReplyLoading = true;
      _autoReplyError = null;
    });
    try {
      final response = await _aiFeedbackService.generateAutoReply(
        recentMessages: recentMessages,
        partnerLastMessage: partnerLastMessage,
        registerMode: _selectedRegisterMode,
      );
      if (!mounted) return;
      _setDraftTextProgrammatically(response.reply);
      setState(() => _autoReplyError = null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _autoReplyError = "자동 응답 생성에 실패했습니다: $e");
    } finally {
      if (mounted) setState(() => _isAutoReplyLoading = false);
    }
  }

  void _applyRewrite() {
    final rewrite = _feedbackRewrite;
    if (rewrite == null || rewrite.trim().isEmpty) return;
    _setDraftTextProgrammatically(rewrite);
    setState(() => _feedbackError = null);
  }

  void _handleDismissFeedback() {
    setState(() {
      _clearFeedbackState();
      _autoReplyError = null;
    });
  }

  void _handleRegisterModeChanged(String mode) {
    if (_selectedRegisterMode == mode) return;
    setState(() => _selectedRegisterMode = mode);
    AppStyle.roomRegisterModes[widget.chatRoom.id] = mode;
  }

  // ─── Profile ──────────────────────────────────────────────────────────────

  Future<void> _showProfile(String senderName) async {
    if (senderName == "me" || senderName == AppStyle.myLoggedInId) {
      if (context.mounted) {
        ProfileModal.show(
          context,
          AppStyle.myProfile ??
              UserProfile(
                userId: AppStyle.myLoggedInId ?? "unknown",
                name: AppStyle.myLoggedInId ?? "나",
                statusMessage: "정보를 불러오는 중...",
              ),
        );
      }
      return;
    }
    try {
      final friends = await DBHelper().getFriends();
      final friend = friends.firstWhere(
        (f) => f.name == senderName,
        orElse: () => UserProfile(userId: senderName, name: senderName),
      );
      if (mounted) ProfileModal.show(context, friend);
    } catch (e) {
      debugPrint("프로필 조회 에러: $e");
    }
  }

  // ─── Kakao Log ────────────────────────────────────────────────────────────

  Future<void> _uploadKakaoLog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null) {
      setState(() => _isLoading = true);
      try {
        File file = File(result.files.single.path!);
        String content = await file.readAsString();
        String myName = AppStyle.myProfile?.name ?? "나";
        List<Message> parsedMsgs = LogParser.parseKakaoLog(content, myName);
        if (parsedMsgs.isEmpty) return;
        for (var msg in parsedMsgs) {
          await DBHelper().insertMessage(widget.chatRoom.id, msg);
        }
        await _loadMessagesFromLocal();
      } catch (e) {
        debugPrint("로그 업로드 에러: $e");
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ─── Invite ───────────────────────────────────────────────────────────────

  void _showInviteDialog() async {
    final friends = await DBHelper().getFriends();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("친구 초대하기",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: friends.isEmpty
              ? const Center(
                  child: Text("초대할 수 있는 친구가 없습니다.",
                      style: TextStyle(color: AppStyle.textSecondary)))
              : ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    final avatarColor = AppStyle.getAvatarColor(friend.name);
                    final initial = AppStyle.getInitial(friend.name);
                    return ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: avatarColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      title: Text(friend.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text("@${friend.userId}"),
                      onTap: () async {
                        final isAlreadyIn = _participants
                            .any((p) => p.userId == friend.userId);
                        Navigator.pop(ctx);
                        if (isAlreadyIn) return;
                        final ts = DateTime.now();
                        final invitePacket = {
                          "type": "INVITE",
                          "room_id": widget.chatRoom.id,
                          "invitee_id": friend.userId,
                          "room_title": widget.chatRoom.title,
                          "relation": widget.chatRoom.relation,
                          "timestamp": ts.toIso8601String(),
                        };
                        AppStyle.channel?.sink.add(jsonEncode(invitePacket));
                        await _addMemberToRoom(friend.userId, friend.name);
                        // 초대 시스템 메시지
                        final sysMsg = Message(
                          text: '${friend.name}님을 초대했습니다.',
                          sender: '__system__',
                          timestamp: ts,
                          isRead: true,
                        );
                        final sysId = await DBHelper().insertMessage(widget.chatRoom.id, sysMsg);
                        if (mounted) {
                          setState(() => _displayMessages.insert(0, sysMsg.copyWith(id: sysId)));
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("취소"),
          ),
        ],
      ),
    );
  }

  // ─── Message List ─────────────────────────────────────────────────────────

  Widget _buildSystemMessage(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppStyle.textSecondary),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMessageList() {
    final messages = _filteredMessages;
    final List<Widget> items = [];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (msg.sender == '__system__') {
        items.add(_buildSystemMessage(msg.displayText));
      } else {
        items.add(ChatMessageBubble(
          message: msg,
          onShowProfile: _showProfile,
          onLongPress: _onMessageLongPress,
          onReact: _onReact,
          searchQuery: _searchQuery,
          participantCount: widget.chatRoom.memberCount,
        ));
      }
      final isLast = i == messages.length - 1;
      final msgDate = DateTime(
          msg.timestamp.year, msg.timestamp.month, msg.timestamp.day);
      if (!isLast) {
        final nextMsg = messages[i + 1];
        final nextDate = DateTime(nextMsg.timestamp.year,
            nextMsg.timestamp.month, nextMsg.timestamp.day);
        if (msgDate != nextDate) {
          items.add(DateSeparator(date: msgDate));
        }
      } else {
        items.add(DateSeparator(date: msgDate));
      }
    }
    return items;
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    if (AppStyle.currentOpenRoomId == widget.chatRoom.id) {
      AppStyle.currentOpenRoomId = null;
    }
    _socketSubscription?.cancel();
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final avatarColor = AppStyle.getAvatarColor(widget.chatRoom.title);
    final initial = AppStyle.getInitial(widget.chatRoom.title);
    final filteredCount = _filteredMessages.length;

    return Scaffold(
      backgroundColor: AppStyle.chatBg,
      appBar: AppBar(
        backgroundColor: AppStyle.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppStyle.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (q) => setState(() => _searchQuery = q),
                style: const TextStyle(
                    fontSize: 15, color: AppStyle.textPrimary),
                decoration: const InputDecoration(
                  hintText: '메시지 검색...',
                  hintStyle: TextStyle(color: AppStyle.textTertiary),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                  filled: false,
                ),
              )
            : Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.chatRoom.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppStyle.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
        centerTitle: false,
        actions: [
          if (_isSearching) ...[
            if (_searchQuery.isNotEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '$filteredCount개',
                    style: const TextStyle(
                        fontSize: 13,
                        color: AppStyle.textSecondary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded,
                  color: AppStyle.textPrimary, size: 22),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded,
                  color: AppStyle.textSecondary, size: 22),
              onPressed: () => setState(() => _isSearching = true),
            ),
            IconButton(
              icon: const Icon(Icons.upload_file_rounded,
                  color: AppStyle.textSecondary, size: 22),
              onPressed: _uploadKakaoLog,
            ),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.people_outline_rounded,
                    color: AppStyle.textSecondary, size: 22),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppStyle.divider),
        ),
      ),
      endDrawer: ChatDrawer(
        participants: _participants,
        onInvite: _showInviteDialog,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppStyle.primary))
          : Column(
              children: [
                Expanded(
                  child: _filteredMessages.isEmpty && _searchQuery.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.search_off_rounded,
                                  size: 48, color: AppStyle.textTertiary),
                              const SizedBox(height: 12),
                              Text(
                                '"$_searchQuery" 검색 결과가 없습니다.',
                                style: const TextStyle(
                                    color: AppStyle.textSecondary,
                                    fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          children: _buildMessageList(),
                        ),
                ),
                ChatInputArea(
                  controller: _controller,
                  onSend: _handleSend,
                  onFeedbackPressed: _handleAiFeedback,
                  onAutoReplyPressed: _handleAutoReply,
                  onApplyRewrite: _applyRewrite,
                  onCloseFeedback: _handleDismissFeedback,
                  onRegisterModeChanged: _handleRegisterModeChanged,
                  isFeedbackLoading: _isFeedbackLoading,
                  isAutoReplyLoading: _isAutoReplyLoading,
                  feedbackError: _feedbackError,
                  autoReplyError: _autoReplyError,
                  shouldFeedback: _shouldFeedback,
                  feedbackText: _feedbackText,
                  feedbackReason: _feedbackReason,
                  feedbackRewrite: _feedbackRewrite,
                  analysisSummary: _analysisSummary,
                  debugSummary: _debugSummary,
                  selectedRegisterMode: _selectedRegisterMode,
                  replyTo: _replyingTo,
                  onCancelReply: _cancelReply,
                ),
              ],
            ),
    );
  }
}

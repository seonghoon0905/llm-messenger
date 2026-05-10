import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../models/user_profile.dart';

class ChatDialogs {
  // 1. 새 채팅방 생성 다이얼로그 (이름 + 친구 선택)
  static void showCreateChatDialog({
    required BuildContext context,
    required List<UserProfile> friends,
    required Function(String title, String relation, List<String> inviteeIds) onCreate,
  }) {
    String newTitle = "";
    final Set<String> selectedIds = {};

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 채팅방', style: TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: "대화방 이름",
                    isDense: true,
                  ),
                  onChanged: (v) => setDialogState(() => newTitle = v),
                ),
                if (friends.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    '초대할 친구',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppStyle.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        final selected = selectedIds.contains(friend.userId);
                        return CheckboxListTile(
                          value: selected,
                          activeColor: AppStyle.primary,
                          onChanged: (v) => setDialogState(() {
                            if (v == true) selectedIds.add(friend.userId);
                            else selectedIds.remove(friend.userId);
                          }),
                          title: Text(friend.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                          subtitle: Text('@${friend.userId}', style: const TextStyle(fontSize: 11)),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            TextButton(
              onPressed: newTitle.trim().isNotEmpty
                  ? () {
                      onCreate(newTitle.trim(), '기타', selectedIds.toList());
                      Navigator.pop(context);
                    }
                  : null,
              child: const Text('생성'),
            ),
          ],
        ),
      ),
    );
  }

  static void showEditChatDialog({
    required BuildContext context,
    required String initialTitle,
    required String initialRelation,
    required Function(String newTitle, String newRelation) onSave,
  }) {
    final editController = TextEditingController(text: initialTitle);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채팅방 이름 수정'),
        content: TextField(
          controller: editController,
          decoration: const InputDecoration(labelText: "이름"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              if (editController.text.isNotEmpty) {
                onSave(editController.text, initialRelation);
                Navigator.pop(context);
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  // 3. 삭제 확인 다이얼로그
  static void showDeleteDialog({
    required BuildContext context,
    required VoidCallback onDelete,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('대화방 삭제'),
        content: const Text('이 대화방을 정말 삭제하시겠습니까?\n삭제된 내용은 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () {
              onDelete();
              Navigator.pop(context);
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
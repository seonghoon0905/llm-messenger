import 'package:flutter/material.dart';

class ChatDialogs {
  // 1. 새 채팅방 생성 다이얼로그
  static void showCreateChatDialog({
    required BuildContext context,
    required Function(String title, String relation) onCreate,
  }) {
    String newTitle = "";
    String selectedRelation = "친구";
    final List<String> relations = ["가족", "부부", "친구", "연인", "인연", "고향", "학교", "회사", "군대", "인터넷 커뮤니티", "기타"];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('새 채팅방 정보'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(hintText: "대화방 이름"),
                onChanged: (value) => newTitle = value,
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: selectedRelation,
                items: relations.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedRelation = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            TextButton(
              onPressed: () {
                if (newTitle.isNotEmpty) {
                  onCreate(newTitle, selectedRelation);
                  Navigator.pop(context);
                }
              },
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
    TextEditingController editController = TextEditingController(text: initialTitle);
    String selectedRelation = initialRelation;
    final List<String> relations = ["가족", "부부", "친구", "연인", "인연", "고향", "학교", "회사", "군대", "인터넷 커뮤니티", "기타"];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('채팅방 정보 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: editController,
                decoration: const InputDecoration(labelText: "이름"),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: "관계"),
                value: selectedRelation,
                items: relations.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedRelation = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
            TextButton(
              onPressed: () {
                if (editController.text.isNotEmpty) {
                  onSave(editController.text, selectedRelation);
                  Navigator.pop(context);
                }
              },
              child: const Text('저장'),
            ),
          ],
        ),
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
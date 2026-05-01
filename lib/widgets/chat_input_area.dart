import 'package:flutter/material.dart';
import '../constants/app_style.dart';

class ChatInputArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.onSend,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  bool _isAiPanelOpen = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.black12)),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.auto_awesome,
                      color: _isAiPanelOpen ? AppStyle.primaryBlue : Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _isAiPanelOpen = !_isAiPanelOpen;
                      });
                    },
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      decoration: InputDecoration(
                        hintText: '메시지를 입력하세요...',
                        fillColor: AppStyle.inputBgColor,
                        filled: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(25),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => widget.onSend(),
                    ),
                  ),
                  IconButton(
                    icon: const CircleAvatar(
                      backgroundColor: AppStyle.primaryBlue,
                      child: Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    onPressed: widget.onSend,
                  ),
                ],
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: _isAiPanelOpen ? 130 : 0,
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: _isAiPanelOpen
                    ? [
                        const BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ]
                    : [],
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                child: Column(
                  children: [
                    _buildAiOptionButton(
                      "💬 대화 피드백 받기",
                      Icons.auto_awesome_motion,
                      () {},
                    ),
                    const SizedBox(height: 10),
                    _buildAiOptionButton(
                      "✨ 자동 응답 생성",
                      Icons.psychology_outlined,
                      () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiOptionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          border: Border.all(color: AppStyle.primaryBlue.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppStyle.primaryBlue),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: AppStyle.primaryBlue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

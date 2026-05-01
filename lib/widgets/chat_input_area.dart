import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../services/llm_assist_service.dart';

class ChatInputArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onRequestFeedback;
  final VoidCallback? onApplyRewrite;
  final bool isFeedbackLoading;
  final String? feedbackError;
  final LlmAssistResponse? feedbackResult;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.onSend,
    this.onRequestFeedback,
    this.onApplyRewrite,
    this.isFeedbackLoading = false,
    this.feedbackError,
    this.feedbackResult,
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
            if (widget.isFeedbackLoading ||
                widget.feedbackError != null ||
                widget.feedbackResult != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppStyle.primaryBlue.withValues(alpha: .2)),
                ),
                child: widget.isFeedbackLoading
                    ? const Text(
                        '피드백을 생성하는 중...',
                        style: TextStyle(
                          color: AppStyle.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : widget.feedbackError != null
                    ? Text(
                        widget.feedbackError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : _buildFeedbackCard(),
              ),
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
                      widget.onRequestFeedback ?? () {},
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

  Widget _buildFeedbackCard() {
    final feedback = widget.feedbackResult;
    if (feedback == null) {
      return const SizedBox.shrink();
    }

    if (!feedback.shouldFeedback) {
      return const Text(
        '현재 문장은 충분히 자연스러워 추가 피드백이 필요하지 않습니다.',
        style: TextStyle(
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (feedback.feedback != null && feedback.feedback!.isNotEmpty) ...[
          const Text(
            '피드백',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(feedback.feedback!),
          const SizedBox(height: 10),
        ],
        if (feedback.reason != null && feedback.reason!.isNotEmpty) ...[
          const Text(
            '이유',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(feedback.reason!),
          const SizedBox(height: 10),
        ],
        if (feedback.rewrite != null && feedback.rewrite!.isNotEmpty) ...[
          const Text(
            '추천 답장',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(feedback.rewrite!),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onApplyRewrite,
              child: const Text('추천 답장 사용'),
            ),
          ),
        ],
      ],
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

import 'package:flutter/material.dart';
import '../constants/app_style.dart';

class ChatInputArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onFeedbackPressed;
  final VoidCallback? onAutoReplyPressed;
  final VoidCallback? onApplyRewrite;
  final bool isFeedbackLoading;
  final bool isAutoReplyLoading;
  final String? feedbackError;
  final String? autoReplyError;
  final bool shouldFeedback;
  final String? feedbackText;
  final String? feedbackReason;
  final String? feedbackRewrite;
  final String? analysisSummary;
  final String? debugSummary;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.onSend,
    this.onFeedbackPressed,
    this.onAutoReplyPressed,
    this.onApplyRewrite,
    this.isFeedbackLoading = false,
    this.isAutoReplyLoading = false,
    this.feedbackError,
    this.autoReplyError,
    this.shouldFeedback = false,
    this.feedbackText,
    this.feedbackReason,
    this.feedbackRewrite,
    this.analysisSummary,
    this.debugSummary,
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
                widget.isAutoReplyLoading ||
                widget.feedbackError != null ||
                widget.autoReplyError != null ||
                widget.feedbackText != null ||
                widget.feedbackReason != null ||
                widget.feedbackRewrite != null ||
                widget.analysisSummary != null)
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
                    : widget.isAutoReplyLoading
                    ? const Text(
                        '자동 응답을 생성하는 중...',
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
                    : widget.autoReplyError != null
                    ? Text(
                        widget.autoReplyError!,
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
                      widget.onFeedbackPressed ?? () {},
                    ),
                    const SizedBox(height: 10),
                    _buildAiOptionButton(
                      "✨ 자동 응답 생성",
                      Icons.psychology_outlined,
                      widget.onAutoReplyPressed ?? () {},
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI 피드백',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppStyle.primaryBlue,
          ),
        ),
        const SizedBox(height: 8),
        if (!widget.shouldFeedback &&
            widget.analysisSummary != null)
          Text(
            widget.analysisSummary!,
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        if (!widget.shouldFeedback &&
            widget.analysisSummary != null &&
            (widget.feedbackText != null ||
                widget.feedbackReason != null ||
                widget.feedbackRewrite != null))
          const SizedBox(height: 10),
        if (widget.feedbackText != null && widget.feedbackText!.isNotEmpty) ...[
          const Text(
            '피드백',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.feedbackText!),
          const SizedBox(height: 10),
        ],
        if (widget.feedbackReason != null && widget.feedbackReason!.isNotEmpty) ...[
          const Text(
            '이유',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.feedbackReason!),
          const SizedBox(height: 10),
        ],
        if (widget.feedbackRewrite != null && widget.feedbackRewrite!.isNotEmpty) ...[
          const Text(
            '추천 답장',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppStyle.primaryBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(widget.feedbackRewrite!),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.onApplyRewrite,
              child: const Text('추천 답장 사용'),
            ),
          ),
        ],
        if (widget.debugSummary != null && widget.debugSummary!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            widget.debugSummary!,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black45,
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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_style.dart';
import '../models/message.dart';

class ChatInputArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onFeedbackPressed;
  final VoidCallback? onAutoReplyPressed;
  final VoidCallback? onApplyRewrite;
  final VoidCallback? onCloseFeedback;
  final ValueChanged<String>? onRegisterModeChanged;
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
  final String selectedRegisterMode;
  final Message? replyTo;
  final VoidCallback? onCancelReply;

  const ChatInputArea({
    super.key,
    required this.controller,
    required this.onSend,
    this.onFeedbackPressed,
    this.onAutoReplyPressed,
    this.onApplyRewrite,
    this.onCloseFeedback,
    this.onRegisterModeChanged,
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
    this.selectedRegisterMode = 'casual',
    this.replyTo,
    this.onCancelReply,
  });

  @override
  State<ChatInputArea> createState() => _ChatInputAreaState();
}

class _ChatInputAreaState extends State<ChatInputArea> {
  bool _isAiPanelOpen = false;
  bool _isDebugExpanded = false;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed) {
          widget.onSend();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  bool _shouldShowFeedbackSurface() {
    return widget.isFeedbackLoading ||
        widget.isAutoReplyLoading ||
        widget.feedbackError != null ||
        widget.autoReplyError != null ||
        widget.feedbackText != null ||
        widget.feedbackReason != null ||
        widget.feedbackRewrite != null ||
        widget.analysisSummary != null;
  }

  @override
  Widget build(BuildContext context) {
    final maxFeedbackHeight = MediaQuery.of(context).size.height * 0.28;
    final maxPanelHeight = MediaQuery.of(context).size.height * 0.22;

    return Container(
      decoration: BoxDecoration(
        color: AppStyle.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply preview strip
            if (widget.replyTo != null) _buildReplyPreview(),
            // Feedback surface
            if (_shouldShowFeedbackSurface())
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppStyle.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppStyle.primary.withValues(alpha: 0.2)),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxFeedbackHeight),
                  child: SingleChildScrollView(
                    child: _buildStatusOrFeedback(),
                  ),
                ),
              ),
            // Register mode selector
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _buildRegisterModeSelector(),
            ),
            // Input row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _isAiPanelOpen = !_isAiPanelOpen),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _isAiPanelOpen
                            ? AppStyle.primary
                            : AppStyle.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        color: _isAiPanelOpen ? Colors.white : AppStyle.primary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppStyle.inputBgColor,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: AppStyle.border),
                      ),
                      child: TextField(
                        controller: widget.controller,
                        focusNode: _focusNode,
                        maxLines: 4,
                        minLines: 1,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppStyle.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: '메시지 입력...',
                          hintStyle: TextStyle(
                              color: AppStyle.textTertiary, fontSize: 15),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: widget.onSend,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppStyle.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            // AI panel
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: _isAiPanelOpen
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: maxPanelHeight),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildAiButton(
                                label: "대화 피드백 받기",
                                icon: Icons.auto_awesome_motion_rounded,
                                onTap: widget.onFeedbackPressed ?? () {},
                              ),
                              const SizedBox(height: 8),
                              _buildAiButton(
                                label: "자동 응답 생성",
                                icon: Icons.psychology_rounded,
                                onTap: widget.onAutoReplyPressed ?? () {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    final reply = widget.replyTo!;
    final senderLabel = reply.isMe ? '나' : reply.sender;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppStyle.primaryLight,
        border: const Border(
          top: BorderSide(color: AppStyle.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppStyle.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$senderLabel에게 답장',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppStyle.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppStyle.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: widget.onCancelReply,
            icon: const Icon(Icons.close_rounded,
                size: 18, color: AppStyle.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterModeSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppStyle.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _buildModeChip('편한 대화', 'casual')),
          const SizedBox(width: 4),
          Expanded(child: _buildModeChip('격식 대화', 'formal')),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, String mode) {
    final selected = widget.selectedRegisterMode == mode;
    return GestureDetector(
      onTap: () => widget.onRegisterModeChanged?.call(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppStyle.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppStyle.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppStyle.primary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildAiButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 16),
        decoration: BoxDecoration(
          color: AppStyle.primaryLight,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppStyle.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: AppStyle.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: AppStyle.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOrFeedback() {
    if (widget.isFeedbackLoading || widget.isAutoReplyLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                color: AppStyle.primary, strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            widget.isFeedbackLoading
                ? '피드백을 생성하는 중...'
                : '자동 응답을 생성하는 중...',
            style: const TextStyle(
              color: AppStyle.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      );
    }
    if (widget.feedbackError != null || widget.autoReplyError != null) {
      return Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.feedbackError ?? widget.autoReplyError ?? '',
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      );
    }
    return _buildFeedbackCard();
  }

  Widget _buildFeedbackCard() {
    final shouldShowDebug = kDebugMode &&
        ((widget.debugSummary?.isNotEmpty == true) ||
            (widget.feedbackReason?.isNotEmpty == true));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_awesome_rounded,
                size: 14, color: AppStyle.primary),
            const SizedBox(width: 6),
            const Text(
              'AI 피드백',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppStyle.primary,
              ),
            ),
            if (kDebugMode) ...[
              const SizedBox(width: 8),
              _buildNluBadge(),
            ],
            const Spacer(),
            GestureDetector(
              onTap: widget.onCloseFeedback,
              child: const Icon(Icons.close_rounded,
                  size: 18, color: AppStyle.textSecondary),
            ),
          ],
        ),
        if (!widget.shouldFeedback && widget.analysisSummary != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.analysisSummary!,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppStyle.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (widget.feedbackText?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          const Text('피드백',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppStyle.primary,
                  letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Text(widget.feedbackText!,
              style: const TextStyle(fontSize: 13.5, height: 1.4)),
        ],
        if (widget.feedbackRewrite?.isNotEmpty == true) ...[
          const SizedBox(height: 12),
          const Text('추천 답장',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppStyle.primary,
                  letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppStyle.border),
            ),
            child: Text(widget.feedbackRewrite!,
                style: const TextStyle(fontSize: 13.5, height: 1.4)),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: widget.onApplyRewrite,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppStyle.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '이 답장 사용하기',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        if (shouldShowDebug) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                setState(() => _isDebugExpanded = !_isDebugExpanded),
            child: Text(
              _isDebugExpanded ? '디버그 정보 숨기기' : '디버그 정보 보기',
              style: const TextStyle(
                fontSize: 11,
                color: AppStyle.textTertiary,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
        if (shouldShowDebug && _isDebugExpanded) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppStyle.border),
            ),
            child: Text(
              [
                if (widget.feedbackReason?.isNotEmpty == true)
                  'reason: ${widget.feedbackReason!}',
                if (widget.debugSummary?.isNotEmpty == true)
                  widget.debugSummary!,
              ].join('\n'),
              style: const TextStyle(
                  fontSize: 10.5, color: AppStyle.textSecondary, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNluBadge() {
    final debug = widget.debugSummary ?? '';
    String label = 'NLU: -';
    Color color = AppStyle.textTertiary;
    if (debug.contains('nluSource=available') ||
        debug.contains('partnerEmotionSource=kote')) {
      label = 'NLU: on';
      color = AppStyle.online;
    } else if (debug.contains('nluSource=fallback') ||
        debug.contains('partnerEmotionSource=fallback')) {
      // nluSource=fallback → rule-based 분석 수행됨 (분석 자체는 작동 중)
      label = 'NLU: fallback';
      color = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

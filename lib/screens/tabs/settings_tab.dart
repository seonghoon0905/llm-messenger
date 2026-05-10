import 'package:flutter/material.dart';
import '../../constants/app_style.dart';
import '../../services/api_service.dart';
import '../../services/db_helper.dart';

class SettingsTab extends StatefulWidget {
  final VoidCallback onLogout;

  const SettingsTab({super.key, required this.onLogout});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  final ApiService _apiService = ApiService();

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('회원 탈퇴',
            style: TextStyle(
                fontWeight: FontWeight.w700, color: Colors.redAccent)),
        content: const Text(
          '정말로 탈퇴하시겠습니까?\n모든 데이터가 삭제되며 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _handleDeleteAccount();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDeleteAccount() async {
    final userId = AppStyle.myLoggedInId;
    if (userId == null) return;

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(color: AppStyle.primary),
              SizedBox(width: 16),
              Text('처리 중...'),
            ],
          ),
        ),
      );
    }

    try {
      // 1. Call backend (may fail if endpoint not implemented)
      await _apiService.deleteAccount(userId);
    } catch (_) {
      // Backend error — proceed with local cleanup anyway
    }

    // 2. Clear local DB
    await DBHelper().clearAllData();

    // 3. Disconnect socket and clear session
    AppStyle.disconnectSocket();
    AppStyle.globalStream = null;
    AppStyle.myLoggedInId = null;
    AppStyle.myProfile = null;

    if (mounted) {
      Navigator.pop(context); // close loading dialog
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.backgroundGrey,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(
              child: _buildSection(
                title: '계정',
                children: [
                  _buildTile(
                    icon: Icons.logout_rounded,
                    iconColor: Colors.redAccent,
                    iconBg: Colors.red.shade50,
                    label: '로그아웃',
                    labelColor: Colors.redAccent,
                    onTap: widget.onLogout,
                  ),
                  _buildTile(
                    icon: Icons.delete_forever_rounded,
                    iconColor: Colors.red.shade700,
                    iconBg: Colors.red.shade50,
                    label: '회원 탈퇴',
                    labelColor: Colors.red.shade700,
                    onTap: _showDeleteAccountDialog,
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: _buildSection(
                title: '앱 정보',
                children: [
                  _buildInfoTile(
                    icon: Icons.info_outline_rounded,
                    iconColor: AppStyle.primary,
                    iconBg: AppStyle.primaryLight,
                    label: '버전',
                    value: 'v1.0.2',
                  ),
                  _buildInfoTile(
                    icon: Icons.psychology_rounded,
                    iconColor: const Color(0xFF7C3AED),
                    iconBg: const Color(0xFFF5F3FF),
                    label: 'AI 엔진',
                    value: 'GPT-4o mini',
                  ),
                ],
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: AppStyle.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: const Text(
        '설정',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppStyle.textPrimary,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppStyle.textTertiary,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppStyle.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: children.asMap().entries.map((e) {
              final isLast = e.key == children.length - 1;
              return Column(
                children: [
                  e.value,
                  if (!isLast)
                    const Padding(
                      padding: EdgeInsets.only(left: 68),
                      child: Divider(
                          height: 0.5,
                          thickness: 0.5,
                          color: AppStyle.divider),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    Color? labelColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? AppStyle.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppStyle.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppStyle.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: AppStyle.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

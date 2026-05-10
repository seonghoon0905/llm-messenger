import 'package:flutter/material.dart';
import '../constants/app_style.dart';
import '../screens/main_screen.dart';
import '../models/user_profile.dart';
import '../services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  bool _isLoading = false;
  bool _pwVisible = false;
  final ApiService _apiService = ApiService();

  Future<void> _handleLogin() async {
    if (_idController.text.trim().isEmpty ||
        _pwController.text.trim().isEmpty) {
      _showError("아이디와 비밀번호를 입력해주세요.");
      return;
    }
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.login(
        _idController.text.trim(),
        _pwController.text.trim(),
      );
      if (data['success'] == true) {
        AppStyle.myLoggedInId = data['user_id'];
        AppStyle.myProfile = UserProfile(
          userId: data['user_id'],
          name: data['nickname'] ?? data['user_id'],
          statusMessage: data['status_message'] ?? "상태 메시지가 없습니다.",
          isSharingPersonality: true,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      } else {
        _showError(data['message'] ?? data['detail'] ?? "아이디 또는 비밀번호가 틀렸습니다.");
      }
    } catch (e) {
      _showError("서버 연결 실패: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  void _showSignupDialog() {
    final idCtrl = TextEditingController();
    final pwCtrl = TextEditingController();
    final nickCtrl = TextEditingController();
    final statusCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> submit() async {
            if (idCtrl.text.trim().isEmpty ||
                pwCtrl.text.trim().isEmpty ||
                nickCtrl.text.trim().isEmpty) {
              _showError("아이디, 비밀번호, 닉네임을 입력해주세요.");
              return;
            }
            setModalState(() => isSubmitting = true);
            final result = await _apiService.signup(
              userId: idCtrl.text.trim(),
              password: pwCtrl.text.trim(),
              nickname: nickCtrl.text.trim(),
              statusMessage: statusCtrl.text.trim(),
            );
            setModalState(() => isSubmitting = false);
            if (result['success'] == true) {
              _idController.text = idCtrl.text.trim();
              _pwController.text = pwCtrl.text.trim();
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              _showError("회원가입이 완료되었습니다. 로그인해주세요.");
            } else {
              _showError(result['message'] ?? "회원가입에 실패했습니다.");
            }
          }

          return AlertDialog(
            title: const Text("회원가입",
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: idCtrl,
                    decoration: const InputDecoration(labelText: "아이디"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: "비밀번호"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nickCtrl,
                    decoration: const InputDecoration(labelText: "닉네임"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: statusCtrl,
                    decoration:
                        const InputDecoration(labelText: "상태 메시지(선택)"),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text("취소"),
              ),
              ElevatedButton(
                onPressed: isSubmitting ? null : submit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text("가입"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyle.primary,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // Brand hero area
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: const Icon(
                        Icons.psychology_rounded,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'LLM Messenger',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'AI 코칭 메신저',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Login card
            Container(
              decoration: const BoxDecoration(
                color: AppStyle.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '로그인',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppStyle.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '계속하려면 로그인하세요',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppStyle.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _buildInputField(
                    controller: _idController,
                    label: '아이디',
                    icon: Icons.person_outline_rounded,
                    onSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 14),
                  _buildInputField(
                    controller: _pwController,
                    label: '비밀번호',
                    icon: Icons.lock_outline_rounded,
                    isPassword: true,
                    onSubmitted: (_) => _handleLogin(),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppStyle.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              '로그인',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading ? null : _showSignupDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: AppStyle.primary,
                      ),
                      child: const Text(
                        '계정이 없으신가요?  회원가입',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
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

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword && !_pwVisible,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        fontSize: 15,
        color: AppStyle.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppStyle.textSecondary, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _pwVisible
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: AppStyle.textSecondary,
                  size: 20,
                ),
                onPressed: () => setState(() => _pwVisible = !_pwVisible),
              )
            : null,
      ),
    );
  }
}

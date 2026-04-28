import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/app_style.dart';
import '../screens/main_screen.dart';
import '../models/user_profile.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();
  bool _isLoading = false;

  Future<void> _handleLogin() async {
    if (_idController.text.trim().isEmpty ||
        _pwController.text.trim().isEmpty) {
      _showError("아이디와 비밀번호를 입력해주세요.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("${AppStyle.baseUrl}/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": _idController.text.trim(),
          "password": _pwController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success']) {
        // 1. 세션 ID 저장
        AppStyle.myLoggedInId = data['user_id'];

        // 2. [핵심] 서버에서 받은 최신 닉네임과 상태 메시지로 프로필 생성
        AppStyle.myProfile = UserProfile(
          userId: data['user_id'],
          name: data['nickname'] ?? data['user_id'],
          statusMessage: data['status_message'] ?? "상태 메시지가 없습니다.",
          isSharingPersonality: true,
        );

        if (!mounted) return;

        // 메인 화면으로 이동
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      } else {
        _showError(data['message'] ?? "아이디 또는 비밀번호가 틀렸습니다.");
      }
    } catch (e) {
      _showError("서버 연결 실패: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("🧠", style: TextStyle(fontSize: 50)),
              const SizedBox(height: 20),
              const Text(
                "LLM Coaching Messenger",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppStyle.primaryBlue,
                ),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  labelText: "User ID",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                onSubmitted: (_) => _handleLogin(), // 엔터키 로그인 지원
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _pwController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                onSubmitted: (_) => _handleLogin(), // 엔터키 로그인 지원
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyle.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "로그인",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

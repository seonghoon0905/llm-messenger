import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/main_screen.dart'; // 메인 스크린 임포트

void main() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  runApp(const LLMMessenger());
}

class LLMMessenger extends StatelessWidget {
  const LLMMessenger({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OPEN SW TEMP PROJECT',
      debugShowCheckedModeBanner: false, // 오른쪽 상단 디버그 띠 제거
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true, // 최신 Material 3 디자인 적용
      ),
      // 앱의 시작 화면을 MainScreen으로 설정
      home: const MainScreen(),
    );
  }
}
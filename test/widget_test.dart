import 'package:flutter_test/flutter_test.dart';

import 'package:llm_messenger/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('AI 코칭 메신저'), findsOneWidget);
    expect(find.text('로그인'), findsWidgets);
    expect(find.text('아이디'), findsOneWidget);
    expect(find.text('비밀번호'), findsOneWidget);
    expect(find.text('계정이 없으신가요?  회원가입'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

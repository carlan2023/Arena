import 'package:arena/screens/login_screen.dart';
import 'package:arena/screens/register_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The old email screens are unused since M2.12 (phone login) and wait for
// removal; this keeps the B5 fix covered until then.
Widget oldApp() => MaterialApp(
  routes: {
    '/': (_) => const LoginScreen(),
    '/register': (_) => const RegisterScreen(),
  },
);

void main() {
  testWidgets('login link on the register screen returns to login (B5)', (
    tester,
  ) async {
    await tester.pumpWidget(oldApp());
    await tester.tap(find.text("Don't have an account? Register"));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    await tester.tap(find.text('Already have an account? Login'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });
}

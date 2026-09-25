import 'dart:async';

import 'package:arena/models/user_model.dart';
import 'package:arena/screens/login_screen.dart';
import 'package:arena/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuthService extends AuthService {
  FakeAuthService(this.result);

  final Completer<User?> result;
  final calls = <(String, String)>[];

  @override
  Future<User?> login(String email, String password) {
    calls.add((email, password));
    return result.future;
  }
}

Widget app(AuthService auth) => MaterialApp(
  routes: {
    '/': (_) => LoginScreen(authService: auth),
    '/home': (_) => const Scaffold(body: Text('home page')),
  },
);

Future<void> fillAndSubmit(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@b.c');
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Password'),
    'secret',
  );
  await tester.tap(find.text('Login'));
  await tester.pump();
}

void main() {
  testWidgets('calls the auth service and opens home on success (B4)', (
    tester,
  ) async {
    final auth = FakeAuthService(Completer());
    await tester.pumpWidget(app(auth));
    await fillAndSubmit(tester);

    expect(auth.calls, [('a@b.c', 'secret')]);
    expect(find.text('Logging in...'), findsOneWidget);

    auth.result.complete(User(id: '1', email: 'a@b.c', name: 'A'));
    await tester.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
  });

  testWidgets('shows an error and resets loading on failure', (tester) async {
    final auth = FakeAuthService(Completer());
    await tester.pumpWidget(app(auth));
    await fillAndSubmit(tester);

    auth.result.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Login failed'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('does not call the service when the form is empty', (
    tester,
  ) async {
    final auth = FakeAuthService(Completer());
    await tester.pumpWidget(app(auth));
    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(auth.calls, isEmpty);
    expect(find.text('Please enter your email'), findsOneWidget);
  });
}

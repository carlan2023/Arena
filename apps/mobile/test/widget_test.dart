import 'package:arena/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts on the login screen', (tester) async {
    await tester.pumpWidget(const ArenaApp());

    expect(find.text('Arena'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}

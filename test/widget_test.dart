import 'package:flutter_test/flutter_test.dart';

import 'package:arena/main.dart';

void main() {
  testWidgets('App opens on the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ArenaApp());

    expect(find.text('Arena'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });

  testWidgets('Login shows errors when fields are empty', (tester) async {
    await tester.pumpWidget(const ArenaApp());

    await tester.tap(find.text('Login'));
    await tester.pump();

    expect(find.text('Please enter your email'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);
  });
}

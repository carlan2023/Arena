import 'package:arena/app/app.dart';
import 'package:arena/online/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app starts on the phone login screen when logged out', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStoreProvider.overrideWithValue(MemorySessionStore()),
          incomingLinksProvider.overrideWithValue(const Stream.empty()),
        ],
        child: const ArenaApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your phone number'), findsOneWidget);
    expect(find.byKey(const Key('phone')), findsOneWidget);
  });
}

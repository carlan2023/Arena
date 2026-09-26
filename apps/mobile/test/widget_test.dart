import 'package:arena/app/app.dart';
import 'package:arena/online/auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app opens on home with no login wall', (tester) async {
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
    expect(find.text('Free games need no sign up. Just play.'), findsOneWidget);
    expect(find.byKey(const Key('play-friends')), findsOneWidget);
    expect(find.byKey(const Key('phone')), findsNothing);
  });
}

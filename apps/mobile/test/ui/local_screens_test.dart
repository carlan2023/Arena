import 'package:arena/game/bots.dart';
import 'package:arena/game/dice.dart';
import 'package:arena/game/local_game.dart';
import 'package:arena/screens/home_screen.dart';
import 'package:arena/ui/local_game_screen.dart';
import 'package:arena/ui/local_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

void main() {
  testWidgets('setup starts a 1v1 with a human and a bot by default', (
    tester,
  ) async {
    LocalGameConfig? started;
    await tester.pumpWidget(
      MaterialApp(home: LocalSetupScreen(onStart: (c) => started = c)),
    );
    await tester.tap(find.byKey(const Key('start')));
    expect(started!.mode, GameMode.oneVsOne);
    expect(started!.seats, {
      PlayerColor.red: SeatKind.human,
      PlayerColor.yellow: SeatKind.normalBot,
    });
  });

  testWidgets('setup for 2v2 seats all four colours', (tester) async {
    LocalGameConfig? started;
    await tester.pumpWidget(
      MaterialApp(home: LocalSetupScreen(onStart: (c) => started = c)),
    );
    await tester.tap(find.text('2v2'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('start')));
    expect(started!.mode, GameMode.teams);
    expect(started!.players, PlayerColor.values);
  });

  testWidgets('free for all needs two seats filled', (tester) async {
    LocalGameConfig? started;
    await tester.pumpWidget(
      MaterialApp(home: LocalSetupScreen(onStart: (c) => started = c)),
    );
    await tester.tap(find.text('All'));
    await tester.pump();
    for (final c in ['green', 'yellow', 'blue']) {
      await tester.tap(find.byKey(Key('seat-$c')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empty').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('start')));
    expect(started, isNull);
  });

  testWidgets('the game screen rolls and shows the dice', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const config = LocalGameConfig(
      mode: GameMode.oneVsOne,
      seats: {
        PlayerColor.red: SeatKind.human,
        PlayerColor.yellow: SeatKind.human,
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diceSourceProvider.overrideWithValue(ScriptedDiceSource([(4, 2)])),
        ],
        child: const MaterialApp(home: LocalGameScreen(config: config)),
      ),
    );
    await tester.tap(find.byKey(const Key('roll')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Die 4, used'), findsOneWidget);
    expect(find.textContaining('no move possible'), findsOneWidget);
  });

  testWidgets('home leads to pass and play', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeScreen())),
    );
    await tester.tap(find.byKey(const Key('pass-and-play')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalSetupScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('start')));
    await tester.pumpAndSettle();
    expect(find.byType(LocalGameScreen), findsOneWidget);
    // Leave the game so its timers stop.
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}

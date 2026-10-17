import 'package:arena/game/bots.dart';
import 'package:arena/game/dice.dart';
import 'package:arena/game/local_game.dart';
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

  for (final (width, scale) in [
    (320.0, 1.0),
    (360.0, 1.0),
    (412.0, 1.0),
    (360.0, 1.3),
    (320.0, 2.0),
  ]) {
    testWidgets('setup fits a ${width.toInt()} px phone at text x$scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(home: LocalSetupScreen(onStart: (_) {})),
      );
      for (final mode in ['1v1', 'All', '2v2']) {
        await tester.tap(find.text(mode));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: mode);
        for (final c in PlayerColor.values) {
          final seat = find.byKey(Key('seat-${c.name}'));
          if (seat.evaluate().isEmpty) continue;
          final box = tester.getRect(seat);
          expect(box.right, lessThanOrEqualTo(width), reason: '$mode $c');
          expect(box.left, greaterThanOrEqualTo(0), reason: '$mode $c');
        }
        expect(tester.getRect(find.text(mode)).right, lessThanOrEqualTo(width));
      }
    });
  }

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
}

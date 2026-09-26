import 'package:arena/game/bots.dart';
import 'package:arena/game/dice.dart';
import 'package:arena/game/local_game.dart';
import 'package:arena/game/move_planner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_bots/ludo_bots.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const yellow = PlayerColor.yellow;

const timings = LocalGameTimings(
  autoPlay: Duration(milliseconds: 500),
  botRoll: Duration(milliseconds: 100),
  botMove: Duration(milliseconds: 100),
);

const twoHumans = LocalGameConfig(
  mode: GameMode.oneVsOne,
  seats: {red: SeatKind.human, yellow: SeatKind.human},
);

ProviderContainer container(DiceSource dice) {
  final c = ProviderContainer(
    overrides: [
      diceSourceProvider.overrideWithValue(dice),
      localTimingsProvider.overrideWithValue(timings),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  testWidgets('worked example 1 by hand: release, then move 3', (tester) async {
    final c = container(ScriptedDiceSource([(6, 3)]));
    final provider = localGameProvider(twoHumans);
    final sub = c.listen(provider, (_, _) {});
    final ctrl = c.read(provider.notifier);

    expect(sub.read().canRoll, isTrue);
    ctrl.roll();
    var view = sub.read();
    expect(view.canRoll, isFalse);
    expect(view.selectable, hasLength(4));

    ctrl.tapPieces([const PieceRef(red, 0)]);
    view = sub.read();
    ctrl.chooseOption(
      view.options.firstWhere((o) => o.kind == OptionKind.single),
    );
    view = sub.read();
    expect(view.canUndo, isTrue);
    expect(view.state.pieces[red]![0], 0);
    expect(view.dice.map((d) => d.used), [true, false]);

    // Only one way to use the 3 remains: it plays itself after 0.5 s.
    await tester.pump(const Duration(milliseconds: 499));
    expect(sub.read().state.pieces[red]![0], 0);
    await tester.pump(const Duration(milliseconds: 1));
    view = sub.read();
    expect(view.state.pieces[red]![0], 3);
    expect(view.state.current, yellow);
    expect(view.canUndo, isFalse);
    expect(view.canRoll, isTrue, reason: 'yellow, a human, may roll');
  });

  testWidgets('undo takes the step back and stops auto play', (tester) async {
    final c = container(ScriptedDiceSource([(6, 3)]));
    final provider = localGameProvider(twoHumans);
    final sub = c.listen(provider, (_, _) {});
    final ctrl = c.read(provider.notifier);
    ctrl.roll();
    ctrl.tapPieces([const PieceRef(red, 0)]);
    ctrl.chooseOption(
      sub.read().options.firstWhere((o) => o.kind == OptionKind.single),
    );
    ctrl.undo();
    expect(sub.read().state.pieces[red], everyElement(kAtHome));
    expect(sub.read().canUndo, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(sub.read().state.pieces[red], everyElement(kAtHome));
    expect(sub.read().state.current, red);
  });

  testWidgets('both dice in one tap', (tester) async {
    final c = container(ScriptedDiceSource([(6, 3)]));
    final provider = localGameProvider(twoHumans);
    final sub = c.listen(provider, (_, _) {});
    final ctrl = c.read(provider.notifier);
    ctrl.roll();
    ctrl.tapPieces([const PieceRef(red, 2)]);
    ctrl.chooseOption(
      sub.read().options.firstWhere((o) => o.kind == OptionKind.both),
    );
    expect(sub.read().state.pieces[red]![2], 3);
    expect(sub.read().state.current, yellow);
  });

  testWidgets('a roll with no move passes the turn with a message', (
    tester,
  ) async {
    final c = container(ScriptedDiceSource([(2, 3)]));
    final provider = localGameProvider(twoHumans);
    final sub = c.listen(provider, (_, _) {});
    c.read(provider.notifier).roll();
    final view = sub.read();
    expect(view.message, contains('no move'));
    expect(view.state.current, yellow);
    expect(view.dice.map((d) => d.value), [2, 3]);
  });

  testWidgets('actions out of turn are ignored', (tester) async {
    final c = container(ScriptedDiceSource([(1, 2)]));
    const config = LocalGameConfig(
      mode: GameMode.oneVsOne,
      seats: {red: SeatKind.normalBot, yellow: SeatKind.human},
    );
    final provider = localGameProvider(config);
    final sub = c.listen(provider, (_, _) {});
    final ctrl = c.read(provider.notifier);
    expect(sub.read().canRoll, isFalse);
    ctrl.roll();
    ctrl.undo();
    ctrl.tapPieces([const PieceRef(red, 0)]);
    expect(sub.read().state.rollNumber, 0);
    // The bot rolls by itself.
    await tester.pump(const Duration(milliseconds: 100));
    expect(sub.read().state.rollNumber, 1);
    expect(sub.read().canRoll, isTrue);
  });

  testWidgets('four bots play a whole game to the end', (tester) async {
    final c = ProviderContainer(
      overrides: [
        localTimingsProvider.overrideWithValue(
          const LocalGameTimings(
            autoPlay: Duration(milliseconds: 1),
            botRoll: Duration(milliseconds: 1),
            botMove: Duration(milliseconds: 1),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    const config = LocalGameConfig(
      mode: GameMode.freeForAll,
      seats: {
        PlayerColor.red: SeatKind.normalBot,
        PlayerColor.green: SeatKind.easyBot,
        PlayerColor.yellow: SeatKind.normalBot,
        PlayerColor.blue: SeatKind.easyBot,
      },
    );
    final provider = localGameProvider(config);
    final sub = c.listen(provider, (_, _) {});
    for (var i = 0; i < 20000; i++) {
      if (sub.read().state.phase == TurnPhase.gameOver) break;
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(sub.read().state.phase, TurnPhase.gameOver);
    expect(sub.read().message, contains('won'));
  });

  test('config lists seated colours in turn order', () {
    const config = LocalGameConfig(
      mode: GameMode.freeForAll,
      seats: {
        PlayerColor.blue: SeatKind.human,
        PlayerColor.red: SeatKind.human,
      },
    );
    expect(config.players, [PlayerColor.red, PlayerColor.blue]);
  });

  test('bot chooser returns a legal sequence', () {
    final s = applyRoll(
      GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
      6,
      3,
    );
    final moves = botForSeat(SeatKind.normalBot).chooseMoves(s);
    expect(legalSequences(s), anyElement(equals(moves)));
    expect(() => botForSeat(SeatKind.human), throwsArgumentError);
    expect(botForSeat(SeatKind.easyBot), isA<EasyBot>());
    expect(botForSeat(SeatKind.normalBot), isA<NormalBot>());
  });
}

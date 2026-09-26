import 'package:arena/game/dice.dart';
import 'package:arena/game/move_planner.dart';
import 'package:arena/game/move_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;

GameState rolled(Map<PlayerColor, List<int>> pieces, int a, int b) => applyRoll(
  GameState.custom(
    mode: GameMode.freeForAll,
    players: const [red, green],
    pieces: pieces,
  ),
  a,
  b,
);

void main() {
  test('all home: the yard stack is selected at once, one tap per die', () {
    final sel = MoveSelection(
      applyRoll(
        GameState.newGame(
          mode: GameMode.oneVsOne,
          players: [red, PlayerColor.yellow],
        ),
        6,
        3,
      ),
    );
    // Four yard pieces sit on four spots, so nothing is preselected.
    expect(sel.selectable, hasLength(4));
    expect(sel.selected, isEmpty);

    expect(sel.select([const PieceRef(red, 1)]), isTrue);
    final release = sel.options.firstWhere((o) => o.kind == OptionKind.single);
    sel.choose(release);
    expect(sel.steps, [Move.release(red, 1)]);
    // Only the released piece can use the 3, so it is selected for us.
    expect(sel.selected, [const PieceRef(red, 1)]);
    expect(sel.options.single.target, 3);
    expect(sel.canUndo, isTrue);

    sel.choose(sel.options.single);
    expect(sel.rollEnded, isTrue);
    expect(sel.selectable, isEmpty);
    expect(sel.canUndo, isFalse);
  });

  test('tapping a piece that cannot move clears the selection', () {
    final sel = MoveSelection(
      rolled(
        {
          red: [10, 20, kAtHome, kAtHome],
        },
        2,
        3,
      ),
    );
    expect(sel.select([const PieceRef(red, 0)]), isTrue);
    expect(sel.options, isNotEmpty);
    expect(sel.select([const PieceRef(red, 3)]), isFalse);
    expect(sel.selected, isEmpty);
    expect(sel.options, isEmpty);
  });

  test('a stack offers its options once, including the block move', () {
    final sel = MoveSelection(
      rolled(
        {
          red: [5, 5, kAtHome, kAtHome],
        },
        4,
        4,
      ),
    );
    // Both movable pieces share one cell, so the stack is preselected.
    expect(sel.selected.toSet(), {
      const PieceRef(red, 0),
      const PieceRef(red, 1),
    });
    final kinds = sel.options.map((o) => (o.kind, o.target)).toList();
    expect(kinds.toSet().length, kinds.length, reason: 'no duplicates');
    expect(kinds, contains((OptionKind.block, 9)));
    expect(kinds, contains((OptionKind.single, 9)));
    expect(kinds, contains((OptionKind.both, 13)));
  });

  test('undo returns the dice and reselects', () {
    final sel = MoveSelection(
      rolled(
        {
          red: [10, 20, kAtHome, kAtHome],
        },
        2,
        3,
      ),
    );
    sel.select([const PieceRef(red, 0)]);
    sel.choose(sel.options.firstWhere((o) => o.moves.single.die == 2));
    expect(diceFaces(sel.state), const [
      DieFace(2, used: true),
      DieFace(3, used: false),
    ]);
    expect(sel.undo(), isTrue);
    expect(diceFaces(sel.state), const [
      DieFace(2, used: false),
      DieFace(3, used: false),
    ]);
    expect(sel.undo(), isFalse);
  });

  test('forced rest is exposed for auto play', () {
    final sel = MoveSelection(
      rolled(
        {
          red: [40, kFinished, kFinished, kFinished],
        },
        2,
        3,
      ),
    );
    expect(sel.forcedRest, isNotNull);
    sel.playRest(sel.forcedRest!);
    expect(sel.rollEnded, isTrue);
  });

  group('diceFaces', () {
    GameState withDice(List<int> last, List<int> left) => GameState.custom(
      mode: GameMode.freeForAll,
      players: const [red, green],
      lastRoll: last,
      remainingDice: left,
    );

    test('before any roll there are no dice', () {
      expect(diceFaces(withDice(const [], const [])), isEmpty);
    });

    test('a double marks one die at a time', () {
      expect(diceFaces(withDice(const [4, 4], const [4])), const [
        DieFace(4, used: true),
        DieFace(4, used: false),
      ]);
    });

    test('after the roll every die is used', () {
      expect(
        diceFaces(withDice(const [5, 1], const [])).every((d) => d.used),
        isTrue,
      );
    });
  });

  test('scripted dice play back in order', () {
    final dice = ScriptedDiceSource([(6, 3), (1, 2)]);
    expect(dice.roll(), (6, 3));
    expect(dice.roll(), (1, 2));
    expect(dice.roll, throwsRangeError);
  });

  test('random dice stay in range', () {
    final dice = RandomDiceSource();
    for (var i = 0; i < 200; i++) {
      final (a, b) = dice.roll();
      expect(a, inInclusiveRange(1, 6));
      expect(b, inInclusiveRange(1, 6));
    }
  });
}

import 'package:arena/board/piece_layout.dart';
import 'package:arena/game/board_marks.dart';
import 'package:arena/game/move_planner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const blue = PlayerColor.blue;

// README worked examples 2 to 4: a red block of two on square 10 and a blue
// piece on square 5 (blue progress 18).
GameState blockPosition() => GameState.custom(
  mode: GameMode.freeForAll,
  players: const [red, blue],
  current: blue,
  pieces: {
    red: [10, 10, kAtHome, kAtHome],
    blue: [18, kAtHome, kAtHome, kAtHome],
  },
);

GameState afterDoubleSix() {
  var s = applyRoll(blockPosition(), 6, 6);
  s = apply(s, Move.release(blue, 1));
  return apply(s, Move.release(blue, 2));
}

void main() {
  test('a block gets a whole bar when it cannot be broken', () {
    final s = applyRoll(blockPosition(), 4, 6);
    final bars = blockBars(s, legal: legalMoves(s));
    expect(bars, hasLength(1));
    expect(bars.single.square, 10);
    expect(bars.single.color, red);
    expect(bars.single.count, 2);
    expect(bars.single.cracked, isFalse);
  });

  test('the bar cracks after a double 6 when blue can reach it', () {
    final s = applyRoll(afterDoubleSix(), 5, 2);
    final bars = blockBars(s, legal: legalMoves(s));
    final redBar = bars.firstWhere((b) => b.color == red);
    expect(redBar.cracked, isTrue);
    // Blue's own new block on its start square never cracks for blue.
    expect(bars.firstWhere((b) => b.color == blue).cracked, isFalse);
  });

  test('no crack without legal moves to show', () {
    final s = applyRoll(afterDoubleSix(), 5, 2);
    expect(blockBars(s).every((b) => !b.cracked), isTrue);
  });

  test('ghost labels and points', () {
    final s = applyRoll(
      GameState.custom(
        mode: GameMode.oneVsOne,
        players: const [red, PlayerColor.yellow],
        pieces: {
          red: [10, kAtHome, kAtHome, kAtHome],
        },
      ),
      3,
      5,
    );
    const piece = PieceRef(red, 0);
    final options = MovePlanner(s).optionsFor(piece);
    final ghosts = ghostMarks(options);
    expect(ghosts.map((g) => g.label).toSet(), {'3', '5', '5+3'});
    for (final g in ghosts) {
      expect(g.point, piecePoint(piece, options[g.id].target));
    }
  });

  test('block ghost is nudged off a single ghost on the same square', () {
    final s = applyRoll(
      GameState.custom(
        mode: GameMode.freeForAll,
        players: const [red, blue],
        pieces: {
          red: [5, 5, kAtHome, kAtHome],
        },
      ),
      4,
      4,
    );
    final options = MovePlanner(s).optionsFor(const PieceRef(red, 0));
    final ghosts = ghostMarks(options);
    final block = ghosts.firstWhere((g) => g.label == 'B4');
    final single = ghosts.firstWhere((g) => g.label == '4');
    expect(block.point, isNot(single.point));
  });
}

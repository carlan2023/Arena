import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  // A red block of two on absolute square 10, a blue piece 5 squares behind.
  GameState blockPosition() => position(
    players: const [red, blue],
    current: blue,
    pieces: {
      red: [10, 10, kAtHome, kAtHome],
      blue: [progressAt(blue, 5), kAtHome, kAtHome, kAtHome],
    },
  );

  // Blue plays a double 6 by releasing two pieces, earning the extra roll.
  GameState afterDoubleSix() {
    var s = applyRoll(blockPosition(), 6, 6);
    expect(legalMoves(s), isNot(contains(Move.advance(blue, 0, 6))));
    s = apply(s, Move.release(blue, 1));
    final r = applyMove(s, Move.release(blue, 2));
    expect(r.extraRoll, isTrue);
    expect(r.state.phase, TurnPhase.awaitingRoll);
    expect(r.state.current, blue);
    return r.state;
  }

  test('worked example 1: release with 6 and move 3', () {
    var s = GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]);
    s = applyRoll(s, 6, 3);
    expect(legalMoves(s), [for (var i = 0; i < 4; i++) Move.release(red, i)]);
    s = apply(s, Move.release(red, 0));
    expect(legalMoves(s), [Move.advance(red, 0, 3)]);
    final r = applyMove(s, Move.advance(red, 0, 3));
    expect(r.state.pieces[red], [3, kAtHome, kAtHome, kAtHome]);
    expect(r.rollEnded, isTrue);
    expect(r.state.current, yellow);
  });

  test('worked example 2: 6 cannot pass a block of two, 4 can', () {
    final s = applyRoll(blockPosition(), 4, 6);
    final moves = legalMoves(s);
    expect(moves, contains(Move.advance(blue, 0, 4)));
    expect(moves, isNot(contains(Move.advance(blue, 0, 6))));
    final after = apply(s, Move.advance(blue, 0, 4));
    expect(
      legalMoves(after),
      everyElement(isA<Move>().having((m) => m.kind, 'kind', MoveKind.release)),
    );
    for (final seq in legalSequences(s)) {
      expect(seq, isNot(contains(Move.advance(blue, 0, 6))));
    }
  });

  test('worked example 3: double 6 then 5 captures a block of two', () {
    var s = applyRoll(afterDoubleSix(), 5, 2);
    expect(hasBlockRights(s, blue, 2), isTrue);
    final r = applyMove(s, Move.advance(blue, 0, 5));
    expect(r.captured, [const PieceRef(red, 0), const PieceRef(red, 1)]);
    expect(r.state.pieces[red], allHome);
    expect(trackSquare(blue, r.state.pieces[blue]![0]), 10);
  });

  test('worked example 4: double 6 then 6 passes the block', () {
    final s = applyRoll(afterDoubleSix(), 6, 3);
    final r = applyMove(s, Move.advance(blue, 0, 6));
    expect(r.captured, isEmpty);
    expect(trackSquare(blue, r.state.pieces[blue]![0]), 11);
    expect(r.state.pieces[red], [10, 10, kAtHome, kAtHome]);
  });

  test('worked example 5: exact finish, 5 cannot be used, 2 can', () {
    final s = applyRoll(
      position(
        mode: GameMode.oneVsOne,
        players: const [red, yellow],
        current: yellow,
        pieces: {
          yellow: [kFinished - 4, kAtHome, kAtHome, kAtHome],
        },
      ),
      5,
      2,
    );
    expect(legalMoves(s), [Move.advance(yellow, 0, 2)]);
    final r = applyMove(s, Move.advance(yellow, 0, 2));
    expect(r.state.pieces[yellow]![0], kFinished - 2);
    expect(r.rollEnded, isTrue);
  });

  // A red piece 4 squares behind a single yellow piece, rolling 4 and 4.
  GameState passPosition(List<int> otherRed) => applyRoll(
    position(
      mode: GameMode.oneVsOne,
      players: const [red, yellow],
      pieces: {
        red: [10, ...otherRed],
        yellow: [progressAt(yellow, 14), kAtHome, kAtHome, kAtHome],
      },
    ),
    4,
    4,
  );

  test(
    'worked example 6: combined 4 and 4 passes a single piece without capturing',
    () {
      final s = passPosition(const [30, kAtHome, kAtHome]);
      final r = applyMove(s, Move.combined(red, 0, 4, 4));
      expect(r.captured, isEmpty);
      expect(r.state.pieces[red]![0], 18);
      expect(r.state.pieces[yellow]![0], progressAt(yellow, 14));
      expect(r.rollEnded, isTrue);
    },
  );

  test(
    'worked example 7: capturing with one 4 sends the other 4 to another piece',
    () {
      final s = passPosition(const [30, kAtHome, kAtHome]);
      final r = applyMove(s, Move.advance(red, 0, 4));
      expect(r.captured, [const PieceRef(yellow, 0)]);
      expect(r.rollEnded, isFalse);
      expect(r.state.stoppedThisRoll, [const PieceRef(red, 0)]);
      expect(legalMoves(r.state), [Move.advance(red, 1, 4)]);
      final end = apply(r.state, Move.advance(red, 1, 4));
      expect(end.pieces[red], [14, 34, kAtHome, kAtHome]);
      expect(end.pieces[yellow], allHome);
    },
  );

  test(
    'worked example 8: a capture that would waste the other die is not allowed',
    () {
      final s = passPosition(const [kAtHome, kAtHome, kAtHome]);
      expect(legalMoves(s), [Move.combined(red, 0, 4, 4)]);
      expect(
        () => applyMove(s, Move.advance(red, 0, 4)),
        throwsA(isA<IllegalMoveException>()),
      );
      final end = apply(s, Move.combined(red, 0, 4, 4));
      expect(end.pieces[red]![0], 18);
      expect(end.pieces[yellow]![0], progressAt(yellow, 14));
    },
  );
}

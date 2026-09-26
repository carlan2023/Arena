import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

const _defaults = RulesConfig();

void main() {
  group('R1 triple double 6', () {
    GameState third(bool cancels) => applyRoll(
      position(
        pieces: {
          red: [10, kAtHome, kAtHome, kAtHome],
        },
        rules: _defaults.copyWith(tripleDoubleSixCancelsTurn: cancels),
        doubleSixStreak: 2,
        sixesThisTurn: 4,
        lastRoll: const [6, 6],
      ),
      6,
      6,
    );

    test('off: the third double 6 is played', () {
      final s = third(false);
      expect(s.phase, TurnPhase.awaitingMove);
      expect(s.doubleSixStreak, 3);
    });

    test('on: the third double 6 ends the turn with no moves', () {
      final s = third(true);
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.current, blue);
      expect(s.pieces[red], [10, kAtHome, kAtHome, kAtHome]);
      expect(s.turnNumber, 1);
      expect(s.doubleSixStreak, 0);
    });
  });

  group('R2 must use both dice', () {
    // Piece 0 needs 1 to finish, piece 1 needs 2. Moving piece 1 by 1 first
    // leaves the 2 unusable.
    GameState start(bool must) => applyRoll(
      position(
        pieces: {
          red: [56, 55, kFinished, kFinished],
        },
        rules: _defaults.copyWith(mustUseBothDice: must),
      ),
      1,
      2,
    );

    test('on: a step that wastes a die is illegal', () {
      final moves = legalMoves(start(true));
      expect(moves, contains(Move.advance(red, 0, 1)));
      expect(moves, contains(Move.advance(red, 1, 2)));
      expect(moves, isNot(contains(Move.advance(red, 1, 1))));
      expect(moves.where((m) => m.kind == MoveKind.pass), isEmpty);
    });

    test('on: if only one die fits, the player chooses which', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [51, kFinished, kFinished, kFinished],
          },
        ),
        6,
        1,
      );
      expect(
        legalMoves(s),
        unorderedEquals([Move.advance(red, 0, 6), Move.advance(red, 0, 1)]),
      );
    });

    test('off: every step is offered, and pass after one die', () {
      final s = start(false);
      expect(legalMoves(s), contains(Move.advance(red, 1, 1)));
      expect(legalMoves(s), isNot(contains(Move.pass(red))));
      final after = apply(s, Move.advance(red, 0, 1));
      expect(legalMoves(after), contains(Move.pass(red)));
      final r = applyMove(after, Move.pass(red));
      expect(r.rollEnded, isTrue);
      expect(r.state.current, blue);
      expect(r.state.pieces[red], [57, 55, kFinished, kFinished]);
    });

    test('on: pass is never legal', () {
      final s = apply(start(true), Move.advance(red, 0, 1));
      expect(
        () => applyMove(s, Move.pass(red)),
        throwsA(isA<IllegalMoveException>()),
      );
    });
  });

  group('R3 block move distance', () {
    GameState moved(bool sum) {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(blockMoveUsesSum: sum),
        ),
        4,
        4,
      );
      expect(legalMoves(s), contains(Move.blockAdvance(red, [1, 0], 4)));
      return apply(s, Move.blockAdvance(red, [0, 1], 4));
    }

    test('off: one die value', () {
      expect(moved(false).pieces[red], [14, 14, kAtHome, kAtHome]);
    });

    test('on: the sum', () {
      expect(moved(true).pieces[red], [18, 18, kAtHome, kAtHome]);
    });

    test('blockAdvance is only offered on a double', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
          },
        ),
        4,
        3,
      );
      expect(
        legalMoves(s).where((m) => m.kind == MoveKind.blockAdvance),
        isEmpty,
      );
    });

    test('a block may enter the home column and finish', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [51, 51, kFinished, kFinished],
          },
        ),
        6,
        6,
      );
      final r = applyMove(s, Move.blockAdvance(red, [0, 1], 6));
      expect(r.newlyFinished, [red]);
      expect(r.state.phase, TurnPhase.gameOver);
      expect(r.extraRoll, isFalse);
    });

    test('a block cannot pass an opponent block', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
            blue: [
              progressAt(blue, 12),
              progressAt(blue, 12),
              kAtHome,
              kAtHome,
            ],
          },
        ),
        3,
        3,
      );
      expect(
        legalMoves(s).where((m) => m.kind == MoveKind.blockAdvance),
        isEmpty,
      );
    });
  });

  group('R4 continuing after joining an own block', () {
    GameState joined(bool canContinue) {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 10, 7, kAtHome],
          },
          rules: _defaults.copyWith(canContinuePastOwnBlock: canContinue),
        ),
        3,
        2,
      );
      final after = apply(s, Move.advance(red, 2, 3));
      expect(after.joinedOwnBlockThisRoll, [const PieceRef(red, 2)]);
      return after;
    }

    test('off: the joining piece gets no further step this roll', () {
      final moves = legalMoves(joined(false));
      expect(moves, isNot(contains(Move.advance(red, 2, 2))));
      expect(moves, contains(Move.advance(red, 0, 2)));
    });

    test('on: the joining piece may move on', () {
      expect(legalMoves(joined(true)), contains(Move.advance(red, 2, 2)));
    });

    test('landing on a single own piece is not joining', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 7, kAtHome, kAtHome],
          },
        ),
        3,
        2,
      );
      final after = apply(s, Move.advance(red, 1, 3));
      expect(after.joinedOwnBlockThisRoll, isEmpty);
      expect(legalMoves(after), contains(Move.advance(red, 1, 2)));
    });

    test('a release onto an own block never counts as joining', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [0, 0, kAtHome, kAtHome],
          },
        ),
        6,
        3,
      );
      final after = apply(s, Move.release(red, 2));
      expect(after.joinedOwnBlockThisRoll, isEmpty);
      expect(legalMoves(after), contains(Move.advance(red, 2, 3)));
    });

    test('an own piece cannot pass its own block', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [10, 10, 7, kFinished],
          },
        ),
        5,
        1,
      );
      expect(legalMoves(s), isNot(contains(Move.advance(red, 2, 5))));
    });
  });

  group('R5 counting sixes', () {
    // A red block of three on square 10, a blue piece 5 behind, after a
    // double 6 in this turn.
    GameState rolled(bool acrossTurn) => applyRoll(
      position(
        current: blue,
        pieces: {
          red: [10, 10, 10, kAtHome],
          blue: [progressAt(blue, 5), 30, kFinished, kFinished],
        },
        rules: _defaults.copyWith(countSixesAcrossTurn: acrossTurn),
        doubleSixStreak: 1,
        sixesThisTurn: 2,
        lastRoll: const [6, 6],
      ),
      5,
      6,
    );

    test('on: the current roll\'s six counts', () {
      final s = rolled(true);
      expect(hasBlockRights(s, blue, 3), isTrue);
      final r = applyMove(s, Move.advance(blue, 0, 5));
      expect(r.captured, hasLength(3));
    });

    test('off: only earlier sixes count', () {
      final s = rolled(false);
      expect(hasBlockRights(s, blue, 3), isFalse);
      expect(hasBlockRights(s, blue, 2), isTrue);
      expect(legalMoves(s), isNot(contains(Move.advance(blue, 0, 5))));
    });

    test('no rights on the first roll of a turn, even a double 6', () {
      final s = applyRoll(
        position(
          current: blue,
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
            blue: [progressAt(blue, 4), 30, kFinished, kFinished],
          },
        ),
        6,
        6,
      );
      expect(hasBlockRights(s, blue, 2), isFalse);
      expect(legalMoves(s), isNot(contains(Move.advance(blue, 0, 6))));
    });

    test('a double 6 with no move still earns a roll, with rights', () {
      final s = applyRoll(
        position(
          current: blue,
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
            blue: [progressAt(blue, 4), kFinished, kFinished, kFinished],
          },
        ),
        6,
        6,
      );
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.current, blue);
      expect(hasBlockRights(s, blue, 2), isTrue);
      expect(hasBlockRights(s, red, 2), isFalse);
    });
  });

  group('R6 free for all after the first finish', () {
    GameState finish(bool playsOn) {
      final s = applyRoll(
        position(
          players: const [red, green, blue],
          pieces: {
            red: [56, kFinished, kFinished, kFinished],
            green: [5, kAtHome, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(freeForAllPlaysOn: playsOn),
        ),
        1,
        2,
      );
      final r = applyMove(s, Move.advance(red, 0, 1));
      expect(r.newlyFinished, [red]);
      expect(winners(r.state), [red]);
      return r.state;
    }

    test('on: play continues for the other places', () {
      final s = finish(true);
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.current, green);
    });

    test('on: ends when one player is left, ranked after the finishers', () {
      var s = position(
        players: const [red, green, blue],
        pieces: {
          red: allDone,
          green: [56, kFinished, kFinished, kFinished],
          blue: [3, kAtHome, kAtHome, kAtHome],
        },
        current: green,
        finishOrder: const [red],
      );
      s = apply(applyRoll(s, 1, 3), Move.advance(green, 0, 1));
      expect(s.phase, TurnPhase.gameOver);
      expect(ranking(s), [red, green, blue]);
    });

    test('off: ends at the first finish', () {
      expect(finish(false).phase, TurnPhase.gameOver);
    });
  });

  group('R7 team win', () {
    GameState finish(bool both) {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [56, kFinished, kFinished, kFinished],
            yellow: [20, kAtHome, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(teamWinsWhenBothFinish: both),
        ),
        1,
        3,
      );
      return apply(s, Move.advance(red, 0, 1));
    }

    test('on: the team needs both partners', () {
      final s = finish(true);
      expect(s.phase, isNot(TurnPhase.gameOver));
      expect(winners(s), isNull);
      expect(s.finishOrder, [red]);
    });

    test('on: team wins once the partner finishes too', () {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          current: yellow,
          pieces: {
            red: allDone,
            yellow: [56, kFinished, kFinished, kFinished],
          },
          finishOrder: const [red],
        ),
        1,
        4,
      );
      final after = apply(s, Move.advance(yellow, 0, 1));
      expect(after.phase, TurnPhase.gameOver);
      expect(winners(after), [red, yellow]);
    });

    test('off: the first partner to finish wins for the team', () {
      final s = finish(false);
      expect(s.phase, TurnPhase.gameOver);
      expect(winners(s), [red, yellow]);
    });
  });

  group('R8 partner blocks', () {
    GameState landOnPartner(bool joint) {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [5, kAtHome, kAtHome, kAtHome],
            yellow: [progressAt(yellow, 8), kAtHome, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(partnersFormJointBlocks: joint),
        ),
        3,
        1,
      );
      return applyMove(s, Move.advance(red, 0, 3)).state;
    }

    test('off: landing on a single partner piece captures it', () {
      final s = landOnPartner(false);
      expect(s.pieces[yellow], allHome);
      expect(blocks(s), isEmpty);
    });

    test('off: a partner block walls you', () {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [5, kFinished, kFinished, kFinished],
            yellow: [
              progressAt(yellow, 8),
              progressAt(yellow, 8),
              kAtHome,
              kAtHome,
            ],
          },
        ),
        4,
        5,
      );
      expect(legalMoves(s), isEmpty);
    });

    test('on: partners share the square and form a joint block', () {
      final s = landOnPartner(true);
      expect(s.pieces[yellow]![0], progressAt(yellow, 8));
      expect(blocks(s), [
        Block(8, const [PieceRef(red, 0), PieceRef(yellow, 0)]),
      ]);
      // The joint block walls green, and red cannot pass it either.
      var g = s.copyWith(
        current: green,
        pieces: {
          ...s.pieces,
          green: [progressAt(green, 6), kFinished, kFinished, kFinished],
        },
      );
      g = applyRoll(g.copyWith(phase: TurnPhase.awaitingRoll), 4, 5);
      expect(legalMoves(g), isEmpty);
    });

    test('on: a mixed square counts as own block for R4', () {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [5, 8, 20, kAtHome],
            yellow: [progressAt(yellow, 8), kAtHome, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(partnersFormJointBlocks: true),
        ),
        3,
        2,
      );
      final t = apply(s, Move.advance(red, 0, 3));
      expect(t.joinedOwnBlockThisRoll, [const PieceRef(red, 0)]);
      expect(legalMoves(t), isNot(contains(Move.advance(red, 0, 2))));
      expect(legalMoves(t), contains(Move.advance(red, 2, 2)));
    });

    test('on: blockAdvance moves only own colour pieces', () {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [8, 8, kAtHome, kAtHome],
            yellow: [progressAt(yellow, 8), kAtHome, kAtHome, kAtHome],
          },
          rules: _defaults.copyWith(partnersFormJointBlocks: true),
        ),
        2,
        2,
      );
      final r = applyMove(s, Move.blockAdvance(red, [0, 1], 2));
      expect(r.state.pieces[red], [10, 10, kAtHome, kAtHome]);
      expect(r.state.pieces[yellow]![0], progressAt(yellow, 8));
    });
  });

  group('R8 finished player rolls for partner', () {
    GameState afterBlue(bool rollsForPartner) => applyRoll(
      position(
        mode: GameMode.teams,
        players: PlayerColor.values,
        current: blue,
        pieces: {red: allDone},
        finishOrder: const [red],
        rules: _defaults.copyWith(
          finishedPlayerRollsForPartner: rollsForPartner,
        ),
      ),
      1,
      2,
    );

    test('on: the finished player keeps a turn and moves partner pieces', () {
      var s = afterBlue(true);
      expect(s.current, red);
      s = applyRoll(s, 6, 1);
      expect(legalMoves(s), contains(Move.release(yellow, 0)));
    });

    test('off: the finished player is skipped', () {
      expect(afterBlue(false).current, green);
    });

    test('on: dice left after finishing move the partner', () {
      final s = applyRoll(
        position(
          mode: GameMode.teams,
          players: PlayerColor.values,
          pieces: {
            red: [56, kFinished, kFinished, kFinished],
          },
        ),
        1,
        6,
      );
      final r = applyMove(s, Move.advance(red, 0, 1));
      expect(r.newlyFinished, [red]);
      expect(r.rollEnded, isFalse);
      expect(legalMoves(r.state), contains(Move.release(yellow, 0)));
      expect(hasBlockRights(r.state, yellow, 2), isFalse);
    });
  });
}

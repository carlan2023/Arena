import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  group('board', () {
    test('start squares and track squares', () {
      expect(
        [for (final c in PlayerColor.values) startSquare(c)],
        [0, 13, 26, 39],
      );
      expect(trackSquare(green, 0), 13);
      expect(trackSquare(blue, 13), 0);
      expect(trackSquare(red, kLastTrackProgress), 51);
      expect(trackSquare(red, kAtHome), isNull);
      expect(trackSquare(red, 52), isNull);
      expect(trackSquare(red, kFinished), isNull);
    });

    test('partners only in teams', () {
      expect(partnerOf(red, GameMode.teams), yellow);
      expect(partnerOf(green, GameMode.teams), blue);
      expect(partnerOf(blue, GameMode.teams), green);
      expect(partnerOf(red, GameMode.freeForAll), isNull);
      expect(partnerOf(red, GameMode.oneVsOne), isNull);
    });
  });

  group('newGame', () {
    test('valid seatings', () {
      final s = GameState.newGame(
        mode: GameMode.teams,
        players: PlayerColor.values,
        firstPlayer: yellow,
      );
      expect(s.current, yellow);
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.pieces.values, everyElement(allHome));
      expect(s.rollNumber, 0);
      GameState.newGame(mode: GameMode.oneVsOne, players: [green, blue]);
      GameState.newGame(mode: GameMode.freeForAll, players: [red, green, blue]);
    });

    test('invalid seatings throw', () {
      void bad(GameMode mode, List<PlayerColor> players, [PlayerColor? first]) {
        expect(
          () => GameState.newGame(
            mode: mode,
            players: players,
            firstPlayer: first,
          ),
          throwsArgumentError,
        );
      }

      bad(GameMode.oneVsOne, [red, green]);
      bad(GameMode.oneVsOne, [yellow, red]);
      bad(GameMode.oneVsOne, [red, green, yellow]);
      bad(GameMode.teams, [red, green, yellow]);
      bad(GameMode.freeForAll, [red]);
      bad(GameMode.freeForAll, [red, red]);
      bad(GameMode.freeForAll, [blue, red]);
      bad(GameMode.freeForAll, [red, blue], green);
    });

    test('custom rejects bad pieces', () {
      expect(
        () => position(
          pieces: {
            red: [1, 2, 3],
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => position(
          pieces: {
            red: [58, 0, 0, 0],
          },
        ),
        throwsArgumentError,
      );
    });
  });

  group('rolls', () {
    test('rollNumber and six counters', () {
      var s = position(
        pieces: {
          red: [5, kAtHome, kAtHome, kAtHome],
        },
      );
      s = applyRoll(s, 6, 6);
      expect(s.rollNumber, 1);
      expect(s.lastRoll, [6, 6]);
      expect(s.sixesThisTurn, 2);
      expect(s.sixesBeforeRoll, 0);
      expect(s.doubleSixStreak, 1);
      s = apply(apply(s, Move.advance(red, 0, 6)), Move.advance(red, 0, 6));
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.current, red);
      s = applyRoll(s, 6, 2);
      expect(s.sixesBeforeRoll, 2);
      expect(s.sixesThisTurn, 3);
      expect(s.rollNumber, 2);
    });

    test('no legal move passes the turn at once', () {
      final s = applyRoll(position(), 1, 2);
      expect(s.current, blue);
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.turnNumber, 1);
      expect(s.remainingDice, isEmpty);
    });

    test('bad calls throw', () {
      expect(() => applyRoll(position(), 0, 3), throwsArgumentError);
      expect(() => applyRoll(position(), 3, 7), throwsArgumentError);
      final moving = applyRoll(
        position(
          pieces: {
            red: [5, 5, 5, 5],
          },
        ),
        1,
        2,
      );
      expect(() => applyRoll(moving, 1, 2), throwsStateError);
      expect(legalMoves(position()), isEmpty);
      expect(legalSequences(position()), isEmpty);
      expect(
        () => applyMove(position(), Move.advance(red, 0, 1)),
        throwsA(isA<IllegalMoveException>()),
      );
      expect(
        () => applyMove(moving, Move.advance(red, 0, 3)),
        throwsA(
          isA<IllegalMoveException>().having(
            (e) => e.toString(),
            'text',
            contains('not legal'),
          ),
        ),
      );
    });
  });

  group('captures and landing', () {
    test('landing on a single piece captures it, start squares included', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [kAtHome, 5, kFinished, kFinished],
            blue: [progressAt(blue, 0), kAtHome, kAtHome, kAtHome],
          },
        ),
        6,
        1,
      );
      final r = applyMove(s, Move.release(red, 0));
      expect(r.captured, [const PieceRef(blue, 0)]);
      expect(r.state.pieces[blue], allHome);
    });

    test('release onto an opponent block needs rights', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [kAtHome, 5, kFinished, kFinished],
            blue: [progressAt(blue, 0), progressAt(blue, 0), kAtHome, kAtHome],
          },
        ),
        6,
        1,
      );
      expect(legalMoves(s).where((m) => m.kind == MoveKind.release), isEmpty);
    });

    test('home columns never block or capture', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [53, 50, kFinished, kFinished],
          },
        ),
        4,
        3,
      );
      // 50 + 4 = 54 passes nothing on the track past 51; 53 is not a block.
      expect(legalMoves(s), contains(Move.advance(red, 1, 4)));
      expect(s.piecesOnSquare(51), isEmpty);
    });

    test('piecesOnSquare lists every occupant', () {
      final s = position(
        pieces: {
          red: [10, 10, kAtHome, 57],
          blue: [progressAt(blue, 11), kAtHome, kAtHome, kAtHome],
        },
      );
      expect(s.piecesOnSquare(10), [
        const PieceRef(red, 0),
        const PieceRef(red, 1),
      ]);
      expect(s.piecesOnSquare(11), [const PieceRef(blue, 0)]);
      expect(s.progressOf(const PieceRef(red, 3)), kFinished);
    });
  });

  group('blocks and rights', () {
    test('blocks lists every wall', () {
      final s = position(
        players: const [red, green, blue],
        pieces: {
          red: [10, 10, 10, 3],
          green: [
            progressAt(green, 40),
            progressAt(green, 40),
            kAtHome,
            kAtHome,
          ],
          blue: [progressAt(blue, 3), kAtHome, kAtHome, kAtHome],
        },
      );
      expect(blocks(s), [
        Block(10, const [PieceRef(red, 0), PieceRef(red, 1), PieceRef(red, 2)]),
        Block(40, const [PieceRef(green, 0), PieceRef(green, 1)]),
      ]);
    });

    test('rights are false for other players and after the game', () {
      final s = position(
        doubleSixStreak: 1,
        sixesThisTurn: 2,
        lastRoll: const [6, 6],
      );
      expect(hasBlockRights(s, red, 2), isTrue);
      expect(hasBlockRights(s, red, 3), isFalse);
      expect(hasBlockRights(s, blue, 2), isFalse);
      final over = forfeit(s, blue);
      expect(hasBlockRights(over, red, 2), isFalse);
    });

    test('rights let a piece pass a block and stay for the turn', () {
      var s = applyRoll(
        position(
          current: blue,
          pieces: {
            red: [10, 10, kAtHome, kAtHome],
            blue: [progressAt(blue, 8), 30, kFinished, kFinished],
          },
          doubleSixStreak: 1,
          sixesThisTurn: 2,
          lastRoll: const [6, 6],
        ),
        5,
        1,
      );
      expect(legalMoves(s), contains(Move.advance(blue, 0, 5)));
      final r = applyMove(s, Move.advance(blue, 0, 5));
      expect(r.captured, isEmpty);
      expect(r.state.pieces[red], [10, 10, kAtHome, kAtHome]);
    });
  });

  group('legalSequences', () {
    test('every sequence ends the roll and duplicates are merged', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [5, 20, kFinished, kFinished],
          },
        ),
        3,
        4,
      );
      final seqs = legalSequences(s);
      // A3 B4 and B4 A3 give the same state; A7, B7, A4 B3 are distinct.
      expect(seqs, hasLength(4));
      for (final seq in seqs) {
        var t = s;
        for (var i = 0; i < seq.length; i++) {
          final r = applyMove(t, seq[i]);
          expect(r.rollEnded, i == seq.length - 1);
          t = r.state;
        }
      }
    });

    test('[[]] when no step is legal', () {
      final s = GameState.custom(
        mode: GameMode.freeForAll,
        players: const [red, blue],
        phase: TurnPhase.awaitingMove,
        lastRoll: const [1, 2],
        remainingDice: const [1, 2],
      );
      expect(legalSequences(s), [<Move>[]]);
    });

    test('R2 off sequences may end with a pass', () {
      final s = applyRoll(
        position(
          pieces: {
            red: [5, kFinished, kFinished, kFinished],
          },
          rules: const RulesConfig(mustUseBothDice: false),
        ),
        1,
        2,
      );
      final seqs = legalSequences(s);
      expect(seqs.where((q) => q.last.kind == MoveKind.pass), isNotEmpty);
    });
  });

  group('forfeit', () {
    test('oneVsOne: the opponent wins', () {
      final s = forfeit(
        GameState.newGame(mode: GameMode.oneVsOne, players: [red, yellow]),
        red,
      );
      expect(s.phase, TurnPhase.gameOver);
      expect(winners(s), [yellow]);
      expect(s.forfeited, [red]);
      expect(ranking(s), [yellow, red]);
    });

    test('freeForAll: the turn passes and dice are dropped', () {
      var s = GameState.newGame(
        mode: GameMode.freeForAll,
        players: [red, green, blue],
      );
      s = applyRoll(s, 6, 1);
      expect(s.phase, TurnPhase.awaitingMove);
      s = forfeit(s, red);
      expect(s.current, green);
      expect(s.phase, TurnPhase.awaitingRoll);
      expect(s.remainingDice, isEmpty);
      expect(winners(s), isNull);
      s = forfeit(s, blue);
      expect(s.phase, TurnPhase.gameOver);
      expect(winners(s), [green]);
      expect(ranking(s), [green, blue, red]);
    });

    test('freeForAll: forfeiting someone else keeps the roll going', () {
      var s = GameState.newGame(
        mode: GameMode.freeForAll,
        players: [red, green, blue],
      );
      s = applyRoll(s, 6, 1);
      s = forfeit(s, blue);
      expect(s.current, red);
      expect(s.phase, TurnPhase.awaitingMove);
    });

    test('forfeiting removes a wall and can end a stuck roll', () {
      // Blue owns the only thing red could move onto; not stuck, so the roll
      // continues with the block gone.
      var s = applyRoll(
        position(
          players: const [red, green, blue],
          pieces: {
            red: [5, kAtHome, kAtHome, kAtHome],
            blue: [progressAt(blue, 8), progressAt(blue, 8), kAtHome, kAtHome],
          },
        ),
        1,
        4,
      );
      expect(legalMoves(s), [Move.advance(red, 0, 1)]);
      s = forfeit(s, blue);
      expect(legalMoves(s), contains(Move.advance(red, 0, 4)));
      expect(s.pieces[blue], allHome);
    });

    test('teams: the other team wins', () {
      final s = forfeit(
        GameState.newGame(mode: GameMode.teams, players: PlayerColor.values),
        yellow,
      );
      expect(s.phase, TurnPhase.gameOver);
      expect(winners(s), [green, blue]);
    });

    test('bad forfeits throw', () {
      final s = position(
        players: const [red, green, blue],
        pieces: {red: allDone},
        finishOrder: const [red],
        current: green,
      );
      expect(() => forfeit(s, red), throwsArgumentError);
      expect(() => forfeit(s, yellow), throwsArgumentError);
      final f = forfeit(s, blue);
      expect(() => forfeit(f, blue), throwsArgumentError);
      expect(f.phase, TurnPhase.gameOver);
      expect(() => forfeit(f, green), throwsStateError);
    });
  });

  group('finishing and results', () {
    test('a finisher with no partner gets no extra roll on double 6', () {
      final s = applyRoll(
        position(
          players: const [red, green, blue],
          pieces: {
            red: [51, kFinished, kFinished, kFinished],
          },
        ),
        6,
        6,
      );
      final r = applyMove(s, Move.advance(red, 0, 6));
      expect(r.rollEnded, isTrue);
      expect(r.extraRoll, isFalse);
      expect(r.state.current, green);
    });

    test('oneVsOne ends at the first finish', () {
      final s = applyRoll(
        position(
          mode: GameMode.oneVsOne,
          players: const [red, yellow],
          pieces: {
            red: [54, kFinished, kFinished, kFinished],
          },
        ),
        3,
        6,
      );
      final r = applyMove(s, Move.advance(red, 0, 3));
      expect(r.state.phase, TurnPhase.gameOver);
      expect(isGameOver(r.state), isTrue);
      expect(winners(r.state), [red]);
      expect(r.state.remainingDice, isEmpty);
      expect(legalMoves(r.state), isEmpty);
    });

    test('ranking orders unfinished players by progress', () {
      final s = position(
        players: const [red, green, yellow, blue],
        pieces: {
          red: [10, 10, kAtHome, kAtHome],
          green: [15, kAtHome, kAtHome, kAtHome],
          yellow: [10, 10, kAtHome, kAtHome],
          blue: allDone,
        },
        finishOrder: const [blue],
      );
      expect(ranking(s), [blue, red, yellow, green]);
      expect(winners(s), [blue]);
      expect(winners(position()), isNull);
      expect(
        winners(
          position(mode: GameMode.oneVsOne, players: const [red, yellow]),
        ),
        isNull,
      );
      expect(
        winners(position(mode: GameMode.teams, players: PlayerColor.values)),
        isNull,
      );
    });
  });
}

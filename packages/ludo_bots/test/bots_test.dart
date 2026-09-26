import 'dart:math';

import 'package:ludo_bots/ludo_bots.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;
const yellow = PlayerColor.yellow;
const blue = PlayerColor.blue;
const home = kAtHome;
const done = kFinished;

int at(PlayerColor c, int square) =>
    (square - startSquare(c) + kTrackLength) % kTrackLength;

/// Red to move after rolling [dice] in a free for all against blue.
GameState rolled(
  Map<PlayerColor, List<int>> pieces,
  int d1,
  int d2, {
  GameMode mode = GameMode.freeForAll,
  List<PlayerColor> players = const [red, blue],
}) => applyRoll(
  GameState.custom(mode: mode, players: players, pieces: pieces),
  d1,
  d2,
);

List<int> redAfter(GameState s, List<Move> seq) {
  for (final m in seq) {
    s = apply(s, m);
  }
  return s.pieces[red]!;
}

void main() {
  group('NormalBot preferences', () {
    // Many seeds so a random tie break cannot hide a wrong preference.
    void expectAlways(GameState s, void Function(List<Move>) check) {
      for (var seed = 0; seed < 20; seed++) {
        check(NormalBot(random: Random(seed)).chooseMoves(s));
      }
    }

    test('captures a single piece', () {
      final s = rolled(
        {
          red: [10, 30, done, done],
          blue: [at(blue, 14), home, home, home],
        },
        4,
        4,
      );
      expectAlways(s, (seq) {
        final after = redAfter(s, seq);
        expect(after, contains(14));
      });
    });

    test('prefers a block capture to a single capture', () {
      final s = applyRoll(
        GameState.custom(
          mode: GameMode.freeForAll,
          players: const [red, green, blue],
          pieces: {
            red: [10, 20, done, done],
            green: [at(green, 13), home, home, home],
            blue: [at(blue, 25), at(blue, 25), home, home],
          },
          doubleSixStreak: 1,
          sixesThisTurn: 2,
          lastRoll: const [6, 6],
        ),
        3,
        5,
      );
      expectAlways(s, (seq) {
        expect(seq, contains(Move.advance(red, 1, 5)));
      });
    });

    test('forms a block', () {
      final s = rolled(
        {
          red: [10, 13, 20, done],
        },
        3,
        1,
      );
      // 10+3 joins 13 to form a block; the 1 goes to the piece on 20.
      expectAlways(s, (seq) {
        final after = redAfter(s, seq);
        expect(after[0], after[1]);
      });
    });

    test('advances the leading piece', () {
      final s = rolled(
        {
          red: [30, 5, done, done],
        },
        2,
        3,
      );
      expectAlways(s, (seq) {
        expect(redAfter(s, seq), [35, 5, done, done]);
      });
    });

    test('finishes a piece', () {
      final s = rolled(
        {
          red: [55, 20, done, done],
        },
        2,
        1,
      );
      expectAlways(s, (seq) {
        expect(seq, contains(Move.advance(red, 0, 2)));
      });
    });

    test('releases a piece', () {
      final s = rolled(
        {
          red: [20, home, done, done],
        },
        6,
        1,
      );
      expectAlways(s, (seq) {
        expect(seq, contains(Move.release(red, 1)));
      });
    });

    test('avoids stopping just in front of an opponent', () {
      // Blue at square 20. Red at 10 moving 5 lands 15 (safe, behind blue);
      // red at 12 moving 5 lands 17: in front? no, 3 behind blue too.
      // Red 25 moving 5 lands 30: 10 in front of blue, in danger; red 25 is
      // already in danger (5 in front), so moving it out of range wins.
      final s = rolled(
        {
          red: [25, 2, done, done],
          blue: [at(blue, 20), home, home, home],
        },
        6,
        6,
      );
      expectAlways(s, (seq) {
        final after = redAfter(s, seq);
        final sq = trackSquare(red, after[0])!;
        final d = (sq - 20 + kTrackLength) % kTrackLength;
        expect(d == 0 || d > BotWeights.dangerRange, isTrue, reason: '$after');
      });
    });

    test('scoreSequence penalises danger', () {
      final before = GameState.custom(
        mode: GameMode.freeForAll,
        players: const [red, blue],
        pieces: {
          red: [5, done, done, done],
          blue: [at(blue, 0), home, home, home],
        },
      );
      final safe = before.copyWith(
        pieces: {
          ...before.pieces,
          red: [20, done, done, done],
        },
      );
      final risky = before.copyWith(
        pieces: {
          ...before.pieces,
          red: [10, done, done, done],
        },
      );
      expect(
        scoreSequence(before, safe, red),
        greaterThan(scoreSequence(before, risky, red)),
      );
    });

    // Red 4 behind a single blue piece, rolling 4 and 4 (D34).
    GameState passOrCapture(List<int> otherRed) => rolled(
      {
        red: [10, ...otherRed],
        blue: [at(blue, 14), home, home, home],
      },
      4,
      4,
    );

    test('captures with one 4 rather than passing with the combined 8', () {
      final s = passOrCapture(const [30, done, done]);
      expect(
        legalSequences(s),
        anyElement(equals([Move.combined(red, 0, 4, 4)])),
      );
      expectAlways(s, (seq) {
        expect(seq, contains(Move.advance(red, 0, 4)));
        expect(redAfter(s, seq)[0], 14);
      });
    });

    test('passes with the combined move when the capture is not allowed', () {
      final s = passOrCapture(const [done, done, done]);
      expectAlways(s, (seq) {
        expect(seq, [Move.combined(red, 0, 4, 4)]);
      });
    });

    test('uses a combined move to capture beyond a single piece', () {
      final s = rolled(
        {
          red: [10, 30, done, done],
          blue: [at(blue, 12), at(blue, 16), home, home],
        },
        2,
        4,
      );
      expectAlways(s, (seq) {
        var t = s;
        for (final m in seq) {
          t = apply(t, m);
        }
        expect(t.pieces[blue]!.where((p) => p == home), hasLength(3));
      });
    });

    test('teams: capturing a partner is avoided when possible', () {
      final s = rolled(
        {
          red: [10, 30, done, done],
          yellow: [at(yellow, 14), home, home, home],
        },
        4,
        4,
        mode: GameMode.teams,
        players: PlayerColor.values,
      );
      expectAlways(s, (seq) {
        var t = s;
        for (final m in seq) {
          t = apply(t, m);
        }
        expect(t.pieces[yellow]![0], at(yellow, 14));
      });
    });
  });

  group('interface', () {
    test('empty unless awaitingMove, deterministic with a seed', () {
      final s = GameState.newGame(
        mode: GameMode.oneVsOne,
        players: [red, yellow],
      );
      for (final level in BotLevel.values) {
        expect(botFor(level).chooseMoves(s), isEmpty);
      }
      expect(botFor(BotLevel.easy), isA<EasyBot>());
      expect(botFor(BotLevel.normal), isA<NormalBot>());
      final r = applyRoll(s, 6, 3);
      for (final level in BotLevel.values) {
        final a = botFor(level, random: Random(7)).chooseMoves(r);
        final b = botFor(level, random: Random(7)).chooseMoves(r);
        expect(a, b);
        expect(legalSequences(r), anyElement(equals(a)));
      }
    });

    test('a roll with one sequence returns it', () {
      final s = rolled(
        {
          red: [5, done, done, done],
        },
        1,
        1,
      );
      expect(NormalBot().chooseMoves(s), [Move.combined(red, 0, 1, 1)]);
    });
  });

  test('bots never throw and always finish games in every mode', () {
    final r = Random(99);
    const games = 600;
    for (var g = 0; g < games; g++) {
      final mode = GameMode.values[g % 3];
      final players = switch (mode) {
        GameMode.oneVsOne => const [red, yellow],
        GameMode.teams => PlayerColor.values,
        GameMode.freeForAll =>
          g % 2 == 0 ? const [red, green, blue] : PlayerColor.values,
      };
      final rules = RulesConfig(
        tripleDoubleSixCancelsTurn: r.nextBool(),
        mustUseBothDice: r.nextBool(),
        blockMoveUsesSum: r.nextBool(),
        canContinuePastOwnBlock: r.nextBool(),
        countSixesAcrossTurn: r.nextBool(),
        freeForAllPlaysOn: r.nextBool(),
        teamWinsWhenBothFinish: r.nextBool(),
        partnersFormJointBlocks: r.nextBool(),
        finishedPlayerRollsForPartner: r.nextBool(),
      );
      final bots = {
        for (final c in players)
          c: botFor(
            BotLevel.values[r.nextInt(2)],
            random: Random(r.nextInt(1 << 30)),
          ),
      };
      var s = GameState.newGame(mode: mode, players: players, rules: rules);
      var rolls = 0;
      while (!isGameOver(s)) {
        if (s.phase == TurnPhase.awaitingRoll) {
          s = applyRoll(s, 1 + r.nextInt(6), 1 + r.nextInt(6));
          rolls++;
          expect(rolls, lessThan(4000));
          continue;
        }
        final seq = bots[s.current]!.chooseMoves(s);
        expect(legalSequences(s), anyElement(equals(seq)));
        for (final m in seq) {
          s = apply(s, m);
        }
      }
      expect(winners(s), isNotNull);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

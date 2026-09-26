// Seeded random games in every mode with random rule settings. Each step is
// re-checked against an independent reading of the block rules.
import 'dart:convert';
import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const _games = 1000;
const _maxRollsPerGame = 4000;

RulesConfig _randomRules(Random r) => RulesConfig(
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

GameState _randomGame(Random r) {
  final mode = GameMode.values[r.nextInt(3)];
  final players = switch (mode) {
    GameMode.oneVsOne =>
      r.nextBool()
          ? [PlayerColor.red, PlayerColor.yellow]
          : [PlayerColor.green, PlayerColor.blue],
    GameMode.teams => PlayerColor.values,
    GameMode.freeForAll => () {
      final seats = [...PlayerColor.values]..shuffle(r);
      return (seats.take(2 + r.nextInt(3)).toList()
        ..sort((a, b) => a.index - b.index));
    }(),
  };
  return GameState.newGame(
    mode: mode,
    players: players,
    rules: _randomRules(r),
    firstPlayer: players[r.nextInt(players.length)],
  );
}

bool _sameSide(GameState s, PlayerColor a, PlayerColor b) =>
    a == b ||
    (s.mode == GameMode.teams &&
        s.rules.partnersFormJointBlocks &&
        partnerOf(a, s.mode) == b);

bool _rights(GameState s, int size) {
  final roll = s.lastRoll;
  final isDoubleSix = roll.length == 2 && roll[0] == 6 && roll[1] == 6;
  final earlier = s.doubleSixStreak - (isDoubleSix ? 1 : 0) >= 1;
  final sixes = s.rules.countSixesAcrossTurn
      ? s.sixesThisTurn
      : s.sixesBeforeRoll;
  return earlier && sixes >= size;
}

/// Independent re-check of one step's path and landing.
void _checkStep(GameState s, Move m) {
  for (final i in m.pieces) {
    expect(s.stoppedThisRoll, isNot(contains(PieceRef(m.color, i))));
  }
  if (m.kind == MoveKind.pass) {
    expect(s.rules.mustUseBothDice, isFalse);
    expect(s.remainingDice, hasLength(1));
    return;
  }
  final c = m.color;
  final from = s.pieces[c]![m.pieces.first];
  for (final i in m.pieces) {
    expect(s.pieces[c]![i], from, reason: 'block pieces share a square');
  }
  final int to;
  switch (m.kind) {
    case MoveKind.release:
      expect(from, kAtHome);
      expect(s.remainingDice, contains(6));
      to = 0;
    case MoveKind.advance:
      expect(s.remainingDice, contains(m.die));
      to = from + m.die;
    case MoveKind.combined:
      expect(s.remainingDice, hasLength(2));
      expect([m.die, m.die2]..sort(), [...s.remainingDice]..sort());
      expect(from, isNot(kAtHome));
      to = from + m.die + m.die2;
    default:
      expect(s.remainingDice, hasLength(2));
      expect(s.remainingDice[0], s.remainingDice[1]);
      expect(m.pieces.length, greaterThanOrEqualTo(2));
      to = from + (s.rules.blockMoveUsesSum ? 2 : 1) * m.die;
  }
  expect(to, lessThanOrEqualTo(kFinished));
  (int, int) count(int progress) {
    var own = 0, opp = 0;
    for (final p in s.piecesOnSquare(trackSquare(c, progress)!)) {
      _sameSide(s, c, p.color) ? own++ : opp++;
    }
    return (own, opp);
  }

  for (var q = from + 1; q < to && q <= kLastTrackProgress; q++) {
    final (own, opp) = count(q);
    expect(own, lessThan(2), reason: '$m passes an own block');
    if (opp >= 2) expect(_rights(s, opp), isTrue, reason: '$m passes a block');
  }
  if (to <= kLastTrackProgress) {
    final (_, opp) = count(to);
    if (opp >= 2) expect(_rights(s, opp), isTrue, reason: '$m lands on block');
  }
}

void _checkInvariants(GameState s) {
  for (final c in s.players) {
    final p = s.pieces[c]!;
    expect(p, hasLength(kPiecesPerPlayer));
    for (final v in p) {
      expect(v, inInclusiveRange(kAtHome, kFinished));
    }
    if (s.forfeited.contains(c)) {
      expect(p, everyElement(kAtHome));
    }
  }
  for (final c in s.finishOrder) {
    expect(s.pieces[c], everyElement(kFinished));
  }
  for (var sq = 0; sq < kTrackLength; sq++) {
    final on = s.piecesOnSquare(sq);
    for (final p in on) {
      expect(
        _sameSide(s, p.color, on.first.color),
        isTrue,
        reason: 'mixed square',
      );
    }
  }
  switch (s.phase) {
    case TurnPhase.awaitingRoll:
      expect(s.remainingDice, isEmpty);
    case TurnPhase.awaitingMove:
      expect(s.remainingDice, isNotEmpty);
      expect(legalMoves(s), isNotEmpty);
    case TurnPhase.gameOver:
      expect(winners(s), isNotNull);
  }
  final json = (jsonDecode(jsonEncode(s.toJson())) as Map)
      .cast<String, Object?>();
  expect(GameState.fromJson(json), s);
}

/// Squares a combined move only crosses, with the pieces on them.
List<PieceRef> _crossed(GameState s, Move m) {
  if (m.kind != MoveKind.combined) return const [];
  final from = s.pieces[m.color]![m.pieces.single];
  final to = from + m.die + m.die2;
  return [
    for (var q = from + 1; q < to && q <= kLastTrackProgress; q++)
      ...s.piecesOnSquare(trackSquare(m.color, q)!),
  ];
}

/// Tracks capture stops independently of the engine: a piece that captured
/// never moves again in the same roll.
class _StopTracker {
  int roll = -1;
  final stopped = <PieceRef>{};

  MoveResult play(GameState s, Move m) {
    _checkStep(s, m);
    if (s.rollNumber != roll) {
      roll = s.rollNumber;
      stopped.clear();
    }
    for (final i in m.pieces) {
      expect(stopped, isNot(contains(PieceRef(m.color, i))));
    }
    final crossed = _crossed(s, m);
    final r = applyMove(s, m);
    for (final p in crossed) {
      expect(
        r.state.pieces[p.color]![p.index],
        s.pieces[p.color]![p.index],
        reason: 'combined $m captured a piece it only crossed',
      );
      expect(r.captured, isNot(contains(p)));
    }
    for (final p in r.captured) {
      expect(r.state.pieces[p.color]![p.index], kAtHome);
    }
    if (r.captured.isNotEmpty) {
      stopped.addAll([for (final i in m.pieces) PieceRef(m.color, i)]);
    }
    return r;
  }
}

Set<GameState> _endStates(GameState s, List<List<Move>> seqs) {
  final out = <GameState>{};
  for (final seq in seqs) {
    var t = s;
    for (final m in seq) {
      t = apply(t, m);
    }
    out.add(t);
  }
  return out;
}

void main() {
  test('$_games random games keep every invariant and end', () {
    final r = Random(20260925);
    final lengths = <int>[];
    final stops = _StopTracker();
    for (var g = 0; g < _games; g++) {
      var s = _randomGame(r);
      final forfeitAt = r.nextInt(10) == 0 ? r.nextInt(200) : -1;
      var rolls = 0;
      while (s.phase != TurnPhase.gameOver) {
        expect(rolls, lessThan(_maxRollsPerGame), reason: 'game $g too long');
        if (rolls == forfeitAt) {
          final active = [
            for (final c in s.players)
              if (!s.finishOrder.contains(c) && !s.forfeited.contains(c)) c,
          ];
          s = forfeit(s, active[r.nextInt(active.length)]);
          _checkInvariants(s);
          if (s.phase == TurnPhase.gameOver) break;
        }
        if (s.phase == TurnPhase.awaitingRoll) {
          final before = s.rollNumber;
          s = applyRoll(s, 1 + r.nextInt(6), 1 + r.nextInt(6));
          expect(s.rollNumber, before + 1);
          rolls++;
        } else {
          final moves = legalMoves(s);
          final seqs = legalSequences(s);
          expect(seqs, isNotEmpty);
          for (final seq in seqs) {
            expect(moves, contains(seq.first));
          }
          // Every legal first step leads to end states the sequences cover.
          if (g % 10 == 0) {
            final all = _endStates(s, seqs);
            for (final m in moves) {
              final res = applyMove(s, m);
              final rest = res.rollEnded
                  ? {res.state}
                  : _endStates(res.state, legalSequences(res.state));
              expect(all.containsAll(rest), isTrue);
            }
          }
          // Alternate between playing a whole sequence and single steps.
          if (r.nextBool()) {
            for (final m in seqs[r.nextInt(seqs.length)]) {
              s = stops.play(s, m).state;
            }
          } else {
            s = stops.play(s, moves[r.nextInt(moves.length)]).state;
          }
        }
        _checkInvariants(s);
      }
      expect(winners(s), isNotNull);
      expect(ranking(s).toSet(), s.players.toSet());
      expect(ranking(s), hasLength(s.players.length));
      lengths.add(rolls);
    }
    lengths.sort();
    printOnFailure('median rolls ${lengths[lengths.length ~/ 2]}');
  }, timeout: const Timeout(Duration(minutes: 10)));
}

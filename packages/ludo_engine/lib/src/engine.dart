import 'dart:math';

import 'board.dart';
import 'game_state.dart';
import 'move.dart';

// ---------------------------------------------------------------------------
// Public functions
// ---------------------------------------------------------------------------

/// Starts a roll. Phase must be awaitingRoll and both values 1..6.
/// If no legal step exists the roll ends at once.
GameState applyRoll(GameState state, int die1, int die2) {
  if (state.phase != TurnPhase.awaitingRoll) {
    throw StateError('applyRoll needs phase awaitingRoll, not ${state.phase}');
  }
  for (final d in [die1, die2]) {
    if (d < 1 || d > 6) throw ArgumentError.value(d, 'die', 'must be 1..6');
  }
  final doubleSix = die1 == 6 && die2 == 6;
  final sixes = (die1 == 6 ? 1 : 0) + (die2 == 6 ? 1 : 0);
  final streak = state.doubleSixStreak + (doubleSix ? 1 : 0);
  var next = state.copyWith(
    rollNumber: state.rollNumber + 1,
    lastRoll: [die1, die2],
    remainingDice: [die1, die2],
    sixesBeforeRoll: state.sixesThisTurn,
    sixesThisTurn: state.sixesThisTurn + sixes,
    doubleSixStreak: streak,
    joinedOwnBlockThisRoll: const [],
    phase: TurnPhase.awaitingMove,
  );
  if (doubleSix && streak >= 3 && state.rules.tripleDoubleSixCancelsTurn) {
    return _passTurn(next);
  }
  if (legalMoves(next).isEmpty) next = _endRoll(next);
  return next;
}

/// The legal next steps. Empty unless phase is awaitingMove.
///
/// With R2 on, a step is legal only if the rest of the roll can still use the
/// largest possible number of dice. With R2 off, every individually legal step
/// is offered, plus a pass once one die of the roll has been used.
List<Move> legalMoves(GameState state) =>
    _legalCache[state] ??= List.unmodifiable(_computeLegalMoves(state));

// States are immutable, so legal moves can be cached per state object.
final _legalCache = Expando<List<Move>>('legalMoves');

List<Move> _computeLegalMoves(GameState state) {
  if (state.phase != TurnPhase.awaitingMove) return const [];
  final candidates = _candidates(state);
  if (!state.rules.mustUseBothDice) {
    if (candidates.isNotEmpty && state.remainingDice.length == 1) {
      return [...candidates, Move.pass(_controlledColor(state))];
    }
    return candidates;
  }
  final scores = [
    for (final m in candidates)
      _diceUsed(m) + _maxDiceUsable(_step(state, m).state),
  ];
  final best = scores.fold(0, max);
  return [
    for (var i = 0; i < candidates.length; i++)
      if (scores[i] == best) candidates[i],
  ];
}

/// Every complete list of steps for the current roll that the rules allow,
/// deduplicated by resulting state. [[]] when no step is legal. Empty unless
/// awaitingMove.
List<List<Move>> legalSequences(GameState state) {
  if (state.phase != TurnPhase.awaitingMove) return const [];
  if (legalMoves(state).isEmpty) return const [[]];
  final seen = <GameState>{};
  final out = <List<Move>>[];
  void walk(GameState s, List<Move> prefix) {
    for (final m in legalMoves(s)) {
      final r = _applyUnchecked(s, m);
      final seq = [...prefix, m];
      if (r.rollEnded) {
        if (seen.add(r.state)) out.add(List.unmodifiable(seq));
      } else {
        walk(r.state, seq);
      }
    }
  }

  walk(state, const []);
  return List.unmodifiable(out);
}

/// Applies one step. Throws [IllegalMoveException] unless [move] is in
/// legalMoves(state).
MoveResult applyMove(GameState state, Move move) {
  if (state.phase != TurnPhase.awaitingMove) {
    throw IllegalMoveException('No move expected in phase ${state.phase}');
  }
  if (!legalMoves(state).contains(move)) {
    throw IllegalMoveException('$move is not legal here');
  }
  return _applyUnchecked(state, move);
}

MoveResult _applyUnchecked(GameState state, Move move) {
  final step = _step(state, move);
  var next = step.state;
  var rollEnded = false;
  if (next.remainingDice.isEmpty ||
      _gameOverNow(next) ||
      legalMoves(next).isEmpty) {
    next = _endRoll(next);
    rollEnded = true;
  }
  return MoveResult(
    state: next,
    move: move,
    captured: step.captured,
    newlyFinished: step.newlyFinished,
    rollEnded: rollEnded,
    extraRoll:
        rollEnded &&
        next.phase == TurnPhase.awaitingRoll &&
        next.current == state.current,
  );
}

GameState apply(GameState state, Move move) => applyMove(state, move).state;

/// Removes a player. Their pieces go home and stay out of play, the rest of
/// their roll is dropped, and the turn passes if it was theirs. May end the
/// game. Throws [ArgumentError] for an unseated, finished or already
/// forfeited colour and [StateError] once the game is over.
GameState forfeit(GameState state, PlayerColor color) {
  if (!state.players.contains(color)) {
    throw ArgumentError.value(color, 'color', 'is not seated');
  }
  if (state.finishOrder.contains(color) || state.forfeited.contains(color)) {
    throw ArgumentError.value(color, 'color', 'already finished or forfeited');
  }
  if (state.phase == TurnPhase.gameOver) {
    throw StateError('The game is already over');
  }
  var next = state.copyWith(
    pieces: {...state.pieces, color: List.filled(kPiecesPerPlayer, kAtHome)},
    forfeited: [...state.forfeited, color],
  );
  if (_gameOverNow(next)) return _finishGame(next);
  if (next.current == color) return _passTurn(next);
  if (next.phase == TurnPhase.awaitingMove && legalMoves(next).isEmpty) {
    next = _endRoll(next);
  }
  return next;
}

/// Null while undecided. oneVsOne: [winner]. teams: both partners.
/// freeForAll: [first finisher] as soon as someone finishes, or the last
/// player standing if everyone else forfeited.
List<PlayerColor>? winners(GameState state) {
  switch (state.mode) {
    case GameMode.oneVsOne:
      if (state.finishOrder.isNotEmpty) return [state.finishOrder.first];
      if (state.forfeited.isNotEmpty) {
        return state.players
            .where((c) => !state.forfeited.contains(c))
            .toList();
      }
      return null;
    case GameMode.freeForAll:
      if (state.finishOrder.isNotEmpty) return [state.finishOrder.first];
      final active = _activePlayers(state);
      return active.length == 1 ? active : null;
    case GameMode.teams:
      if (state.forfeited.isNotEmpty) {
        final loser = state.forfeited.first;
        return _team(_nextColor(loser));
      }
      for (final c in state.finishOrder) {
        final partner = partnerOf(c, GameMode.teams)!;
        if (!state.rules.teamWinsWhenBothFinish ||
            state.finishOrder.contains(partner)) {
          return _team(c);
        }
      }
      return null;
  }
}

bool isGameOver(GameState state) => state.phase == TurnPhase.gameOver;

/// finishOrder, then the others by total progress (seat order breaks ties),
/// then forfeited players, latest forfeit first.
List<PlayerColor> ranking(GameState state) {
  int total(PlayerColor c) => state.pieces[c]!.fold(0, (a, b) => a + b);
  final rest =
      state.players
          .where(
            (c) =>
                !state.finishOrder.contains(c) && !state.forfeited.contains(c),
          )
          .toList()
        ..sort((a, b) {
          final byProgress = total(b).compareTo(total(a));
          return byProgress != 0 ? byProgress : a.index.compareTo(b.index);
        });
  return [...state.finishOrder, ...rest, ...state.forfeited.reversed];
}

/// Every block on the shared track, by square.
List<Block> blocks(GameState state) {
  final out = <Block>[];
  for (var square = 0; square < kTrackLength; square++) {
    final on = state.piecesOnSquare(square);
    if (on.length < 2) continue;
    final groups = <List<PieceRef>>[];
    for (final p in on) {
      final group = groups.where(
        (g) => _sameSide(state, g.first.color, p.color),
      );
      if (group.isEmpty) {
        groups.add([p]);
      } else {
        group.first.add(p);
      }
    }
    for (final g in groups) {
      if (g.length >= 2) out.add(Block(square, g));
    }
  }
  return out;
}

/// Whether [mover] may pass or land on an opponent block of [blockSize] now:
/// an earlier roll in this turn was a double 6 and the six count (R5) is at
/// least [blockSize]. In awaitingRoll this answers for the upcoming roll.
bool hasBlockRights(GameState state, PlayerColor mover, int blockSize) {
  if (mover != state.current && mover != _controlledColor(state)) return false;
  switch (state.phase) {
    case TurnPhase.gameOver:
      return false;
    case TurnPhase.awaitingRoll:
      return state.doubleSixStreak >= 1 && state.sixesThisTurn >= blockSize;
    case TurnPhase.awaitingMove:
      final currentIsDoubleSix =
          state.lastRoll.length == 2 &&
          state.lastRoll[0] == 6 &&
          state.lastRoll[1] == 6;
      final earlier = state.doubleSixStreak - (currentIsDoubleSix ? 1 : 0);
      final sixes = state.rules.countSixesAcrossTurn
          ? state.sixesThisTurn
          : state.sixesBeforeRoll;
      return earlier >= 1 && sixes >= blockSize;
  }
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

class _StepResult {
  _StepResult(this.state, this.captured, this.newlyFinished);
  final GameState state;
  final List<PieceRef> captured;
  final List<PlayerColor> newlyFinished;
}

bool _jointTeams(GameState s) =>
    s.mode == GameMode.teams && s.rules.partnersFormJointBlocks;

bool _sameSide(GameState s, PlayerColor a, PlayerColor b) =>
    a == b || (_jointTeams(s) && partnerOf(a, s.mode) == b);

List<PlayerColor> _team(PlayerColor c) =>
    [c, partnerOf(c, GameMode.teams)!]..sort((a, b) => a.index - b.index);

PlayerColor _nextColor(PlayerColor c) =>
    PlayerColor.values[(c.index + 1) % PlayerColor.values.length];

/// Not finished and not forfeited.
List<PlayerColor> _activePlayers(GameState s) => [
  for (final c in s.players)
    if (!s.finishOrder.contains(c) && !s.forfeited.contains(c)) c,
];

bool _rollsForPartner(GameState s, PlayerColor c) {
  if (s.mode != GameMode.teams || !s.rules.finishedPlayerRollsForPartner) {
    return false;
  }
  final partner = partnerOf(c, s.mode)!;
  return !s.finishOrder.contains(partner) && !s.forfeited.contains(partner);
}

/// Whether a seat still takes turns.
bool _stillPlaying(GameState s, PlayerColor c) {
  if (s.forfeited.contains(c)) return false;
  if (!s.finishOrder.contains(c)) return true;
  return _rollsForPartner(s, c);
}

/// The colour whose pieces the current player moves.
PlayerColor _controlledColor(GameState s) {
  final c = s.current;
  if (s.finishOrder.contains(c) && _rollsForPartner(s, c)) {
    return partnerOf(c, s.mode)!;
  }
  return c;
}

bool _gameOverNow(GameState s) {
  switch (s.mode) {
    case GameMode.oneVsOne:
    case GameMode.teams:
      return winners(s) != null;
    case GameMode.freeForAll:
      if (!s.rules.freeForAllPlaysOn && s.finishOrder.isNotEmpty) return true;
      return _activePlayers(s).length <= 1;
  }
}

GameState _finishGame(GameState s) => s.copyWith(
  phase: TurnPhase.gameOver,
  remainingDice: const [],
  joinedOwnBlockThisRoll: const [],
);

/// Ends the current roll: game over, extra roll on a double 6, or next seat.
GameState _endRoll(GameState s) {
  if (_gameOverNow(s)) return _finishGame(s);
  final doubleSix = s.lastRoll.length == 2 && s.lastRoll.every((d) => d == 6);
  if (doubleSix && _stillPlaying(s, s.current)) {
    return s.copyWith(
      phase: TurnPhase.awaitingRoll,
      remainingDice: const [],
      joinedOwnBlockThisRoll: const [],
    );
  }
  return _passTurn(s);
}

GameState _passTurn(GameState s) {
  final seats = s.players;
  final from = seats.indexOf(s.current);
  var next = s.current;
  for (var i = 1; i <= seats.length; i++) {
    final c = seats[(from + i) % seats.length];
    if (_stillPlaying(s, c)) {
      next = c;
      break;
    }
  }
  return s.copyWith(
    current: next,
    phase: TurnPhase.awaitingRoll,
    remainingDice: const [],
    joinedOwnBlockThisRoll: const [],
    doubleSixStreak: 0,
    sixesThisTurn: 0,
    sixesBeforeRoll: 0,
    turnNumber: s.turnNumber + 1,
  );
}

int _diceUsed(Move m) => switch (m.kind) {
  MoveKind.blockAdvance => 2,
  MoveKind.pass => 0,
  _ => 1,
};

/// Largest number of the remaining dice that can still be used.
int _maxDiceUsable(GameState s) {
  if (s.remainingDice.isEmpty || _gameOverNow(s)) return 0;
  var best = 0;
  for (final m in _candidates(s)) {
    final used = _diceUsed(m) + _maxDiceUsable(_step(s, m).state);
    if (used > best) best = used;
    if (best == s.remainingDice.length) break;
  }
  return best;
}

/// Own side and opponent pieces on a track square for [mover].
(int own, int opponent) _occupancy(GameState s, PlayerColor mover, int square) {
  var own = 0, opp = 0;
  for (final p in s.piecesOnSquare(square)) {
    if (_sameSide(s, mover, p.color)) {
      own++;
    } else {
      opp++;
    }
  }
  return (own, opp);
}

/// Whether a piece of [mover] can go from progress [from] to [to]: no
/// passing any own side block or an opponent block without rights, and a
/// legal landing square.
bool _pathOk(GameState s, PlayerColor mover, int from, int to) {
  if (to > kFinished) return false;
  final lastPassed = to - 1 < kLastTrackProgress ? to - 1 : kLastTrackProgress;
  for (var q = from + 1; q <= lastPassed; q++) {
    final (own, opp) = _occupancy(s, mover, trackSquare(mover, q)!);
    if (own >= 2) return false;
    if (opp >= 2 && !hasBlockRights(s, mover, opp)) return false;
  }
  if (to <= kLastTrackProgress) {
    final (_, opp) = _occupancy(s, mover, trackSquare(mover, to)!);
    if (opp >= 2 && !hasBlockRights(s, mover, opp)) return false;
  }
  return true;
}

/// Every individually legal step, before the R2 filter.
List<Move> _candidates(GameState s) {
  if (s.remainingDice.isEmpty) return const [];
  final c = _controlledColor(s);
  if (s.forfeited.contains(c)) return const [];
  final pieces = s.pieces[c]!;
  final out = <Move>[];
  final dice = s.remainingDice.toSet().toList()..sort();
  for (final d in dice) {
    for (var i = 0; i < kPiecesPerPlayer; i++) {
      final p = pieces[i];
      if (p == kAtHome) {
        if (d == 6 && _pathOk(s, c, kAtHome, 0)) out.add(Move.release(c, i));
      } else if (p < kFinished) {
        if (!s.rules.canContinuePastOwnBlock &&
            s.joinedOwnBlockThisRoll.contains(PieceRef(c, i))) {
          continue;
        }
        if (_pathOk(s, c, p, p + d)) out.add(Move.advance(c, i, d));
      }
    }
  }
  final isDouble =
      s.remainingDice.length == 2 && s.remainingDice[0] == s.remainingDice[1];
  if (isDouble) {
    final d = s.remainingDice[0];
    final distance = s.rules.blockMoveUsesSum ? 2 * d : d;
    final done = <int>{};
    for (var i = 0; i < kPiecesPerPlayer; i++) {
      final p = pieces[i];
      if (p < 0 || p > kLastTrackProgress || !done.add(p)) continue;
      final group = [
        for (var j = 0; j < kPiecesPerPlayer; j++)
          if (pieces[j] == p) j,
      ];
      if (group.length >= 2 && _pathOk(s, c, p, p + distance)) {
        out.add(Move.blockAdvance(c, group, d));
      }
    }
  }
  return out;
}

/// Performs a step's mechanics without ending the roll. Assumes legality.
_StepResult _step(GameState s, Move m) {
  if (m.kind == MoveKind.pass) {
    return _StepResult(s.copyWith(remainingDice: const []), const [], const []);
  }
  final c = m.color;
  final dice = [...s.remainingDice];
  final int target;
  final int from = s.pieces[c]![m.pieces.first];
  switch (m.kind) {
    case MoveKind.release:
      dice.remove(6);
      target = 0;
    case MoveKind.advance:
      dice.remove(m.die);
      target = from + m.die;
    case MoveKind.blockAdvance:
      dice.clear();
      target = from + (s.rules.blockMoveUsesSum ? 2 * m.die : m.die);
    case MoveKind.pass:
      throw StateError('unreachable');
  }

  final newPieces = {
    for (final e in s.pieces.entries) e.key: [...e.value],
  };
  final captured = <PieceRef>[];
  var joined = s.joinedOwnBlockThisRoll;
  final square = trackSquare(c, target);
  if (square != null) {
    final (own, _) = _occupancy(s, c, square);
    for (final p in s.piecesOnSquare(square)) {
      if (!_sameSide(s, c, p.color)) {
        captured.add(p);
        newPieces[p.color]![p.index] = kAtHome;
      }
    }
    if (m.kind == MoveKind.advance && own >= 2) {
      joined = [...joined, PieceRef(c, m.pieces.single)];
    }
  }
  for (final i in m.pieces) {
    newPieces[c]![i] = target;
  }

  final newlyFinished = <PlayerColor>[];
  if (!s.finishOrder.contains(c) &&
      newPieces[c]!.every((p) => p == kFinished)) {
    newlyFinished.add(c);
  }
  final next = s.copyWith(
    pieces: newPieces,
    remainingDice: dice,
    joinedOwnBlockThisRoll: joined,
    finishOrder: [...s.finishOrder, ...newlyFinished],
  );
  return _StepResult(next, captured, newlyFinished);
}

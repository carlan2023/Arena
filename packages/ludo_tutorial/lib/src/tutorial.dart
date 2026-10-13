import 'package:ludo_engine/ludo_engine.dart';

/// Result of checking the player's moves for one roll.
class TutorialCheck {
  const TutorialCheck.ok() : ok = true, hintKey = null;
  const TutorialCheck.wrong(String this.hintKey) : ok = false;

  final bool ok;

  /// The hint to show again when [ok] is false.
  final String? hintKey;

  @override
  bool operator ==(Object other) =>
      other is TutorialCheck && other.ok == ok && other.hintKey == hintKey;

  @override
  int get hashCode => Object.hash(ok, hintKey);

  @override
  String toString() =>
      ok ? 'TutorialCheck.ok' : 'TutorialCheck.wrong($hintKey)';
}

/// One roll of a lesson: either the player's (red) or the scripted bot's
/// (yellow).
///
/// Wherever a method takes `before`, it is the state at the start of the
/// step, either before its roll (awaitingRoll) or right after it
/// (awaitingMove). The roll is applied when needed.
class TutorialStep {
  TutorialStep.player({
    required this.roll,
    required this.hintKey,
    required List<Move> suggested,
    required this.expected,
  }) : suggested = List.unmodifiable(suggested),
       botMoves = null;

  TutorialStep.bot({
    required this.roll,
    required this.hintKey,
    required List<Move> botMoves,
  }) : botMoves = List.unmodifiable(botMoves),
       suggested = const [],
       expected = null;

  /// The dice for this step.
  final (int, int) roll;

  /// Text key: what to do (player step) or what just happened (bot step).
  final String hintKey;

  /// Scripted reply for a bot step; null for a player step.
  final List<Move>? botMoves;

  /// The sequence the app highlights for a player step; empty for a bot step.
  final List<Move> suggested;

  /// The state after a player step is played as intended; null for a bot
  /// step. Any legal sequence reaching the same board is accepted.
  final GameState? expected;

  bool get isPlayerStep => botMoves == null;

  /// [before] with this step's roll applied.
  GameState rolled(GameState before) => before.phase == TurnPhase.awaitingRoll
      ? applyRoll(before, roll.$1, roll.$2)
      : before;

  /// Whether [played] is a legal, complete sequence for the roll that ends
  /// on the expected board.
  bool accepts(GameState before, List<Move> played) {
    if (!isPlayerStep) return false;
    var s = rolled(before);
    for (final m in played) {
      if (s.phase != TurnPhase.awaitingMove) return false;
      try {
        s = apply(s, m);
      } on IllegalMoveException {
        return false;
      }
    }
    return s.phase != TurnPhase.awaitingMove && sameBoard(s, expected!);
  }

  /// [TutorialCheck.ok] when [accepts], else wrong with this step's hint.
  TutorialCheck check(GameState before, List<Move> played) =>
      accepts(before, played)
      ? const TutorialCheck.ok()
      : TutorialCheck.wrong(hintKey);

  /// A legal sequence for this roll that reaches the expected board from
  /// [before]: [suggested] when it fits, else the first matching one (piece
  /// numbers can differ when the player picked another piece earlier).
  List<Move> suggestedFor(GameState before) {
    if (!isPlayerStep) return const [];
    if (accepts(before, suggested)) return suggested;
    for (final seq in legalSequences(rolled(before))) {
      if (accepts(before, seq)) return seq;
    }
    return const [];
  }

  /// Plays a bot step: the roll, then [botMoves].
  GameState playBot(GameState before) {
    if (isPlayerStep) throw StateError('Not a bot step');
    var s = rolled(before);
    for (final m in botMoves!) {
      s = apply(s, m);
    }
    return s;
  }
}

/// One lesson: a hand built position and the rolls that teach one rule.
class TutorialLesson {
  TutorialLesson({
    required this.id,
    required this.titleKey,
    required this.introKey,
    required this.start,
    required List<TutorialStep> steps,
  }) : steps = List.unmodifiable(steps);

  /// release, combine, block, break_block or exact_finish.
  final String id;
  final String titleKey;
  final String introKey;

  /// Red (the player) to roll, against a scripted yellow.
  final GameState start;
  final List<TutorialStep> steps;
}

/// Whether two states show the same board: the same squares per colour
/// (piece numbers ignored), the same player to act and the same phase.
bool sameBoard(GameState a, GameState b) {
  if (a.current != b.current || a.phase != b.phase) return false;
  if (a.players.length != b.players.length) return false;
  for (final c in a.players) {
    final x = [...a.pieces[c]!]..sort();
    final y = [...?b.pieces[c]]..sort();
    if (x.length != y.length) return false;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
  }
  return true;
}

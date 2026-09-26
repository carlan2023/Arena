import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';

import 'scoring.dart';

enum BotLevel { easy, normal }

abstract interface class LudoBot {
  /// The full ordered list of steps for the current roll, one of
  /// legalSequences(state). Empty unless state.phase is awaitingMove.
  List<Move> chooseMoves(GameState state);
}

/// Plays a random legal sequence.
class EasyBot implements LudoBot {
  EasyBot({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  List<Move> chooseMoves(GameState state) {
    final seqs = legalSequences(state);
    if (seqs.isEmpty) return const [];
    return seqs[_random.nextInt(seqs.length)];
  }
}

/// Plays the sequence with the best [scoreSequence], breaking ties at random.
class NormalBot implements LudoBot {
  NormalBot({Random? random}) : _random = random ?? Random();

  final Random _random;

  @override
  List<Move> chooseMoves(GameState state) {
    final seqs = legalSequences(state);
    if (seqs.isEmpty) return const [];
    if (seqs.length == 1) return seqs.single;
    var best = <List<Move>>[];
    var bestScore = double.negativeInfinity;
    for (final seq in seqs) {
      var s = state;
      for (final m in seq) {
        s = apply(s, m);
      }
      final score = scoreSequence(state, s, seq.first.color);
      if (score > bestScore) {
        bestScore = score;
        best = [seq];
      } else if (score == bestScore) {
        best.add(seq);
      }
    }
    return best[_random.nextInt(best.length)];
  }
}

LudoBot botFor(BotLevel level, {Random? random}) => switch (level) {
  BotLevel.easy => EasyBot(random: random),
  BotLevel.normal => NormalBot(random: random),
};

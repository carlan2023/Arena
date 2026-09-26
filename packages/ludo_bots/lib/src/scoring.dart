import 'package:ludo_engine/ludo_engine.dart';

/// NormalBot weights, all in one place.
abstract final class BotWeights {
  /// Per opponent piece sent home.
  static const double capture = 50;

  /// Extra per opponent block captured, on top of its pieces.
  static const double blockCapture = 40;

  /// Per partner piece sent home (teams). Negative: avoid it when possible.
  static const double capturePartner = -50;

  /// Per own block formed (net change in own blocks).
  static const double formBlock = 20;

  /// Per step of total progress gained by own pieces.
  static const double progress = 1;

  /// Extra per step gained by the piece that was furthest ahead.
  static const double leaderProgress = 1.5;

  /// Per own piece that reached the centre.
  static const double finish = 60;

  /// Per own piece released from home.
  static const double release = 30;

  /// Per own single piece 1 to 12 squares in front of an opponent piece.
  static const double danger = -25;

  /// How far ahead of an opponent piece counts as in danger.
  static const int dangerRange = 12;
}

/// Scores the end state [after] of one sequence played from [before] by the
/// owner of [color]'s pieces. Higher is better.
double scoreSequence(GameState before, GameState after, PlayerColor color) {
  final partner = partnerOf(color, before.mode);
  bool isOpponent(PlayerColor c) => c != color && c != partner;

  var score = 0.0;

  // Captures, counted from pieces that were on the track and are now home.
  final capturedSquares = <int, int>{};
  for (final c in before.players) {
    if (c == color) continue;
    for (var i = 0; i < kPiecesPerPlayer; i++) {
      final was = before.pieces[c]![i];
      if (was >= 0 && after.pieces[c]![i] == kAtHome) {
        if (isOpponent(c)) {
          score += BotWeights.capture;
          final sq = trackSquare(c, was)!;
          capturedSquares[sq] = (capturedSquares[sq] ?? 0) + 1;
        } else {
          score += BotWeights.capturePartner;
        }
      }
    }
  }
  score +=
      BotWeights.blockCapture *
      capturedSquares.values.where((n) => n >= 2).length;

  // Own blocks formed.
  int ownBlocks(GameState s) =>
      blocks(s).where((b) => b.pieces.every((p) => p.color == color)).length;
  score += BotWeights.formBlock * (ownBlocks(after) - ownBlocks(before));

  // Progress, the leader's progress, releases and finishes.
  final was = before.pieces[color]!;
  final now = after.pieces[color]!;
  var leader = -1;
  for (var i = 0; i < kPiecesPerPlayer; i++) {
    if (was[i] < kFinished && (leader < 0 || was[i] > was[leader])) leader = i;
  }
  for (var i = 0; i < kPiecesPerPlayer; i++) {
    score += BotWeights.progress * (now[i] - was[i]);
    if (was[i] == kAtHome && now[i] != kAtHome) score += BotWeights.release;
    if (was[i] != kFinished && now[i] == kFinished) score += BotWeights.finish;
  }
  if (leader >= 0 && was[leader] >= 0) {
    score += BotWeights.leaderProgress * (now[leader] - was[leader]);
  }

  // Danger: own single pieces an opponent could reach next turn.
  for (var i = 0; i < kPiecesPerPlayer; i++) {
    final sq = trackSquare(color, now[i]);
    if (sq == null) continue;
    if (after.piecesOnSquare(sq).length >= 2) continue;
    if (_threatened(after, sq, isOpponent)) score += BotWeights.danger;
  }
  return score;
}

bool _threatened(
  GameState s,
  int square,
  bool Function(PlayerColor) isOpponent,
) {
  for (final c in s.players) {
    if (!isOpponent(c)) continue;
    for (final p in s.pieces[c]!) {
      final from = trackSquare(c, p);
      if (from == null) continue;
      final distance = (square - from + kTrackLength) % kTrackLength;
      if (distance >= 1 &&
          distance <= BotWeights.dangerRange &&
          p + distance <= kLastTrackProgress) {
        return true;
      }
    }
  }
  return false;
}

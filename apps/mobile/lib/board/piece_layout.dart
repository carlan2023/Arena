import 'dart:ui';

import 'package:ludo_engine/ludo_engine.dart';

import 'board_geometry.dart';

/// Pieces drawn together at one point: one piece, or a stack sharing a cell.
class PieceStack {
  PieceStack(this.point, this.pieces);

  /// Board point in cell units, before any view rotation.
  final Offset point;
  final List<PieceRef> pieces;

  PlayerColor get color => pieces.first.color;
  bool get mixed => pieces.any((p) => p.color != color);
}

/// Where a piece is drawn for a given progress.
Offset piecePoint(PieceRef piece, int progress) =>
    BoardGeometry.piecePoint(piece.color.index, piece.index, progress);

/// Groups the pieces of [pieces] (progress per colour) into stacks. Pieces
/// on the same track or home column cell share a stack; yard and finish
/// pieces each have their own spot. [overrides] replaces the point of
/// pieces that are in flight, which are never stacked.
List<PieceStack> layoutPieces(
  Map<PlayerColor, List<int>> pieces, {
  Map<PieceRef, Offset> overrides = const {},
}) {
  final byCell = <(int, int), List<PieceRef>>{};
  final stacks = <PieceStack>[];
  for (final entry in pieces.entries) {
    final color = entry.key;
    for (var i = 0; i < entry.value.length; i++) {
      final ref = PieceRef(color, i);
      final flying = overrides[ref];
      if (flying != null) {
        stacks.add(PieceStack(flying, [ref]));
        continue;
      }
      final progress = entry.value[i];
      final cell = BoardGeometry.cellFor(color.index, progress);
      if (cell == null) {
        stacks.add(PieceStack(piecePoint(ref, progress), [ref]));
      } else {
        (byCell[cell] ??= []).add(ref);
      }
    }
  }
  for (final entry in byCell.entries) {
    stacks.add(PieceStack(BoardGeometry.cellCentre(entry.key), entry.value));
  }
  return stacks;
}

/// One piece's flight for an animation: the points it passes through, and
/// when in the animation (0 to 1) it starts and lands.
class PieceMotion {
  const PieceMotion(this.piece, this.waypoints, this.begin, this.end);

  final PieceRef piece;
  final List<Offset> waypoints;
  final double begin;
  final double end;

  /// The point at animation time [t] (0 to 1), or null once landed.
  Offset? pointAt(double t) {
    if (t >= end) return null;
    if (t <= begin) return waypoints.first;
    final f = (t - begin) / (end - begin) * (waypoints.length - 1);
    final i = f.floor().clamp(0, waypoints.length - 2);
    return Offset.lerp(waypoints[i], waypoints[i + 1], f - i)!;
  }
}

/// A planned animation between two positions.
class MotionPlan {
  const MotionPlan(this.motions, this.duration);

  final List<PieceMotion> motions;
  final Duration duration;

  bool get isEmpty => motions.isEmpty;

  static const empty = MotionPlan([], Duration.zero);

  /// Pieces in flight at time [t], with their points.
  Map<PieceRef, Offset> pointsAt(double t) => {
    for (final m in motions)
      if (m.pointAt(t) case final p?) m.piece: p,
  };
}

/// Plans how pieces get from [before] to [after]: pieces that moved forward
/// walk square by square, all at once; pieces sent home fly back to the yard
/// after the walkers land. Everything else jumps.
MotionPlan planMotion(
  Map<PlayerColor, List<int>> before,
  Map<PlayerColor, List<int>> after, {
  Duration step = const Duration(milliseconds: 110),
  Duration flight = const Duration(milliseconds: 420),
  Duration maxWalk = const Duration(milliseconds: 1600),
}) {
  final walkers = <PieceRef, List<Offset>>{};
  final flyers = <PieceRef, List<Offset>>{};
  for (final entry in after.entries) {
    final old = before[entry.key];
    if (old == null) continue;
    for (var i = 0; i < entry.value.length; i++) {
      final from = old[i];
      final to = entry.value[i];
      if (from == to) continue;
      final ref = PieceRef(entry.key, i);
      final start = piecePoint(ref, from);
      if (to > from) {
        final path = BoardGeometry.path(entry.key.index, i, from, to);
        walkers[ref] = [start, ...path];
      } else if (to == kAtHome) {
        flyers[ref] = [start, piecePoint(ref, to)];
      }
    }
  }
  if (walkers.isEmpty && flyers.isEmpty) return MotionPlan.empty;

  var steps = 0;
  for (final w in walkers.values) {
    if (w.length - 1 > steps) steps = w.length - 1;
  }
  var walkMs = step.inMilliseconds * steps;
  if (walkMs > maxWalk.inMilliseconds) walkMs = maxWalk.inMilliseconds;
  final flyMs = flyers.isEmpty ? 0 : flight.inMilliseconds;
  final total = walkMs + flyMs;
  final walkEnd = total == 0 ? 1.0 : walkMs / total;

  return MotionPlan([
    for (final e in walkers.entries)
      PieceMotion(e.key, e.value, 0, walkEnd * (e.value.length - 1) / steps),
    for (final e in flyers.entries) PieceMotion(e.key, e.value, walkEnd, 1),
  ], Duration(milliseconds: total));
}

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'board_geometry.dart';
import 'board_palette.dart';
import 'piece_layout.dart';

/// A translucent landing spot the player can tap.
class GhostMark {
  const GhostMark(this.point, this.label, this.color, {this.id = 0});

  /// Board point in cell units, before view rotation.
  final Offset point;
  final String label;
  final PlayerColor color;

  /// Caller's handle to find the option when the ghost is tapped.
  final int id;
}

/// The bar drawn across the track over a block.
class BlockBar {
  const BlockBar(this.square, this.color, this.count, {this.cracked = false});

  /// Absolute track square 0..51.
  final int square;
  final PlayerColor color;
  final int count;

  /// The mover could break this block (README section 7).
  final bool cracked;
}

/// Paints pieces, block bars, highlights and ghost landing spots, in the
/// same cell units and rotation as [BoardPainter].
class PiecesPainter extends CustomPainter {
  PiecesPainter({
    required this.stacks,
    this.turns = 0,
    this.palette = BoardPalette.standard,
    this.selectable = const {},
    this.selected = const {},
    this.ghosts = const [],
    this.bars = const [],
  });

  final List<PieceStack> stacks;
  final int turns;
  final BoardPalette palette;
  final Set<PieceRef> selectable;
  final Set<PieceRef> selected;
  final List<GhostMark> ghosts;
  final List<BlockBar> bars;

  static const double pieceRadius = 0.36;

  Offset _view(Offset p) => BoardGeometry.rotatePoint(p, turns);

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.shortestSide / BoardGeometry.gridSize;
    canvas.save();
    canvas.scale(cell);

    for (final bar in bars) {
      _paintBar(canvas, bar);
    }
    for (final g in ghosts) {
      _paintGhost(canvas, g);
    }
    for (final s in stacks) {
      _paintStack(canvas, s);
    }
    canvas.restore();
  }

  void _paintStack(Canvas canvas, PieceStack stack) {
    final centre = _view(stack.point);
    final isSelected = stack.pieces.any(selected.contains);
    final isSelectable = stack.pieces.any(selectable.contains);
    if (isSelectable || isSelected) {
      canvas.drawCircle(
        centre,
        pieceRadius + 0.12,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 0.16 : 0.09
          ..color = palette.highlight,
      );
    }

    if (stack.mixed) {
      // Joint blocks (R8): draw each colour slightly apart.
      final colors = {for (final p in stack.pieces) p.color}.toList();
      for (var i = 0; i < colors.length; i++) {
        final a = 2 * math.pi * i / colors.length;
        _paintPiece(
          canvas,
          centre + Offset(math.cos(a), math.sin(a)) * 0.14,
          colors[i],
          pieceRadius * 0.8,
        );
      }
    } else {
      _paintPiece(canvas, centre, stack.color, pieceRadius);
    }
    if (stack.pieces.length > 1) {
      _paintCount(canvas, centre, stack.pieces.length);
    }
  }

  void _paintPiece(Canvas canvas, Offset c, PlayerColor color, double r) {
    canvas.drawCircle(
      c + const Offset(0.03, 0.05),
      r,
      Paint()..color = const Color(0x55000000),
    );
    canvas.drawCircle(c, r, Paint()..color = palette.player(color.index));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..color = const Color(0xFFFFFFFF),
    );
    _paintShape(canvas, c, color, r * 0.45);
  }

  /// A white shape per colour so colour blind players can tell pieces apart:
  /// red circle, green triangle, yellow square, blue diamond.
  void _paintShape(Canvas canvas, Offset c, PlayerColor color, double r) {
    final paint = Paint()..color = const Color(0xFFFFFFFF);
    switch (color) {
      case PlayerColor.red:
        canvas.drawCircle(c, r, paint);
      case PlayerColor.green:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r, c.dy + r * 0.8)
            ..lineTo(c.dx - r, c.dy + r * 0.8)
            ..close(),
          paint,
        );
      case PlayerColor.yellow:
        canvas.drawRect(
          Rect.fromCenter(center: c, width: r * 1.6, height: r * 1.6),
          paint,
        );
      case PlayerColor.blue:
        canvas.drawPath(
          Path()
            ..moveTo(c.dx, c.dy - r)
            ..lineTo(c.dx + r, c.dy)
            ..lineTo(c.dx, c.dy + r)
            ..lineTo(c.dx - r, c.dy)
            ..close(),
          paint,
        );
    }
  }

  void _paintCount(Canvas canvas, Offset c, int count) {
    final badge = c + const Offset(0.28, -0.28);
    canvas.drawCircle(badge, 0.2, Paint()..color = const Color(0xFF212121));
    _paintText(canvas, badge, '$count', 0.28, const Color(0xFFFFFFFF));
  }

  void _paintGhost(Canvas canvas, GhostMark g) {
    final c = _view(g.point);
    final color = palette.player(g.color.index);
    canvas.drawCircle(
      c,
      pieceRadius,
      Paint()..color = color.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      c,
      pieceRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.07
        ..color = color,
    );
    _paintText(canvas, c, g.label, 0.34, const Color(0xFF212121));
  }

  void _paintBar(Canvas canvas, BlockBar bar) {
    final s = bar.square;
    final prev = BoardGeometry.cellCentre(
      BoardGeometry.trackCell((s + 51) % 52),
    );
    final next = BoardGeometry.cellCentre(
      BoardGeometry.trackCell((s + 1) % 52),
    );
    final centre = _view(BoardGeometry.cellCentre(BoardGeometry.trackCell(s)));
    final along = _view(next) - _view(prev);
    final dir = along / along.distance;
    final across = Offset(-dir.dy, dir.dx);
    // The bar sits on the back edge of the square, facing the pieces it
    // walls off.
    final mid = centre - dir * 0.44;
    final half = across * 0.5;
    final paint = Paint()
      ..strokeWidth = 0.12
      ..strokeCap = StrokeCap.round
      ..color = palette.player(bar.color.index);
    final dark = Paint()
      ..strokeWidth = 0.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF212121);
    if (!bar.cracked) {
      canvas.drawLine(mid - half, mid + half, dark);
      canvas.drawLine(mid - half, mid + half, paint);
      return;
    }
    // Cracked: two halves with a zigzag gap.
    final gap = across * 0.08;
    final kink = dir * 0.08;
    for (final sign in const [-1.0, 1.0]) {
      final outer = mid + half * sign;
      final inner = mid + gap * sign + kink * sign;
      canvas.drawLine(outer, inner, dark);
      canvas.drawLine(outer, inner, paint);
    }
  }

  void _paintText(Canvas canvas, Offset c, String text, double h, Color col) {
    // Text is laid out at a readable size and scaled into cell units.
    const scale = 100.0;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: h * scale,
          fontWeight: FontWeight.bold,
          color: col,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1 / scale);
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
    tp.dispose();
  }

  @override
  bool shouldRepaint(PiecesPainter old) =>
      old.stacks != stacks ||
      old.turns != turns ||
      old.palette != palette ||
      old.selectable != selectable ||
      old.selected != selected ||
      old.ghosts != ghosts ||
      old.bars != bars;
}

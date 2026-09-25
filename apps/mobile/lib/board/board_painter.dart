import 'package:flutter/rendering.dart';

import 'board_geometry.dart';
import 'board_palette.dart';

/// Paints the static board: yards, track, home columns and the centre.
///
/// It never changes during a game, so wrap it in a RepaintBoundary and it is
/// rasterised once. [turns] rotates the board clockwise in quarter turns so
/// the viewer's yard can sit at the bottom left.
class BoardPainter extends CustomPainter {
  const BoardPainter({this.palette = BoardPalette.standard, this.turns = 0});

  final BoardPalette palette;
  final int turns;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final cell = side / BoardGeometry.gridSize;

    canvas.save();
    // Rotate around the board centre, then work in cell units.
    canvas.translate(side / 2, side / 2);
    canvas.rotate(turns % 4 * 1.5707963267948966);
    canvas.translate(-side / 2, -side / 2);
    canvas.scale(cell);

    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04
      ..color = palette.gridLine;

    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 15, 15),
      fill..color = palette.background,
    );

    for (var c = 0; c < 4; c++) {
      _paintYard(canvas, c, fill, line);
    }

    // Track squares, start squares in the owner's colour.
    for (var s = 0; s < BoardGeometry.trackLength; s++) {
      final rect = _cellRect(BoardGeometry.trackCell(s));
      final owner = s % 13 == 0 ? s ~/ 13 : null;
      fill.color = owner == null ? palette.track : palette.player(owner);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, line);
    }

    // Home columns.
    for (var c = 0; c < 4; c++) {
      fill.color = palette.tint(c);
      for (var step = 1; step <= BoardGeometry.homeColumnLength; step++) {
        final rect = _cellRect(BoardGeometry.homeColumnCell(c, step));
        canvas.drawRect(rect, fill);
        canvas.drawRect(rect, line);
      }
    }

    _paintCentre(canvas, fill, line);
    canvas.restore();
  }

  Rect _cellRect((int, int) cell) =>
      Rect.fromLTWH(cell.$2.toDouble(), cell.$1.toDouble(), 1, 1);

  void _paintYard(Canvas canvas, int colorIndex, Paint fill, Paint line) {
    // Red's yard is the top left 6 by 6 corner; rotate for the others.
    final a = BoardGeometry.rotatePoint(Offset.zero, colorIndex);
    final b = BoardGeometry.rotatePoint(const Offset(6, 6), colorIndex);
    final outer = Rect.fromPoints(a, b);
    canvas.drawRect(outer, fill..color = palette.player(colorIndex));
    canvas.drawRect(outer, line);

    final inner = outer.deflate(0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(0.4)),
      fill..color = palette.yardInner,
    );
    fill.color = palette.tint(colorIndex);
    for (var i = 0; i < 4; i++) {
      canvas.drawCircle(BoardGeometry.yardSlot(colorIndex, i), 0.6, fill);
    }
  }

  void _paintCentre(Canvas canvas, Paint fill, Paint line) {
    const centre = Offset(7.5, 7.5);
    // Red's triangle is the left one; rotate for the others.
    for (var c = 0; c < 4; c++) {
      final p1 = BoardGeometry.rotatePoint(const Offset(6, 6), c);
      final p2 = BoardGeometry.rotatePoint(const Offset(6, 9), c);
      final path = Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..lineTo(centre.dx, centre.dy)
        ..close();
      canvas.drawPath(path, fill..color = palette.player(c));
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(BoardPainter oldDelegate) =>
      oldDelegate.turns != turns || oldDelegate.palette != palette;
}

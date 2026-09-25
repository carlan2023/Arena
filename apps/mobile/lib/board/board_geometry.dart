import 'dart:ui';

/// Maps engine positions to places on the 15 by 15 board grid.
///
/// Follows the board paragraph in docs/contracts/engine_api.md. Red (colour
/// index 0) is the left arm; green, yellow and blue follow clockwise, each the
/// red layout turned 90 degrees clockwise per colour.
///
/// Positions are returned as [Offset]s in cell units measured from the top
/// left corner of the board: `dx` is the column, `dy` the row, and the centre
/// of cell (row, col) is `Offset(col + 0.5, row + 0.5)`. Multiply by the cell
/// size to get pixels.
class BoardGeometry {
  BoardGeometry._();

  static const int gridSize = 15;
  static const int trackLength = 52;
  static const int homeColumnLength = 5;
  static const int atHome = -1;
  static const int lastTrackProgress = 51;
  static const int finished = 57;

  /// Red's part of the track: absolute squares 0 to 12, as (row, col).
  static const List<(int, int)> _redQuarter = [
    (6, 0), (6, 1), (6, 2), (6, 3), (6, 4), (6, 5), //
    (5, 6), (4, 6), (3, 6), (2, 6), (1, 6), (0, 6), //
    (0, 7),
  ];

  /// Turns a cell `turns` quarter turns clockwise around the board centre.
  static (int, int) rotateCell((int, int) cell, int turns) {
    var (r, c) = cell;
    for (var i = 0; i < turns % 4; i++) {
      (r, c) = (c, gridSize - 1 - r);
    }
    return (r, c);
  }

  /// Turns a point in cell units `turns` quarter turns clockwise.
  static Offset rotatePoint(Offset p, int turns) {
    var x = p.dx;
    var y = p.dy;
    for (var i = 0; i < turns % 4; i++) {
      final nx = gridSize - y;
      y = x;
      x = nx;
    }
    return Offset(x, y);
  }

  /// The (row, col) of absolute track square 0..51.
  static (int, int) trackCell(int square) {
    RangeError.checkValueInInterval(square, 0, trackLength - 1, 'square');
    return rotateCell(_redQuarter[square % 13], square ~/ 13);
  }

  /// The (row, col) of home column step 1..5 for [colorIndex]
  /// (progress 52 is step 1).
  static (int, int) homeColumnCell(int colorIndex, int step) {
    RangeError.checkValueInInterval(step, 1, homeColumnLength, 'step');
    return rotateCell((7, step), colorIndex);
  }

  /// Absolute track square for a progress 0..51, as in the engine.
  static int absoluteSquare(int colorIndex, int progress) =>
      (colorIndex * 13 + progress) % trackLength;

  /// The grid cell for a piece on the track or in its home column, or null
  /// for pieces at home (in the yard) or finished.
  static (int, int)? cellFor(int colorIndex, int progress) {
    if (progress >= 0 && progress <= lastTrackProgress) {
      return trackCell(absoluteSquare(colorIndex, progress));
    }
    if (progress > lastTrackProgress && progress < finished) {
      return homeColumnCell(colorIndex, progress - lastTrackProgress);
    }
    return null;
  }

  static Offset cellCentre((int, int) cell) =>
      Offset(cell.$2 + 0.5, cell.$1 + 0.5);

  /// Red's yard slots (top left corner), in cell units.
  static const List<Offset> _redYardSlots = [
    Offset(2, 2),
    Offset(4, 2),
    Offset(2, 4),
    Offset(4, 4),
  ];

  /// Where piece [pieceIndex] of [colorIndex] sits while at home.
  static Offset yardSlot(int colorIndex, int pieceIndex) =>
      rotatePoint(_redYardSlots[pieceIndex % 4], colorIndex);

  /// Where finished pieces of [colorIndex] gather: inside the colour's
  /// triangle in the centre, spread a little per piece.
  static Offset finishSpot(int colorIndex, int pieceIndex) {
    const spots = [
      Offset(6.55, 7.1),
      Offset(6.55, 7.9),
      Offset(6.95, 7.3),
      Offset(6.95, 7.7),
    ];
    return rotatePoint(spots[pieceIndex % 4], colorIndex);
  }

  /// The centre point, in cell units, where a piece is drawn.
  static Offset piecePoint(int colorIndex, int pieceIndex, int progress) {
    if (progress == atHome) return yardSlot(colorIndex, pieceIndex);
    if (progress >= finished) return finishSpot(colorIndex, pieceIndex);
    return cellCentre(cellFor(colorIndex, progress)!);
  }

  /// The points a piece passes through moving from [from] to [to] one step
  /// at a time, ending at [to]. A release is one hop from the yard.
  static List<Offset> path(int colorIndex, int pieceIndex, int from, int to) {
    if (from == atHome || to <= from) {
      return [piecePoint(colorIndex, pieceIndex, to)];
    }
    return [
      for (var p = from + 1; p <= to; p++)
        piecePoint(colorIndex, pieceIndex, p),
    ];
  }

  /// Quarter turns clockwise that put [colorIndex]'s yard at the bottom left
  /// (decision D24). Red's yard is top left, so red needs three.
  static int viewTurnsFor(int colorIndex) => (3 - colorIndex) % 4;
}

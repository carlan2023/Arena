import 'package:arena/board/board_geometry.dart';
import 'package:arena/board/piece_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;

void main() {
  test('pieces on one cell share a stack, yard pieces do not', () {
    final stacks = layoutPieces({
      red: [5, 5, kAtHome, kAtHome],
      green: [kAtHome, kAtHome, kAtHome, kFinished],
    });
    expect(stacks, hasLength(7));
    final stack = stacks.singleWhere((s) => s.pieces.length > 1);
    expect(stack.pieces, [const PieceRef(red, 0), const PieceRef(red, 1)]);
    expect(stack.point, BoardGeometry.cellCentre(BoardGeometry.trackCell(5)));
    expect(stack.mixed, isFalse);
  });

  test('different colours on one square form a mixed stack', () {
    // Red progress 13 and green progress 0 are both square 13.
    final stacks = layoutPieces({
      red: [13, kAtHome, kAtHome, kAtHome],
      green: [0, kAtHome, kAtHome, kAtHome],
    });
    expect(stacks.singleWhere((s) => s.pieces.length == 2).mixed, isTrue);
  });

  test('pieces in flight are drawn at their override point', () {
    const p = Offset(3, 3);
    final stacks = layoutPieces(
      {
        red: [5, 5, kAtHome, kAtHome],
      },
      overrides: {const PieceRef(red, 1): p},
    );
    expect(stacks, hasLength(4));
    expect(stacks.where((s) => s.point == p).single.pieces, [
      const PieceRef(red, 1),
    ]);
  });

  group('planMotion', () {
    test('no change, no motion', () {
      final m = planMotion(
        {
          red: [1, 2, 3, 4],
        },
        {
          red: [1, 2, 3, 4],
        },
      );
      expect(m.isEmpty, isTrue);
      expect(m.duration, Duration.zero);
    });

    test('a walk visits every square', () {
      final m = planMotion(
        {
          red: [3, kAtHome, kAtHome, kAtHome],
        },
        {
          red: [8, kAtHome, kAtHome, kAtHome],
        },
      );
      expect(m.motions, hasLength(1));
      final walk = m.motions.single;
      expect(walk.waypoints, hasLength(6));
      expect(walk.waypoints.first, piecePoint(const PieceRef(red, 0), 3));
      expect(walk.pointAt(0), walk.waypoints.first);
      expect(walk.pointAt(0.5), isNotNull);
      expect(walk.pointAt(1), isNull, reason: 'landed');
      expect(m.duration, const Duration(milliseconds: 550));
    });

    test('a capture flies home after the walker lands', () {
      // Red walks from 10 to 13 and sends green's piece on square 13 home.
      final m = planMotion(
        {
          red: [10, kAtHome, kAtHome, kAtHome],
          green: [0, kAtHome, kAtHome, kAtHome],
        },
        {
          red: [13, kAtHome, kAtHome, kAtHome],
          green: [kAtHome, kAtHome, kAtHome, kAtHome],
        },
      );
      final walk = m.motions.firstWhere((x) => x.piece.color == red);
      final fly = m.motions.firstWhere((x) => x.piece.color == green);
      expect(fly.begin, walk.end);
      expect(fly.end, 1);
      expect(fly.waypoints.last, BoardGeometry.yardSlot(green.index, 0));
      expect(m.duration.inMilliseconds, lessThan(1000));
      expect(m.pointsAt(0).keys, containsAll([walk.piece, fly.piece]));
    });

    test('long walks are capped', () {
      final m = planMotion(
        {
          red: [0, kAtHome, kAtHome, kAtHome],
        },
        {
          red: [56, kAtHome, kAtHome, kAtHome],
        },
      );
      expect(m.duration, const Duration(milliseconds: 1600));
    });

    test('shorter walks finish earlier, at the same pace', () {
      final m = planMotion(
        {
          red: [0, 10, kAtHome, kAtHome],
        },
        {
          red: [2, 14, kAtHome, kAtHome],
        },
      );
      final short = m.motions.firstWhere((x) => x.piece.index == 0);
      expect(short.end, closeTo(0.5, 1e-9));
    });
  });
}

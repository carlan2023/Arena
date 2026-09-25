import 'package:arena/board/board_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

const red = 0, green = 1, yellow = 2, blue = 3;

void main() {
  group('contract geometry paragraph (engine_api.md)', () {
    test('red track cells', () {
      const expected = {
        0: (6, 0),
        1: (6, 1),
        2: (6, 2),
        3: (6, 3),
        4: (6, 4),
        5: (6, 5),
        6: (5, 6),
        7: (4, 6),
        8: (3, 6),
        9: (2, 6),
        10: (1, 6),
        11: (0, 6),
        12: (0, 7),
        13: (0, 8),
        51: (7, 0),
      };
      expected.forEach((progress, cell) {
        expect(
          BoardGeometry.cellFor(red, progress),
          cell,
          reason: 'progress $progress',
        );
      });
    });

    test('red home column is (7,1) to (7,5)', () {
      for (var p = 52; p <= 56; p++) {
        expect(BoardGeometry.cellFor(red, p), (7, p - 51));
      }
    });

    test('green start square is red progress 13', () {
      expect(BoardGeometry.cellFor(green, 0), (0, 8));
      expect(BoardGeometry.cellFor(green, 0), BoardGeometry.cellFor(red, 13));
    });

    test('other colours are the red path turned clockwise', () {
      expect(BoardGeometry.cellFor(green, 51), (0, 7));
      expect(BoardGeometry.cellFor(green, 52), (1, 7));
      expect(BoardGeometry.cellFor(yellow, 0), (8, 14));
      expect(BoardGeometry.cellFor(yellow, 51), (7, 14));
      expect(BoardGeometry.cellFor(yellow, 56), (7, 9));
      expect(BoardGeometry.cellFor(blue, 0), (14, 6));
      expect(BoardGeometry.cellFor(blue, 51), (14, 7));
      expect(BoardGeometry.cellFor(blue, 56), (9, 7));
    });

    test('absolute square matches the engine formula', () {
      for (var c = 0; c < 4; c++) {
        for (var p = 0; p <= 51; p++) {
          expect(BoardGeometry.absoluteSquare(c, p), (c * 13 + p) % 52);
          expect(
            BoardGeometry.cellFor(c, p),
            BoardGeometry.trackCell((c * 13 + p) % 52),
          );
        }
      }
    });
  });

  group('track shape', () {
    final cells = [for (var s = 0; s < 52; s++) BoardGeometry.trackCell(s)];

    test('52 distinct cells, none in a yard or the centre', () {
      expect(cells.toSet().length, 52);
      for (final (r, c) in cells) {
        final inArmRows = r >= 6 && r <= 8;
        final inArmCols = c >= 6 && c <= 8;
        expect(inArmRows || inArmCols, isTrue, reason: '($r,$c)');
        expect(inArmRows && inArmCols, isFalse, reason: '($r,$c)');
      }
    });

    test('consecutive squares touch, and the loop closes', () {
      // The track turns diagonally at the four inner corners: the contract
      // puts progress 5 at (6,5) and 6 at (5,6).
      var diagonals = 0;
      for (var s = 0; s < 52; s++) {
        final (r1, c1) = cells[s];
        final (r2, c2) = cells[(s + 1) % 52];
        final dr = (r1 - r2).abs();
        final dc = (c1 - c2).abs();
        expect(dr <= 1 && dc <= 1 && dr + dc > 0, isTrue, reason: 'sq $s');
        if (dr + dc == 2) diagonals++;
      }
      expect(diagonals, 4);
    });

    test('home columns do not overlap the track and lead to the centre', () {
      final home = <(int, int)>{};
      for (var c = 0; c < 4; c++) {
        final entry = BoardGeometry.cellFor(c, 51)!;
        final first = BoardGeometry.cellFor(c, 52)!;
        expect((entry.$1 - first.$1).abs() + (entry.$2 - first.$2).abs(), 1);
        for (var p = 52; p <= 56; p++) {
          home.add(BoardGeometry.cellFor(c, p)!);
        }
      }
      expect(home.length, 20);
      expect(home.intersection(cells.toSet()), isEmpty);
    });
  });

  group('points', () {
    test('cell centres are in cell units', () {
      expect(BoardGeometry.piecePoint(red, 0, 0), const Offset(0.5, 6.5));
    });

    test('yard and finish points are null cells', () {
      expect(BoardGeometry.cellFor(red, -1), isNull);
      expect(BoardGeometry.cellFor(red, 57), isNull);
    });

    test('red yard is top left, blue yard bottom left', () {
      final r = BoardGeometry.yardSlot(red, 0);
      expect(r.dx < 6 && r.dy < 6, isTrue);
      final b = BoardGeometry.yardSlot(blue, 0);
      expect(b.dx < 6 && b.dy > 9, isTrue);
    });

    test('yard slots are distinct per piece', () {
      for (var c = 0; c < 4; c++) {
        final slots = {
          for (var i = 0; i < 4; i++) BoardGeometry.yardSlot(c, i),
        };
        expect(slots.length, 4);
      }
    });

    test('finish spots sit in the centre square', () {
      for (var c = 0; c < 4; c++) {
        for (var i = 0; i < 4; i++) {
          final p = BoardGeometry.finishSpot(c, i);
          expect(p.dx, inInclusiveRange(6, 9));
          expect(p.dy, inInclusiveRange(6, 9));
        }
      }
    });

    test('rotatePoint four times is the identity', () {
      const p = Offset(2.25, 11.5);
      final q = BoardGeometry.rotatePoint(p, 4);
      expect(q, p);
      final back = BoardGeometry.rotatePoint(
        BoardGeometry.rotatePoint(p, 1),
        3,
      );
      expect(back.dx, closeTo(p.dx, 1e-9));
      expect(back.dy, closeTo(p.dy, 1e-9));
    });

    test('path steps one cell at a time', () {
      final path = BoardGeometry.path(red, 0, 3, 8);
      expect(path.length, 5);
      expect(path.last, BoardGeometry.piecePoint(red, 0, 8));
      expect(BoardGeometry.path(red, 0, -1, 0), [
        BoardGeometry.piecePoint(red, 0, 0),
      ]);
      expect(BoardGeometry.path(red, 0, 30, -1), [
        BoardGeometry.yardSlot(red, 0),
      ]);
    });

    test('view turns put each yard at the bottom left', () {
      for (var c = 0; c < 4; c++) {
        final p = BoardGeometry.rotatePoint(
          BoardGeometry.yardSlot(c, 0),
          BoardGeometry.viewTurnsFor(c),
        );
        expect(p.dx < 6 && p.dy > 9, isTrue, reason: 'colour $c');
      }
    });
  });
}

import 'package:arena/board/board_painter.dart';
import 'package:arena/board/board_palette.dart';
import 'package:arena/board/board_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('board paints at phone width for every view turn', (
    tester,
  ) async {
    for (var turns = 0; turns < 4; turns++) {
      await tester.pumpWidget(
        Center(
          child: SizedBox(width: 360, child: BoardView(turns: turns)),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(BoardView)), const Size(360, 360));
    }
  });

  testWidgets('board sits behind a repaint boundary', (tester) async {
    await tester.pumpWidget(const Center(child: BoardView()));
    final paint = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    expect(
      find.ancestor(of: paint, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
  });

  test('repaints only when turns or palette change', () {
    const a = BoardPainter();
    expect(a.shouldRepaint(const BoardPainter()), isFalse);
    expect(a.shouldRepaint(const BoardPainter(turns: 1)), isTrue);
    expect(
      a.shouldRepaint(
        const BoardPainter(palette: BoardPalette(track: Color(0xFF000000))),
      ),
      isTrue,
    );
  });

  test('palette has four player colours and lighter tints', () {
    const p = BoardPalette.standard;
    expect(p.players.length, 4);
    for (var c = 0; c < 4; c++) {
      expect(
        p.tint(c).computeLuminance(),
        greaterThan(p.player(c).computeLuminance()),
      );
    }
  });
}

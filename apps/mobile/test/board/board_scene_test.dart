import 'package:arena/board/board_geometry.dart';
import 'package:arena/board/board_scene.dart';
import 'package:arena/board/piece_layout.dart';
import 'package:arena/board/pieces_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;
const side = 300.0;
const cell = side / 15;

Map<PlayerColor, List<int>> pieces(List<int> r, [List<int>? g]) => {
  red: r,
  green: g ?? [kAtHome, kAtHome, kAtHome, kAtHome],
};

Widget host(BoardScene scene) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: side, height: side, child: scene),
  ),
);

/// Global position of a board point once the view is turned.
Offset screen(WidgetTester tester, Offset boardPoint, int turns) {
  final origin = tester.getTopLeft(find.byType(BoardScene));
  return origin + BoardGeometry.rotatePoint(boardPoint, turns) * cell;
}

void main() {
  for (final turns in [0, 1, 3]) {
    testWidgets('tapping a piece reports it (turns $turns)', (tester) async {
      List<PieceRef>? tapped;
      await tester.pumpWidget(
        host(
          BoardScene(
            pieces: pieces([5, 5, 20, kAtHome]),
            turns: turns,
            onTapPieces: (p) => tapped = p,
          ),
        ),
      );
      final stack = BoardGeometry.cellCentre(BoardGeometry.trackCell(5));
      await tester.tapAt(screen(tester, stack, turns));
      expect(tapped, [const PieceRef(red, 0), const PieceRef(red, 1)]);

      await tester.tapAt(
        screen(tester, piecePoint(const PieceRef(red, 3), kAtHome), turns),
      );
      expect(tapped, [const PieceRef(red, 3)]);
    });
  }

  testWidgets('ghosts win over pieces under them', (tester) async {
    int? ghost;
    List<PieceRef>? tapped;
    final target = piecePoint(const PieceRef(red, 0), 8);
    await tester.pumpWidget(
      host(
        BoardScene(
          pieces: pieces([5, kAtHome, kAtHome, kAtHome]),
          ghosts: [GhostMark(target, '3', red, id: 7)],
          onTapGhost: (id) => ghost = id,
          onTapPieces: (p) => tapped = p,
        ),
      ),
    );
    await tester.tapAt(screen(tester, target, 0));
    expect(ghost, 7);
    expect(tapped, isNull);
  });

  testWidgets('taps on empty squares do nothing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        BoardScene(
          pieces: pieces([5, kAtHome, kAtHome, kAtHome]),
          onTapPieces: (_) => calls++,
          onTapGhost: (_) => calls++,
        ),
      ),
    );
    await tester.tapAt(
      screen(tester, BoardGeometry.cellCentre(BoardGeometry.trackCell(30)), 0),
    );
    expect(calls, 0);
  });

  testWidgets('a change animates, blocks taps, then reports done', (
    tester,
  ) async {
    var done = 0;
    List<PieceRef>? tapped;
    Widget scene(List<int> r, List<int> g) => host(
      BoardScene(
        pieces: pieces(r, g),
        onTapPieces: (p) => tapped = p,
        onAnimationDone: () => done++,
      ),
    );
    await tester.pumpWidget(
      scene([10, kAtHome, kAtHome, kAtHome], [0, -1, -1, -1]),
    );
    await tester.pumpWidget(
      scene([13, kAtHome, kAtHome, kAtHome], [kAtHome, -1, -1, -1]),
    );
    final state = tester.state<BoardSceneState>(find.byType(BoardScene));
    expect(state.animating, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(
      screen(tester, BoardGeometry.cellCentre(BoardGeometry.trackCell(13)), 0),
    );
    expect(tapped, isNull, reason: 'taps are ignored mid animation');

    await tester.pumpAndSettle();
    expect(state.animating, isFalse);
    expect(done, 1);
    await tester.tapAt(
      screen(tester, BoardGeometry.cellCentre(BoardGeometry.trackCell(13)), 0),
    );
    expect(tapped, [const PieceRef(red, 0)]);
  });

  testWidgets('paints highlights, ghosts, bars and a mixed stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        BoardScene(
          pieces: pieces([13, 20, 20, kFinished], [0, 1, kAtHome, kAtHome]),
          selectable: {const PieceRef(red, 1)},
          selected: {const PieceRef(red, 1)},
          ghosts: [GhostMark(piecePoint(const PieceRef(red, 1), 24), '4', red)],
          bars: const [
            BlockBar(20, red, 2),
            BlockBar(33, green, 2, cracked: true),
          ],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

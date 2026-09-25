import 'package:flutter/widgets.dart';

import 'board_painter.dart';
import 'board_palette.dart';

/// A square board that fills the available width. Layers such as pieces and
/// highlights go in [overlay], painted in the same cell units.
class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    this.turns = 0,
    this.palette = BoardPalette.standard,
    this.overlay,
  });

  final int turns;
  final BoardPalette palette;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: BoardPainter(palette: palette, turns: turns),
            ),
          ),
          ?overlay,
        ],
      ),
    );
  }
}

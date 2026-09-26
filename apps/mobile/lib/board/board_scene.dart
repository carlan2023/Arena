import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'board_geometry.dart';
import 'board_palette.dart';
import 'board_view.dart';
import 'piece_layout.dart';
import 'pieces_painter.dart';

/// The board with its pieces. Animates whenever [pieces] changes, and
/// reports taps on ghosts and on pieces.
///
/// It holds no game logic: the caller decides what is selectable and what
/// the ghosts are.
class BoardScene extends StatefulWidget {
  const BoardScene({
    super.key,
    required this.pieces,
    this.turns = 0,
    this.palette = BoardPalette.standard,
    this.selectable = const {},
    this.selected = const {},
    this.ghosts = const [],
    this.bars = const [],
    this.onTapPieces,
    this.onTapGhost,
    this.onAnimationDone,
  });

  /// Progress of every seated colour's pieces.
  final Map<PlayerColor, List<int>> pieces;
  final int turns;
  final BoardPalette palette;
  final Set<PieceRef> selectable;
  final Set<PieceRef> selected;
  final List<GhostMark> ghosts;
  final List<BlockBar> bars;

  /// Called with every piece at the tapped spot.
  final ValueChanged<List<PieceRef>>? onTapPieces;

  /// Called with the [GhostMark.id] of the tapped ghost.
  final ValueChanged<int>? onTapGhost;
  final VoidCallback? onAnimationDone;

  @override
  State<BoardScene> createState() => BoardSceneState();
}

class BoardSceneState extends State<BoardScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _plan = MotionPlan.empty);
        widget.onAnimationDone?.call();
      }
    });
  MotionPlan _plan = MotionPlan.empty;

  bool get animating => !_plan.isEmpty;

  @override
  void didUpdateWidget(BoardScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePieces(oldWidget.pieces, widget.pieces)) {
      _plan = planMotion(oldWidget.pieces, widget.pieces);
      if (_plan.isEmpty) {
        _controller.value = 0;
      } else {
        _controller.duration = _plan.duration;
        _controller.forward(from: 0);
      }
    }
  }

  static bool _samePieces(
    Map<PlayerColor, List<int>> a,
    Map<PlayerColor, List<int>> b,
  ) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (!listEquals(e.value, b[e.key])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap(TapUpDetails details, double side) {
    final cell = side / BoardGeometry.gridSize;
    final view = details.localPosition / cell;
    final point = BoardGeometry.rotatePoint(view, 4 - widget.turns % 4);

    if (widget.onTapGhost != null) {
      final ghost = _nearest(widget.ghosts, (g) => g.point, point, 0.6);
      if (ghost != null) {
        widget.onTapGhost!(ghost.id);
        return;
      }
    }
    if (widget.onTapPieces != null) {
      final stacks = layoutPieces(widget.pieces);
      final stack = _nearest(stacks, (s) => s.point, point, 0.7);
      if (stack != null) widget.onTapPieces!(stack.pieces);
    }
  }

  static T? _nearest<T>(
    List<T> items,
    Offset Function(T) pointOf,
    Offset p,
    double within,
  ) {
    T? best;
    var bestDistance = within;
    for (final item in items) {
      final d = (pointOf(item) - p).distance;
      if (d <= bestDistance) {
        best = item;
        bestDistance = d;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    return BoardView(
      turns: widget.turns,
      palette: widget.palette,
      overlay: LayoutBuilder(
        builder: (context, constraints) {
          final side = constraints.biggest.shortestSide;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: animating ? null : (d) => _handleTap(d, side),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final moving = animating;
                return CustomPaint(
                  size: Size.square(side),
                  painter: PiecesPainter(
                    stacks: layoutPieces(
                      widget.pieces,
                      overrides: moving
                          ? _plan.pointsAt(_controller.value)
                          : const {},
                    ),
                    turns: widget.turns,
                    palette: widget.palette,
                    selectable: moving ? const {} : widget.selectable,
                    selected: moving ? const {} : widget.selected,
                    ghosts: moving ? const [] : widget.ghosts,
                    bars: moving ? const [] : widget.bars,
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

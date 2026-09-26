import 'package:flutter/material.dart';

import '../game/dice.dart';

/// Draws one die with pips. Used dice are greyed out.
class DieView extends StatelessWidget {
  const DieView({super.key, required this.face, this.size = 56});

  final DieFace face;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Die ${face.value}${face.used ? ', used' : ''}',
      child: CustomPaint(
        size: Size.square(size),
        painter: _DiePainter(face.value, face.used),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  const _DiePainter(this.value, this.used);

  final int value;
  final bool used;

  // Pip positions on a 3 by 3 grid, per face value.
  static const _pips = <int, List<(int, int)>>{
    1: [(1, 1)],
    2: [(0, 0), (2, 2)],
    3: [(0, 0), (1, 1), (2, 2)],
    4: [(0, 0), (0, 2), (2, 0), (2, 2)],
    5: [(0, 0), (0, 2), (1, 1), (2, 0), (2, 2)],
    6: [(0, 0), (0, 2), (1, 0), (1, 2), (2, 0), (2, 2)],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & Size.square(s),
      Radius.circular(s * 0.18),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = used ? const Color(0xFFE0E0E0) : const Color(0xFFFFFFFF),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04
        ..color = const Color(0xFF424242),
    );
    final pip = Paint()
      ..color = used ? const Color(0xFF9E9E9E) : const Color(0xFF212121);
    for (final (r, c) in _pips[value] ?? const <(int, int)>[]) {
      canvas.drawCircle(
        Offset(s * (0.25 + c * 0.25), s * (0.25 + r * 0.25)),
        s * 0.085,
        pip,
      );
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) => old.value != value || old.used != used;
}

/// The bottom tray: undo, the two dice, and the roll or pass button.
/// Everything a turn needs sits here, in thumb reach (README section 7).
class DiceTray extends StatelessWidget {
  const DiceTray({
    super.key,
    required this.dice,
    required this.rollKey,
    this.canRoll = false,
    this.canUndo = false,
    this.canPass = false,
    this.message,
    this.onRoll,
    this.onUndo,
    this.onPass,
  });

  final List<DieFace> dice;

  /// Changes on every roll, to replay the tumble.
  final int rollKey;
  final bool canRoll;
  final bool canUndo;
  final bool canPass;
  final String? message;
  final VoidCallback? onRoll;
  final VoidCallback? onUndo;
  final VoidCallback? onPass;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 22,
            child: message == null
                ? null
                : Text(message!, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Row(
            children: [
              IconButton.filledTonal(
                key: const Key('undo'),
                tooltip: 'Undo',
                onPressed: canUndo ? onUndo : null,
                icon: const Icon(Icons.undo),
              ),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(rollKey),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 350),
                  builder: (context, t, child) =>
                      Transform.rotate(angle: (1 - t) * 3.1416, child: child),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (final d in dice)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: DieView(face: d),
                        ),
                      if (dice.isEmpty) const SizedBox(height: 56),
                    ],
                  ),
                ),
              ),
              if (canPass)
                FilledButton.tonal(
                  key: const Key('pass'),
                  onPressed: onPass,
                  child: const Text('Pass'),
                )
              else
                FilledButton(
                  key: const Key('roll'),
                  onPressed: canRoll ? onRoll : null,
                  child: const Text('Roll'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

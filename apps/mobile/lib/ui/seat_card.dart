import 'package:flutter/material.dart';

import '../board/board_palette.dart';
import '../game/table_view.dart';

/// A player's card with a ring that counts down their time.
class SeatCard extends StatelessWidget {
  const SeatCard({
    super.key,
    required this.seat,
    required this.active,
    this.finishedPlace,
    this.deadline,
    this.serverOffset = Duration.zero,
    this.palette = BoardPalette.standard,
  });

  final SeatView seat;
  final bool active;
  final int? finishedPlace;

  /// Server epoch milliseconds; only shown while [active].
  final int? deadline;
  final Duration serverOffset;
  final BoardPalette palette;

  static const turnLength = Duration(seconds: 20);

  @override
  Widget build(BuildContext context) {
    final color = palette.player(seat.color.index);
    Widget avatar = CircleAvatar(
      radius: 16,
      backgroundColor: color,
      child: Icon(
        seat.isBot ? Icons.smart_toy : Icons.person,
        size: 18,
        color: Colors.white,
      ),
    );
    final deadline = this.deadline;
    if (active && deadline != null) {
      final now = DateTime.now().add(serverOffset).millisecondsSinceEpoch;
      final left = (deadline - now).clamp(0, turnLength.inMilliseconds);
      avatar = Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(deadline),
            tween: Tween(begin: left / turnLength.inMilliseconds, end: 0),
            duration: Duration(milliseconds: left),
            builder: (context, v, _) => SizedBox.square(
              dimension: 40,
              child: CircularProgressIndicator(
                value: v,
                strokeWidth: 3,
                color: color,
              ),
            ),
          ),
          avatar,
        ],
      );
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.18) : null,
        border: Border.all(
          color: active ? color : Colors.transparent,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(dimension: 40, child: Center(child: avatar)),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  seat.isYou ? '${seat.name} (you)' : seat.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (finishedPlace != null)
                  Text('Place $finishedPlace')
                else if (!seat.connected)
                  const Text('Reconnecting...'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

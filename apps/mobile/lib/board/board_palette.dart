import 'package:flutter/painting.dart';

/// Colours for the standard board. Kept in one place so themes (bark cloth,
/// kitenge) can swap them later.
class BoardPalette {
  const BoardPalette({
    this.players = const [
      Color(0xFFD32F2F), // red
      Color(0xFF2E7D32), // green
      Color(0xFFF9A825), // yellow
      Color(0xFF1565C0), // blue
    ],
    this.track = const Color(0xFFFFFFFF),
    this.gridLine = const Color(0xFF37474F),
    this.background = const Color(0xFFFAFAFA),
    this.yardInner = const Color(0xFFFFFFFF),
    this.highlight = const Color(0xFFFFD600),
  });

  /// Indexed by colour index: red, green, yellow, blue.
  final List<Color> players;
  final Color track;
  final Color gridLine;
  final Color background;
  final Color yardInner;
  final Color highlight;

  Color player(int colorIndex) => players[colorIndex];

  /// A lighter tint for home columns and yard slots.
  Color tint(int colorIndex) =>
      Color.lerp(players[colorIndex], const Color(0xFFFFFFFF), 0.55)!;

  static const standard = BoardPalette();
}

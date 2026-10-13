import 'package:flutter/material.dart';

/// The 16 preset avatars (D35), by number. Each is an icon and a colour; at
/// the board the icon is drawn on the player's piece colour instead.
const List<(IconData, Color)> avatarPresets = [
  (Icons.pets, Color(0xFF8D6E63)),
  (Icons.sports_soccer, Color(0xFF43A047)),
  (Icons.local_florist, Color(0xFFD81B60)),
  (Icons.music_note, Color(0xFF8E24AA)),
  (Icons.star, Color(0xFFFFA000)),
  (Icons.bolt, Color(0xFFF4511E)),
  (Icons.rocket_launch, Color(0xFF3949AB)),
  (Icons.wb_sunny, Color(0xFFFDD835)),
  (Icons.water_drop, Color(0xFF039BE5)),
  (Icons.park, Color(0xFF2E7D32)),
  (Icons.emoji_events, Color(0xFFC0CA33)),
  (Icons.favorite, Color(0xFFE53935)),
  (Icons.sports_basketball, Color(0xFFEF6C00)),
  (Icons.coffee, Color(0xFF6D4C41)),
  (Icons.face, Color(0xFF00897B)),
  (Icons.diamond, Color(0xFF5E35B1)),
];

IconData avatarIcon(int avatar) =>
    avatarPresets[avatar.clamp(0, avatarPresets.length - 1)].$1;

/// A round avatar: the preset's icon on its own colour, or on [background].
class ArenaAvatar extends StatelessWidget {
  const ArenaAvatar({
    super.key,
    required this.avatar,
    this.isBot = false,
    this.radius = 20,
    this.background,
  });

  final int avatar;
  final bool isBot;
  final double radius;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final preset = avatarPresets[avatar.clamp(0, avatarPresets.length - 1)];
    return CircleAvatar(
      radius: radius,
      backgroundColor: background ?? (isBot ? Colors.blueGrey : preset.$2),
      child: Icon(
        isBot ? Icons.smart_toy : preset.$1,
        size: radius * 1.1,
        color: Colors.white,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_palette.dart';
import '../game/bots.dart';
import '../game/local_game.dart';

/// Picks the mode and who plays each colour, then starts pass and play.
class LocalSetupScreen extends StatefulWidget {
  const LocalSetupScreen({super.key, required this.onStart});

  final ValueChanged<LocalGameConfig> onStart;

  @override
  State<LocalSetupScreen> createState() => _LocalSetupScreenState();
}

class _LocalSetupScreenState extends State<LocalSetupScreen> {
  GameMode _mode = GameMode.oneVsOne;

  /// Null means the seat is empty (free for all only).
  final Map<PlayerColor, SeatKind?> _seats = {
    PlayerColor.red: SeatKind.human,
    PlayerColor.green: SeatKind.normalBot,
    PlayerColor.yellow: SeatKind.normalBot,
    PlayerColor.blue: SeatKind.normalBot,
  };

  static const _oneVsOne = [PlayerColor.red, PlayerColor.yellow];

  List<PlayerColor> get _colors =>
      _mode == GameMode.oneVsOne ? _oneVsOne : PlayerColor.values;

  LocalGameConfig? get _config {
    final seats = <PlayerColor, SeatKind>{
      for (final c in _colors)
        if (_seats[c] case final kind?) c: kind,
    };
    if (seats.length < 2) return null;
    if (_mode == GameMode.teams && seats.length != 4) return null;
    return LocalGameConfig(mode: _mode, seats: seats);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('Pass and play')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<GameMode>(
            segments: const [
              ButtonSegment(value: GameMode.oneVsOne, label: Text('1v1')),
              ButtonSegment(value: GameMode.freeForAll, label: Text('All')),
              ButtonSegment(value: GameMode.teams, label: Text('2v2')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.single;
              if (_mode != GameMode.freeForAll) {
                for (final c in _colors) {
                  _seats[c] ??= SeatKind.normalBot;
                }
              }
            }),
          ),
          const SizedBox(height: 16),
          for (final c in _colors) _seatRow(c),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('start'),
            onPressed: config == null ? null : () => widget.onStart(config),
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  Widget _seatRow(PlayerColor c) {
    final kinds = <SeatKind?>[
      ...SeatKind.values,
      if (_mode == GameMode.freeForAll) null,
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: BoardPalette.standard.player(c.index),
      ),
      title: Text(colorName(c)),
      trailing: DropdownButton<SeatKind?>(
        key: Key('seat-${c.name}'),
        value: _seats[c],
        items: [
          for (final k in kinds)
            DropdownMenuItem(value: k, child: Text(_label(k))),
        ],
        onChanged: (k) => setState(() => _seats[c] = k),
      ),
    );
  }

  static String _label(SeatKind? k) => switch (k) {
    SeatKind.human => 'Player',
    SeatKind.easyBot => 'Easy bot',
    SeatKind.normalBot => 'Normal bot',
    null => 'Empty',
  };
}

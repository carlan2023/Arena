import 'package:ludo_engine/ludo_engine.dart';

import '../board/pieces_painter.dart';
import 'board_marks.dart';
import 'dice.dart';
import 'move_planner.dart';
import 'move_selection.dart';

/// A player's card at the board corner.
class SeatView {
  const SeatView({
    required this.color,
    required this.name,
    this.isBot = false,
    this.connected = true,
    this.isYou = false,
  });

  final PlayerColor color;
  final String name;
  final bool isBot;
  final bool connected;
  final bool isYou;
}

/// Everything the game table draws. Built by the local and online
/// controllers; the widgets only read it.
class TableView {
  const TableView({
    required this.state,
    required this.seats,
    this.turns = 0,
    this.selectable = const {},
    this.selected = const {},
    this.options = const [],
    this.bars = const [],
    this.canRoll = false,
    this.canUndo = false,
    this.pass,
    this.deadline,
    this.serverOffset = Duration.zero,
    this.message,
  });

  /// Builds the view for a state, with an optional selection in progress.
  factory TableView.of(
    GameState state, {
    required List<SeatView> seats,
    MoveSelection? selection,
    int turns = 0,
    bool canRoll = false,
    int? deadline,
    Duration serverOffset = Duration.zero,
    String? message,
  }) {
    final shown = selection?.state ?? state;
    final legal = selection == null
        ? const <Move>[]
        : selection.planner.legalSteps;
    return TableView(
      state: shown,
      seats: seats,
      turns: turns,
      selectable: selection?.selectable ?? const {},
      selected: {...?selection?.selected},
      options: selection?.options ?? const [],
      bars: blockBars(shown, legal: legal),
      canRoll: canRoll,
      canUndo: selection?.canUndo ?? false,
      pass: selection?.pass,
      deadline: deadline,
      serverOffset: serverOffset,
      message: message,
    );
  }

  final GameState state;
  final List<SeatView> seats;
  final int turns;
  final Set<PieceRef> selectable;
  final Set<PieceRef> selected;
  final List<MoveOption> options;
  final List<BlockBar> bars;
  final bool canRoll;
  final bool canUndo;
  final MoveOption? pass;

  /// Epoch milliseconds (server clock) when the current decision times out.
  final int? deadline;

  /// Server clock minus phone clock, for the countdown ring.
  final Duration serverOffset;

  /// A short line for the tray, such as "No move possible".
  final String? message;

  List<DieFace> get dice => diceFaces(state);
  List<GhostMark> get ghosts => ghostMarks(options);

  SeatView? seatOf(PlayerColor color) {
    for (final s in seats) {
      if (s.color == color) return s;
    }
    return null;
  }
}

/// What the table can ask its controller to do.
abstract interface class TableActions {
  void roll();
  void tapPieces(List<PieceRef> pieces);
  void chooseOption(MoveOption option);
  void undo();
}

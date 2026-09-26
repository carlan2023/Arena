import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_scene.dart';
import '../game/table_view.dart';
import 'dice_tray.dart';
import 'seat_card.dart';

/// The game screen body: seat cards at the board corners, the board, and
/// the dice tray at the bottom. Shared by pass and play and online games.
class GameTable extends StatelessWidget {
  const GameTable({
    super.key,
    required this.view,
    required this.actions,
    this.footer,
  });

  final TableView view;
  final TableActions actions;

  /// Shown under the tray, for quick chat.
  final Widget? footer;

  /// Corner a colour's yard ends up in: 0 top left, 1 top right,
  /// 2 bottom right, 3 bottom left.
  int cornerOf(PlayerColor color) => (color.index + view.turns) % 4;

  Widget _card(int corner) {
    for (final seat in view.seats) {
      if (cornerOf(seat.color) != corner) continue;
      final state = view.state;
      final place = state.finishOrder.indexOf(seat.color);
      return SeatCard(
        key: ValueKey('seat-${seat.color.name}'),
        seat: seat,
        active:
            state.current == seat.color && state.phase != TurnPhase.gameOver,
        finishedPlace: place < 0 ? null : place + 1,
        deadline: view.deadline,
        serverOffset: view.serverOffset,
      );
    }
    return const SizedBox.shrink();
  }

  static const double cardRowHeight = 56;

  Widget _cardRow(int left, int right) => SizedBox(
    height: cardRowHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: _card(left)),
          Flexible(child: _card(right)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = view.state;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // The board fills the width, shrinking only on short screens.
              final side = (box.maxHeight - 2 * cardRowHeight).clamp(
                0.0,
                box.maxWidth,
              );
              return Column(
                children: [
                  _cardRow(0, 1),
                  SizedBox.square(
                    dimension: side,
                    child: BoardScene(
                      pieces: state.pieces,
                      turns: view.turns,
                      selectable: view.selectable,
                      selected: view.selected,
                      ghosts: view.ghosts,
                      bars: view.bars,
                      onTapPieces: actions.tapPieces,
                      onTapGhost: (id) =>
                          actions.chooseOption(view.options[id]),
                    ),
                  ),
                  _cardRow(3, 2),
                ],
              );
            },
          ),
        ),
        DiceTray(
          dice: view.dice,
          rollKey: state.rollNumber,
          canRoll: view.canRoll,
          canUndo: view.canUndo,
          canPass: view.pass != null,
          message: view.message,
          onRoll: actions.roll,
          onUndo: actions.undo,
          onPass: () => actions.chooseOption(view.pass!),
        ),
        ?footer,
      ],
    );
  }
}

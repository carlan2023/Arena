import 'dart:ui';

import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_geometry.dart';
import '../board/piece_layout.dart';
import '../board/pieces_painter.dart';
import 'move_planner.dart';

/// Block bars for [state]. A bar cracks when the player to move holds block
/// rights for it and one of [legal] lands on or passes its square, which is
/// how the board teaches the double 6 rule.
List<BlockBar> blockBars(GameState state, {List<Move> legal = const []}) {
  final bars = <BlockBar>[];
  for (final block in blocks(state)) {
    final owners = {for (final p in block.pieces) p.color};
    final color = block.pieces.first.color;
    var cracked = false;
    for (final m in legal) {
      if (owners.contains(m.color) || m.kind == MoveKind.pass) continue;
      if (!hasBlockRights(state, m.color, block.pieces.length)) continue;
      if (_reaches(state, m, block.square)) {
        cracked = true;
        break;
      }
    }
    bars.add(
      BlockBar(block.square, color, block.pieces.length, cracked: cracked),
    );
  }
  return bars;
}

bool _reaches(GameState state, Move m, int square) {
  final piece = PieceRef(m.color, m.pieces.first);
  final from = state.progressOf(piece);
  final to = applyMove(state, m).state.progressOf(piece);
  for (var p = from < 0 ? 0 : from + 1; p <= to; p++) {
    if (p > kLastTrackProgress) break;
    if (BoardGeometry.absoluteSquare(m.color.index, p) == square) return true;
  }
  return false;
}

/// Ghost landing spots for [options]; each ghost's id is its index.
List<GhostMark> ghostMarks(List<MoveOption> options) {
  return [
    for (var i = 0; i < options.length; i++)
      if (options[i].piece case final piece?)
        GhostMark(
          _ghostPoint(options[i], piece),
          optionLabel(options[i]),
          piece.color,
          id: i,
        ),
  ];
}

Offset _ghostPoint(MoveOption option, PieceRef piece) {
  final p = piecePoint(piece, option.target);
  // A block spot can share a square with a single die spot on a double.
  return option.kind == OptionKind.block ? p.translate(0.18, -0.18) : p;
}

/// Short label for an option: "3", "5+3" for a combined move, "B4" for a
/// block, "Pass".
String optionLabel(MoveOption option) => switch (option.kind) {
  OptionKind.single => '${option.moves.single.die}',
  OptionKind.both => option.dice.join('+'),
  OptionKind.block => 'B${option.moves.single.die}',
  OptionKind.pass => 'Pass',
};

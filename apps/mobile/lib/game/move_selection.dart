import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_geometry.dart';
import 'move_planner.dart';

/// Move selection during one roll (README section 7): which pieces light
/// up, which one is picked, and its landing spots.
class MoveSelection {
  MoveSelection(GameState rolled) : planner = MovePlanner(rolled) {
    _autoSelect();
  }

  final MovePlanner planner;
  List<PieceRef> _selected = const [];
  List<MoveOption> _options = const [];

  GameState get state => planner.current;
  List<PieceRef> get selected => _selected;
  List<MoveOption> get options => _options;
  bool get rollEnded => planner.rollEnded;
  bool get canUndo => planner.canUndo;
  List<Move> get steps => planner.steps;
  MoveOption? get pass => planner.passOption;
  List<Move>? get forcedRest => planner.forcedRest;

  Set<PieceRef> get selectable => rollEnded ? const {} : planner.movablePieces;

  /// Picks the movable pieces among [pieces] (everything at one tapped
  /// spot). Tapping pieces that cannot move clears the selection. Returns
  /// true when something is selected.
  bool select(List<PieceRef> pieces) {
    final movable = selectable;
    final picked = [
      for (final p in pieces)
        if (movable.contains(p)) p,
    ];
    if (picked.isEmpty) {
      clear();
      return false;
    }
    _selected = picked;
    // Pieces on one spot have the same options; keep the first per target.
    final seen = <(OptionKind, int)>{};
    _options = [
      for (final p in picked)
        for (final o in planner.optionsFor(p))
          if (seen.add((o.kind, o.target))) o,
    ];
    return true;
  }

  void clear() {
    _selected = const [];
    _options = const [];
  }

  /// Plays [option] and clears the selection.
  void choose(MoveOption option) {
    planner.play(option.moves);
    clear();
    _autoSelect();
  }

  /// Plays the rest of the roll in one go (auto play, timeouts).
  void playRest(List<Move> moves) {
    planner.play(moves);
    clear();
  }

  bool undo() {
    final undone = planner.undo();
    if (undone) {
      clear();
      _autoSelect();
    }
    return undone;
  }

  /// When every movable piece stands on one spot, select it straight away
  /// so its landing spots show without an extra tap.
  void _autoSelect() {
    final movable = selectable;
    if (movable.isEmpty) return;
    final spots = {for (final p in movable) _spot(p)};
    if (spots.length == 1) select(movable.toList());
  }

  Object _spot(PieceRef p) {
    final progress = state.progressOf(p);
    return BoardGeometry.cellFor(p.color.index, progress) ?? (p, progress);
  }
}

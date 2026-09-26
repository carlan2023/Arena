import 'package:ludo_engine/ludo_engine.dart';

/// How a destination option spends the dice.
enum OptionKind { single, both, block, pass }

/// A place the player can send a piece (or block) to, and the engine steps
/// that get it there.
class MoveOption {
  const MoveOption({
    required this.kind,
    required this.moves,
    required this.piece,
    required this.target,
  });

  final OptionKind kind;

  /// The engine steps to play; one for every kind.
  final List<Move> moves;

  /// The piece the option was offered for (the first piece of a block).
  /// Null for pass.
  final PieceRef? piece;

  /// Progress of [piece] after the option is played.
  final int target;

  /// The dice this option uses, for labels.
  List<int> get dice => [
    for (final m in moves)
      ...switch (m.kind) {
        MoveKind.blockAdvance => [m.die, m.die],
        MoveKind.combined => [m.die, m.die2],
        _ => [m.die],
      },
  ];

  @override
  String toString() => 'MoveOption($kind, $moves -> $target)';
}

/// The steps a player has taken so far in one roll, with undo.
///
/// Every question is answered by the engine on the current in-between
/// state, so no rule lives here. Built when a roll leaves the player with a
/// decision (phase awaitingMove).
class MovePlanner {
  MovePlanner(GameState start)
    : assert(start.phase == TurnPhase.awaitingMove),
      _states = [start];

  final List<GameState> _states;
  final List<MoveResult> _results = [];

  GameState get start => _states.first;
  GameState get current => _states.last;

  /// Steps played so far, in order. This is what goes in the move message.
  List<Move> get steps => [for (final r in _results) r.move];
  List<MoveResult> get results => List.unmodifiable(_results);

  /// True once no dice are left or no step is possible.
  bool get rollEnded => _results.isNotEmpty && _results.last.rollEnded;

  bool get canUndo => _results.isNotEmpty && !rollEnded;

  List<Move> get legalSteps => rollEnded ? const [] : legalMoves(current);

  List<List<Move>> get sequences =>
      rollEnded ? const [] : legalSequences(current);

  /// The rest of the roll when only one way remains, else null.
  List<Move>? get forcedRest {
    final seqs = sequences;
    if (seqs.length != 1 || seqs.single.isEmpty) return null;
    return seqs.single;
  }

  /// Pieces that a legal next step moves.
  Set<PieceRef> get movablePieces => {
    for (final m in legalSteps)
      for (final i in m.pieces) PieceRef(m.color, i),
  };

  /// Every option for [piece]: each die alone, both dice together as one
  /// combined move (D34: it passes single pieces without capturing), and a
  /// block move when [piece] is in a block that may move. Each option is
  /// one engine step.
  List<MoveOption> optionsFor(PieceRef piece) {
    final state = current;
    final options = <MoveOption>[];
    final seen = <(OptionKind, int)>{};

    for (final m in legalSteps) {
      if (m.color != piece.color || !m.pieces.contains(piece.index)) continue;
      final after = applyMove(state, m).state;
      final target = after.progressOf(piece);
      final kind = switch (m.kind) {
        MoveKind.blockAdvance => OptionKind.block,
        MoveKind.combined => OptionKind.both,
        MoveKind.release || MoveKind.advance => OptionKind.single,
        MoveKind.pass => OptionKind.pass,
      };
      if (seen.add((kind, target))) {
        options.add(
          MoveOption(kind: kind, moves: [m], piece: piece, target: target),
        );
      }
    }

    return options;
  }

  /// The pass option (only under R2 off), or null.
  MoveOption? get passOption {
    for (final m in legalSteps) {
      if (m.kind == MoveKind.pass) {
        return MoveOption(
          kind: OptionKind.pass,
          moves: [m],
          piece: null,
          target: 0,
        );
      }
    }
    return null;
  }

  /// Plays [moves] in order. Throws [IllegalMoveException] if any step is
  /// not legal at that point, and then nothing is played.
  void play(List<Move> moves) {
    var state = current;
    var ended = rollEnded;
    final results = <MoveResult>[];
    for (final m in moves) {
      if (ended) throw const IllegalMoveException('the roll has ended');
      final result = applyMove(state, m);
      results.add(result);
      state = result.state;
      ended = result.rollEnded;
    }
    _results.addAll(results);
    _states.addAll(results.map((r) => r.state));
  }

  /// Takes back the last step. Returns false when there is nothing to undo.
  bool undo() {
    if (!canUndo) return false;
    _results.removeLast();
    _states.removeLast();
    return true;
  }

  /// Takes back every step of this roll.
  void undoAll() {
    while (undo()) {}
  }
}

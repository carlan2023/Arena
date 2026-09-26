import 'board.dart';
import 'game_state.dart';
import 'util.dart';

enum MoveKind { release, advance, blockAdvance, pass }

/// One step of a roll. A combined move is two [MoveKind.advance] steps.
class Move {
  Move._(this.kind, this.color, List<int> pieces, this.die)
    : pieces = List.unmodifiable(pieces);

  /// Places a piece from home on its start square using a 6.
  Move.release(PlayerColor color, int piece)
    : this._(MoveKind.release, color, [piece], 6);

  /// Moves one piece by one die value.
  Move.advance(PlayerColor color, int piece, int die)
    : this._(MoveKind.advance, color, [piece], die);

  /// Moves every piece of a block together on a double. [die] is the face
  /// value. Piece indices are stored sorted, so order does not matter.
  Move.blockAdvance(PlayerColor color, List<int> pieces, int die)
    : this._(MoveKind.blockAdvance, color, [...pieces]..sort(), die);

  /// Gives up the rest of the roll (only offered when R2 is off).
  Move.pass(PlayerColor color) : this._(MoveKind.pass, color, const [], 0);

  final MoveKind kind;

  /// Owner of the moved pieces. Differs from state.current only when a
  /// finished 2v2 player rolls for the partner (R8).
  final PlayerColor color;

  /// Piece indices: one for release and advance, the whole block for
  /// blockAdvance, none for pass.
  final List<int> pieces;

  /// Die value used: 6 for release, the face value for blockAdvance, 0 for pass.
  final int die;

  Map<String, Object?> toJson() => {
    'k': kind.name,
    'c': color.name,
    'p': List<int>.of(pieces),
    'd': die,
  };

  /// Parses and shape checks a move. Malformed input throws [FormatException].
  factory Move.fromJson(Map<String, Object?> json) => parseJson('Move', () {
    final kind = enumByName(MoveKind.values, json['k']);
    final color = enumByName(PlayerColor.values, json['c']);
    final pieces = intList(json['p']);
    final die = json['d'] as int;
    if (pieces.any((p) => p < 0 || p >= kPiecesPerPlayer)) {
      throw const FormatException('Move piece index out of range');
    }
    switch (kind) {
      case MoveKind.release:
        if (pieces.length != 1 || die != 6) break;
        return Move.release(color, pieces.single);
      case MoveKind.advance:
        if (pieces.length != 1 || die < 1 || die > 6) break;
        return Move.advance(color, pieces.single, die);
      case MoveKind.blockAdvance:
        if (pieces.length < 2 || die < 1 || die > 6) break;
        if (pieces.toSet().length != pieces.length) break;
        return Move.blockAdvance(color, pieces, die);
      case MoveKind.pass:
        if (pieces.isNotEmpty || die != 0) break;
        return Move.pass(color);
    }
    throw FormatException('Malformed ${kind.name} move');
  });

  @override
  bool operator ==(Object other) =>
      other is Move &&
      other.kind == kind &&
      other.color == color &&
      other.die == die &&
      listEquals(other.pieces, pieces);

  @override
  int get hashCode => Object.hash(kind, color, die, Object.hashAll(pieces));

  @override
  String toString() => switch (kind) {
    MoveKind.pass => 'pass(${color.name})',
    _ => '${kind.name}(${color.name} $pieces by $die)',
  };
}

/// The outcome of one [Move].
class MoveResult {
  MoveResult({
    required this.state,
    required this.move,
    List<PieceRef> captured = const [],
    List<PlayerColor> newlyFinished = const [],
    required this.rollEnded,
    required this.extraRoll,
  }) : captured = List.unmodifiable(captured),
       newlyFinished = List.unmodifiable(newlyFinished);

  final GameState state;
  final Move move;

  /// Pieces sent home by this step.
  final List<PieceRef> captured;
  final List<PlayerColor> newlyFinished;

  /// No dice left or no legal step left.
  final bool rollEnded;

  /// The roll ended and the same player rolls again (double 6).
  final bool extraRoll;

  Map<String, Object?> toJson() => {
    'state': state.toJson(),
    'move': move.toJson(),
    'captured': [for (final p in captured) p.toJson()],
    'newlyFinished': [for (final c in newlyFinished) c.name],
    'rollEnded': rollEnded,
    'extraRoll': extraRoll,
  };

  factory MoveResult.fromJson(Map<String, Object?> json) =>
      parseJson('MoveResult', () {
        return MoveResult(
          state: GameState.fromJson(
            (json['state'] as Map).cast<String, Object?>(),
          ),
          move: Move.fromJson((json['move'] as Map).cast<String, Object?>()),
          captured: [
            for (final p in json['captured'] as List)
              PieceRef.fromJson((p as Map).cast<String, Object?>()),
          ],
          newlyFinished: [
            for (final c in json['newlyFinished'] as List)
              enumByName(PlayerColor.values, c),
          ],
          rollEnded: json['rollEnded'] as bool,
          extraRoll: json['extraRoll'] as bool,
        );
      });

  @override
  bool operator ==(Object other) =>
      other is MoveResult &&
      other.state == state &&
      other.move == move &&
      listEquals(other.captured, captured) &&
      listEquals(other.newlyFinished, newlyFinished) &&
      other.rollEnded == rollEnded &&
      other.extraRoll == extraRoll;

  @override
  int get hashCode => Object.hash(
    state,
    move,
    Object.hashAll(captured),
    Object.hashAll(newlyFinished),
    rollEnded,
    extraRoll,
  );
}

class IllegalMoveException implements Exception {
  const IllegalMoveException(this.reason);

  final String reason;

  @override
  String toString() => 'IllegalMoveException: $reason';
}

import 'board.dart';
import 'rules_config.dart';
import 'util.dart';

enum GameMode { oneVsOne, freeForAll, teams }

enum TurnPhase { awaitingRoll, awaitingMove, gameOver }

/// One piece: its owner colour and its index 0..3.
class PieceRef {
  const PieceRef(this.color, this.index);

  final PlayerColor color;
  final int index;

  Map<String, Object?> toJson() => {'c': color.name, 'i': index};

  factory PieceRef.fromJson(Map<String, Object?> json) =>
      parseJson('PieceRef', () {
        final index = json['i'] as int;
        if (index < 0 || index >= kPiecesPerPlayer) {
          throw FormatException('Piece index $index out of range');
        }
        return PieceRef(enumByName(PlayerColor.values, json['c']), index);
      });

  @override
  bool operator ==(Object other) =>
      other is PieceRef && other.color == color && other.index == index;

  @override
  int get hashCode => Object.hash(color, index);

  @override
  String toString() => '${color.name}#$index';
}

/// Two or more pieces that wall a track square. [square] is absolute, 0..51.
class Block {
  Block(this.square, List<PieceRef> pieces)
    : pieces = List.unmodifiable(pieces);

  final int square;
  final List<PieceRef> pieces;

  Map<String, Object?> toJson() => {
    'square': square,
    'pieces': [for (final p in pieces) p.toJson()],
  };

  factory Block.fromJson(Map<String, Object?> json) => parseJson(
    'Block',
    () => Block(json['square'] as int, [
      for (final p in json['pieces'] as List)
        PieceRef.fromJson((p as Map).cast<String, Object?>()),
    ]),
  );

  @override
  bool operator ==(Object other) =>
      other is Block &&
      other.square == square &&
      listEquals(other.pieces, pieces);

  @override
  int get hashCode => Object.hash(square, Object.hashAll(pieces));

  @override
  String toString() => 'Block($square, $pieces)';
}

/// The whole game. Immutable; every engine function returns a new state.
class GameState {
  GameState._({
    required this.rules,
    required this.mode,
    required List<PlayerColor> players,
    required Map<PlayerColor, List<int>> pieces,
    required this.current,
    required this.phase,
    required List<int> lastRoll,
    required List<int> remainingDice,
    required this.doubleSixStreak,
    required this.sixesThisTurn,
    required this.sixesBeforeRoll,
    required List<PieceRef> joinedOwnBlockThisRoll,
    required List<PieceRef> stoppedThisRoll,
    required List<PlayerColor> finishOrder,
    required List<PlayerColor> forfeited,
    required this.turnNumber,
    required this.rollNumber,
  }) : players = List.unmodifiable(players),
       pieces = Map.unmodifiable({
         for (final c in players) c: List<int>.unmodifiable(pieces[c]!),
       }),
       lastRoll = List.unmodifiable(lastRoll),
       remainingDice = List.unmodifiable(remainingDice),
       joinedOwnBlockThisRoll = List.unmodifiable(joinedOwnBlockThisRoll),
       stoppedThisRoll = List.unmodifiable(stoppedThisRoll),
       finishOrder = List.unmodifiable(finishOrder),
       forfeited = List.unmodifiable(forfeited);

  /// A fresh game: all pieces at home, [firstPlayer] (default the first
  /// seat) to roll. Throws [ArgumentError] for an invalid seating.
  factory GameState.newGame({
    required GameMode mode,
    required List<PlayerColor> players,
    RulesConfig rules = const RulesConfig(),
    PlayerColor? firstPlayer,
  }) {
    _checkSeating(mode, players);
    final first = firstPlayer ?? players.first;
    if (!players.contains(first)) {
      throw ArgumentError.value(firstPlayer, 'firstPlayer', 'is not seated');
    }
    return GameState.custom(
      mode: mode,
      players: players,
      rules: rules,
      current: first,
    );
  }

  /// Test only: builds any position without seating checks. Pieces default
  /// to all at home for each seated colour. Not for production code.
  factory GameState.custom({
    required GameMode mode,
    required List<PlayerColor> players,
    RulesConfig rules = const RulesConfig(),
    Map<PlayerColor, List<int>>? pieces,
    PlayerColor? current,
    TurnPhase phase = TurnPhase.awaitingRoll,
    List<int> lastRoll = const [],
    List<int> remainingDice = const [],
    int doubleSixStreak = 0,
    int sixesThisTurn = 0,
    int sixesBeforeRoll = 0,
    List<PieceRef> joinedOwnBlockThisRoll = const [],
    List<PieceRef> stoppedThisRoll = const [],
    List<PlayerColor> finishOrder = const [],
    List<PlayerColor> forfeited = const [],
    int turnNumber = 0,
    int rollNumber = 0,
  }) {
    final all = <PlayerColor, List<int>>{
      for (final c in players)
        c: pieces?[c] ?? List.filled(kPiecesPerPlayer, kAtHome),
    };
    for (final entry in all.entries) {
      if (entry.value.length != kPiecesPerPlayer ||
          entry.value.any((p) => p < kAtHome || p > kFinished)) {
        throw ArgumentError.value(entry.value, 'pieces[${entry.key.name}]');
      }
    }
    return GameState._(
      rules: rules,
      mode: mode,
      players: players,
      pieces: all,
      current: current ?? players.first,
      phase: phase,
      lastRoll: lastRoll,
      remainingDice: remainingDice,
      doubleSixStreak: doubleSixStreak,
      sixesThisTurn: sixesThisTurn,
      sixesBeforeRoll: sixesBeforeRoll,
      joinedOwnBlockThisRoll: joinedOwnBlockThisRoll,
      stoppedThisRoll: stoppedThisRoll,
      finishOrder: finishOrder,
      forfeited: forfeited,
      turnNumber: turnNumber,
      rollNumber: rollNumber,
    );
  }

  static void _checkSeating(GameMode mode, List<PlayerColor> players) {
    for (var i = 1; i < players.length; i++) {
      if (players[i].index <= players[i - 1].index) {
        throw ArgumentError.value(
          players,
          'players',
          'must be in clockwise order with no duplicates',
        );
      }
    }
    final ok = switch (mode) {
      GameMode.oneVsOne =>
        players.length == 2 && players[1].index - players[0].index == 2,
      GameMode.teams => players.length == 4,
      GameMode.freeForAll => players.length >= 2 && players.length <= 4,
    };
    if (!ok) {
      throw ArgumentError.value(players, 'players', 'invalid for $mode');
    }
  }

  final RulesConfig rules;
  final GameMode mode;

  /// Seated colours in clockwise turn order.
  final List<PlayerColor> players;

  /// Four progress values per seated colour.
  final Map<PlayerColor, List<int>> pieces;

  /// Seat whose turn it is.
  final PlayerColor current;
  final TurnPhase phase;

  /// Most recent roll [a, b]; empty before the first roll.
  final List<int> lastRoll;

  /// Unused values of the current roll; empty unless awaitingMove.
  final List<int> remainingDice;

  /// Consecutive double 6 rolls in this turn, current roll included.
  final int doubleSixStreak;

  /// Sixes rolled in this turn, current roll included.
  final int sixesThisTurn;

  /// Sixes rolled in this turn before the current roll.
  final int sixesBeforeRoll;

  /// Pieces that joined their own block during the current roll (R4).
  final List<PieceRef> joinedOwnBlockThisRoll;

  /// Pieces that captured during the current roll; they get no further step
  /// in it. Cleared when a new roll starts.
  final List<PieceRef> stoppedThisRoll;

  /// Players who finished, in order.
  final List<PlayerColor> finishOrder;

  /// Players removed by forfeit, in order.
  final List<PlayerColor> forfeited;

  /// +1 each time the turn passes to another seat.
  final int turnNumber;

  /// +1 on every roll. Read it before applyRoll to get that roll's dice nonce.
  final int rollNumber;

  /// Pieces on an absolute track square, by seat order then piece index.
  List<PieceRef> piecesOnSquare(int trackSquareIndex) =>
      trackSquareIndex < 0 || trackSquareIndex >= kTrackLength
      ? const []
      : _squares[trackSquareIndex];

  late final List<List<PieceRef>> _squares = () {
    final squares = List.generate(kTrackLength, (_) => <PieceRef>[]);
    for (final c in players) {
      for (var i = 0; i < kPiecesPerPlayer; i++) {
        final sq = trackSquare(c, pieces[c]![i]);
        if (sq != null) squares[sq].add(PieceRef(c, i));
      }
    }
    return [for (final l in squares) List<PieceRef>.unmodifiable(l)];
  }();

  /// Progress of one piece.
  int progressOf(PieceRef piece) => pieces[piece.color]![piece.index];

  GameState copyWith({
    Map<PlayerColor, List<int>>? pieces,
    PlayerColor? current,
    TurnPhase? phase,
    List<int>? lastRoll,
    List<int>? remainingDice,
    int? doubleSixStreak,
    int? sixesThisTurn,
    int? sixesBeforeRoll,
    List<PieceRef>? joinedOwnBlockThisRoll,
    List<PieceRef>? stoppedThisRoll,
    List<PlayerColor>? finishOrder,
    List<PlayerColor>? forfeited,
    int? turnNumber,
    int? rollNumber,
  }) => GameState._(
    rules: rules,
    mode: mode,
    players: players,
    pieces: pieces ?? this.pieces,
    current: current ?? this.current,
    phase: phase ?? this.phase,
    lastRoll: lastRoll ?? this.lastRoll,
    remainingDice: remainingDice ?? this.remainingDice,
    doubleSixStreak: doubleSixStreak ?? this.doubleSixStreak,
    sixesThisTurn: sixesThisTurn ?? this.sixesThisTurn,
    sixesBeforeRoll: sixesBeforeRoll ?? this.sixesBeforeRoll,
    joinedOwnBlockThisRoll:
        joinedOwnBlockThisRoll ?? this.joinedOwnBlockThisRoll,
    stoppedThisRoll: stoppedThisRoll ?? this.stoppedThisRoll,
    finishOrder: finishOrder ?? this.finishOrder,
    forfeited: forfeited ?? this.forfeited,
    turnNumber: turnNumber ?? this.turnNumber,
    rollNumber: rollNumber ?? this.rollNumber,
  );

  Map<String, Object?> toJson() => {
    'rules': rules.toJson(),
    'mode': mode.name,
    'players': [for (final c in players) c.name],
    'pieces': {for (final c in players) c.name: List<int>.of(pieces[c]!)},
    'current': current.name,
    'phase': phase.name,
    'lastRoll': List<int>.of(lastRoll),
    'remainingDice': List<int>.of(remainingDice),
    'doubleSixStreak': doubleSixStreak,
    'sixesThisTurn': sixesThisTurn,
    'sixesBeforeRoll': sixesBeforeRoll,
    'joinedOwnBlockThisRoll': [
      for (final p in joinedOwnBlockThisRoll) p.toJson(),
    ],
    'stoppedThisRoll': [for (final p in stoppedThisRoll) p.toJson()],
    'finishOrder': [for (final c in finishOrder) c.name],
    'forfeited': [for (final c in forfeited) c.name],
    'turnNumber': turnNumber,
    'rollNumber': rollNumber,
  };

  /// Parses [toJson] output. Malformed input throws [FormatException].
  factory GameState.fromJson(Map<String, Object?> json) =>
      parseJson('GameState', () {
        List<PlayerColor> colors(Object? v) => [
          for (final e in v as List) enumByName(PlayerColor.values, e),
        ];
        final players = colors(json['players']);
        final rawPieces = (json['pieces'] as Map).cast<String, Object?>();
        return GameState.custom(
          rules: RulesConfig.fromJson(
            (json['rules'] as Map).cast<String, Object?>(),
          ),
          mode: enumByName(GameMode.values, json['mode']),
          players: players,
          pieces: {for (final c in players) c: intList(rawPieces[c.name])},
          current: enumByName(PlayerColor.values, json['current']),
          phase: enumByName(TurnPhase.values, json['phase']),
          lastRoll: intList(json['lastRoll']),
          remainingDice: intList(json['remainingDice']),
          doubleSixStreak: json['doubleSixStreak'] as int,
          sixesThisTurn: json['sixesThisTurn'] as int,
          sixesBeforeRoll: json['sixesBeforeRoll'] as int,
          joinedOwnBlockThisRoll: [
            for (final p in json['joinedOwnBlockThisRoll'] as List)
              PieceRef.fromJson((p as Map).cast<String, Object?>()),
          ],
          stoppedThisRoll: [
            for (final p in (json['stoppedThisRoll'] as List?) ?? const [])
              PieceRef.fromJson((p as Map).cast<String, Object?>()),
          ],
          finishOrder: colors(json['finishOrder']),
          forfeited: colors(json['forfeited']),
          turnNumber: json['turnNumber'] as int,
          rollNumber: json['rollNumber'] as int,
        );
      });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! GameState) return false;
    if (other.rules != rules ||
        other.mode != mode ||
        other.current != current ||
        other.phase != phase ||
        other.doubleSixStreak != doubleSixStreak ||
        other.sixesThisTurn != sixesThisTurn ||
        other.sixesBeforeRoll != sixesBeforeRoll ||
        other.turnNumber != turnNumber ||
        other.rollNumber != rollNumber ||
        !listEquals(other.players, players) ||
        !listEquals(other.lastRoll, lastRoll) ||
        !listEquals(other.remainingDice, remainingDice) ||
        !listEquals(other.joinedOwnBlockThisRoll, joinedOwnBlockThisRoll) ||
        !listEquals(other.stoppedThisRoll, stoppedThisRoll) ||
        !listEquals(other.finishOrder, finishOrder) ||
        !listEquals(other.forfeited, forfeited)) {
      return false;
    }
    for (final c in players) {
      if (!listEquals(other.pieces[c]!, pieces[c]!)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    rules,
    mode,
    current,
    phase,
    doubleSixStreak,
    sixesThisTurn,
    sixesBeforeRoll,
    turnNumber,
    rollNumber,
    Object.hashAll(players),
    Object.hashAll([for (final c in players) ...pieces[c]!]),
    Object.hashAll(lastRoll),
    Object.hashAll(remainingDice),
    Object.hashAll(joinedOwnBlockThisRoll),
    Object.hashAll(stoppedThisRoll),
    Object.hashAll(finishOrder),
    Object.hashAll(forfeited),
  );

  @override
  String toString() => 'GameState(${toJson()})';
}

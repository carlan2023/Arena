import 'package:ludo_engine/ludo_engine.dart';

const red = PlayerColor.red;
const green = PlayerColor.green;
const yellow = PlayerColor.yellow;
const blue = PlayerColor.blue;

/// Progress a piece of [color] needs to stand on absolute track [square].
int progressAt(PlayerColor color, int square) =>
    (square - startSquare(color) + kTrackLength) % kTrackLength;

/// Builds a position. Colours missing from [pieces] are all at home.
GameState position({
  GameMode mode = GameMode.freeForAll,
  List<PlayerColor> players = const [red, blue],
  Map<PlayerColor, List<int>> pieces = const {},
  PlayerColor? current,
  RulesConfig rules = const RulesConfig(),
  List<PlayerColor> finishOrder = const [],
  int doubleSixStreak = 0,
  int sixesThisTurn = 0,
  List<int> lastRoll = const [],
}) => GameState.custom(
  mode: mode,
  players: players,
  pieces: pieces,
  current: current,
  rules: rules,
  finishOrder: finishOrder,
  doubleSixStreak: doubleSixStreak,
  sixesThisTurn: sixesThisTurn,
  lastRoll: lastRoll,
);

const allHome = [kAtHome, kAtHome, kAtHome, kAtHome];
const allDone = [kFinished, kFinished, kFinished, kFinished];

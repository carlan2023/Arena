# Contract: ludo_engine public API

Status: frozen for M1 and M2. Owner: Engine. Changes go through the supervisor and are logged in docs/decisions.md.

Package: packages/ludo_engine, pub name `ludo_engine`. Pure Dart, SDK ^3.9.0. No Flutter, no dart:io, no dart:html, no clock, no randomness. The engine never rolls dice: callers pass dice values in. Every public type is immutable, has value equality, and round trips through `toJson` and `fromJson` exactly.

Import: `import 'package:ludo_engine/ludo_engine.dart';`

## Board model

The board has 52 shared track squares numbered 0 to 51 clockwise, then a private home column of 5 squares per colour, then the finish.

A piece's position is its progress, counted in steps from its own start square.

| Progress | Meaning |
|---|---|
| -1 | At home, not yet released (`kAtHome`) |
| 0 | On its start square |
| 1 to 51 | On the track. Progress 51 is the square just before its own start square, the last track square before the home column |
| 52 to 56 | In its home column, 5 squares |
| 57 | Finished, in the centre (`kFinished`) |

So a piece needs 57 steps from its start square to finish, as section 2 of the README says.

Absolute track square of a piece on the track: `(startSquare(color) + progress) % 52`, with `startSquare(color) = color.index * 13`.

Only track squares (progress 0 to 51) are shared. Captures and blocks happen only on track squares. Pieces in a home column or in the finish never block, never capture and are never captured (decision D6).

For the board painter (Client): with a 15 by 15 grid, colour c's start square is the first cell of its outgoing arm column next to the middle end cell of its arm, and the middle end cell is progress 51. The home column is the 5 middle cells of the arm. Red's arm is the left arm.

```dart
enum PlayerColor { red, green, yellow, blue } // clockwise seat order

const int kTrackLength = 52;
const int kHomeColumnLength = 5;
const int kAtHome = -1;
const int kLastTrackProgress = 51;
const int kFinished = 57;
const int kPiecesPerPlayer = 4;

int startSquare(PlayerColor color);                  // color.index * 13
int? trackSquare(PlayerColor color, int progress);   // 0..51 for progress 0..51, else null
PlayerColor? partnerOf(PlayerColor color, GameMode mode); // teams only: red<->yellow, green<->blue
```

## Rules settings

Each open rule R1 to R8 from README section 2 is a field. Defaults are the documented defaults in docs/decisions.md.

```dart
class RulesConfig {
  const RulesConfig({
    this.tripleDoubleSixCancelsTurn = false,   // R1
    this.mustUseBothDice = true,               // R2 (if only one die fits, player chooses which)
    this.blockMoveUsesSum = false,             // R3 false: block moves one die value on a double
    this.canContinuePastOwnBlock = false,      // R4
    this.countSixesAcrossTurn = true,          // R5
    this.freeForAllPlaysOn = true,             // R6
    this.teamWinsWhenBothFinish = true,        // R7
    this.partnersFormJointBlocks = false,      // R8 first half
    this.finishedPlayerRollsForPartner = true, // R8 second half
  });
  Map<String, Object?> toJson();
  factory RulesConfig.fromJson(Map<String, Object?> json); // missing keys take defaults
}
```

Meaning of the settings when not default:

| Setting | Non default behaviour |
|---|---|
| R1 true | A third double 6 in a row in one turn ends the turn at once, with no moves for that roll |
| R2 false | After at least one die is used, the player may pass the rest of the roll with a `pass` move |
| R3 true | A block moves the sum of the double (4 and 4 moves 8) |
| R4 true | A piece that joined its own block with one die may use the other die to move on past it |
| R5 false | Only sixes from rolls before the current roll count toward a block capture |
| R6 false | Free for all ends as soon as the first player finishes |
| R7 false | A team wins when the first partner finishes |
| R8 joint true | A partner's piece landing on a single partner piece does not capture it. Mixed partner pieces form a joint block that walls opponents |
| R8 roll false | A finished player's turns are skipped |

## Game state

```dart
enum GameMode { oneVsOne, freeForAll, teams }
enum TurnPhase { awaitingRoll, awaitingMove, gameOver }

class PieceRef { final PlayerColor color; final int index; } // index 0..3

class GameState {
  final RulesConfig rules;
  final GameMode mode;
  final List<PlayerColor> players;            // seated colours, in clockwise turn order
  final Map<PlayerColor, List<int>> pieces;   // 4 progress values per seated colour
  final PlayerColor current;                  // seat whose turn it is
  final TurnPhase phase;
  final List<int> lastRoll;                   // most recent roll [a, b]; empty before the first roll
  final List<int> remainingDice;              // unused values of the current roll; empty unless awaitingMove
  final int doubleSixStreak;                  // consecutive double 6 rolls in this turn
  final int sixesThisTurn;                    // sixes rolled in this turn, current roll included
  final int sixesBeforeRoll;                  // sixes rolled in this turn before the current roll
  final List<PieceRef> joinedOwnBlockThisRoll;// for R4
  final List<PlayerColor> finishOrder;        // players who finished, in order
  final List<PlayerColor> forfeited;          // players removed by forfeit
  final int turnNumber;                       // +1 each time the turn passes to another seat
  final int rollNumber;                       // +1 on every roll in the game, starts at 0; used as the dice nonce

  factory GameState.newGame({
    required GameMode mode,
    required List<PlayerColor> players,        // oneVsOne: two opposite colours; teams: all four; freeForAll: 2 to 4
    RulesConfig rules = const RulesConfig(),
    PlayerColor? firstPlayer,                  // defaults to players.first
  });

  List<PieceRef> piecesOnSquare(int trackSquare); // who occupies an absolute track square
  Map<String, Object?> toJson();
  factory GameState.fromJson(Map<String, Object?> json);
}
```

`newGame` throws `ArgumentError` for an invalid seating. All pieces start at `kAtHome`, phase is `awaitingRoll`.

## Moves

A move is one step of a roll: one die used on one piece, a release, or a block moving together on a double. A combined move (both dice on one piece) is two `advance` moves on the same piece.

```dart
enum MoveKind { release, advance, blockAdvance, pass }

class Move {
  final MoveKind kind;
  final PlayerColor color;   // owner of the moved pieces. Differs from state.current only when a
                             // finished 2v2 player rolls for the partner (R8)
  final List<int> pieces;    // piece indices. release/advance: one. blockAdvance: every piece of the block. pass: empty
  final int die;             // die value used. release: 6. blockAdvance: the double's value (uses both dice). pass: 0

  const Move.release(PlayerColor color, int piece);
  const Move.advance(PlayerColor color, int piece, int die);
  const Move.blockAdvance(PlayerColor color, List<int> pieces, int die);
  const Move.pass(PlayerColor color);
  Map<String, Object?> toJson(); // {"k":"advance","c":"red","p":[2],"d":5}
  factory Move.fromJson(Map<String, Object?> json);
}
```

## Functions

```dart
/// Starts a roll. Phase must be awaitingRoll. Values 1..6.
/// If no legal move exists the roll ends at once (see "end of a roll").
GameState applyRoll(GameState state, int die1, int die2);

/// The legal next steps. Empty unless phase is awaitingMove.
/// Under R2 default a step is legal only if the rest of the roll can still use the
/// largest possible number of dice. If only one die can be used, every usable single
/// die step is legal and the player chooses.
List<Move> legalMoves(GameState state);

/// Applies one step. Throws IllegalMoveException if move is not in legalMoves(state).
MoveResult applyMove(GameState state, Move move);
GameState apply(GameState state, Move move); // applyMove(state, move).state

/// Removes a player (timeouts in paid games, leaving). Their pieces go home and stay out of play.
/// If it is their turn the turn passes. May end the game.
GameState forfeit(GameState state, PlayerColor color);

/// Winner check. Null while undecided. oneVsOne: [winner]. teams: both partners.
/// freeForAll: [first finisher] as soon as someone finishes, even if play continues (R6).
List<PlayerColor>? winners(GameState state);
bool isGameOver(GameState state);            // phase == gameOver
List<PlayerColor> ranking(GameState state);  // finishOrder, then the rest by pieces progress, forfeits last

class MoveResult {
  final GameState state;
  final Move move;
  final List<PieceRef> captured;       // pieces sent home by this step
  final List<PlayerColor> newlyFinished;
  final bool rollEnded;                // no dice left or no legal step left
  final bool extraRoll;                // rollEnded and the same player rolls again (double 6)
}

class IllegalMoveException implements Exception { final String reason; }
```

### End of a roll

A roll ends when no dice remain, or when no legal step remains. Then:

1. If the player has won or the game is over, phase becomes gameOver.
2. Else if the roll was a double 6 (and R1 did not cancel), the same player rolls again: phase awaitingRoll, turn counters kept.
3. Else the turn passes clockwise to the next seat still playing: turnNumber +1, doubleSixStreak, sixesThisTurn and sixesBeforeRoll reset.

A double 6 with no legal move still earns the extra roll.

### Block rules the engine enforces

1. No piece may pass (jump over) an opponent block on the track, unless the mover holds block rights for that block.
2. No piece may pass its own block. It may land on it exactly, joining it.
3. Landing on a single opponent piece captures it. Landing on an opponent block captures every piece in it, and needs block rights. Without rights, landing on an opponent block is illegal.
4. Block rights for a block of size n: a double 6 was rolled earlier in this turn, and the six count is at least n. The six count is sixesThisTurn under R5 default, sixesBeforeRoll when R5 is false. Rights last until the turn ends and apply to every piece of the mover.
5. A release is a step onto the start square and follows the same landing rules.
6. `blockAdvance` is offered only on a double, for pieces sharing one track square, and moves them all by one die value (R3) using both dice.

## Worked examples as named tests

Engine test file test/worked_examples_test.dart has one test per README section 2 case, named exactly:

1. `worked example 1: release with 6 and move 3`
2. `worked example 2: 6 cannot pass a block of two, 4 can`
3. `worked example 3: double 6 then 5 captures a block of two`
4. `worked example 4: double 6 then 6 passes the block`
5. `worked example 5: exact finish, 5 cannot be used, 2 can`

Test helpers can build positions with `GameState.fromJson` or a `GameState.custom(...)` test constructor, which the engine may add as long as it is marked `@visibleForTesting` in spirit (documented as test only).

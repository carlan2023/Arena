# Contract: ludo_bots

Status: frozen for M1 and M2. Owner: Engine (decision D12). Used by the app (offline play, practice) and the server (timeout moves and bot seats).

Package: packages/ludo_bots, pub name `ludo_bots`. Pure Dart, depends only on ludo_engine. Deterministic when given a seeded Random.

```dart
enum BotLevel { easy, normal }

abstract interface class LudoBot {
  /// The full ordered list of steps for the current roll, one of legalSequences(state).
  /// Empty unless state.phase is awaitingMove. Moves for the colour whose pieces the
  /// current player controls (state.current, or the partner under R8).
  List<Move> chooseMoves(GameState state);
}

class EasyBot implements LudoBot { EasyBot({Random? random}); }   // a random legal sequence
class NormalBot implements LudoBot { NormalBot({Random? random}); } // best score, random tie break
LudoBot botFor(BotLevel level, {Random? random});
```

NormalBot scores each complete sequence by its end state: captures (block captures worth more), forming a block, advancing the leading piece, finishing a piece, releasing a piece, and a penalty for each own single piece left within 1 to 12 squares in front of an opponent piece (can be hit next turn). Weights are constants in one place, with tests showing each preference on a small hand built position.

A bot must never throw on any reachable state, which the property tests check by playing thousands of bot games to the end.

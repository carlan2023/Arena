import 'dart:math';

import 'package:arena_server/src/bot.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  test('the server bot plays legal full move lists to the end', () {
    final choose = normalBotChooser(Random(3));
    final rng = Random(4);
    var state = GameState.newGame(
      mode: GameMode.freeForAll,
      players: const [PlayerColor.red, PlayerColor.green, PlayerColor.yellow],
    );
    for (var i = 0; i < 5000 && !isGameOver(state); i++) {
      if (state.phase == TurnPhase.awaitingRoll) {
        state = applyRoll(state, rng.nextInt(6) + 1, rng.nextInt(6) + 1);
      } else {
        final moves = choose(state);
        MoveResult? last;
        for (final m in moves) {
          last = applyMove(state, m);
          state = last.state;
        }
        expect(last?.rollEnded ?? true, isTrue);
      }
    }
    expect(isGameOver(state), isTrue);
  });
}

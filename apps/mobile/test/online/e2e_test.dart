// End to end against a running server with AUTH_PROVIDER=fake:
//   cd server && AUTH_PROVIDER=fake dart run bin/server.dart
//   cd apps/mobile && ARENA_E2E_URL=http://localhost:8080 flutter test test/online/e2e_test.dart
// Skipped when ARENA_E2E_URL is not set.
import 'dart:async';
import 'dart:io';

import 'package:arena/game/move_planner.dart';
import 'package:arena/online/api.dart';
import 'package:arena/online/auth.dart';
import 'package:arena/online/room_controller.dart';
import 'package:arena/online/socket.dart';
import 'package:arena_protocol/client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

final _url = Platform.environment['ARENA_E2E_URL'];

Future<void> waitFor(bool Function() done, String what) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'app controller plays against a headless client, with a reconnect',
    () async {
      final base = Uri.parse(_url!);
      final suffix = DateTime.now().millisecondsSinceEpoch % 10000000;
      String phone(int n) =>
          '+2567${(suffix * 10 + n).toString().padLeft(8, '0')}';

      final c = ProviderContainer(
        overrides: [
          arenaApiProvider.overrideWithValue(HttpArenaApi(base)),
          sessionStoreProvider.overrideWithValue(MemorySessionStore()),
          socketConnectorProvider.overrideWithValue(
            (token) => WsGameSocket.connect(base, token),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(authProvider.future);
      await c.read(authProvider.notifier).login(phone(1), '123456');
      await c.read(authProvider.notifier).setDisplayName('App');
      final token = c.read(authProvider).value!.token;
      final room = await c
          .read(arenaApiProvider)
          .createRoom(token, mode: GameMode.oneVsOne, seats: 2);

      final sub = c.listen(roomProvider(room.code), (_, _) {});
      final ctrl = c.read(roomProvider(room.code).notifier);
      await waitFor(() => sub.read().room != null, 'lobby');
      expect(sub.read().isOwner, isTrue);

      final other = ArenaClient(baseUrl: base);
      addTearDown(other.close);
      await other.login('fake:${phone(2)}');
      await other.connect();
      other.joinRoom(room.code);
      await waitFor(() => sub.read().table != null, 'game start');

      var rolls = 0;
      var myRolls = 0;
      var dropped = false;
      final otherColor = sub.read().you!.color == PlayerColor.red
          ? PlayerColor.yellow
          : PlayerColor.red;
      StreamSubscription<ServerMessage>? otherSub;
      otherSub = other.messages.listen((m) {
        if (m is DiceMessage &&
            m.color == otherColor &&
            m.legalMoves.isNotEmpty) {
          other.move(legalSequences(m.state).first);
        }
      });
      addTearDown(() => otherSub?.cancel());

      while (rolls < 12) {
        final view = sub.read();
        final table = view.table!;
        final g = table.state;
        if (view.connection != Connection.connected) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          continue;
        }
        if (g.phase == TurnPhase.gameOver) break;
        if (g.current == otherColor) {
          if (g.phase == TurnPhase.awaitingRoll) {
            final before = g.rollNumber;
            other.roll();
            rolls++;
            await waitFor(
              () => sub.read().table!.state.rollNumber > before,
              'their roll',
            );
          } else {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          continue;
        }
        if (table.canRoll) {
          final before = g.rollNumber;
          ctrl.roll();
          rolls++;
          myRolls++;
          await waitFor(
            () => sub.read().table!.state.rollNumber > before,
            'my roll',
          );
          if (myRolls == 3 && !dropped) {
            dropped = true;
            await ctrl.dropConnection();
            await waitFor(
              () => sub.read().connection == Connection.reconnecting,
              'drop noticed',
            );
            await waitFor(
              () => sub.read().connection == Connection.connected,
              'reconnect',
            );
          }
          continue;
        }
        if (table.selectable.isNotEmpty) {
          ctrl.tapPieces([table.selectable.first]);
          final options = sub.read().table!.options;
          if (options.isNotEmpty) {
            ctrl.chooseOption(
              options.firstWhere(
                (o) => o.kind != OptionKind.pass,
                orElse: () => options.first,
              ),
            );
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      expect(dropped, isTrue);
      expect(sub.read().connection, Connection.connected);
      expect(rolls, greaterThanOrEqualTo(12));
    },
    skip: _url == null ? 'set ARENA_E2E_URL to run against a server' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

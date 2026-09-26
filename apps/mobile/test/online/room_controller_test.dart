import 'package:arena/game/move_planner.dart';
import 'package:arena/online/auth.dart';
import 'package:arena/online/room_controller.dart';
import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'fakes.dart';

const red = PlayerColor.red;
const yellow = PlayerColor.yellow;

class Harness {
  Harness(this.tester) {
    container = ProviderContainer(overrides: onlineOverrides(connector));
  }

  final WidgetTester tester;
  final connector = FakeConnector();
  late final ProviderContainer container;
  late final ProviderSubscription<RoomScreenView> sub;

  RoomScreenView get view => sub.read();
  RoomController get ctrl => container.read(roomProvider(code).notifier);
  FakeSocket get socket => connector.last;
  List<ClientMessage> get sent => socket.sent;

  Future<void> open() async {
    await container.read(authProvider.future);
    sub = container.listen(roomProvider(code), (_, _) {});
    await tester.pump();
  }

  Future<void> receive(ServerMessage m) async {
    socket.receive(m);
    await tester.pump();
  }
}

/// Runs [body] with a fresh harness and disposes it before the test ends,
/// so no timer outlives the test.
void testRoom(String name, Future<void> Function(Harness h) body) {
  testWidgets(name, (tester) async {
    final h = Harness(tester);
    try {
      await body(h);
    } finally {
      h.container.dispose();
    }
  });
}

void main() {
  testRoom('joins with the room code and a client seed', (h) async {
    await h.open();
    expect(h.connector.tokens, ['tok-1']);
    final join = h.sent.single as JoinRoomMessage;
    expect(join.roomCode, code);
    expect(join.clientSeed, matches(RegExp(r'^[A-Za-z0-9]{16}$')));
    expect(join.lastSeq, isNull);
    expect(join.cseq, 1);
    expect(h.view.connection, Connection.connecting);

    await h.receive(lobbyState());
    expect(h.view.connection, Connection.connected);
    expect(h.view.room!.code, code);
    expect(h.view.isOwner, isTrue);
    expect(h.view.table, isNull);
  });

  testRoom('owner starts the game; others are not owners', (h) async {
    await h.open();
    await h.receive(
      lobbyState(
        room: lobbyRoom(players: [player(0, them), player(1, me)], owner: 'u1'),
      ),
    );
    // You are seat 0 in lobbyState, which is Brian here; Amina owns it.
    expect(h.view.isOwner, isFalse);
    h.ctrl.startGame();
    expect(h.sent.last, isA<StartGameMessage>());
  });

  testRoom('roll, plan both dice, send one move list', (h) async {
    await h.open();
    final start = newGame();
    await h.receive(gameState(state: start));
    var table = h.view.table!;
    expect(table.canRoll, isTrue);
    expect(table.turns, 3, reason: 'red yard bottom left');
    expect(table.seats.firstWhere((s) => s.isYou).color, red);

    h.ctrl.roll();
    h.ctrl.roll();
    expect(h.sent.whereType<RollMessage>(), hasLength(1));
    expect(h.view.table!.canRoll, isFalse);

    await h.receive(dice(4, start, 6, 3));
    table = h.view.table!;
    expect(table.selectable, hasLength(4));

    h.ctrl.tapPieces([const PieceRef(red, 1)]);
    h.ctrl.chooseOption(h.view.table!.options.single);
    expect(h.sent.whereType<MoveMessage>(), isEmpty, reason: 'a die is left');
    // Only the released piece can use the 3: it plays after 0.5 s.
    await h.tester.pump(const Duration(milliseconds: 500));
    final move = h.sent.last as MoveMessage;
    expect(move.moves, [Move.release(red, 1), Move.advance(red, 1, 3)]);
    // The board shows the planned result until the server confirms.
    expect(h.view.table!.state.pieces[red]![1], 3);
    expect(h.view.table!.canUndo, isFalse);

    final after = applyRoll(start, 6, 3);
    final done = apply(apply(after, move.moves[0]), move.moves[1]);
    await h.receive(
      StatePatchMessage(
        seq: 5,
        color: red,
        moves: move.moves,
        captured: const [],
        state: done,
        deadline: now + 20000,
        auto: false,
        serverNow: now,
      ),
    );
    expect(h.view.table!.state.current, yellow);
    expect(h.view.table!.canRoll, isFalse);
  });

  testRoom('a combined move is one element of the move list (D34)', (h) async {
    await h.open();
    // Red 4 behind a single yellow piece rolls 4 and 4.
    final start = GameState.custom(
      mode: GameMode.oneVsOne,
      players: const [red, yellow],
      pieces: {
        red: [10, 30, kAtHome, kAtHome],
        yellow: [40, kAtHome, kAtHome, kAtHome],
      },
    );
    await h.receive(gameState(state: start));
    await h.receive(dice(4, start, 4, 4));
    h.ctrl.tapPieces([const PieceRef(red, 0)]);
    final both = h.view.table!.options.firstWhere(
      (o) => o.kind == OptionKind.both,
    );
    h.ctrl.chooseOption(both);
    final move = h.sent.last as MoveMessage;
    expect(move.moves, [Move.combined(red, 0, 4, 4)]);
    expect(move.toJson()['moves'], [
      {
        'k': 'combined',
        'c': 'red',
        'p': [0],
        'd': 4,
        'd2': 4,
      },
    ]);
    final table = h.view.table!;
    expect(table.state.pieces[red]![0], 18);
    expect(table.state.pieces[yellow]![0], 40, reason: 'passed, not taken');
  });

  testRoom('a forced roll plays itself after half a second', (h) async {
    await h.open();
    final start = GameState.custom(
      mode: GameMode.oneVsOne,
      players: const [red, yellow],
      pieces: {
        red: [40, kFinished, kFinished, kFinished],
      },
    );
    await h.receive(gameState(state: start));
    await h.receive(dice(4, start, 2, 3));
    expect(h.sent.whereType<MoveMessage>(), isEmpty);
    await h.tester.pump(const Duration(milliseconds: 500));
    expect(h.sent.whereType<MoveMessage>(), hasLength(1));
  });

  testRoom('an illegal_move reply resets the plan', (h) async {
    await h.open();
    final start = newGame();
    await h.receive(gameState(state: start));
    await h.receive(dice(4, start, 6, 3));
    h.ctrl.tapPieces([const PieceRef(red, 0)]);
    h.ctrl.chooseOption(h.view.table!.options.single);
    await h.tester.pump(const Duration(milliseconds: 500));
    expect(h.sent.last, isA<MoveMessage>());
    await h.receive(
      const ErrorMessage(code: 'illegal_move', message: 'no', ref: 3),
    );
    final table = h.view.table!;
    expect(table.state.pieces[red], everyElement(kAtHome));
    expect(table.selectable, hasLength(4));
    expect(table.message, contains('refused'));
  });

  testRoom('dice for someone else only update the board', (h) async {
    await h.open();
    final start = GameState.newGame(
      mode: GameMode.oneVsOne,
      players: const [red, yellow],
      firstPlayer: yellow,
    );
    await h.receive(gameState(state: start));
    expect(h.view.table!.canRoll, isFalse);
    await h.receive(dice(4, start, 6, 1));
    expect(h.view.table!.selectable, isEmpty);
    expect(h.view.table!.dice.map((d) => d.value), [6, 1]);
    h.ctrl.roll();
    expect(h.sent.whereType<RollMessage>(), isEmpty);
  });

  testRoom('a seq gap asks for a fresh snapshot; old seqs are ignored', (
    h,
  ) async {
    await h.open();
    final start = newGame();
    await h.receive(gameState(seq: 3, state: start));
    await h.receive(dice(3, start, 6, 3));
    expect(h.view.table!.dice, isEmpty, reason: 'seq 3 already seen');

    await h.receive(dice(6, start, 6, 3));
    final join = h.sent.last as JoinRoomMessage;
    expect(join.lastSeq, 3);
    expect(h.view.table!.dice, isEmpty, reason: 'gap: not applied');
  });

  testRoom('player status and emotes update the view', (h) async {
    await h.open();
    await h.receive(gameState(seq: 3));
    await h.receive(
      const PlayerStatusMessage(
        seq: 4,
        seat: 1,
        connected: false,
        graceDeadline: null,
        isBot: true,
      ),
    );
    final brian = h.view.table!.seats.firstWhere((s) => s.color == yellow);
    expect(brian.connected, isFalse);
    expect(brian.isBot, isTrue);
    await h.receive(const EmoteEvent(seq: 5, seat: 1, id: 'gg'));
    expect(h.view.emote, (1, 'gg'));
    h.ctrl.sendEmote('hello');
    expect((h.sent.last as EmoteMessage).id, 'hello');
  });

  testRoom('a drop reconnects with backoff and rejoins with lastSeq', (
    h,
  ) async {
    await h.open();
    await h.receive(gameState(seq: 7));
    h.connector.fail = true;
    h.socket.drop();
    await h.tester.pump();
    expect(h.view.connection, Connection.reconnecting);
    expect(h.view.table!.canRoll, isFalse, reason: 'no acting offline');

    await h.tester.pump(const Duration(seconds: 1));
    expect(h.connector.tokens, hasLength(2), reason: 'first retry failed');
    h.connector.fail = false;
    await h.tester.pump(const Duration(seconds: 1));
    expect(h.connector.tokens, hasLength(2), reason: 'second waits 2 s');
    await h.tester.pump(const Duration(seconds: 1));
    expect(h.connector.sockets, hasLength(2));
    final join = h.sent.single as JoinRoomMessage;
    expect(join.lastSeq, 7);

    await h.receive(gameState(seq: 9));
    expect(h.view.connection, Connection.connected);
    expect(h.view.table!.canRoll, isTrue);
  });

  testRoom('resume reconnects at once', (h) async {
    await h.open();
    await h.receive(gameState(seq: 7));
    h.socket.drop();
    await h.tester.pump();
    h.ctrl.resume();
    await h.tester.pump();
    expect(h.connector.sockets, hasLength(2));
    await h.tester.pump(const Duration(seconds: 5));
    expect(h.connector.sockets, hasLength(2), reason: 'retry was cancelled');
  });

  testRoom('room_not_found before joining is fatal', (h) async {
    await h.open();
    await h.receive(
      const ErrorMessage(code: 'room_not_found', message: 'x', ref: 1),
    );
    expect(h.view.fatal, contains('not found'));
    expect(h.socket.closed, isTrue);
    await h.tester.pump(const Duration(seconds: 10));
    expect(h.connector.sockets, hasLength(1), reason: 'no retry');
  });

  testRoom('game over shows results and stops the timer', (h) async {
    await h.open();
    await h.receive(gameState(seq: 3));
    await h.receive(
      const GameOverMessage(
        seq: 4,
        matchId: 'm1',
        ranking: [red, yellow],
        winners: [red],
        serverSeed: 'aa',
        clientSeed: 'x:1',
        walletDelta: {},
      ),
    );
    expect(h.view.gameOver!.winners, [red]);
    expect(h.view.table!.deadline, isNull);
  });

  testRoom('leave sends leave_room and closes', (h) async {
    await h.open();
    await h.receive(lobbyState());
    h.ctrl.leave();
    expect(h.sent.last, isA<LeaveRoomMessage>());
    expect(h.socket.closed, isTrue);
    await h.tester.pump(const Duration(seconds: 10));
    expect(h.connector.sockets, hasLength(1));
  });

  testRoom('pings keep the socket alive and set the clock offset', (h) async {
    await h.open();
    await h.receive(gameState(seq: 3));
    await h.tester.pump(const Duration(seconds: 20));
    expect(h.sent.last, isA<PingMessage>());
    await h.receive(PongMessage(ref: 2, serverNow: now + 60000));
    expect(h.view.table!.serverOffset.inSeconds, inInclusiveRange(59, 60));
  });

  testWidgets('without a session the room joins as a guest', (tester) async {
    final connector = FakeConnector();
    final api = FakeApi();
    final container = ProviderContainer(
      overrides: [
        for (final o in onlineOverrides(connector, api: api, session: null)) o,
      ],
    );
    await container.read(authProvider.future);
    final sub = container.listen(roomProvider(code), (_, _) {});
    await tester.pump();
    await tester.pump();
    expect(sub.read().fatal, isNull);
    expect(api.calls, ['guest']);
    expect(connector.tokens, ['guest-tok']);
    expect(container.read(authProvider).value!.isGuest, isTrue);
    container.dispose();
  });

  testWidgets('a guest token the server rejects is replaced', (tester) async {
    final connector = FakeConnector()..fail = true;
    final api = FakeApi()..meStatus = 401;
    final container = ProviderContainer(
      overrides: [
        for (final o in onlineOverrides(connector, api: api, session: null)) o,
      ],
    );
    await container.read(authProvider.future);
    final sub = container.listen(roomProvider(code), (_, _) {});
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['guest', 'me guest-tok', 'guest']);
    connector.fail = false;
    api.meStatus = null;
    await tester.pump(const Duration(seconds: 1));
    expect(connector.last.sent.first, isA<JoinRoomMessage>());
    expect(sub.read().fatal, isNull);
    container.dispose();
  });

  testWidgets('a lost network does not throw away the guest', (tester) async {
    final connector = FakeConnector()..fail = true;
    final api = FakeApi();
    final container = ProviderContainer(
      overrides: [
        for (final o in onlineOverrides(connector, api: api, session: null)) o,
      ],
    );
    await container.read(authProvider.future);
    container.listen(roomProvider(code), (_, _) {});
    await tester.pump();
    await tester.pump();
    expect(api.calls, ['guest', 'me guest-tok']);
    container.dispose();
  });
}

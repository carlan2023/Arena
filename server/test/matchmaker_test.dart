import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_server/arena_server.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'support/room_harness.dart';

void main() {
  late Harness h;
  setUp(() => h = Harness());

  void queue(
    TestConnection c, {
    GameMode mode = GameMode.oneVsOne,
    int entry = 0,
    int stake = 0,
  }) => h.send(
    c,
    (n) => QueueJoinMessage(
      mode: mode,
      entry: entry,
      stake: stake,
      clientSeed: 'seed${c.userId}',
      cseq: n,
    ),
  );

  QueueStatusMessage status(TestConnection c) => c.last<QueueStatusMessage>();

  test('two players in the 1v1 queue start a game together', () {
    final a = h.connect('a');
    final b = h.connect('b');
    queue(a);
    expect(status(a).state, QueueState.waiting);
    expect(status(a).ref, 1);
    expect((status(a).playersFound, status(a).playersNeeded), (1, 2));

    h.clock.advance(const Duration(seconds: 3));
    queue(b);
    final sa = status(a);
    final sb = status(b);
    expect(sa.state, QueueState.matched);
    expect(sb.state, QueueState.matched);
    expect(sa.roomCode, sb.roomCode);
    expect(sa.waited, 3);
    expect(sa.playersFound, 2);

    final room = h.manager.room(sa.roomCode!)!;
    expect(room.status, RoomStatus.playing);
    expect(room.seated.map((s) => s.userId), ['a', 'b']);
    expect(room.clientSeed, 'seeda:seedb');
    expect(h.manager.matchmaker.waiting(const QueueKey(GameMode.oneVsOne)), 0);

    // Joining is a reconnect: each gets the running game.
    h.join(a, room.code);
    h.join(b, room.code);
    expect(a.last<RoomStateMessage>().room.status, RoomStatus.playing);
    expect(b.last<RoomStateMessage>().you.color, PlayerColor.yellow);
    expect(a.lastError, isNull);
    h.playToEnd(room);
    expect(room.status, RoomStatus.finished);
  });

  test('a player who never joins the match is handled by the grace', () {
    final a = h.connect('a');
    final b = h.connect('b');
    queue(a);
    queue(b);
    final room = h.manager.room(status(a).roomCode!)!;
    h.join(a, room.code);
    h.clock.advance(const Duration(seconds: 61));
    final bSeat = room.seatOfUser('b')!;
    expect(bSeat.isBot, isTrue, reason: 'a bot plays a free seat');
    expect(room.status, RoomStatus.playing);
  });

  test('four players fill a free for all; others keep waiting', () {
    final conns = [for (final u in 'abcde'.split('')) h.connect(u)];
    for (final c in conns.take(3)) {
      queue(c, mode: GameMode.freeForAll);
    }
    expect(status(conns[0]).playersFound, 3);
    expect(status(conns[0]).playersNeeded, 4);
    queue(conns[3], mode: GameMode.freeForAll);
    queue(conns[4], mode: GameMode.freeForAll);
    final code = status(conns[0]).roomCode!;
    for (final c in conns.take(4)) {
      expect(status(c).state, QueueState.matched);
      expect(status(c).roomCode, code);
    }
    expect(status(conns[4]).state, QueueState.waiting);
    expect(status(conns[4]).playersFound, 1);
    expect(h.manager.room(code)!.seated, hasLength(4));
  });

  test('queues are separate per mode', () {
    final a = h.connect('a');
    final b = h.connect('b');
    queue(a);
    queue(b, mode: GameMode.freeForAll);
    expect(status(a).state, QueueState.waiting);
    expect(status(b).state, QueueState.waiting);
  });

  test('leaving and dropping take the player out of the queue', () {
    final a = h.connect('a');
    final b = h.connect('b');
    final c = h.connect('c');
    queue(a, mode: GameMode.freeForAll);
    queue(b, mode: GameMode.freeForAll);
    h.send(a, (n) => QueueLeaveMessage(cseq: n));
    expect(status(a).state, QueueState.cancelled);
    expect(status(b).playersFound, 1);
    h.manager.disconnected(b);
    queue(c, mode: GameMode.freeForAll);
    expect(status(c).playersFound, 1);
    h.send(a, (n) => QueueLeaveMessage(cseq: n));
    expect(a.lastError!.code, ErrorCodes.notFound);
  });

  test('a seat in a room or another queue makes the queue busy', () {
    final room = h.openRoom(['a', 'b'], seats: 2);
    expect(room.status, RoomStatus.playing);
    queue(h.conns['a']!);
    expect(h.conns['a']!.lastError!.code, ErrorCodes.queueBusy);

    final c = h.connect('c');
    queue(c);
    queue(c, mode: GameMode.freeForAll);
    expect(c.lastError!.code, ErrorCodes.queueBusy);
    queue(c);
    expect(status(c).state, QueueState.waiting, reason: 'same queue again');
  });

  test('a new socket for the same player takes over the place', () {
    final old = h.connect('a');
    queue(old);
    final fresh = TestConnection('a');
    queue(fresh);
    expect(h.manager.matchmaker.waiting(const QueueKey(GameMode.oneVsOne)), 1);
    h.manager.disconnected(old);
    expect(h.manager.matchmaker.isQueued('a'), isTrue);
    final b = h.connect('b');
    queue(b);
    expect(status(fresh).state, QueueState.matched);
  });

  test('a player who took a seat by code since queueing is dropped', () {
    final a = h.connect('a');
    queue(a);
    final room = h.manager.createRoom(
      ownerUserId: 'x',
      mode: GameMode.freeForAll,
      seats: 4,
    );
    h.join(a, room.code);
    final b = h.connect('b');
    queue(b);
    expect(status(a).state, QueueState.cancelled);
    expect(status(b).state, QueueState.waiting);
  });

  test('teams, bad tables and closed tables are refused', () {
    final a = h.connect('a');
    queue(a, mode: GameMode.teams);
    expect(a.lastError!.code, ErrorCodes.badRequest);
    queue(a, entry: -1);
    expect(a.lastError!.code, ErrorCodes.badRequest);
    queue(a, entry: 50, stake: 1000);
    expect(a.lastError!.code, ErrorCodes.badRequest);
    queue(a, stake: 1000);
    expect(a.lastError!.code, ErrorCodes.paidTablesDisabled);
    queue(a, entry: 50);
    expect(a.lastError!.code, ErrorCodes.badRequest);
    h.send(
      a,
      (n) => QueueJoinMessage(
        mode: GameMode.oneVsOne,
        clientSeed: 'x' * 200,
        cseq: n,
      ),
    );
    expect(a.lastError!.code, ErrorCodes.badRequest);
    expect(h.manager.matchmaker.isQueued('a'), isFalse);
  });
}

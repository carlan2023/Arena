import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_server/arena_server.dart';
import 'package:arena_server/src/rooms/matchmaker.dart';
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

  test('open coin tables accept 50 and still refuse a stake or 75', () {
    final open = Harness(allowTable: openCoinTables);
    final a = open.connect('a');
    open.send(
      a,
      (n) => QueueJoinMessage(
        mode: GameMode.oneVsOne,
        entry: 50,
        clientSeed: 'seeda',
        cseq: n,
      ),
    );
    expect(a.last<QueueStatusMessage>().state, QueueState.waiting);
    expect(a.last<QueueStatusMessage>().entry, 50);
    final b = open.connect('b');
    open.send(
      b,
      (n) => QueueJoinMessage(
        mode: GameMode.oneVsOne,
        entry: 75,
        clientSeed: 'seedb',
        cseq: n,
      ),
    );
    expect(b.lastError!.code, ErrorCodes.badRequest);
    open.send(
      b,
      (n) => QueueJoinMessage(
        mode: GameMode.oneVsOne,
        stake: 1000,
        clientSeed: 'seedb',
        cseq: n,
      ),
    );
    expect(b.lastError!.code, ErrorCodes.paidTablesDisabled);
  });

  group('bot seat fill', () {
    test('a lone 1v1 player gets a bot after 20 seconds', () async {
      final a = h.connect('a');
      queue(a);
      final start = h.clock.nowMs();
      expect(status(a).botFillAt, start + 20000);
      expect(status(a).serverNow, start);
      h.clock.advance(const Duration(seconds: 19));
      expect(status(a).state, QueueState.waiting);
      h.clock.advance(const Duration(seconds: 1));
      expect(status(a).state, QueueState.matched);
      expect(status(a).waited, 20);

      final room = h.manager.room(status(a).roomCode!)!;
      expect(room.status, RoomStatus.playing);
      final bot = room.seated.last;
      expect((bot.isBot, bot.everBot, bot.displayName), (true, true, 'Bot 2'));
      expect(h.manager.activeRoomOf('a'), room.code);
      expect(h.manager.activeRoomOf(bot.userId), isNull);

      h.join(a, room.code);
      final you = a.last<RoomStateMessage>().room.players;
      expect(you.map((p) => p.isBot), [false, true]);
      // The bot plays its own turns; after three timeouts one plays a's too.
      for (var i = 0; i < 2000 && room.status == RoomStatus.playing; i++) {
        h.clock.advance(const Duration(seconds: 20));
      }
      expect(room.status, RoomStatus.finished);
      await h.manager.flush();
      expect(h.log.ends.values.single.status, MatchStatus.finished);
      expect(h.log.ends.values.single.botSeats, {0, 1});
    });

    test('the oldest player sets the time for their group of four', () {
      final conns = [for (final u in 'abcdef'.split('')) h.connect(u)];
      final start = h.clock.nowMs();
      queue(conns[0], mode: GameMode.freeForAll);
      h.clock.advance(const Duration(seconds: 5));
      queue(conns[1], mode: GameMode.freeForAll);
      expect(status(conns[1]).botFillAt, start + 20000);

      h.clock.advance(const Duration(seconds: 15));
      final code = status(conns[0]).roomCode!;
      expect(status(conns[1]).roomCode, code);
      final room = h.manager.room(code)!;
      expect(room.seated.map((s) => s.isBot), [false, false, true, true]);
      expect(h.manager.matchmaker.isQueued('b'), isFalse);

      queue(conns[2], mode: GameMode.freeForAll);
      expect(status(conns[2]).botFillAt, h.clock.nowMs() + 20000);
    });

    test('a group that fills up before the time needs no bots', () {
      final conns = [for (final u in 'abcde'.split('')) h.connect(u)];
      for (final c in conns) {
        queue(c, mode: GameMode.freeForAll);
      }
      final room = h.manager.room(status(conns[0]).roomCode!)!;
      expect(room.seated.where((s) => s.isBot), isEmpty);
      // The fifth player is first in the queue now, so their own time counts.
      expect(status(conns[4]).botFillAt, h.clock.nowMs() + 20000);
      h.clock.advance(const Duration(seconds: 20));
      expect(status(conns[4]).state, QueueState.matched);
    });

    test('a player who leaves before the time gets no game', () {
      final a = h.connect('a');
      queue(a);
      h.send(a, (n) => QueueLeaveMessage(cseq: n));
      h.clock.advance(const Duration(seconds: 30));
      expect(status(a).state, QueueState.cancelled);
      expect(h.manager.rooms, isEmpty);
    });

    test(
      'a bot game the player never joins is abandoned after the grace',
      () async {
        final a = h.connect('a');
        queue(a);
        h.clock.advance(const Duration(seconds: 20));
        final room = h.manager.room(status(a).roomCode!)!;
        h.clock.advance(const Duration(seconds: 61));
        expect(room.status, RoomStatus.finished);
        await h.manager.flush();
        expect(h.log.ends.values.single.status, MatchStatus.abandoned);
      },
    );

    test('BOT_FILL_SECONDS sets the time', () {
      h = Harness(settings: const RoomSettings(botFill: Duration(seconds: 5)));
      final a = h.connect('a');
      queue(a);
      h.clock.advance(const Duration(seconds: 5));
      expect(status(a).state, QueueState.matched);
    });

    test('paid queues get no bots and time out after 60 seconds', () {
      h = Harness(allowTable: (_, _) => null);
      final a = h.connect('a');
      queue(a, stake: 1000);
      expect(status(a).botFillAt, isNull);
      h.clock.advance(const Duration(seconds: 59));
      expect(status(a).state, QueueState.waiting);
      h.clock.advance(const Duration(seconds: 1));
      expect(status(a).state, QueueState.timeout);
      expect(h.manager.matchmaker.isQueued('a'), isFalse);
      expect(h.manager.rooms, isEmpty);
    });
  });
}

import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_protocol/fair_dice.dart';
import 'package:arena_server/src/rooms/room_manager.dart';
import 'package:arena_server/src/store/match_log.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'support/room_harness.dart';

void main() {
  group('lobby', () {
    test('rejects bad seat counts for the mode', () {
      final h = Harness();
      for (final (mode, seats) in [
        (GameMode.oneVsOne, 3),
        (GameMode.teams, 2),
        (GameMode.freeForAll, 1),
        (GameMode.freeForAll, 5),
      ]) {
        expect(
          () =>
              h.manager.createRoom(ownerUserId: 'a', mode: mode, seats: seats),
          throwsA(isA<RoomException>()),
        );
      }
    });

    test('room codes use the protocol alphabet', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.oneVsOne,
        seats: 2,
      );
      expect(
        room.code,
        matches(RegExp(r'^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{6}$')),
      );
      expect(h.manager.view(room).link, 'http://localhost:8080/r/${room.code}');
    });

    test('first join replies with room_state echoing cseq', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.freeForAll,
        seats: 3,
      );
      final a = h.connect('a');
      h.join(a, room.code.toLowerCase());
      final rs = a.last<RoomStateMessage>();
      expect(rs.ref, 1);
      expect(rs.seq, 1);
      expect(rs.you.seat, 0);
      expect(rs.you.color, isNull);
      expect(rs.state, isNull);
      expect(rs.serverSeedHash, room.serverSeedHash);
      expect(rs.room.players.single.userId, 'a');
    });

    test('a full 1v1 room starts by itself with red and yellow', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      expect(room.status, RoomStatus.playing);
      final a = h.conns['a']!;
      final b = h.conns['b']!;
      final start = b.last<RoomStateMessage>();
      expect(start.state, isNotNull);
      expect(start.room.matchId, room.matchId);
      expect(start.you.color, PlayerColor.yellow);
      expect(a.last<RoomStateMessage>().you.color, PlayerColor.red);
      expect(start.deadline, h.clock.nowMs() + 20000);
      expect(room.clientSeed, 'seeda:seedb');
      expect(hashServerSeed(room.serverSeed), start.serverSeedHash);
    });

    test('join errors', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final c = h.connect('c');
      h.join(c, 'ZZZZZZ');
      expect(c.lastError!.code, ErrorCodes.roomNotFound);
      h.join(c, room.code);
      expect(c.lastError!.code, ErrorCodes.alreadyStarted);
      final other = h.manager.createRoom(
        ownerUserId: 'c',
        mode: GameMode.oneVsOne,
        seats: 2,
      );
      h.join(c, other.code, seed: 'bad:seed');
      expect(c.lastError!.code, ErrorCodes.badRequest);
      // a already holds a seat in a running room.
      final a2 = h.connect('a');
      h.join(a2, other.code);
      expect(a2.lastError!.code, ErrorCodes.badRequest);
    });

    test('commands before joining give not_in_room', () {
      final h = Harness();
      final c = h.connect('c');
      h.roll(c);
      expect(c.lastError!.code, ErrorCodes.notInRoom);
      expect(c.lastError!.ref, 1);
    });

    test('owner starts a free for all early; others cannot', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.freeForAll,
        seats: 4,
      );
      final a = h.connect('a');
      h.join(a, room.code);
      h.send(a, (n) => StartGameMessage(cseq: n));
      expect(a.lastError!.code, ErrorCodes.badRequest);
      final b = h.connect('b');
      final c = h.connect('c');
      h.join(b, room.code);
      h.join(c, room.code);
      h.send(b, (n) => StartGameMessage(cseq: n));
      expect(b.lastError!.code, ErrorCodes.notOwner);
      h.send(a, (n) => StartGameMessage(cseq: n));
      expect(room.status, RoomStatus.playing);
      expect(room.state!.players, [
        PlayerColor.red,
        PlayerColor.green,
        PlayerColor.yellow,
      ]);
      // Nobody sent a seed, so seat numbers are used.
      expect(room.clientSeed, '0:1:2');
      h.send(a, (n) => StartGameMessage(cseq: n));
      expect(a.lastError!.code, ErrorCodes.alreadyStarted);
    });

    test('leaving the lobby frees the seat and passes ownership', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.freeForAll,
        seats: 3,
      );
      final a = h.connect('a');
      final b = h.connect('b');
      h.join(a, room.code);
      h.join(b, room.code);
      h.send(a, (n) => LeaveRoomMessage(cseq: n));
      expect(room.ownerUserId, 'b');
      expect(room.seats[0], isNull);
      final rs = b.last<RoomStateMessage>();
      expect(rs.room.ownerUserId, 'b');
      expect(rs.room.players.map((p) => p.userId), ['b']);
      // The next joiner takes the lowest free seat.
      final c = h.connect('c');
      h.join(c, room.code);
      expect(c.last<RoomStateMessage>().you.seat, 0);
    });

    test('an empty waiting room expires after the idle time', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.oneVsOne,
        seats: 2,
      );
      h.clock.advance(const Duration(minutes: 29));
      expect(h.manager.room(room.code), isNotNull);
      h.clock.advance(const Duration(minutes: 2));
      expect(h.manager.room(room.code), isNull);
    });

    test('a lobby player who drops is removed after the grace period', () {
      final h = Harness();
      final room = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.freeForAll,
        seats: 3,
      );
      final a = h.connect('a');
      final b = h.connect('b');
      h.join(a, room.code);
      h.join(b, room.code);
      h.manager.disconnected(b);
      expect(a.last<RoomStateMessage>().room.players[1].connected, isFalse);
      h.clock.advance(const Duration(seconds: 61));
      expect(room.seated.map((s) => s.userId), ['a']);
    });
  });

  group('turns', () {
    test('seq goes up by one per broadcast and join replies keep it', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final a = h.conns['a']!;
      final seqBefore = room.seq;
      h.playOne(room);
      expect(room.seq, seqBefore + 1);
      expect(a.last<DiceMessage>().seq, room.seq);
      final a2 = h.connect('a');
      h.join(a2, room.code);
      final rs = a2.last<RoomStateMessage>();
      expect(rs.seq, room.seq);
      expect(rs.state, room.state);
    });

    test('roll gives dice from the fair dice function', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      h.roll(h.conns['a']!);
      final dice = h.conns['b']!.last<DiceMessage>();
      expect(dice.rollNumber, 0);
      expect(dice.color, PlayerColor.red);
      expect(dice.auto, isFalse);
      expect(dice.values, rollDice(room.serverSeed, room.clientSeed!, 0));
      expect(dice.legalMoves, legalMoves(dice.state));
    });

    test('turn and phase errors', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final b = h.conns['b']!;
      h.roll(b);
      expect(b.lastError!.code, ErrorCodes.notYourTurn);
      final a = h.conns['a']!;
      h.move(a, [Move.pass(PlayerColor.red)]);
      expect(a.lastError!.code, ErrorCodes.wrongPhase);
      expect(room.state!.phase, TurnPhase.awaitingRoll);
    });

    test('an illegal move list leaves state, seq and timer unchanged', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      // Roll until red has a move to make.
      while (room.state!.phase != TurnPhase.awaitingMove) {
        h.playOne(room);
      }
      final c = h.currentConn(room);
      final before = room.state;
      final seq = room.seq;
      final deadline = room.deadline;
      final color = before!.current;
      h.move(c, [
        Move.advance(color, 0, 5),
        Move.advance(color, 0, 5),
        Move.advance(color, 0, 5),
      ]);
      expect(c.lastError!.code, ErrorCodes.illegalMove);
      h.move(c, const []);
      expect(c.lastError!.code, ErrorCodes.illegalMove);
      // A valid first step alone does not finish the roll when more dice fit.
      final seqs = legalSequences(before);
      if (seqs.first.length > 1) {
        h.move(c, [seqs.first.first]);
        expect(c.lastError!.code, ErrorCodes.illegalMove);
      }
      expect(room.state, before);
      expect(room.seq, seq);
      expect(room.deadline, deadline);
    });

    test('a full game ends with game_over and verifiable dice', () async {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      h.playToEnd(room);
      expect(room.status, RoomStatus.finished);
      final over = h.conns['a']!.last<GameOverMessage>();
      expect(h.conns['b']!.last<GameOverMessage>().seq, over.seq);
      expect(over.matchId, room.matchId);
      expect(over.winners, hasLength(1));
      expect(over.ranking.first, over.winners.first);
      expect(over.walletDelta, isEmpty);
      await h.manager.flush();
      final stored = (await h.log.loadMatch(room.matchId!))!;
      expect(stored.status, MatchStatus.finished);
      expect(stored.serverSeed, over.serverSeed);
      expect(stored.rolls, isNotEmpty);
      expect(
        verifyRolls(
          serverSeedHex: over.serverSeed,
          serverSeedHash: room.serverSeedHash,
          clientSeed: over.clientSeed,
          rolls: stored.rolls,
        ),
        isTrue,
      );
      final events = await h.log.events(room.matchId!);
      expect(
        events.map((e) => e.index),
        List.generate(events.length, (i) => i),
      );
      final end = h.log.ends[room.matchId!]!;
      expect(end.places.values.toSet(), {1, 2});
      expect(h.log.roomStatus[room.id], 'finished');
      // Seats are free for another room once the game ends.
      final next = h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.oneVsOne,
        seats: 2,
      );
      h.join(h.conns['a']!, next.code);
      expect(h.conns['a']!.last<RoomStateMessage>().room.code, next.code);
    });

    test('emotes are relayed and checked', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final a = h.conns['a']!;
      h.send(a, (n) => EmoteMessage(id: 'wave', cseq: n));
      final e = h.conns['b']!.last<EmoteEvent>();
      expect((e.seat, e.id, e.seq), (0, 'wave', room.seq));
      h.send(a, (n) => EmoteMessage(id: 'x' * 33, cseq: n));
      expect(a.lastError!.code, ErrorCodes.badRequest);
      final stranger = h.connect('z');
      h.send(stranger, (n) => EmoteMessage(id: 'wave', cseq: n));
      expect(stranger.inbox, isEmpty);
    });

    test('ping replies pong with the server time', () {
      final h = Harness();
      final c = h.connect('c');
      h.send(c, (n) => PingMessage(cseq: n));
      final pong = c.last<PongMessage>();
      expect(pong.ref, 1);
      expect(pong.serverNow, h.clock.nowMs());
    });
  });

  group('timers', () {
    test('a timeout rolls for the player with auto true', () {
      final h = Harness();
      h.openRoom(['a', 'b']);
      h.clock.advance(const Duration(seconds: 20));
      final dice = h.conns['b']!.last<DiceMessage>();
      expect(dice.auto, isTrue);
      expect(dice.color, PlayerColor.red);
    });

    test('three timeouts in a row hand a free seat to a bot, '
        'and acting takes it back', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final a = h.conns['a']!;
      final b = h.conns['b']!;
      // b always plays at once; a never does.
      var guard = 0;
      while (!room.seats[0]!.isBot && guard++ < 200) {
        if (room.currentSeat!.userId == 'b') {
          h.playOne(room);
        } else {
          h.clock.advance(const Duration(seconds: 20));
        }
        if (room.status != RoomStatus.playing) break;
      }
      expect(room.seats[0]!.isBot, isTrue);
      final status = b.last<PlayerStatusMessage>();
      expect((status.seat, status.isBot, status.connected), (0, true, true));
      // The bot now plays red after the short delay, not the full timeout.
      while (room.currentSeat!.userId == 'b') {
        h.playOne(room);
      }
      final seq = room.seq;
      h.clock.advance(const Duration(milliseconds: 800));
      expect(room.seq, greaterThan(seq));
      final lastAuto = [
        ...b.inbox,
      ].reversed.firstWhere((m) => m is DiceMessage || m is StatePatchMessage);
      expect(
        lastAuto is DiceMessage
            ? lastAuto.auto
            : (lastAuto as StatePatchMessage).auto,
        isTrue,
      );
      // Red acts again: any roll or move from a takes the seat back.
      while (room.currentSeat!.userId == 'b') {
        h.playOne(room);
      }
      h.playOne(room);
      expect(room.seats[0]!.isBot, isFalse);
      expect(a.all<PlayerStatusMessage>().last.isBot, isFalse);
    });

    test('in a paid game three timeouts forfeit the seat', () async {
      final h = Harness();
      final room = h.openRoom(['a', 'b'], stake: 1000);
      var guard = 0;
      while (room.status == RoomStatus.playing && guard++ < 200) {
        if (room.currentSeat!.userId == 'b') {
          h.playOne(room);
        } else {
          h.clock.advance(const Duration(seconds: 20));
        }
      }
      expect(room.status, RoomStatus.finished);
      expect(room.seats[0]!.forfeited, isTrue);
      expect(room.seats[0]!.isBot, isFalse);
      final over = h.conns['b']!.last<GameOverMessage>();
      expect(over.winners, [PlayerColor.yellow]);
      await h.manager.flush();
      final events = await h.log.events(room.matchId!);
      expect(events.last.kind, EventKinds.forfeit);
      expect(events.last.data['reason'], 'timeouts');
    });

    test('leaving a running game forfeits it', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      h.send(h.conns['b']!, (n) => LeaveRoomMessage(cseq: n));
      expect(room.status, RoomStatus.finished);
      expect(h.conns['a']!.last<GameOverMessage>().winners, [PlayerColor.red]);
    });
  });

  group('reconnect', () {
    test('drop and rejoin within the grace period', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final a = h.conns['a']!;
      h.manager.disconnected(h.conns['b']!);
      final down = a.last<PlayerStatusMessage>();
      expect(down.connected, isFalse);
      expect(down.graceDeadline, h.clock.nowMs() + 60000);
      h.clock.advance(const Duration(seconds: 30));
      final b2 = h.connect('b');
      h.join(b2, room.code, seed: 'ignored');
      final rs = b2.last<RoomStateMessage>();
      expect(rs.ref, 1);
      expect(rs.you.color, PlayerColor.yellow);
      expect(rs.state, room.state);
      expect(rs.room.players[1].connected, isTrue);
      final up = a.last<PlayerStatusMessage>();
      expect((up.connected, up.graceDeadline), (true, null));
      h.clock.advance(const Duration(seconds: 60));
      expect(room.seats[1]!.isBot, isFalse);
      // The seed is fixed at the start.
      expect(room.clientSeed, 'seeda:seedb');
    });

    test('a second socket replaces the first', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      final old = h.conns['a']!;
      final fresh = h.connect('a');
      h.join(fresh, room.code);
      expect(old.closed, isTrue);
      expect(room.seats[0]!.connection, same(fresh));
      // The old socket closing later changes nothing.
      h.manager.disconnected(old);
      expect(room.seats[0]!.connected, isTrue);
      h.roll(fresh);
      expect(fresh.last<DiceMessage>().color, PlayerColor.red);
    });

    test('after the grace period a bot takes a free seat', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      h.manager.disconnected(h.conns['a']!);
      h.clock.advance(const Duration(seconds: 60));
      expect(room.seats[0]!.isBot, isTrue);
      final s = h.conns['b']!.last<PlayerStatusMessage>();
      expect((s.seat, s.isBot, s.connected), (0, true, false));
      // It is red's turn, so the bot rolls after its delay.
      h.clock.advance(const Duration(milliseconds: 800));
      expect(h.conns['b']!.all<DiceMessage>(), isNotEmpty);
      // Coming back later takes the seat back.
      final a2 = h.connect('a');
      h.join(a2, room.code);
      expect(room.seats[0]!.isBot, isFalse);
      expect(h.conns['b']!.last<PlayerStatusMessage>().isBot, isFalse);
    });

    test('after the grace period a paid seat forfeits', () {
      final h = Harness();
      final room = h.openRoom(['a', 'b'], stake: 1000);
      h.manager.disconnected(h.conns['b']!);
      h.clock.advance(const Duration(seconds: 60));
      expect(room.seats[1]!.forfeited, isTrue);
      expect(room.status, RoomStatus.finished);
    });

    test('a game with nobody left is abandoned without game_over', () async {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      h.manager.disconnected(h.conns['a']!);
      h.manager.disconnected(h.conns['b']!);
      h.clock.advance(const Duration(seconds: 61));
      expect(room.status, RoomStatus.finished);
      expect(h.conns['a']!.all<GameOverMessage>(), isEmpty);
      await h.manager.flush();
      expect(h.log.ends[room.matchId!]!.status, MatchStatus.abandoned);
      expect((await h.log.loadMatch(room.matchId!))!.serverSeed, isNotNull);
    });
  });

  group('live store', () {
    test('rooms are written through and restored after a restart', () async {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      for (var i = 0; i < 6; i++) {
        h.playOne(room);
      }
      await h.manager.flush();
      h.manager.dispose();

      // A new server process over the same stores.
      final h2 = Harness(live: h.live, log: h.log, clock: h.clock);
      expect(await h2.manager.restore(), 1);
      final restored = h2.manager.room(room.code)!;
      expect(restored.state, room.state);
      expect(restored.seq, room.seq);
      expect(restored.serverSeedHash, room.serverSeedHash);
      expect(restored.seated.every((s) => !s.connected), isTrue);

      final a = h2.connect('a');
      final b = h2.connect('b');
      h2.join(a, room.code);
      h2.join(b, room.code);
      expect(a.last<RoomStateMessage>().state, room.state);
      h2.playToEnd(restored);
      expect(restored.status, RoomStatus.finished);
      await h2.manager.flush();
      final stored = (await h2.log.loadMatch(room.matchId!))!;
      expect(
        verifyRolls(
          serverSeedHex: stored.serverSeed!,
          serverSeedHash: stored.serverSeedHash,
          clientSeed: stored.clientSeed,
          rolls: stored.rolls,
        ),
        isTrue,
      );
      expect(await h.live.loadAll(), isEmpty);
    });

    test('restored timers keep running', () async {
      final h = Harness();
      final room = h.openRoom(['a', 'b']);
      await h.manager.flush();
      h.manager.dispose();
      final h2 = Harness(live: h.live, log: h.log, clock: h.clock);
      await h2.manager.restore();
      h2.clock.advance(const Duration(seconds: 20));
      expect(h2.manager.room(room.code)!.state!.rollNumber, 1);
    });
  });
}

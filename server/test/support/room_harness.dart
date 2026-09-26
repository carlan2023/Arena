import 'dart:math';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_server/src/clock.dart';
import 'package:arena_server/src/rooms/room.dart';
import 'package:arena_server/src/rooms/room_manager.dart';
import 'package:arena_server/src/store/live_store.dart';
import 'package:arena_server/src/store/match_log.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Picks the first legal sequence; stands in for the bot in unit tests.
List<Move> firstSequence(GameState state) {
  final all = legalSequences(state);
  return all.isEmpty ? const [] : all.first;
}

class TestConnection extends Connection {
  TestConnection(String userId, {String? name})
    : super(userId: userId, displayName: name ?? 'Player $userId');

  final List<ServerMessage> inbox = [];
  bool closed = false;
  int _cseq = 0;

  @override
  void send(ServerMessage message) {
    // Round trip through JSON so tests check the wire format too.
    inbox.add(ServerMessage.decode(message.encode()));
  }

  @override
  void close() => closed = true;

  int nextCseq() => ++_cseq;

  List<T> all<T extends ServerMessage>() => inbox.whereType<T>().toList();

  T last<T extends ServerMessage>() => all<T>().last;

  ErrorMessage? get lastError {
    final errors = all<ErrorMessage>();
    return errors.isEmpty ? null : errors.last;
  }
}

class Harness {
  Harness({
    RoomSettings settings = const RoomSettings(),
    LiveRoomStore? live,
    InMemoryMatchLog? log,
    FakeClock? clock,
    int seed = 1,
  }) : clock = clock ?? FakeClock(),
       live = live ?? InMemoryLiveRoomStore(),
       log = log ?? InMemoryMatchLog() {
    manager = RoomManager(
      clock: this.clock,
      chooseMoves: firstSequence,
      settings: settings,
      liveStore: this.live,
      matchLog: this.log,
      random: Random(seed),
    );
  }

  final FakeClock clock;
  final LiveRoomStore live;
  final InMemoryMatchLog log;
  late final RoomManager manager;
  final Map<String, TestConnection> conns = {};

  TestConnection connect(String userId) =>
      conns[userId] = TestConnection(userId);

  void send(TestConnection c, ClientMessage Function(int cseq) build) =>
      manager.handle(c, build(c.nextCseq()));

  void join(TestConnection c, String code, {String? seed}) => send(
    c,
    (n) => JoinRoomMessage(roomCode: code, clientSeed: seed, cseq: n),
  );

  void roll(TestConnection c) => send(c, (n) => RollMessage(cseq: n));

  void move(TestConnection c, List<Move> moves) =>
      send(c, (n) => MoveMessage(moves: moves, cseq: n));

  /// Creates a room owned by the first user and seats everyone in order.
  Room openRoom(
    List<String> users, {
    GameMode mode = GameMode.oneVsOne,
    int? seats,
    int stake = 0,
  }) {
    final room = manager.createRoom(
      ownerUserId: users.first,
      mode: mode,
      seats: seats ?? users.length,
      stake: stake,
    );
    for (final u in users) {
      join(connect(u), room.code, seed: 'seed$u');
    }
    return room;
  }

  TestConnection currentConn(Room room) => conns[room.currentSeat!.userId]!;

  /// Plays the current decision as the player would.
  void playOne(Room room) {
    final c = currentConn(room);
    final state = room.state!;
    if (state.phase == TurnPhase.awaitingRoll) {
      roll(c);
    } else {
      move(c, firstSequence(state));
    }
  }

  void playToEnd(Room room, {int limit = 5000}) {
    for (var i = 0; i < limit && room.status == RoomStatus.playing; i++) {
      playOne(room);
    }
  }
}

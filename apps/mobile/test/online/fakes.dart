import 'dart:async';

import 'package:arena/online/api.dart';
import 'package:arena/online/auth.dart';
import 'package:arena/online/room_controller.dart';
import 'package:arena/online/socket.dart';
import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:ludo_engine/ludo_engine.dart';

const me = UserView(id: 'u1', phone: '+256772000001', displayName: 'Amina');
const them = UserView(id: 'u2', phone: '+256772000002', displayName: 'Brian');
const session = Session(token: 'tok-1', user: me);

class FakeApi implements ArenaApi {
  final calls = <String>[];
  UserView user = const UserView(
    id: 'u1',
    phone: '+256772000001',
    displayName: '',
  );
  RoomView? room;
  Object? failWith;

  @override
  Future<Session> login(String idToken) async {
    calls.add('login $idToken');
    if (failWith case final e?) throw e;
    return Session(token: 'tok-1', user: user);
  }

  @override
  Future<UserView> setDisplayName(String token, String name) async {
    calls.add('name $token $name');
    return user = UserView(id: user.id, phone: user.phone, displayName: name);
  }

  @override
  Future<RoomView> createRoom(
    String token, {
    required GameMode mode,
    required int seats,
  }) async {
    calls.add('create $token ${mode.name} $seats');
    return room ?? lobbyRoom();
  }

  @override
  Future<RoomView> getRoom(String token, String code) async => lobbyRoom();
}

class FakeSocket implements GameSocket {
  final _controller = StreamController<ServerMessage>();
  final sent = <ClientMessage>[];
  bool closed = false;

  @override
  Stream<ServerMessage> get messages => _controller.stream;

  @override
  void send(ClientMessage message) => sent.add(message);

  void receive(ServerMessage m) => _controller.add(m);

  /// The network drops.
  void drop() {
    closed = true;
    _controller.close();
  }

  @override
  Future<void> close() async {
    if (!closed) drop();
  }
}

/// Hands out sockets and records the tokens used.
class FakeConnector {
  final sockets = <FakeSocket>[];
  final tokens = <String>[];
  bool fail = false;

  FakeSocket get last => sockets.last;

  Future<GameSocket> call(String token) async {
    tokens.add(token);
    if (fail) throw StateError('no network');
    final s = FakeSocket();
    sockets.add(s);
    return s;
  }
}

List<Override> onlineOverrides(
  FakeConnector connector, {
  FakeApi? api,
  Session? session = session,
}) => [
  sessionStoreProvider.overrideWithValue(MemorySessionStore(session)),
  socketConnectorProvider.overrideWithValue(connector.call),
  arenaApiProvider.overrideWithValue(api ?? FakeApi()),
  onlineTimingsProvider.overrideWithValue(
    const OnlineTimings(
      autoPlay: Duration(milliseconds: 500),
      ping: Duration(seconds: 20),
      firstRetry: Duration(seconds: 1),
      maxRetry: Duration(seconds: 4),
    ),
  ),
];

const code = 'ABC234';

PlayerView player(
  int seat,
  UserView u, {
  PlayerColor? color,
  bool connected = true,
}) => PlayerView(
  seat: seat,
  userId: u.id,
  displayName: u.displayName,
  color: color,
  isBot: false,
  connected: connected,
);

RoomView lobbyRoom({List<PlayerView>? players, String owner = 'u1'}) =>
    RoomView(
      code: code,
      link: 'https://arena.example/r/$code',
      mode: GameMode.oneVsOne,
      seats: 2,
      stake: 0,
      status: RoomStatus.waiting,
      ownerUserId: owner,
      matchId: null,
      players: players ?? [player(0, me)],
    );

RoomView playingRoom() => RoomView(
  code: code,
  link: 'https://arena.example/r/$code',
  mode: GameMode.oneVsOne,
  seats: 2,
  stake: 0,
  status: RoomStatus.playing,
  ownerUserId: 'u1',
  matchId: 'm1',
  players: [
    player(0, me, color: PlayerColor.red),
    player(1, them, color: PlayerColor.yellow),
  ],
);

int get now => DateTime.now().millisecondsSinceEpoch;

RoomStateMessage lobbyState({int seq = 1, RoomView? room}) => RoomStateMessage(
  seq: seq,
  room: room ?? lobbyRoom(),
  state: null,
  deadline: null,
  serverSeedHash: 'abc',
  you: const YouInfo(seat: 0),
  serverNow: now,
);

GameState newGame() => GameState.newGame(
  mode: GameMode.oneVsOne,
  players: const [PlayerColor.red, PlayerColor.yellow],
);

RoomStateMessage gameState({int seq = 3, GameState? state}) => RoomStateMessage(
  seq: seq,
  room: playingRoom(),
  state: state ?? newGame(),
  deadline: now + 20000,
  serverSeedHash: 'abc',
  you: const YouInfo(seat: 0, color: PlayerColor.red),
  serverNow: now,
);

DiceMessage dice(int seq, GameState before, int a, int b, {bool auto = false}) {
  final after = applyRoll(before, a, b);
  return DiceMessage(
    seq: seq,
    color: before.current,
    values: (a, b),
    rollNumber: before.rollNumber,
    legalMoves: legalMoves(after),
    state: after,
    deadline: now + 20000,
    auto: auto,
    serverNow: now,
  );
}

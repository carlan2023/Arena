import 'package:arena_protocol/arena_protocol.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  final state = GameState.newGame(
    mode: GameMode.oneVsOne,
    players: const [PlayerColor.red, PlayerColor.yellow],
  );
  const room = RoomView(
    code: 'ABC234',
    link: 'http://localhost/r/ABC234',
    mode: GameMode.oneVsOne,
    seats: 2,
    stake: 0,
    status: RoomStatus.playing,
    ownerUserId: 'u1',
    matchId: 'm1',
    players: [
      PlayerView(
        seat: 0,
        userId: 'u1',
        displayName: 'A',
        color: PlayerColor.red,
        isBot: false,
        connected: true,
      ),
      PlayerView(
        seat: 1,
        userId: 'u2',
        displayName: 'B',
        color: null,
        isBot: true,
        connected: false,
      ),
    ],
  );

  String roundTripServer(ServerMessage m) =>
      ServerMessage.decode(m.encode()).encode();
  String roundTripClient(ClientMessage m) =>
      ClientMessage.decode(m.encode()).encode();

  test('client messages round trip', () {
    final messages = <ClientMessage>[
      const JoinRoomMessage(
        roomCode: 'ABC234',
        clientSeed: 's',
        lastSeq: 3,
        cseq: 1,
      ),
      const JoinRoomMessage(roomCode: 'ABC234'),
      const StartGameMessage(cseq: 2),
      const RollMessage(cseq: 3),
      MoveMessage(
        moves: [
          Move.release(PlayerColor.red, 0),
          Move.advance(PlayerColor.red, 0, 3),
        ],
        cseq: 4,
      ),
      const LeaveRoomMessage(cseq: 5),
      const EmoteMessage(id: 'wave', cseq: 6),
      const PingMessage(cseq: 7),
    ];
    for (final m in messages) {
      expect(roundTripClient(m), m.encode());
      expect(ClientMessage.decode(m.encode()).runtimeType, m.runtimeType);
    }
    final move = ClientMessage.decode(messages[4].encode()) as MoveMessage;
    expect(move.moves.first, Move.release(PlayerColor.red, 0));
  });

  test('server messages round trip', () {
    final messages = <ServerMessage>[
      RoomStateMessage(
        seq: 1,
        ref: 2,
        room: room,
        state: state,
        deadline: 1000,
        serverSeedHash: 'ab',
        you: const YouInfo(seat: 0, color: PlayerColor.red),
        serverNow: 5,
      ),
      RoomStateMessage(
        seq: 1,
        room: room,
        state: null,
        deadline: null,
        serverSeedHash: null,
        you: const YouInfo(seat: 1),
        serverNow: 5,
      ),
      DiceMessage(
        seq: 2,
        color: PlayerColor.red,
        values: (6, 3),
        rollNumber: 0,
        legalMoves: [Move.release(PlayerColor.red, 0)],
        state: state,
        deadline: 9,
        auto: false,
        serverNow: 5,
      ),
      StatePatchMessage(
        seq: 3,
        color: PlayerColor.red,
        moves: [Move.pass(PlayerColor.red)],
        captured: const [PieceRef(PlayerColor.yellow, 2)],
        state: state,
        deadline: null,
        auto: true,
        serverNow: 5,
      ),
      const PlayerStatusMessage(
        seq: 4,
        seat: 1,
        connected: false,
        graceDeadline: 60,
        isBot: false,
      ),
      const EmoteEvent(seq: 5, seat: 0, id: 'wave'),
      const GameOverMessage(
        seq: 6,
        matchId: 'm1',
        ranking: [PlayerColor.red, PlayerColor.yellow],
        winners: [PlayerColor.red],
        serverSeed: 'aa',
        clientSeed: '0:1',
        walletDelta: {'u1': 10},
      ),
      const ErrorMessage(ref: 3, code: ErrorCodes.illegalMove, message: 'no'),
      const PongMessage(ref: 7, serverNow: 5),
    ];
    for (final m in messages) {
      expect(roundTripServer(m), m.encode());
      expect(ServerMessage.decode(m.encode()).runtimeType, m.runtimeType);
    }
    final rs = ServerMessage.decode(messages[0].encode()) as RoomStateMessage;
    expect(rs.state, state);
    expect(rs.room.players[1].isBot, isTrue);
  });

  test('unknown server types are kept as UnknownServerMessage', () {
    final m = ServerMessage.decode('{"type":"future_thing","x":1}');
    expect(m, isA<UnknownServerMessage>());
  });

  test('bad input throws ProtocolException', () {
    for (final bad in [
      'not json',
      '[]',
      '{}',
      '{"type":"nope"}',
      '{"type":"join_room"}',
      '{"type":"join_room","roomCode":5}',
      '{"type":"move","moves":[{"k":"zzz"}]}',
      '{"type":"emote","cseq":"x","id":"a"}',
    ]) {
      expect(
        () => ClientMessage.decode(bad),
        throwsA(isA<ProtocolException>()),
        reason: bad,
      );
    }
    for (final bad in [
      '{"type":"dice","seq":1}',
      '{"type":"room_state","seq":1,"room":{}}',
      '{"type":"game_over","seq":1,"matchId":"m","ranking":["pink"],'
          '"winners":[],"serverSeed":"","clientSeed":"","walletDelta":{}}',
    ]) {
      expect(
        () => ServerMessage.decode(bad),
        throwsA(isA<ProtocolException>()),
        reason: bad,
      );
    }
  });

  test('models round trip', () {
    expect(RoomView.fromJson(room.toJson()).toJson(), room.toJson());
    final p = PaymentView(
      id: 'p',
      provider: 'fake',
      amount: 500,
      status: 'pending',
      createdAt: DateTime.utc(2026, 9, 25),
    );
    expect(PaymentView.fromJson(p.toJson()).toJson(), p.toJson());
    final w = WalletEntryView(
      txId: 't',
      kind: 'deposit',
      amount: 500,
      balanceAfter: 500,
      at: DateTime.utc(2026, 9, 25),
    );
    expect(WalletEntryView.fromJson(w.toJson()).toJson(), w.toJson());
    const v = MatchVerification(
      serverSeed: 'a',
      serverSeedHash: 'b',
      clientSeed: 'c',
      rolls: [(1, 2), (6, 6)],
    );
    expect(MatchVerification.fromJson(v.toJson()).rolls, v.rolls);
  });
}

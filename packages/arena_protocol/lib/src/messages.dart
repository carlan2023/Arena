import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';

import 'json.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// App to server
// ---------------------------------------------------------------------------

/// A message from the app. [cseq] is the client's per message counter, echoed
/// by the server as `ref`.
sealed class ClientMessage {
  const ClientMessage({this.cseq});

  final int? cseq;

  String get type;

  Json fieldsToJson() => const {};

  Json toJson() => {'type': type, 'cseq': ?cseq, ...fieldsToJson()};

  String encode() => jsonEncode(toJson());

  /// Parses one frame. Throws [ProtocolException] on bad input or an unknown
  /// type.
  static ClientMessage decode(String text) => fromJson(decodeObject(text));

  static ClientMessage fromJson(Json j) {
    final type = reqString(j, 'type');
    final cseq = optInt(j, 'cseq');
    return switch (type) {
      JoinRoomMessage.kType => JoinRoomMessage(
        roomCode: reqString(j, 'roomCode'),
        clientSeed: optString(j, 'clientSeed'),
        lastSeq: optInt(j, 'lastSeq'),
        cseq: cseq,
      ),
      StartGameMessage.kType => StartGameMessage(cseq: cseq),
      RollMessage.kType => RollMessage(cseq: cseq),
      MoveMessage.kType => MoveMessage(
        moves: parseMoves(j, 'moves'),
        cseq: cseq,
      ),
      LeaveRoomMessage.kType => LeaveRoomMessage(cseq: cseq),
      EmoteMessage.kType => EmoteMessage(id: reqString(j, 'id'), cseq: cseq),
      PingMessage.kType => PingMessage(cseq: cseq),
      _ => throw ProtocolException('unknown message type $type'),
    };
  }
}

class JoinRoomMessage extends ClientMessage {
  const JoinRoomMessage({
    required this.roomCode,
    this.clientSeed,
    this.lastSeq,
    super.cseq,
  });
  static const kType = 'join_room';
  final String roomCode;
  final String? clientSeed;
  final int? lastSeq;
  @override
  String get type => kType;
  @override
  Json fieldsToJson() => {
    'roomCode': roomCode,
    'clientSeed': ?clientSeed,
    'lastSeq': ?lastSeq,
  };
}

class StartGameMessage extends ClientMessage {
  const StartGameMessage({super.cseq});
  static const kType = 'start_game';
  @override
  String get type => kType;
}

class RollMessage extends ClientMessage {
  const RollMessage({super.cseq});
  static const kType = 'roll';
  @override
  String get type => kType;
}

class MoveMessage extends ClientMessage {
  const MoveMessage({required this.moves, super.cseq});
  static const kType = 'move';

  /// Every step of the current roll, in order.
  final List<Move> moves;
  @override
  String get type => kType;
  @override
  Json fieldsToJson() => {
    'moves': [for (final m in moves) m.toJson()],
  };
}

class LeaveRoomMessage extends ClientMessage {
  const LeaveRoomMessage({super.cseq});
  static const kType = 'leave_room';
  @override
  String get type => kType;
}

class EmoteMessage extends ClientMessage {
  const EmoteMessage({required this.id, super.cseq});
  static const kType = 'emote';
  final String id;
  @override
  String get type => kType;
  @override
  Json fieldsToJson() => {'id': id};
}

class PingMessage extends ClientMessage {
  const PingMessage({super.cseq});
  static const kType = 'ping';
  @override
  String get type => kType;
}

// ---------------------------------------------------------------------------
// Server to app
// ---------------------------------------------------------------------------

/// A message from the server. Room events carry [seq]; direct replies do not.
sealed class ServerMessage {
  const ServerMessage();

  String get type;

  Json toJson();

  String encode() => jsonEncode(toJson());

  /// Parses one frame. Unknown types come back as [UnknownServerMessage] so
  /// the client can ignore them. Throws [ProtocolException] on bad input.
  static ServerMessage decode(String text) => fromJson(decodeObject(text));

  static ServerMessage fromJson(Json j) {
    final type = reqString(j, 'type');
    return switch (type) {
      RoomStateMessage.kType => RoomStateMessage.fromJson(j),
      DiceMessage.kType => DiceMessage.fromJson(j),
      StatePatchMessage.kType => StatePatchMessage.fromJson(j),
      PlayerStatusMessage.kType => PlayerStatusMessage.fromJson(j),
      EmoteEvent.kType => EmoteEvent.fromJson(j),
      GameOverMessage.kType => GameOverMessage.fromJson(j),
      ErrorMessage.kType => ErrorMessage.fromJson(j),
      PongMessage.kType => PongMessage.fromJson(j),
      _ => UnknownServerMessage(type, j),
    };
  }
}

/// A server message this version does not know.
class UnknownServerMessage extends ServerMessage {
  const UnknownServerMessage(this.type, this.json);
  @override
  final String type;
  final Json json;
  @override
  Json toJson() => json;
}

/// The recipient's own seat and colour.
class YouInfo {
  const YouInfo({required this.seat, this.color});
  final int seat;
  final PlayerColor? color;
  Json toJson() => {'seat': seat, 'color': color?.name};
  factory YouInfo.fromJson(Json j) =>
      YouInfo(seat: reqInt(j, 'seat'), color: optColor(j, 'color'));
}

/// Full snapshot of a room.
class RoomStateMessage extends ServerMessage {
  const RoomStateMessage({
    required this.seq,
    required this.room,
    required this.state,
    required this.deadline,
    required this.serverSeedHash,
    required this.you,
    required this.serverNow,
    this.ref,
  });
  static const kType = 'room_state';
  final int seq;
  final RoomView room;
  final GameState? state;
  final int? deadline;
  final String? serverSeedHash;
  final YouInfo you;
  final int serverNow;

  /// The cseq of the join_room this answers, if any.
  final int? ref;

  @override
  String get type => kType;
  @override
  Json toJson() => {
    'type': type,
    'seq': seq,
    'ref': ?ref,
    'room': room.toJson(),
    'state': state?.toJson(),
    'deadline': deadline,
    'serverSeedHash': serverSeedHash,
    'you': you.toJson(),
    'serverNow': serverNow,
  };
  factory RoomStateMessage.fromJson(Json j) => RoomStateMessage(
    seq: reqInt(j, 'seq'),
    ref: optInt(j, 'ref'),
    room: RoomView.fromJson(asObject(j['room'], 'room')),
    state: optState(j, 'state'),
    deadline: optInt(j, 'deadline'),
    serverSeedHash: optString(j, 'serverSeedHash'),
    you: YouInfo.fromJson(asObject(j['you'], 'you')),
    serverNow: reqInt(j, 'serverNow'),
  );
}

class DiceMessage extends ServerMessage {
  const DiceMessage({
    required this.seq,
    required this.color,
    required this.values,
    required this.rollNumber,
    required this.legalMoves,
    required this.state,
    required this.deadline,
    required this.auto,
    required this.serverNow,
  });
  static const kType = 'dice';
  final int seq;
  final PlayerColor color;
  final (int, int) values;
  final int rollNumber;
  final List<Move> legalMoves;
  final GameState state;
  final int deadline;
  final bool auto;
  final int serverNow;

  @override
  String get type => kType;
  @override
  Json toJson() => {
    'type': type,
    'seq': seq,
    'color': color.name,
    'values': [values.$1, values.$2],
    'rollNumber': rollNumber,
    'legalMoves': [for (final m in legalMoves) m.toJson()],
    'state': state.toJson(),
    'deadline': deadline,
    'auto': auto,
    'serverNow': serverNow,
  };
  factory DiceMessage.fromJson(Json j) {
    final v = reqIntList(j, 'values');
    if (v.length != 2) throw ProtocolException('values must hold two dice');
    return DiceMessage(
      seq: reqInt(j, 'seq'),
      color: parseColor(reqString(j, 'color')),
      values: (v[0], v[1]),
      rollNumber: reqInt(j, 'rollNumber'),
      legalMoves: parseMoves(j, 'legalMoves'),
      state: parseState(j['state'], 'state'),
      deadline: reqInt(j, 'deadline'),
      auto: reqBool(j, 'auto'),
      serverNow: reqInt(j, 'serverNow'),
    );
  }
}

class StatePatchMessage extends ServerMessage {
  const StatePatchMessage({
    required this.seq,
    required this.color,
    required this.moves,
    required this.captured,
    required this.state,
    required this.deadline,
    required this.auto,
    required this.serverNow,
  });
  static const kType = 'state_patch';
  final int seq;
  final PlayerColor color;
  final List<Move> moves;
  final List<PieceRef> captured;
  final GameState state;
  final int? deadline;
  final bool auto;
  final int serverNow;

  @override
  String get type => kType;
  @override
  Json toJson() => {
    'type': type,
    'seq': seq,
    'color': color.name,
    'moves': [for (final m in moves) m.toJson()],
    'captured': [for (final c in captured) c.toJson()],
    'state': state.toJson(),
    'deadline': deadline,
    'auto': auto,
    'serverNow': serverNow,
  };
  factory StatePatchMessage.fromJson(Json j) => StatePatchMessage(
    seq: reqInt(j, 'seq'),
    color: parseColor(reqString(j, 'color')),
    moves: parseMoves(j, 'moves'),
    captured: [
      for (final c in reqList(j, 'captured'))
        engineValue(
          'captured',
          () => PieceRef.fromJson(asObject(c, 'captured')),
        ),
    ],
    state: parseState(j['state'], 'state'),
    deadline: optInt(j, 'deadline'),
    auto: reqBool(j, 'auto'),
    serverNow: reqInt(j, 'serverNow'),
  );
}

class PlayerStatusMessage extends ServerMessage {
  const PlayerStatusMessage({
    required this.seq,
    required this.seat,
    required this.connected,
    required this.graceDeadline,
    required this.isBot,
  });
  static const kType = 'player_status';
  final int seq;
  final int seat;
  final bool connected;
  final int? graceDeadline;
  final bool isBot;

  @override
  String get type => kType;
  @override
  Json toJson() => {
    'type': type,
    'seq': seq,
    'seat': seat,
    'connected': connected,
    'graceDeadline': graceDeadline,
    'isBot': isBot,
  };
  factory PlayerStatusMessage.fromJson(Json j) => PlayerStatusMessage(
    seq: reqInt(j, 'seq'),
    seat: reqInt(j, 'seat'),
    connected: reqBool(j, 'connected'),
    graceDeadline: optInt(j, 'graceDeadline'),
    isBot: reqBool(j, 'isBot'),
  );
}

/// An emote relayed to the room.
class EmoteEvent extends ServerMessage {
  const EmoteEvent({required this.seq, required this.seat, required this.id});
  static const kType = 'emote';
  final int seq;
  final int seat;
  final String id;
  @override
  String get type => kType;
  @override
  Json toJson() => {'type': type, 'seq': seq, 'seat': seat, 'id': id};
  factory EmoteEvent.fromJson(Json j) => EmoteEvent(
    seq: reqInt(j, 'seq'),
    seat: reqInt(j, 'seat'),
    id: reqString(j, 'id'),
  );
}

class GameOverMessage extends ServerMessage {
  const GameOverMessage({
    required this.seq,
    required this.matchId,
    required this.ranking,
    required this.winners,
    required this.serverSeed,
    required this.clientSeed,
    required this.walletDelta,
  });
  static const kType = 'game_over';
  final int seq;
  final String matchId;
  final List<PlayerColor> ranking;
  final List<PlayerColor> winners;

  /// Hex of the revealed server seed.
  final String serverSeed;
  final String clientSeed;

  /// userId to wallet change. Empty for free games.
  final Map<String, int> walletDelta;

  @override
  String get type => kType;
  @override
  Json toJson() => {
    'type': type,
    'seq': seq,
    'matchId': matchId,
    'ranking': [for (final c in ranking) c.name],
    'winners': [for (final c in winners) c.name],
    'serverSeed': serverSeed,
    'clientSeed': clientSeed,
    'walletDelta': walletDelta,
  };
  factory GameOverMessage.fromJson(Json j) {
    final delta = asObject(j['walletDelta'], 'walletDelta');
    return GameOverMessage(
      seq: reqInt(j, 'seq'),
      matchId: reqString(j, 'matchId'),
      ranking: [for (final s in reqStringList(j, 'ranking')) parseColor(s)],
      winners: [for (final s in reqStringList(j, 'winners')) parseColor(s)],
      serverSeed: reqString(j, 'serverSeed'),
      clientSeed: reqString(j, 'clientSeed'),
      walletDelta: {
        for (final e in delta.entries)
          e.key: e.value is int
              ? e.value as int
              : throw ProtocolException('walletDelta values must be integers'),
      },
    );
  }
}

/// Error codes used in [ErrorMessage] and HTTP error bodies.
abstract final class ErrorCodes {
  static const badRequest = 'bad_request';
  static const unauthorized = 'unauthorized';
  static const roomNotFound = 'room_not_found';
  static const roomFull = 'room_full';
  static const alreadyStarted = 'already_started';
  static const notInRoom = 'not_in_room';
  static const notYourTurn = 'not_your_turn';
  static const wrongPhase = 'wrong_phase';
  static const illegalMove = 'illegal_move';
  static const notOwner = 'not_owner';
  static const rateLimited = 'rate_limited';
  static const paidTablesDisabled = 'paid_tables_disabled';
  static const insufficientFunds = 'insufficient_funds';
  static const internal = 'internal';
}

class ErrorMessage extends ServerMessage {
  const ErrorMessage({required this.code, required this.message, this.ref});
  static const kType = 'error';
  final int? ref;
  final String code;
  final String message;
  @override
  String get type => kType;
  @override
  Json toJson() => {'type': type, 'ref': ref, 'code': code, 'message': message};
  factory ErrorMessage.fromJson(Json j) => ErrorMessage(
    ref: optInt(j, 'ref'),
    code: reqString(j, 'code'),
    message: reqString(j, 'message'),
  );
}

class PongMessage extends ServerMessage {
  const PongMessage({this.ref, required this.serverNow});
  static const kType = 'pong';
  final int? ref;
  final int serverNow;
  @override
  String get type => kType;
  @override
  Json toJson() => {'type': type, 'ref': ref, 'serverNow': serverNow};
  factory PongMessage.fromJson(Json j) =>
      PongMessage(ref: optInt(j, 'ref'), serverNow: reqInt(j, 'serverNow'));
}

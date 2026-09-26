import 'package:ludo_engine/ludo_engine.dart';

import 'json.dart';

/// `User` in the protocol.
class UserView {
  const UserView({
    required this.id,
    required this.phone,
    required this.displayName,
  });

  final String id;
  final String phone;
  final String displayName;

  Json toJson() => {'id': id, 'phone': phone, 'displayName': displayName};

  factory UserView.fromJson(Json j) => UserView(
    id: reqString(j, 'id'),
    phone: reqString(j, 'phone'),
    displayName: reqString(j, 'displayName'),
  );
}

/// One entry of `Room.players`.
class PlayerView {
  const PlayerView({
    required this.seat,
    required this.userId,
    required this.displayName,
    required this.color,
    required this.isBot,
    required this.connected,
  });

  final int seat;
  final String userId;
  final String displayName;

  /// Null in the lobby; colours are given at the start.
  final PlayerColor? color;
  final bool isBot;
  final bool connected;

  Json toJson() => {
    'seat': seat,
    'userId': userId,
    'displayName': displayName,
    'color': color?.name,
    'isBot': isBot,
    'connected': connected,
  };

  factory PlayerView.fromJson(Json j) => PlayerView(
    seat: reqInt(j, 'seat'),
    userId: reqString(j, 'userId'),
    displayName: reqString(j, 'displayName'),
    color: optColor(j, 'color'),
    isBot: reqBool(j, 'isBot'),
    connected: reqBool(j, 'connected'),
  );
}

enum RoomStatus { waiting, playing, finished }

/// `Room` in the protocol.
class RoomView {
  const RoomView({
    required this.code,
    required this.link,
    required this.mode,
    required this.seats,
    required this.stake,
    required this.status,
    required this.ownerUserId,
    required this.matchId,
    required this.players,
  });

  final String code;
  final String link;
  final GameMode mode;
  final int seats;
  final int stake;
  final RoomStatus status;
  final String ownerUserId;

  /// Null before the start.
  final String? matchId;
  final List<PlayerView> players;

  Json toJson() => {
    'code': code,
    'link': link,
    'mode': mode.name,
    'seats': seats,
    'stake': stake,
    'status': status.name,
    'ownerUserId': ownerUserId,
    'matchId': matchId,
    'players': [for (final p in players) p.toJson()],
  };

  factory RoomView.fromJson(Json j) => RoomView(
    code: reqString(j, 'code'),
    link: reqString(j, 'link'),
    mode: parseMode(reqString(j, 'mode')),
    seats: reqInt(j, 'seats'),
    stake: reqInt(j, 'stake'),
    status: _parseEnum(RoomStatus.values, reqString(j, 'status'), 'status'),
    ownerUserId: reqString(j, 'ownerUserId'),
    matchId: optString(j, 'matchId'),
    players: [
      for (final p in reqList(j, 'players'))
        PlayerView.fromJson(asObject(p, 'players')),
    ],
  );
}

GameMode parseMode(String name) => _parseEnum(GameMode.values, name, 'mode');

T _parseEnum<T extends Enum>(List<T> values, String name, String key) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw ProtocolException('unknown $key $name');
}

/// `Payment` in the protocol.
class PaymentView {
  const PaymentView({
    required this.id,
    required this.provider,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String provider;
  final int amount;

  /// pending, succeeded or failed.
  final String status;
  final DateTime createdAt;

  Json toJson() => {
    'id': id,
    'provider': provider,
    'amount': amount,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory PaymentView.fromJson(Json j) => PaymentView(
    id: reqString(j, 'id'),
    provider: reqString(j, 'provider'),
    amount: reqInt(j, 'amount'),
    status: reqString(j, 'status'),
    createdAt: _parseDate(reqString(j, 'createdAt')),
  );
}

/// `WalletEntry` in the protocol.
class WalletEntryView {
  const WalletEntryView({
    required this.txId,
    required this.kind,
    required this.amount,
    required this.balanceAfter,
    required this.at,
  });

  final String txId;
  final String kind;
  final int amount;
  final int balanceAfter;
  final DateTime at;

  Json toJson() => {
    'txId': txId,
    'kind': kind,
    'amount': amount,
    'balanceAfter': balanceAfter,
    'at': at.toUtc().toIso8601String(),
  };

  factory WalletEntryView.fromJson(Json j) => WalletEntryView(
    txId: reqString(j, 'txId'),
    kind: reqString(j, 'kind'),
    amount: reqInt(j, 'amount'),
    balanceAfter: reqInt(j, 'balanceAfter'),
    at: _parseDate(reqString(j, 'at')),
  );
}

/// Result of GET /v1/matches/{id}/verify.
class MatchVerification {
  const MatchVerification({
    required this.serverSeed,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.rolls,
  });

  final String serverSeed;
  final String serverSeedHash;
  final String clientSeed;
  final List<(int, int)> rolls;

  Json toJson() => {
    'serverSeed': serverSeed,
    'serverSeedHash': serverSeedHash,
    'clientSeed': clientSeed,
    'rolls': [
      for (final (a, b) in rolls) [a, b],
    ],
  };

  factory MatchVerification.fromJson(Json j) => MatchVerification(
    serverSeed: reqString(j, 'serverSeed'),
    serverSeedHash: reqString(j, 'serverSeedHash'),
    clientSeed: reqString(j, 'clientSeed'),
    rolls: [
      for (final r in reqList(j, 'rolls'))
        if (r is List && r.length == 2 && r[0] is int && r[1] is int)
          (r[0] as int, r[1] as int)
        else
          throw ProtocolException('rolls must hold pairs of integers'),
    ],
  );
}

/// HTTP error body `{"error": {"code", "message"}}`.
class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  Json toJson() => {
    'error': {'code': code, 'message': message},
  };

  @override
  String toString() => 'ApiError($status $code: $message)';
}

DateTime _parseDate(String s) {
  final d = DateTime.tryParse(s);
  if (d == null) throw ProtocolException('bad date $s');
  return d;
}

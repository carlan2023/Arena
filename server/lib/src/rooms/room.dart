import 'dart:typed_data';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_protocol/fair_dice.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../clock.dart';

/// One open web socket, as the room manager sees it.
abstract class Connection {
  Connection({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  /// Code of the room this socket is bound to by join_room.
  String? roomCode;

  void send(ServerMessage message);

  /// Closes the socket from the server side.
  void close();
}

/// A seat taken by a player.
class Seat {
  Seat({
    required this.index,
    required this.userId,
    required this.displayName,
    this.clientSeed,
  });

  final int index;
  final String userId;
  String displayName;
  final String? clientSeed;

  PlayerColor? color;
  bool isBot = false;

  /// True once a bot has played this seat, for the match log.
  bool everBot = false;
  bool connected = false;
  bool forfeited = false;
  int timeouts = 0;
  int? graceDeadline;

  TimerHandle? graceTimer;
  Connection? connection;

  Json toSnapshot() => {
    'index': index,
    'userId': userId,
    'displayName': displayName,
    'clientSeed': clientSeed,
    'color': color?.name,
    'isBot': isBot,
    'everBot': everBot,
    'forfeited': forfeited,
    'timeouts': timeouts,
  };

  factory Seat.fromSnapshot(Json j) {
    final s = Seat(
      index: j['index'] as int,
      userId: j['userId'] as String,
      displayName: j['displayName'] as String,
      clientSeed: j['clientSeed'] as String?,
    );
    final color = j['color'] as String?;
    s.color = color == null ? null : PlayerColor.values.byName(color);
    s.isBot = j['isBot'] as bool;
    s.everBot = j['everBot'] as bool;
    s.forfeited = j['forfeited'] as bool;
    s.timeouts = j['timeouts'] as int;
    return s;
  }
}

class Room {
  Room({
    required this.id,
    required this.code,
    required this.ownerUserId,
    required this.mode,
    required this.seatCount,
    required this.stake,
    required this.rules,
    required this.serverSeed,
    required this.createdAtMs,
  }) : serverSeedHash = hashServerSeed(serverSeed),
       seats = List<Seat?>.filled(seatCount, null);

  final String id;
  final String code;
  String ownerUserId;
  final GameMode mode;
  final int seatCount;
  final int stake;
  final RulesConfig rules;
  final Uint8List serverSeed;
  final String serverSeedHash;
  final int createdAtMs;

  RoomStatus status = RoomStatus.waiting;
  final List<Seat?> seats;

  /// Set at the start.
  String? clientSeed;
  String? matchId;
  GameState? state;

  /// Per room event counter; +1 for every broadcast.
  int seq = 0;

  /// Epoch ms when the current decision times out.
  int? deadline;

  /// Next index in the match's move log.
  int eventIndex = 0;

  /// Bumped whenever the current decision changes, so stale timers do nothing.
  int decisionId = 0;
  TimerHandle? decisionTimer;
  TimerHandle? botTimer;
  TimerHandle? idleTimer;

  bool get isPaid => stake > 0;

  Iterable<Seat> get seated => seats.whereType<Seat>();

  Seat? seatOfUser(String userId) {
    for (final s in seated) {
      if (s.userId == userId) return s;
    }
    return null;
  }

  Seat? seatOfColor(PlayerColor color) {
    for (final s in seated) {
      if (s.color == color) return s;
    }
    return null;
  }

  /// The seat whose decision it is, while playing.
  Seat? get currentSeat {
    final s = state;
    if (status != RoomStatus.playing || s == null) return null;
    return seatOfColor(s.current);
  }

  void cancelTimers() {
    decisionId++;
    decisionTimer?.cancel();
    botTimer?.cancel();
    idleTimer?.cancel();
    decisionTimer = botTimer = idleTimer = null;
    for (final s in seated) {
      s.graceTimer?.cancel();
      s.graceTimer = null;
    }
  }

  RoomView view(String publicBaseUrl) => RoomView(
    code: code,
    link: '$publicBaseUrl/r/$code',
    mode: mode,
    seats: seatCount,
    stake: stake,
    status: status,
    ownerUserId: ownerUserId,
    matchId: matchId,
    players: [
      for (final s in seated)
        PlayerView(
          seat: s.index,
          userId: s.userId,
          displayName: s.displayName,
          color: s.color,
          isBot: s.isBot,
          connected: s.connected,
        ),
    ],
  );

  /// Everything needed to rebuild the room after a restart. Holds the secret
  /// server seed, so it must only go to the live store.
  Json toSnapshot() => {
    'v': 1,
    'id': id,
    'code': code,
    'ownerUserId': ownerUserId,
    'mode': mode.name,
    'seatCount': seatCount,
    'stake': stake,
    'rules': rules.toJson(),
    'serverSeed': toHex(serverSeed),
    'createdAtMs': createdAtMs,
    'status': status.name,
    'seats': [for (final s in seats) s?.toSnapshot()],
    'clientSeed': clientSeed,
    'matchId': matchId,
    'state': state?.toJson(),
    'seq': seq,
    'deadline': deadline,
    'eventIndex': eventIndex,
  };

  factory Room.fromSnapshot(Json j) {
    final room = Room(
      id: j['id'] as String,
      code: j['code'] as String,
      ownerUserId: j['ownerUserId'] as String,
      mode: GameMode.values.byName(j['mode'] as String),
      seatCount: j['seatCount'] as int,
      stake: j['stake'] as int,
      rules: RulesConfig.fromJson((j['rules'] as Map).cast()),
      serverSeed: fromHex(j['serverSeed'] as String),
      createdAtMs: j['createdAtMs'] as int,
    );
    room.status = RoomStatus.values.byName(j['status'] as String);
    final seats = j['seats'] as List;
    for (var i = 0; i < seats.length && i < room.seatCount; i++) {
      final s = seats[i];
      if (s != null) room.seats[i] = Seat.fromSnapshot((s as Map).cast());
    }
    room.clientSeed = j['clientSeed'] as String?;
    room.matchId = j['matchId'] as String?;
    final state = j['state'];
    room.state = state == null
        ? null
        : GameState.fromJson((state as Map).cast());
    room.seq = j['seq'] as int;
    room.deadline = j['deadline'] as int?;
    room.eventIndex = j['eventIndex'] as int;
    return room;
  }
}

/// Colours by number of players (protocol: seats and colours).
List<PlayerColor> colorsFor(int players) => switch (players) {
  2 => const [PlayerColor.red, PlayerColor.yellow],
  3 => const [PlayerColor.red, PlayerColor.green, PlayerColor.yellow],
  4 => PlayerColor.values,
  _ => throw ArgumentError.value(players, 'players'),
};

/// Whether [mode] allows a table of [seats].
bool validSeats(GameMode mode, int seats) => switch (mode) {
  GameMode.oneVsOne => seats == 2,
  GameMode.teams => seats == 4,
  GameMode.freeForAll => seats >= 2 && seats <= 4,
};

/// Whether a room of [mode] may start with [players] seated.
bool canStart(GameMode mode, int seats, int players) => switch (mode) {
  GameMode.oneVsOne => players == 2,
  GameMode.teams => players == 4,
  GameMode.freeForAll => players >= 2 && players <= seats,
};

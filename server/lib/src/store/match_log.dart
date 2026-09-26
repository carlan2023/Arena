import 'package:arena_protocol/arena_protocol.dart' show Json;

/// A room as first created.
class RoomRecord {
  const RoomRecord({
    required this.id,
    required this.code,
    required this.mode,
    required this.seats,
    required this.stake,
    required this.rules,
    required this.ownerUserId,
    required this.createdAt,
  });
  final String id;
  final String code;
  final String mode;
  final int seats;
  final int stake;
  final Json rules;
  final String ownerUserId;
  final DateTime createdAt;
}

class MatchPlayerRecord {
  const MatchPlayerRecord({
    required this.seat,
    required this.userId,
    required this.color,
  });
  final int seat;
  final String userId;
  final String color;
}

class MatchStartRecord {
  const MatchStartRecord({
    required this.matchId,
    required this.roomId,
    required this.mode,
    required this.rules,
    required this.stake,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.startedAt,
    required this.players,
  });
  final String matchId;
  final String roomId;
  final String mode;
  final Json rules;
  final int stake;
  final String serverSeedHash;
  final String clientSeed;
  final DateTime startedAt;
  final List<MatchPlayerRecord> players;
}

/// Kinds of logged match events.
abstract final class EventKinds {
  /// data: {"values": [a, b], "rollNumber": n}
  static const roll = 'roll';

  /// data: {"moves": [Move JSON], "captured": [PieceRef JSON]}
  static const move = 'move';

  /// data: {"reason": "leave" | "timeouts" | "grace"}
  static const forfeit = 'forfeit';

  /// A bot took the seat. data: {"reason": "timeouts" | "grace"}
  static const botTakeover = 'bot_takeover';

  /// The player took the seat back from the bot.
  static const botRelease = 'bot_release';
}

/// One entry of a match's move log. [index] counts from 0 per match.
class MatchEventRecord {
  const MatchEventRecord({
    required this.matchId,
    required this.index,
    required this.kind,
    required this.seat,
    required this.color,
    required this.data,
    required this.auto,
    required this.at,
  });
  final String matchId;
  final int index;
  final String kind;
  final int seat;
  final String color;
  final Json data;
  final bool auto;
  final DateTime at;
}

enum MatchStatus { playing, finished, abandoned }

class MatchEndRecord {
  const MatchEndRecord({
    required this.matchId,
    required this.status,
    required this.serverSeedHex,
    required this.endedAt,
    required this.places,
    required this.forfeitedSeats,
    required this.botSeats,
  });
  final String matchId;
  final MatchStatus status;
  final String serverSeedHex;
  final DateTime endedAt;

  /// Seat to finishing place (1 is first). Empty for abandoned matches.
  final Map<int, int> places;
  final Set<int> forfeitedSeats;

  /// Seats a bot played at any point.
  final Set<int> botSeats;
}

/// A match as read back, for the verify route and tests.
class StoredMatch {
  const StoredMatch({
    required this.id,
    required this.roomCode,
    required this.status,
    required this.serverSeed,
    required this.serverSeedHash,
    required this.clientSeed,
    required this.rolls,
  });
  final String id;
  final String roomCode;
  final MatchStatus status;

  /// Hex, null until the match ends.
  final String? serverSeed;
  final String serverSeedHash;
  final String clientSeed;

  /// rolls[i] is roll number i.
  final List<(int, int)> rolls;
}

/// Durable record of rooms, matches, players and every move (README section 6,
/// task M2.7).
abstract interface class MatchLog {
  Future<void> roomCreated(RoomRecord room);
  Future<void> roomStatusChanged(String roomId, String status);
  Future<void> matchStarted(MatchStartRecord match);
  Future<void> event(MatchEventRecord event);
  Future<void> matchEnded(MatchEndRecord end);
  Future<StoredMatch?> loadMatch(String matchId);
  Future<List<MatchEventRecord>> events(String matchId);
}

class InMemoryMatchLog implements MatchLog {
  final Map<String, RoomRecord> rooms = {};
  final Map<String, String> roomStatus = {};
  final Map<String, MatchStartRecord> matches = {};
  final Map<String, MatchEndRecord> ends = {};
  final Map<String, List<MatchEventRecord>> _events = {};

  @override
  Future<void> roomCreated(RoomRecord room) async {
    rooms[room.id] = room;
    roomStatus[room.id] = 'waiting';
  }

  @override
  Future<void> roomStatusChanged(String roomId, String status) async {
    roomStatus[roomId] = status;
  }

  @override
  Future<void> matchStarted(MatchStartRecord match) async {
    matches[match.matchId] = match;
    _events[match.matchId] = [];
  }

  @override
  Future<void> event(MatchEventRecord event) async {
    final list = _events.putIfAbsent(event.matchId, () => []);
    if (list.any((e) => e.index == event.index)) {
      throw StateError('duplicate event ${event.index}');
    }
    list.add(event);
  }

  @override
  Future<void> matchEnded(MatchEndRecord end) async {
    ends[end.matchId] = end;
  }

  @override
  Future<StoredMatch?> loadMatch(String matchId) async {
    final m = matches[matchId];
    if (m == null) return null;
    final end = ends[matchId];
    return StoredMatch(
      id: matchId,
      roomCode: rooms[m.roomId]?.code ?? '',
      status: end?.status ?? MatchStatus.playing,
      serverSeed: end?.serverSeedHex,
      serverSeedHash: m.serverSeedHash,
      clientSeed: m.clientSeed,
      rolls: rollsOf(await events(matchId)),
    );
  }

  @override
  Future<List<MatchEventRecord>> events(String matchId) async =>
      [...?_events[matchId]]..sort((a, b) => a.index.compareTo(b.index));
}

/// The dice of every roll event, in order.
List<(int, int)> rollsOf(Iterable<MatchEventRecord> events) => [
  for (final e in events)
    if (e.kind == EventKinds.roll)
      (
        (e.data['values'] as List)[0] as int,
        (e.data['values'] as List)[1] as int,
      ),
];

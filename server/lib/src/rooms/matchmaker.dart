import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_protocol/fair_dice.dart' show isValidClientSeed;
import 'package:ludo_engine/ludo_engine.dart';

import '../clock.dart';
import 'room.dart';

/// One quick match queue: a mode at a table (m3.md section 4, D39).
class QueueKey {
  const QueueKey(this.mode, {this.entry = 0, this.stake = 0});

  final GameMode mode;

  /// Coins per player, 0 for a free table.
  final int entry;

  /// UGX per player, 0 unless a paid table.
  final int stake;

  /// 1v1 matches two players; free for all matches four.
  int get seats => mode == GameMode.oneVsOne ? 2 : 4;

  bool get isPaid => stake > 0;

  @override
  bool operator ==(Object other) =>
      other is QueueKey &&
      other.mode == mode &&
      other.entry == entry &&
      other.stake == stake;

  @override
  int get hashCode => Object.hash(mode, entry, stake);

  @override
  String toString() => 'QueueKey(${mode.name}, entry $entry, stake $stake)';
}

/// A player taken from a queue into a new game.
class MatchedPlayer {
  const MatchedPlayer({
    required this.userId,
    required this.displayName,
    this.clientSeed,
  });

  final String userId;
  final String displayName;
  final String? clientSeed;
}

class _Waiting {
  _Waiting(this.conn, this.key, this.clientSeed, this.joinedAtMs);

  final Connection conn;
  final QueueKey key;
  final String? clientSeed;
  final int joinedAtMs;

  String get userId => conn.userId;
}

/// What the matchmaker needs from the room manager.
abstract interface class MatchHost {
  /// The code of the room where [userId] holds a seat, if any.
  String? activeRoomOf(String userId);

  /// Creates and starts a game with these players and returns its code.
  String startMatch(QueueKey key, List<MatchedPlayer> players);

  void sendError(Connection conn, int? ref, String code, String message);
}

/// Quick match queues. Players wait per [QueueKey]; when a queue holds
/// enough players for a game, the first of them are seated in a new room
/// that starts at once, and each gets queue_status matched with its code.
/// Queues live in memory only: after a restart the app joins again.
class Matchmaker {
  Matchmaker({required this.clock, required this.host, this.allowTable});

  final Clock clock;
  final MatchHost host;

  /// Returns an error code and message when a table is not open, or null.
  /// Without it only free tables are open.
  final (String, String)? Function(QueueKey key, Connection conn)? allowTable;

  static (String, String)? freeTablesOnly(QueueKey key, Connection _) {
    if (key.isPaid) {
      return (ErrorCodes.paidTablesDisabled, 'paid tables are not open yet');
    }
    if (key.entry > 0) {
      return (ErrorCodes.badRequest, 'coin tables are not open yet');
    }
    return null;
  }

  final Map<QueueKey, List<_Waiting>> _queues = {};
  final Map<String, _Waiting> _byUser = {};

  /// Players waiting in [key], for tests and the health page.
  int waiting(QueueKey key) => _queues[key]?.length ?? 0;

  bool isQueued(String userId) => _byUser.containsKey(userId);

  void join(Connection conn, QueueJoinMessage msg) {
    final ref = msg.cseq;
    final key = QueueKey(msg.mode, entry: msg.entry, stake: msg.stake);
    if (msg.mode == GameMode.teams) {
      return host.sendError(
        conn,
        ref,
        ErrorCodes.badRequest,
        'quick match is for 1v1 and four player free for all',
      );
    }
    if (msg.entry < 0 || msg.stake < 0 || (msg.entry > 0 && msg.stake > 0)) {
      return host.sendError(conn, ref, ErrorCodes.badRequest, 'bad table');
    }
    final seed = msg.clientSeed;
    if (seed != null && !isValidClientSeed(seed)) {
      return host.sendError(conn, ref, ErrorCodes.badRequest, 'bad clientSeed');
    }
    final refused = (allowTable ?? freeTablesOnly)(key, conn);
    if (refused != null) {
      return host.sendError(conn, ref, refused.$1, refused.$2);
    }
    final room = host.activeRoomOf(conn.userId);
    if (room != null) {
      return host.sendError(
        conn,
        ref,
        ErrorCodes.queueBusy,
        'you already hold a seat in room $room',
      );
    }
    final existing = _byUser[conn.userId];
    if (existing != null) {
      if (!identical(existing.conn, conn)) {
        // The same player on a new socket, for example after a reconnect:
        // the new socket takes the place in the queue.
        _remove(existing);
      } else if (existing.key == key) {
        return _send(existing, QueueState.waiting, ref: ref);
      } else {
        return host.sendError(
          conn,
          ref,
          ErrorCodes.queueBusy,
          'leave the other queue first',
        );
      }
    }
    final w = _Waiting(conn, key, seed, clock.nowMs());
    _byUser[w.userId] = w;
    final queue = _queues.putIfAbsent(key, () => []);
    queue.add(w);
    _send(w, QueueState.waiting, ref: ref);
    _match(key);
    if (_byUser[w.userId] == w) _broadcastWaiting(key, except: w);
  }

  void leave(Connection conn, int? ref) {
    final w = _byUser[conn.userId];
    if (w == null || !identical(w.conn, conn)) {
      return host.sendError(conn, ref, ErrorCodes.notFound, 'not in a queue');
    }
    _remove(w);
    _send(w, QueueState.cancelled, ref: ref);
    _broadcastWaiting(w.key);
  }

  void disconnected(Connection conn) {
    final w = _byUser[conn.userId];
    if (w == null || !identical(w.conn, conn)) return;
    _remove(w);
    _broadcastWaiting(w.key);
  }

  void _remove(_Waiting w) {
    if (_byUser[w.userId] == w) _byUser.remove(w.userId);
    final queue = _queues[w.key];
    queue?.remove(w);
    if (queue != null && queue.isEmpty) _queues.remove(w.key);
  }

  /// Takes full games off the front of the queue.
  void _match(QueueKey key) {
    final queue = _queues[key];
    while (queue != null && queue.length >= key.seats) {
      final group = queue.sublist(0, key.seats);
      // Someone who took a seat by code since queueing cannot play twice.
      final busy = [
        for (final w in group)
          if (host.activeRoomOf(w.userId) != null) w,
      ];
      if (busy.isNotEmpty) {
        for (final w in busy) {
          _remove(w);
          _send(w, QueueState.cancelled);
        }
        continue;
      }
      _startGroup(key, group);
    }
  }

  /// Seats [group] in a new game. Bot seat filling adds bots to the list.
  void _startGroup(QueueKey key, List<_Waiting> group) {
    for (final w in group) {
      _remove(w);
    }
    final code = host.startMatch(key, [
      for (final w in group)
        MatchedPlayer(
          userId: w.userId,
          displayName: w.conn.displayName,
          clientSeed: w.clientSeed,
        ),
    ]);
    for (final w in group) {
      _send(w, QueueState.matched, roomCode: code, playersFound: key.seats);
    }
  }

  void _broadcastWaiting(QueueKey key, {_Waiting? except}) {
    for (final w in _queues[key] ?? const <_Waiting>[]) {
      if (!identical(w, except)) _send(w, QueueState.waiting);
    }
  }

  void _send(
    _Waiting w,
    QueueState state, {
    int? ref,
    String? roomCode,
    int? playersFound,
  }) {
    w.conn.send(
      QueueStatusMessage(
        ref: ref,
        state: state,
        mode: w.key.mode,
        entry: w.key.entry,
        stake: w.key.stake,
        waited: (clock.nowMs() - w.joinedAtMs) ~/ 1000,
        playersFound: playersFound ?? waiting(w.key),
        playersNeeded: w.key.seats,
        roomCode: roomCode,
        serverNow: clock.nowMs(),
      ),
    );
  }
}

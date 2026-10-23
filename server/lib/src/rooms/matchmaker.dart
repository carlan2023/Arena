import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_protocol/fair_dice.dart' show isValidClientSeed;
import 'package:arena_wallet/arena_wallet.dart' show CoinTableSettings;
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
    this.avatar = 0,
    this.clientSeed,
    this.isBot = false,
  });

  /// A bot for an empty seat. Bots have no account; [userId] is only unique
  /// within the room.
  const MatchedPlayer.bot(int n)
    : userId = 'bot:$n',
      displayName = 'Bot ${n + 1}',
      avatar = n,
      clientSeed = null,
      isBot = true;

  final String userId;
  final String displayName;
  final int avatar;
  final String? clientSeed;
  final bool isBot;
}

class _Waiting {
  _Waiting(this.conn, this.key, this.clientSeed, this.joinedAtMs);

  final Connection conn;
  final QueueKey key;
  final String? clientSeed;
  final int joinedAtMs;

  /// Bot fill for free and coin queues, the time out for paid ones.
  TimerHandle? timer;

  String get userId => conn.userId;
}

/// What the matchmaker needs from the room manager.
abstract interface class MatchHost {
  /// The code of the room where [userId] holds a seat, if any.
  String? activeRoomOf(String userId);

  /// Creates a game with these players and returns its code. A free game is
  /// started before this returns. A coin game is only seated: the entries are
  /// collected by the future from [takePendingStake], and the game starts
  /// when that succeeds.
  String startMatch(QueueKey key, List<MatchedPlayer> players);

  /// The in-flight coin charge for [code], or null when the match was free.
  /// Completes with the user ids removed because they could not pay.
  Future<Set<String>>? takePendingStake(String code);

  void sendError(Connection conn, int? ref, String code, String message);
}

/// Free tables and the coin entries in [CoinTableSettings]. A stake is still
/// refused: paid tables stay closed until M3.9.
(String, String)? openCoinTables(QueueKey key, Connection _) {
  if (key.isPaid) {
    return (ErrorCodes.paidTablesDisabled, 'paid tables are not open yet');
  }
  if (const CoinTableSettings().allows(key.entry)) return null;
  return (ErrorCodes.badRequest, 'that coin table is not open');
}

/// Quick match queues. Players wait per [QueueKey]; when a queue holds
/// enough players for a game, the first of them are seated in a new room
/// that starts at once, and each gets queue_status matched with its code.
/// In free and coin queues a player who has waited [botFill] is seated with
/// the players behind them and bots in the empty seats. Paid queues never
/// get bots; a paid player who has waited [paidTimeout] gets queue_status
/// timeout. Queues live in memory only: after a restart the app joins again.
class Matchmaker {
  Matchmaker({
    required this.clock,
    required this.host,
    this.allowTable,
    this.botFill = const Duration(seconds: 20),
    this.paidTimeout = const Duration(seconds: 60),
  });

  final Clock clock;
  final MatchHost host;
  final Duration botFill;
  final Duration paidTimeout;

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
    w.timer = key.isPaid
        ? clock.schedule(paidTimeout, () => _timedOut(w))
        : clock.schedule(botFill, () => _fill(w));
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
    w.timer?.cancel();
    w.timer = null;
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
      if (_dropBusy(group)) continue;
      _startGroup(key, group);
    }
  }

  /// Removes players who took a seat by code since queueing, since nobody
  /// plays two games at once. Returns true if anyone was removed.
  bool _dropBusy(List<_Waiting> group) {
    final busy = [
      for (final w in group)
        if (host.activeRoomOf(w.userId) != null) w,
    ];
    for (final w in busy) {
      _remove(w);
      _send(w, QueueState.cancelled);
    }
    return busy.isNotEmpty;
  }

  /// [w] has waited botFill: seat them with whoever is behind them, and bots.
  void _fill(_Waiting w) {
    w.timer = null;
    if (_byUser[w.userId] != w) return;
    final queue = _queues[w.key]!;
    var group = queue.take(w.key.seats).toList();
    if (_dropBusy(group)) {
      if (_byUser[w.userId] != w) return _broadcastWaiting(w.key);
      group = queue.take(w.key.seats).toList();
    }
    _startGroup(w.key, group);
    _broadcastWaiting(w.key);
  }

  void _timedOut(_Waiting w) {
    w.timer = null;
    if (_byUser[w.userId] != w) return;
    _remove(w);
    _send(w, QueueState.timeout);
    _broadcastWaiting(w.key);
  }

  /// Seats [group] in a new game, with bots in any seats left over.
  void _startGroup(QueueKey key, List<_Waiting> group) {
    for (final w in group) {
      _remove(w);
    }
    final code = host.startMatch(key, [
      for (final w in group)
        MatchedPlayer(
          userId: w.userId,
          displayName: w.conn.displayName,
          avatar: w.conn.avatar,
          clientSeed: w.clientSeed,
        ),
      for (var i = group.length; i < key.seats; i++) MatchedPlayer.bot(i),
    ]);
    final pending = host.takePendingStake(code);
    if (pending == null) {
      for (final w in group) {
        _send(w, QueueState.matched, roomCode: code, playersFound: key.seats);
      }
      return;
    }
    pending.then((removed) {
      for (final w in group) {
        if (removed.contains(w.userId)) {
          host.sendError(
            w.conn,
            null,
            ErrorCodes.insufficientFunds,
            'not enough coins for this table',
          );
        } else {
          _send(w, QueueState.matched, roomCode: code, playersFound: key.seats);
        }
      }
    });
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
        botFillAt: state == QueueState.waiting ? _botFillAt(w) : null,
        serverNow: clock.nowMs(),
      ),
    );
  }

  /// When bots fill [w]'s game. Players are seated from the front of the
  /// queue in groups of a game's size, and each group fills when its first
  /// player has waited botFill.
  int? _botFillAt(_Waiting w) {
    if (w.key.isPaid) return null;
    final queue = _queues[w.key];
    final i = queue?.indexOf(w) ?? -1;
    if (i < 0) return null;
    final first = queue![i - i % w.key.seats];
    return first.joinedAtMs + botFill.inMilliseconds;
  }
}

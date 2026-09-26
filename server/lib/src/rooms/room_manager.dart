import 'dart:async';
import 'dart:math';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_protocol/fair_dice.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../clock.dart';
import '../ids.dart';
import '../store/live_store.dart';
import '../store/match_log.dart';
import 'room.dart';

/// Picks the full move list for the current roll (a bot).
typedef MoveChooser = List<Move> Function(GameState state);

typedef ErrorLogger =
    void Function(String message, Object? error, StackTrace? stack);

/// Timing and limits for rooms.
class RoomSettings {
  const RoomSettings({
    this.turnTimeout = const Duration(seconds: 20),
    this.reconnectGrace = const Duration(seconds: 60),
    this.botDelay = const Duration(milliseconds: 800),
    this.roomIdle = const Duration(minutes: 30),
    this.maxTimeouts = 3,
    this.publicBaseUrl = 'http://localhost:8080',
  });

  final Duration turnTimeout;
  final Duration reconnectGrace;
  final Duration botDelay;
  final Duration roomIdle;

  /// Timed out decisions in a row before a bot takes the seat (free games)
  /// or the seat forfeits (paid games).
  final int maxTimeouts;
  final String publicBaseUrl;
}

/// Thrown by [RoomManager.createRoom] for a request it refuses.
class RoomException implements Exception {
  RoomException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'RoomException($code: $message)';
}

/// Owns every live room: seats, turns, dice, timers and reconnects. All game
/// logic runs synchronously on the event loop; storage writes are queued per
/// room in order and never block play.
class RoomManager {
  RoomManager({
    required this.clock,
    required this.chooseMoves,
    this.settings = const RoomSettings(),
    LiveRoomStore? liveStore,
    MatchLog? matchLog,
    Random? random,
    ErrorLogger? logError,
  }) : liveStore = liveStore ?? InMemoryLiveRoomStore(),
       matchLog = matchLog ?? InMemoryMatchLog(),
       _random = random ?? Random.secure(),
       _logError = logError ?? _printError;

  final Clock clock;
  final MoveChooser chooseMoves;
  final RoomSettings settings;
  final LiveRoomStore liveStore;
  final MatchLog matchLog;
  final Random _random;
  final ErrorLogger _logError;

  final Map<String, Room> _rooms = {};

  /// userId to the code of the waiting or playing room where they hold a seat.
  final Map<String, String> _activeRoomOf = {};

  final Set<Future<void>> _pendingWrites = {};
  final Map<String, Future<void>> _writeChains = {};

  static void _printError(String message, Object? error, StackTrace? stack) {
    // ignore: avoid_print
    print('ERROR $message: $error\n${stack ?? ''}');
  }

  Room? room(String code) => _rooms[code.toUpperCase()];

  Iterable<Room> get rooms => _rooms.values;

  RoomView view(Room room) => room.view(settings.publicBaseUrl);

  // ---------------------------------------------------------------------------
  // Creating and restoring rooms
  // ---------------------------------------------------------------------------

  Room createRoom({
    required String ownerUserId,
    required GameMode mode,
    required int seats,
    int stake = 0,
    RulesConfig rules = const RulesConfig(),
  }) {
    if (!validSeats(mode, seats)) {
      throw RoomException(
        ErrorCodes.badRequest,
        '${mode.name} does not allow $seats seats',
      );
    }
    if (stake < 0) throw RoomException(ErrorCodes.badRequest, 'bad stake');
    var code = newRoomCode(_random);
    while (_rooms.containsKey(code)) {
      code = newRoomCode(_random);
    }
    final room = Room(
      id: newUuid(_random),
      code: code,
      ownerUserId: ownerUserId,
      mode: mode,
      seatCount: seats,
      stake: stake,
      rules: rules,
      serverSeed: generateServerSeed(_random),
      createdAtMs: clock.nowMs(),
    );
    _rooms[code] = room;
    _armIdle(room);
    _write(
      room,
      () => matchLog.roomCreated(
        RoomRecord(
          id: room.id,
          code: code,
          mode: mode.name,
          seats: seats,
          stake: stake,
          rules: rules.toJson(),
          ownerUserId: ownerUserId,
          createdAt: _now(),
        ),
      ),
    );
    _persist(room);
    return room;
  }

  /// Reloads live rooms from the live store after a restart and re-arms their
  /// timers. Every player starts disconnected, with a fresh grace period.
  Future<int> restore() async {
    final snapshots = await liveStore.loadAll();
    var count = 0;
    for (final snap in snapshots) {
      final Room room;
      try {
        room = Room.fromSnapshot(snap);
      } catch (e, st) {
        _logError('skipping unreadable room snapshot', e, st);
        continue;
      }
      if (room.status == RoomStatus.finished || _rooms.containsKey(room.code)) {
        continue;
      }
      _rooms[room.code] = room;
      count++;
      for (final seat in room.seated) {
        if (!seat.forfeited) _activeRoomOf[seat.userId] = room.code;
        seat.connected = false;
        if (!seat.forfeited && !seat.isBot) _startGrace(room, seat);
      }
      if (room.status == RoomStatus.waiting) {
        if (room.seated.isEmpty) _armIdle(room);
      } else {
        final remaining = max(0, (room.deadline ?? 0) - clock.nowMs());
        _armDecision(room, delay: Duration(milliseconds: remaining));
        _checkAbandoned(room);
      }
    }
    return count;
  }

  /// Waits for every queued storage write.
  Future<void> flush() async {
    while (_pendingWrites.isNotEmpty) {
      await Future.wait(_pendingWrites.toList());
    }
  }

  /// Cancels every timer. Rooms stay in the live store for the next start.
  void dispose() {
    for (final room in _rooms.values) {
      room.cancelTimers();
    }
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  void handle(Connection conn, ClientMessage msg) {
    try {
      _handle(conn, msg);
    } catch (e, st) {
      _logError('handling ${msg.type}', e, st);
      _error(conn, msg.cseq, ErrorCodes.internal, 'internal error');
    }
  }

  void _handle(Connection conn, ClientMessage msg) {
    switch (msg) {
      case JoinRoomMessage():
        _join(conn, msg);
      case PingMessage():
        conn.send(PongMessage(ref: msg.cseq, serverNow: clock.nowMs()));
      case StartGameMessage():
        final room = _boundRoom(conn, msg);
        if (room != null) _startGame(conn, room, msg);
      case RollMessage():
        final room = _boundRoom(conn, msg);
        if (room != null) _roll(conn, room, msg);
      case MoveMessage():
        final room = _boundRoom(conn, msg);
        if (room != null) _move(conn, room, msg);
      case LeaveRoomMessage():
        final room = _boundRoom(conn, msg);
        if (room != null) _leave(conn, room);
      case EmoteMessage():
        final room = _boundRoom(conn, msg, quiet: true);
        if (room != null) _emote(conn, room, msg);
    }
  }

  /// A socket closed.
  void disconnected(Connection conn) {
    final room = _rooms[conn.roomCode];
    conn.roomCode = null;
    if (room == null) return;
    final seat = room.seatOfUser(conn.userId);
    if (seat == null || !identical(seat.connection, conn)) return;
    seat.connection = null;
    seat.connected = false;
    if (room.status == RoomStatus.finished || seat.forfeited) return;
    _startGrace(room, seat);
    if (room.status == RoomStatus.waiting) {
      _broadcastRoomState(room);
    } else {
      _broadcastStatus(room, seat);
    }
    _persist(room);
  }

  Room? _boundRoom(Connection conn, ClientMessage msg, {bool quiet = false}) {
    final room = _rooms[conn.roomCode];
    if (room == null) {
      if (!quiet) {
        _error(conn, msg.cseq, ErrorCodes.notInRoom, 'join a room first');
      }
      return null;
    }
    return room;
  }

  void _join(Connection conn, JoinRoomMessage msg) {
    final ref = msg.cseq;
    final room = _rooms[msg.roomCode.toUpperCase()];
    if (room == null) {
      return _error(conn, ref, ErrorCodes.roomNotFound, 'no such room');
    }
    final seed = msg.clientSeed;
    if (seed != null && !isValidClientSeed(seed)) {
      return _error(conn, ref, ErrorCodes.badRequest, 'bad clientSeed');
    }
    if (room.status == RoomStatus.finished) {
      return _error(conn, ref, ErrorCodes.alreadyStarted, 'game is over');
    }
    final existing = room.seatOfUser(conn.userId);
    if (existing != null && !existing.forfeited) {
      return _rejoin(conn, room, existing, ref);
    }
    if (room.status != RoomStatus.waiting) {
      return _error(conn, ref, ErrorCodes.alreadyStarted, 'game has started');
    }
    final active = _activeRoomOf[conn.userId];
    if (active != null && active != room.code) {
      return _error(
        conn,
        ref,
        ErrorCodes.badRequest,
        'you already hold a seat in room $active',
      );
    }
    final free = room.seats.indexOf(null);
    if (free < 0) return _error(conn, ref, ErrorCodes.roomFull, 'room is full');

    final seat = Seat(
      index: free,
      userId: conn.userId,
      displayName: conn.displayName,
      clientSeed: seed,
    );
    room.seats[free] = seat;
    _activeRoomOf[conn.userId] = room.code;
    room.idleTimer?.cancel();
    room.idleTimer = null;
    _bind(conn, room, seat);
    _broadcastRoomState(room, replyTo: seat, ref: ref);
    if (room.seated.length == room.seatCount &&
        canStart(room.mode, room.seatCount, room.seatCount)) {
      _start(room);
    }
    _persist(room);
  }

  void _rejoin(Connection conn, Room room, Seat seat, int? ref) {
    final old = seat.connection;
    if (old != null && !identical(old, conn)) {
      old.roomCode = null;
      old.close();
    }
    final wasConnected = seat.connected;
    _bind(conn, room, seat);
    seat.graceTimer?.cancel();
    seat.graceTimer = null;
    seat.graceDeadline = null;
    final reclaimed =
        room.status == RoomStatus.playing && _releaseBot(room, seat);

    if (room.status == RoomStatus.waiting) {
      if (wasConnected) {
        conn.send(_roomState(room, seat, ref));
      } else {
        _broadcastRoomState(room, replyTo: seat, ref: ref);
      }
    } else {
      if (!wasConnected && !reclaimed) {
        _broadcastStatus(room, seat, except: seat);
      }
      conn.send(_roomState(room, seat, ref));
    }
    _persist(room);
  }

  void _bind(Connection conn, Room room, Seat seat) {
    final previous = _rooms[conn.roomCode];
    if (previous != null && !identical(previous, room)) {
      final s = previous.seatOfUser(conn.userId);
      if (s != null && identical(s.connection, conn)) {
        s.connection = null;
        s.connected = false;
      }
    }
    conn.roomCode = room.code;
    seat.connection = conn;
    seat.connected = true;
  }

  void _startGame(Connection conn, Room room, StartGameMessage msg) {
    final ref = msg.cseq;
    if (room.ownerUserId != conn.userId) {
      return _error(conn, ref, ErrorCodes.notOwner, 'only the owner can start');
    }
    if (room.status != RoomStatus.waiting) {
      return _error(conn, ref, ErrorCodes.alreadyStarted, 'already started');
    }
    final players = room.seated.length;
    if (!canStart(room.mode, room.seatCount, players)) {
      return _error(
        conn,
        ref,
        ErrorCodes.badRequest,
        '${room.mode.name} cannot start with $players players',
      );
    }
    _start(room);
    _persist(room);
  }

  void _start(Room room) {
    final seated = room.seated.toList();
    final colors = colorsFor(seated.length);
    for (var i = 0; i < seated.length; i++) {
      seated[i].color = colors[i];
      seated[i].graceTimer?.cancel();
      seated[i].graceTimer = null;
      seated[i].graceDeadline = null;
    }
    room.clientSeed = [
      for (final s in seated) s.clientSeed ?? '${s.index}',
    ].join(':');
    room.matchId = newUuid(_random);
    room.state = GameState.newGame(
      mode: room.mode,
      players: colors,
      rules: room.rules,
    );
    room.status = RoomStatus.playing;
    room.idleTimer?.cancel();
    room.idleTimer = null;
    final matchId = room.matchId!;
    final startRecord = MatchStartRecord(
      matchId: matchId,
      roomId: room.id,
      mode: room.mode.name,
      rules: room.rules.toJson(),
      stake: room.stake,
      serverSeedHash: room.serverSeedHash,
      clientSeed: room.clientSeed!,
      startedAt: _now(),
      players: [
        for (final s in seated)
          MatchPlayerRecord(
            seat: s.index,
            userId: s.userId,
            color: s.color!.name,
          ),
      ],
    );
    _write(room, () => matchLog.matchStarted(startRecord));
    _write(room, () => matchLog.roomStatusChanged(room.id, 'playing'));
    _armDecision(room);
    _broadcastRoomState(room);
    // Players who dropped in the lobby start the game disconnected.
    for (final s in seated) {
      if (!s.connected) _startGrace(room, s);
    }
    _checkAbandoned(room);
  }

  void _roll(Connection conn, Room room, RollMessage msg) {
    final seat = _actingSeat(conn, room, msg.cseq, TurnPhase.awaitingRoll);
    if (seat == null) return;
    _doRoll(room, auto: false);
    _persist(room);
  }

  void _move(Connection conn, Room room, MoveMessage msg) {
    final seat = _actingSeat(conn, room, msg.cseq, TurnPhase.awaitingMove);
    if (seat == null) return;
    final error = _applyMoves(room, msg.moves, auto: false);
    if (error != null) {
      _error(conn, msg.cseq, ErrorCodes.illegalMove, error);
    }
    _persist(room);
  }

  /// Checks that [conn]'s user may act now. Sends the error and returns null
  /// otherwise. Acting resets the timeout count and takes the seat back from
  /// a bot in free games.
  Seat? _actingSeat(Connection conn, Room room, int? ref, TurnPhase phase) {
    final seat = room.seatOfUser(conn.userId);
    if (seat == null || seat.forfeited) {
      _error(conn, ref, ErrorCodes.notInRoom, 'you have no seat here');
      return null;
    }
    final state = room.state;
    if (room.status != RoomStatus.playing || state == null) {
      _error(conn, ref, ErrorCodes.wrongPhase, 'the game is not running');
      return null;
    }
    _releaseBot(room, seat);
    if (!identical(room.currentSeat, seat)) {
      _error(conn, ref, ErrorCodes.notYourTurn, 'not your turn');
      return null;
    }
    if (state.phase != phase) {
      _error(conn, ref, ErrorCodes.wrongPhase, 'expected ${state.phase.name}');
      return null;
    }
    seat.timeouts = 0;
    return seat;
  }

  void _leave(Connection conn, Room room) {
    final seat = room.seatOfUser(conn.userId);
    conn.roomCode = null;
    if (seat == null || !identical(seat.connection, conn)) return;
    seat.connection = null;
    seat.connected = false;
    switch (room.status) {
      case RoomStatus.waiting:
        _removeFromLobby(room, seat);
      case RoomStatus.playing:
        if (!seat.forfeited) _forfeit(room, seat, 'leave');
      case RoomStatus.finished:
        break;
    }
    _persist(room);
  }

  void _removeFromLobby(Room room, Seat seat) {
    seat.graceTimer?.cancel();
    room.seats[seat.index] = null;
    if (_activeRoomOf[seat.userId] == room.code) {
      _activeRoomOf.remove(seat.userId);
    }
    if (room.ownerUserId == seat.userId && room.seated.isNotEmpty) {
      room.ownerUserId = room.seated.first.userId;
    }
    if (room.seated.isEmpty) _armIdle(room);
    _broadcastRoomState(room);
  }

  void _emote(Connection conn, Room room, EmoteMessage msg) {
    final seat = room.seatOfUser(conn.userId);
    if (seat == null || seat.forfeited || room.status == RoomStatus.finished) {
      return;
    }
    if (msg.id.isEmpty || msg.id.length > 32) {
      return _error(conn, msg.cseq, ErrorCodes.badRequest, 'bad emote id');
    }
    _broadcast(
      room,
      (_) => EmoteEvent(seq: room.seq, seat: seat.index, id: msg.id),
    );
  }

  // ---------------------------------------------------------------------------
  // Turns
  // ---------------------------------------------------------------------------

  void _doRoll(Room room, {required bool auto}) {
    final state = room.state!;
    final seat = room.currentSeat!;
    final color = state.current;
    final n = state.rollNumber;
    final (a, b) = rollDice(room.serverSeed, room.clientSeed!, n);
    final next = applyRoll(state, a, b);
    room.state = next;
    final legal = legalMoves(next);
    _logEvent(room, EventKinds.roll, seat, {
      'values': [a, b],
      'rollNumber': n,
    }, auto: auto);
    _armDecision(room);
    _broadcast(
      room,
      (_) => DiceMessage(
        seq: room.seq,
        color: color,
        values: (a, b),
        rollNumber: n,
        legalMoves: legal,
        state: next,
        deadline: room.deadline ?? clock.nowMs(),
        auto: auto,
        serverNow: clock.nowMs(),
      ),
    );
    if (isGameOver(next)) _finish(room);
  }

  /// Applies a whole move list, all or nothing. Returns an error message, or
  /// null when applied.
  String? _applyMoves(Room room, List<Move> moves, {required bool auto}) {
    final start = room.state!;
    final seat = room.currentSeat!;
    if (moves.isEmpty) return 'the move list is empty';
    var s = start;
    final captured = <PieceRef>[];
    var ended = false;
    for (final m in moves) {
      if (ended) return 'moves after the end of the roll';
      final MoveResult r;
      try {
        r = applyMove(s, m);
      } on IllegalMoveException catch (e) {
        return e.reason;
      } on Object catch (e) {
        return 'illegal move: $e';
      }
      s = r.state;
      captured.addAll(r.captured);
      ended = r.rollEnded;
    }
    if (!ended) return 'the move list does not finish the roll';

    room.state = s;
    _logEvent(room, EventKinds.move, seat, {
      'moves': [for (final m in moves) m.toJson()],
      'captured': [for (final c in captured) c.toJson()],
    }, auto: auto);
    _armDecision(room);
    _broadcast(
      room,
      (_) => StatePatchMessage(
        seq: room.seq,
        color: start.current,
        moves: moves,
        captured: captured,
        state: s,
        deadline: room.deadline,
        auto: auto,
        serverNow: clock.nowMs(),
      ),
    );
    if (isGameOver(s)) _finish(room);
    return null;
  }

  /// Plays the current decision for the seat: roll, or the bot's move list.
  void _autoAct(Room room) {
    final state = room.state!;
    if (state.phase == TurnPhase.awaitingRoll) {
      _doRoll(room, auto: true);
    } else if (state.phase == TurnPhase.awaitingMove) {
      List<Move> moves;
      try {
        moves = chooseMoves(state);
      } catch (e, st) {
        _logError('bot failed', e, st);
        moves = const [];
      }
      final error = _applyMoves(room, moves, auto: true);
      if (error != null) {
        _logError('bot move rejected: $error', null, null);
        final fallback = legalSequences(state);
        if (fallback.isEmpty ||
            _applyMoves(room, fallback.first, auto: true) != null) {
          throw StateError('no legal move list for an auto move');
        }
      }
    }
  }

  /// Starts the timer for the current decision, and the bot's think time when
  /// a bot holds the seat.
  void _armDecision(Room room, {Duration? delay}) {
    room.decisionId++;
    room.decisionTimer?.cancel();
    room.botTimer?.cancel();
    room.decisionTimer = room.botTimer = null;
    final state = room.state;
    if (state == null ||
        isGameOver(state) ||
        room.status == RoomStatus.finished) {
      room.deadline = null;
      return;
    }
    final wait = delay ?? settings.turnTimeout;
    room.deadline = clock.nowMs() + wait.inMilliseconds;
    final id = room.decisionId;
    room.decisionTimer = clock.schedule(wait, () => _onTimeout(room, id));
    if (room.currentSeat?.isBot ?? false) _armBot(room);
  }

  void _armBot(Room room) {
    room.botTimer?.cancel();
    final id = room.decisionId;
    room.botTimer = clock.schedule(settings.botDelay, () {
      if (room.decisionId != id) return;
      _guard(room, 'bot turn', () => _autoAct(room));
    });
  }

  void _onTimeout(Room room, int id) {
    if (room.decisionId != id) return;
    _guard(room, 'timeout', () {
      final seat = room.currentSeat;
      if (seat == null) return;
      if (!seat.isBot) {
        seat.timeouts++;
        if (seat.timeouts >= settings.maxTimeouts) {
          if (room.isPaid) {
            _forfeit(room, seat, 'timeouts');
            return;
          }
          _takeOver(room, seat, 'timeouts');
        }
      }
      _autoAct(room);
    });
  }

  /// A bot plays the seat (free games).
  void _takeOver(Room room, Seat seat, String reason) {
    if (seat.isBot) return;
    seat.isBot = true;
    seat.everBot = true;
    _logEvent(room, EventKinds.botTakeover, seat, {'reason': reason});
    _broadcastStatus(room, seat);
  }

  /// Gives the seat back to the player. Returns true if a bot held it.
  bool _releaseBot(Room room, Seat seat) {
    if (!seat.isBot || room.isPaid) return false;
    seat.isBot = false;
    seat.timeouts = 0;
    if (identical(room.currentSeat, seat)) {
      room.botTimer?.cancel();
      room.botTimer = null;
    }
    _logEvent(room, EventKinds.botRelease, seat, const {});
    _broadcastStatus(room, seat);
    return true;
  }

  void _forfeit(Room room, Seat seat, String reason) {
    final state = room.state!;
    final wasCurrent = identical(room.currentSeat, seat);
    seat.forfeited = true;
    seat.graceTimer?.cancel();
    seat.graceTimer = null;
    seat.graceDeadline = null;
    if (_activeRoomOf[seat.userId] == room.code) {
      _activeRoomOf.remove(seat.userId);
    }
    final next = forfeit(state, seat.color!);
    room.state = next;
    _logEvent(room, EventKinds.forfeit, seat, {'reason': reason});
    if (wasCurrent || next.current != state.current || isGameOver(next)) {
      _armDecision(room);
    }
    _broadcastRoomState(room);
    if (isGameOver(next)) {
      _finish(room);
    } else {
      _checkAbandoned(room);
    }
  }

  void _startGrace(Room room, Seat seat) {
    seat.graceTimer?.cancel();
    seat.graceDeadline = clock.nowMs() + settings.reconnectGrace.inMilliseconds;
    seat.graceTimer = clock.schedule(settings.reconnectGrace, () {
      seat.graceTimer = null;
      if (seat.connected || seat.forfeited) return;
      seat.graceDeadline = null;
      _guard(room, 'grace expiry', () => _graceExpired(room, seat));
    });
  }

  void _graceExpired(Room room, Seat seat) {
    switch (room.status) {
      case RoomStatus.waiting:
        _removeFromLobby(room, seat);
      case RoomStatus.playing:
        if (room.isPaid) {
          _forfeit(room, seat, 'grace');
        } else {
          if (seat.isBot) {
            _broadcastStatus(room, seat);
          } else {
            _takeOver(room, seat, 'grace');
          }
          if (identical(room.currentSeat, seat) && room.botTimer == null) {
            _armBot(room);
          }
          _checkAbandoned(room);
        }
      case RoomStatus.finished:
        break;
    }
  }

  /// Ends a running game with nobody left: no seat is connected or still in
  /// its reconnect grace.
  void _checkAbandoned(Room room) {
    if (room.status != RoomStatus.playing) return;
    final someoneThere = room.seated.any(
      (s) => !s.forfeited && (s.connected || s.graceTimer != null),
    );
    if (!someoneThere) _finish(room, abandoned: true);
  }

  void _finish(Room room, {bool abandoned = false}) {
    if (room.status == RoomStatus.finished) return;
    final state = room.state!;
    room.status = RoomStatus.finished;
    room.cancelTimers();
    room.deadline = null;
    for (final s in room.seated) {
      s.graceDeadline = null;
      if (_activeRoomOf[s.userId] == room.code) _activeRoomOf.remove(s.userId);
    }
    final seedHex = toHex(room.serverSeed);
    final places = <int, int>{};
    if (!abandoned) {
      final order = ranking(state);
      for (var i = 0; i < order.length; i++) {
        final seat = room.seatOfColor(order[i]);
        if (seat != null) places[seat.index] = i + 1;
      }
      _broadcast(
        room,
        (_) => GameOverMessage(
          seq: room.seq,
          matchId: room.matchId!,
          ranking: order,
          winners: winners(state) ?? const [],
          serverSeed: seedHex,
          clientSeed: room.clientSeed!,
          walletDelta: const {},
        ),
      );
    }
    final end = MatchEndRecord(
      matchId: room.matchId!,
      status: abandoned ? MatchStatus.abandoned : MatchStatus.finished,
      serverSeedHex: seedHex,
      endedAt: _now(),
      places: places,
      forfeitedSeats: {
        for (final s in room.seated)
          if (s.forfeited) s.index,
      },
      botSeats: {
        for (final s in room.seated)
          if (s.everBot) s.index,
      },
    );
    _write(room, () => matchLog.matchEnded(end));
    _write(room, () => matchLog.roomStatusChanged(room.id, 'finished'));
    _write(room, () => liveStore.delete(room.code));
    // Kept in memory for GET /v1/rooms/{code} until it goes idle.
    _armIdle(room);
  }

  /// Removes a room that stays empty (waiting) or finished for roomIdle.
  void _armIdle(Room room) {
    room.idleTimer?.cancel();
    room.idleTimer = clock.schedule(settings.roomIdle, () {
      room.idleTimer = null;
      final empty = room.status == RoomStatus.waiting && room.seated.isEmpty;
      if (!empty && room.status != RoomStatus.finished) return;
      if (_rooms[room.code] != room) return;
      _rooms.remove(room.code);
      if (empty) {
        room.cancelTimers();
        _write(room, () => matchLog.roomStatusChanged(room.id, 'expired'));
        _write(room, () => liveStore.delete(room.code));
      }
    });
  }

  void _guard(Room room, String what, void Function() body) {
    try {
      body();
      _persist(room);
    } catch (e, st) {
      _logError('room ${room.code}: $what', e, st);
    }
  }

  // ---------------------------------------------------------------------------
  // Sending
  // ---------------------------------------------------------------------------

  /// Increments seq and sends one message per connected seat.
  void _broadcast(
    Room room,
    ServerMessage Function(Seat seat) build, {
    Seat? except,
  }) {
    room.seq++;
    for (final seat in room.seated) {
      final conn = seat.connection;
      if (conn == null || identical(seat, except)) continue;
      conn.send(build(seat));
    }
  }

  void _broadcastRoomState(Room room, {Seat? replyTo, int? ref}) {
    _broadcast(
      room,
      (seat) => _roomState(room, seat, identical(seat, replyTo) ? ref : null),
    );
  }

  void _broadcastStatus(Room room, Seat seat, {Seat? except}) {
    _broadcast(
      room,
      (_) => PlayerStatusMessage(
        seq: room.seq,
        seat: seat.index,
        connected: seat.connected,
        graceDeadline: seat.graceDeadline,
        isBot: seat.isBot,
      ),
      except: except,
    );
  }

  RoomStateMessage _roomState(Room room, Seat seat, int? ref) =>
      RoomStateMessage(
        seq: room.seq,
        ref: ref,
        room: view(room),
        state: room.state,
        deadline: room.deadline,
        serverSeedHash: room.serverSeedHash,
        you: YouInfo(seat: seat.index, color: seat.color),
        serverNow: clock.nowMs(),
      );

  void _error(Connection conn, int? ref, String code, String message) {
    conn.send(ErrorMessage(ref: ref, code: code, message: message));
  }

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  DateTime _now() =>
      DateTime.fromMillisecondsSinceEpoch(clock.nowMs(), isUtc: true);

  void _logEvent(
    Room room,
    String kind,
    Seat seat,
    Json data, {
    bool auto = false,
  }) {
    final record = MatchEventRecord(
      matchId: room.matchId!,
      index: room.eventIndex++,
      kind: kind,
      seat: seat.index,
      color: seat.color!.name,
      data: data,
      auto: auto,
      at: _now(),
    );
    _write(room, () => matchLog.event(record));
  }

  /// Queues a snapshot of the room for the live store.
  void _persist(Room room) {
    if (room.status == RoomStatus.finished) return;
    if (_rooms[room.code] != room) return;
    final snapshot = room.toSnapshot();
    _write(room, () => liveStore.save(room.code, snapshot));
  }

  /// Runs [op] after every earlier write for the same room.
  void _write(Room room, Future<void> Function() op) {
    final previous = _writeChains[room.id] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .then((_) => op())
        .catchError((Object e, StackTrace st) {
          _logError('storage write for room ${room.code}', e, st);
        })
        .whenComplete(() {
          _pendingWrites.remove(next);
          if (identical(_writeChains[room.id], next)) {
            _writeChains.remove(room.id);
          }
        });
    _writeChains[room.id] = next;
    _pendingWrites.add(next);
  }
}

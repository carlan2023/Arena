import 'dart:async';
import 'dart:math';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../board/board_geometry.dart';
import '../game/local_game.dart' show colorName;
import '../game/move_planner.dart';
import '../game/move_selection.dart';
import '../game/table_view.dart';
import 'auth.dart';
import 'socket.dart';

enum Connection { connecting, connected, reconnecting }

/// Everything the room screens show.
class RoomScreenView {
  const RoomScreenView({
    this.connection = Connection.connecting,
    this.room,
    this.you,
    this.table,
    this.gameOver,
    this.fatal,
    this.emote,
  });

  final Connection connection;
  final RoomView? room;
  final YouInfo? you;

  /// Null until the game starts.
  final TableView? table;
  final GameOverMessage? gameOver;

  /// An error that ends the visit, such as room_not_found.
  final String? fatal;

  /// The last quick chat message: (seat, id).
  final (int, String)? emote;

  bool get isOwner {
    final r = room;
    final y = you;
    if (r == null || y == null) return false;
    for (final p in r.players) {
      if (p.seat == y.seat) return p.userId == r.ownerUserId;
    }
    return false;
  }
}

/// Timings, shortened in tests.
class OnlineTimings {
  const OnlineTimings({
    this.autoPlay = const Duration(milliseconds: 500),
    this.ping = const Duration(seconds: 20),
    this.firstRetry = const Duration(seconds: 1),
    this.maxRetry = const Duration(seconds: 10),
  });

  final Duration autoPlay;
  final Duration ping;
  final Duration firstRetry;
  final Duration maxRetry;
}

final onlineTimingsProvider = Provider<OnlineTimings>(
  (ref) => const OnlineTimings(),
);

final roomProvider = NotifierProvider.autoDispose
    .family<RoomController, RoomScreenView, String>(RoomController.new);

/// One visit to a room over the game socket: lobby, game and results.
/// The server has the final say; the app only plans the current roll.
class RoomController extends Notifier<RoomScreenView> implements TableActions {
  RoomController(this.code);

  final String code;

  GameSocket? _socket;
  StreamSubscription<ServerMessage>? _sub;
  Timer? _retryTimer;
  Timer? _pingTimer;
  Timer? _autoTimer;
  int _attempt = 0;
  int _cseq = 0;
  bool _closed = false;

  int? _seq;
  RoomView? _room;
  YouInfo? _you;
  GameState? _game;
  int? _deadline;
  Duration _offset = Duration.zero;
  MoveSelection? _selection;
  bool _pendingRoll = false;
  bool _pendingMove = false;
  String? _message;
  GameOverMessage? _gameOver;
  String? _fatal;
  (int, String)? _emote;
  Connection _connection = Connection.connecting;

  late final String _clientSeed = _randomSeed();

  OnlineTimings get _timings => ref.read(onlineTimingsProvider);

  @override
  RoomScreenView build() {
    ref.onDispose(_shutdown);
    scheduleMicrotask(_connect);
    return const RoomScreenView();
  }

  static String _randomSeed() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(16, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }

  // --- Connection -------------------------------------------------------

  Future<void> _connect() async {
    if (_closed) return;
    final session = ref.read(authProvider).value;
    if (session == null) {
      _fatal = 'Please log in again';
      _emit();
      return;
    }
    final GameSocket socket;
    try {
      socket = await ref.read(socketConnectorProvider)(session.token);
    } on Object {
      _scheduleRetry();
      return;
    }
    if (_closed) {
      await socket.close();
      return;
    }
    _socket = socket;
    _attempt = 0;
    _sub = socket.messages.listen(
      _onMessage,
      onDone: _onClosed,
      onError: (_) {},
    );
    _join();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(
      _timings.ping,
      (_) => _send((c) => PingMessage(cseq: c)),
    );
  }

  void _join() => _send(
    (c) => JoinRoomMessage(
      roomCode: code,
      clientSeed: _clientSeed,
      lastSeq: _seq,
      cseq: c,
    ),
  );

  void _onClosed() {
    _socket = null;
    _sub = null;
    _pingTimer?.cancel();
    if (_closed || _fatal != null) return;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _connection = Connection.reconnecting;
    _emit();
    final ms = min(
      _timings.firstRetry.inMilliseconds * (1 << min(_attempt, 10)),
      _timings.maxRetry.inMilliseconds,
    );
    _attempt++;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: ms), _connect);
  }

  /// The app came back to the foreground: reconnect now if the socket is
  /// gone, instead of waiting for the retry timer.
  void resume() {
    if (_closed || _socket != null || _fatal != null) return;
    _retryTimer?.cancel();
    _connect();
  }

  /// Drops the socket, as a lost network would. For tests and debugging.
  Future<void> dropConnection() async => _socket?.close();

  void _send(ClientMessage Function(int cseq) build) {
    _socket?.send(build(++_cseq));
  }

  void _shutdown() {
    _closed = true;
    _retryTimer?.cancel();
    _pingTimer?.cancel();
    _autoTimer?.cancel();
    _sub?.cancel();
    _socket?.close();
  }

  // --- Messages ---------------------------------------------------------

  void _onMessage(ServerMessage m) {
    switch (m) {
      case RoomStateMessage():
        _onRoomState(m);
      case ErrorMessage():
        _onError(m);
      case PongMessage():
        _setOffset(m.serverNow);
      case DiceMessage(:final seq) ||
          StatePatchMessage(:final seq) ||
          PlayerStatusMessage(:final seq) ||
          EmoteEvent(:final seq) ||
          GameOverMessage(:final seq):
        final last = _seq;
        if (last == null || seq <= last) return;
        if (seq != last + 1) {
          // Missed something: ask for a fresh snapshot (amendment 3).
          _join();
          return;
        }
        _seq = seq;
        _onRoomEvent(m);
      default:
        return;
    }
    _emit();
  }

  void _onRoomState(RoomStateMessage m) {
    _connection = Connection.connected;
    _seq = m.seq;
    _room = m.room;
    _you = m.you;
    _game = m.state;
    _deadline = m.deadline;
    _setOffset(m.serverNow);
    _pendingRoll = false;
    _pendingMove = false;
    if (m.room.status != RoomStatus.finished) _gameOver = null;
    _newDecision();
  }

  void _onRoomEvent(ServerMessage m) {
    switch (m) {
      case DiceMessage():
        _game = m.state;
        _deadline = m.deadline;
        _setOffset(m.serverNow);
        _pendingRoll = false;
        final (a, b) = m.values;
        final who = _isMe(m.color) ? 'You' : colorName(m.color);
        if (m.legalMoves.isEmpty) {
          _message = '$who rolled $a and $b: no move possible';
        } else if (m.auto && _isMe(m.color)) {
          _message = 'Time ran out, the server rolled for you';
        } else {
          _message = null;
        }
        _newDecision();
      case StatePatchMessage():
        _game = m.state;
        _deadline = m.deadline;
        _setOffset(m.serverNow);
        _pendingMove = false;
        _message = m.auto && _isMe(m.color)
            ? 'Time ran out, the server moved for you'
            : null;
        _newDecision();
      case PlayerStatusMessage():
        final room = _room;
        if (room == null) return;
        _room = _withPlayers(room, [
          for (final p in room.players)
            p.seat == m.seat
                ? PlayerView(
                    seat: p.seat,
                    userId: p.userId,
                    displayName: p.displayName,
                    color: p.color,
                    isBot: m.isBot,
                    connected: m.connected,
                  )
                : p,
        ]);
      case EmoteEvent():
        _emote = (m.seat, m.id);
      case GameOverMessage():
        _gameOver = m;
        _deadline = null;
        _selection = null;
      default:
    }
  }

  void _onError(ErrorMessage m) {
    switch (m.code) {
      case ErrorCodes.roomNotFound ||
          ErrorCodes.alreadyStarted ||
          ErrorCodes.roomFull ||
          ErrorCodes.unauthorized:
        if (_room == null || m.code == ErrorCodes.unauthorized) {
          _fatal = switch (m.code) {
            ErrorCodes.roomNotFound => 'Room $code was not found',
            ErrorCodes.alreadyStarted => 'That game has already started',
            ErrorCodes.roomFull => 'That room is full',
            _ => 'Please log in again',
          };
          _shutdown();
        }
      case ErrorCodes.illegalMove:
        // The server refused our steps: plan the roll again.
        _pendingMove = false;
        _newDecision();
        _message = 'That move was refused, please try again';
      default:
        _pendingRoll = false;
        _message = m.message;
    }
  }

  void _setOffset(int serverNow) {
    _offset = Duration(
      milliseconds: serverNow - DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _isMe(PlayerColor c) => _you?.color == c;

  bool get _myTurn {
    final g = _game;
    return g != null && _you?.color == g.current && _gameOver == null;
  }

  /// Sets up move selection when the server waits for our move list.
  void _newDecision() {
    _autoTimer?.cancel();
    final g = _game;
    if (g != null &&
        _myTurn &&
        g.phase == TurnPhase.awaitingMove &&
        legalMoves(g).isNotEmpty) {
      _selection = MoveSelection(g);
      _scheduleForced();
    } else {
      _selection = null;
    }
  }

  static RoomView _withPlayers(RoomView r, List<PlayerView> players) =>
      RoomView(
        code: r.code,
        link: r.link,
        mode: r.mode,
        seats: r.seats,
        stake: r.stake,
        status: r.status,
        ownerUserId: r.ownerUserId,
        matchId: r.matchId,
        players: players,
      );

  // --- Actions ----------------------------------------------------------

  bool get _canAct =>
      _socket != null && _connection == Connection.connected && _myTurn;

  @override
  void roll() {
    final g = _game;
    if (!_canAct || _pendingRoll || g?.phase != TurnPhase.awaitingRoll) return;
    _pendingRoll = true;
    _message = null;
    _send((c) => RollMessage(cseq: c));
    _emit();
  }

  @override
  void tapPieces(List<PieceRef> pieces) {
    if (_pendingMove) return;
    _selection?.select(pieces);
    _emit();
  }

  @override
  void chooseOption(MoveOption option) {
    final sel = _selection;
    if (sel == null || _pendingMove || !_canAct) return;
    _autoTimer?.cancel();
    sel.choose(option);
    _afterStep();
  }

  @override
  void undo() {
    final sel = _selection;
    if (sel == null || _pendingMove) return;
    _autoTimer?.cancel();
    if (sel.undo()) _scheduleForced();
    _emit();
  }

  void _afterStep() {
    final sel = _selection!;
    if (sel.rollEnded) {
      _pendingMove = true;
      final steps = sel.steps;
      _send((c) => MoveMessage(moves: steps, cseq: c));
    } else {
      _scheduleForced();
    }
    _emit();
  }

  void _scheduleForced() {
    _autoTimer?.cancel();
    final rest = _selection?.forcedRest;
    if (rest == null) return;
    _autoTimer = Timer(_timings.autoPlay, () {
      final sel = _selection;
      if (sel == null || _pendingMove || !_canAct) return;
      sel.playRest(rest);
      _afterStep();
    });
  }

  void startGame() => _send((c) => StartGameMessage(cseq: c));

  void sendEmote(String id) => _send((c) => EmoteMessage(id: id, cseq: c));

  /// Leaves the lobby, or forfeits a running game.
  void leave() {
    _send((c) => LeaveRoomMessage(cseq: c));
    _shutdown();
  }

  // --- View -------------------------------------------------------------

  void _emit() {
    if (!ref.mounted) return;
    state = _view();
  }

  RoomScreenView _view() {
    final g = _game;
    final you = _you;
    TableView? table;
    if (g != null) {
      table = TableView.of(
        g,
        seats: [
          for (final p in _room?.players ?? const <PlayerView>[])
            if (p.color case final color?)
              SeatView(
                color: color,
                name: p.displayName,
                isBot: p.isBot,
                connected: p.connected,
                isYou: p.seat == you?.seat,
              ),
        ],
        selection: _selection,
        turns: you?.color == null
            ? 0
            : BoardGeometry.viewTurnsFor(you!.color!.index),
        canRoll: _canAct && !_pendingRoll && g.phase == TurnPhase.awaitingRoll,
        deadline: _gameOver == null ? _deadline : null,
        serverOffset: _offset,
        message: _message,
      );
    }
    return RoomScreenView(
      connection: _connection,
      room: _room,
      you: you,
      table: table,
      gameOver: _gameOver,
      fatal: _fatal,
      emote: _emote,
    );
  }
}

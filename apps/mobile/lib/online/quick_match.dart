import 'dart:async';
import 'dart:math';

import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'auth.dart';
import 'room_controller.dart' show onlineTimingsProvider;
import 'socket.dart';

/// A quick match table: a mode with a coin entry or UGX stake (0 is free).
class QuickMatchTable {
  const QuickMatchTable(this.mode, {this.entry = 0, this.stake = 0});

  final GameMode mode;
  final int entry;
  final int stake;

  int get players => mode == GameMode.oneVsOne ? 2 : 4;

  @override
  bool operator ==(Object other) =>
      other is QuickMatchTable &&
      other.mode == mode &&
      other.entry == entry &&
      other.stake == stake;

  @override
  int get hashCode => Object.hash(mode, entry, stake);
}

/// What the search screen shows.
class QuickMatchView {
  const QuickMatchView({
    this.searching = true,
    this.connected = false,
    this.playersFound = 0,
    this.playersNeeded = 2,
    this.waitedSince,
    this.botFillAt,
    this.roomCode,
    this.error,
  });

  /// False once matched, timed out, cancelled or refused.
  final bool searching;
  final bool connected;
  final int playersFound;
  final int playersNeeded;

  /// Local time the search started, for the waiting clock.
  final DateTime? waitedSince;

  /// Local time bots take the empty seats, if they will.
  final DateTime? botFillAt;

  /// Set when matched: open this room.
  final String? roomCode;

  /// Why the search ended without a game.
  final String? error;
}

final quickMatchProvider = NotifierProvider.autoDispose
    .family<QuickMatchController, QuickMatchView, QuickMatchTable>(
      QuickMatchController.new,
    );

/// One search in the quick match queue, on its own socket. A dropped socket
/// reconnects and joins the queue again; the server keeps one place per
/// player.
class QuickMatchController extends Notifier<QuickMatchView> {
  QuickMatchController(this.table);

  final QuickMatchTable table;

  GameSocket? _socket;
  StreamSubscription<ServerMessage>? _sub;
  Timer? _retry;
  int _attempt = 0;
  int _cseq = 0;
  bool _closed = false;
  late final String _clientSeed = _randomSeed();

  @override
  QuickMatchView build() {
    ref.onDispose(_shutdown);
    scheduleMicrotask(_connect);
    return QuickMatchView(
      playersNeeded: table.players,
      waitedSince: DateTime.now(),
    );
  }

  static String _randomSeed() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return String.fromCharCodes(
      List.generate(16, (_) => chars.codeUnitAt(r.nextInt(chars.length))),
    );
  }

  Future<void> _connect() async {
    if (_closed) return;
    final GameSocket socket;
    try {
      final session = await ref.read(authProvider.notifier).ensureSession();
      if (_closed) return;
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
    _sub = socket.messages.listen(_onMessage, onDone: _onClosed);
    _send(
      (c) => QueueJoinMessage(
        mode: table.mode,
        entry: table.entry,
        stake: table.stake,
        clientSeed: _clientSeed,
        cseq: c,
      ),
    );
  }

  void _scheduleRetry() {
    if (_closed) return;
    _set(connected: false);
    final timings = ref.read(onlineTimingsProvider);
    final ms = min(
      timings.firstRetry.inMilliseconds * (1 << min(_attempt, 10)),
      timings.maxRetry.inMilliseconds,
    );
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(milliseconds: ms), _connect);
  }

  void _onClosed() {
    _socket = null;
    _sub = null;
    if (!_closed && state.searching) _scheduleRetry();
  }

  void _send(ClientMessage Function(int cseq) build) =>
      _socket?.send(build(++_cseq));

  void _onMessage(ServerMessage m) {
    switch (m) {
      case QueueStatusMessage():
        _onStatus(m);
      case ErrorMessage():
        _finish(error: _errorText(m));
      default:
    }
  }

  void _onStatus(QueueStatusMessage m) {
    switch (m.state) {
      case QueueState.waiting:
        final now = DateTime.now();
        final offset = m.serverNow - now.millisecondsSinceEpoch;
        final fill = m.botFillAt;
        state = QuickMatchView(
          connected: true,
          playersFound: m.playersFound,
          playersNeeded: m.playersNeeded,
          waitedSince: now.subtract(Duration(seconds: m.waited)),
          botFillAt: fill == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(fill - offset),
        );
      case QueueState.matched:
        _finish(roomCode: m.roomCode);
      case QueueState.timeout:
        _finish(error: 'Nobody else is looking for this table right now');
      case QueueState.cancelled:
        _finish(error: 'The search was stopped');
    }
  }

  static String _errorText(ErrorMessage m) => switch (m.code) {
    ErrorCodes.queueBusy => 'You are already in a game or another search',
    ErrorCodes.paidTablesDisabled => 'Paid tables are not open yet',
    ErrorCodes.phoneRequired => 'Log in with your phone number first',
    ErrorCodes.insufficientFunds => 'You do not have enough for this table',
    _ => m.message,
  };

  void _finish({String? roomCode, String? error}) {
    state = QuickMatchView(
      searching: false,
      connected: state.connected,
      playersFound: state.playersFound,
      playersNeeded: state.playersNeeded,
      waitedSince: state.waitedSince,
      roomCode: roomCode,
      error: error,
    );
    _shutdown();
  }

  void _set({required bool connected}) {
    state = QuickMatchView(
      searching: state.searching,
      connected: connected,
      playersFound: state.playersFound,
      playersNeeded: state.playersNeeded,
      waitedSince: state.waitedSince,
      botFillAt: state.botFillAt,
    );
  }

  /// Stops searching.
  void cancel() {
    _send((c) => QueueLeaveMessage(cseq: c));
    _shutdown();
  }

  void _shutdown() {
    _closed = true;
    _retry?.cancel();
    _sub?.cancel();
    _socket?.close();
    _socket = null;
  }
}

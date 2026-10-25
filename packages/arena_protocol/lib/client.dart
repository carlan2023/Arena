/// Headless Arena client for tests and bots: HTTP login and rooms, plus the
/// game web socket.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:ludo_engine/ludo_engine.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'arena_protocol.dart';

export 'arena_protocol.dart';

class ArenaClient {
  ArenaClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client(),
      _ownsHttp = httpClient == null;

  /// For example http://localhost:8080.
  final Uri baseUrl;
  final http.Client _http;
  final bool _ownsHttp;

  String? sessionToken;
  UserView? user;

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _sub;
  int _cseq = 0;
  final _messages = StreamController<ServerMessage>.broadcast();
  final List<ServerMessage> _log = [];

  /// Every known server message received on the socket, in order.
  Stream<ServerMessage> get messages => _messages.stream;

  /// Everything received since [connect], in order. Tests use it to avoid
  /// racing the broadcast stream.
  List<ServerMessage> get received => List.unmodifiable(_log);

  bool get isConnected => _channel != null;

  // --- HTTP -----------------------------------------------------------------

  /// POST /v1/auth/login. With AUTH_PROVIDER=fake use `fake:+2567...`.
  Future<UserView> login(String idToken) async {
    final body = await _send('POST', '/v1/auth/login', {'idToken': idToken});
    sessionToken = body['sessionToken'] as String;
    return user = UserView.fromJson(_asJson(body['user']));
  }

  /// POST /v1/auth/guest. A guest account for free play, no phone needed.
  Future<UserView> guest() async {
    final body = await _send('POST', '/v1/auth/guest');
    sessionToken = body['sessionToken'] as String;
    return user = UserView.fromJson(_asJson(body['user']));
  }

  Future<UserView> me() async =>
      UserView.fromJson(await _send('GET', '/v1/me'));

  Future<UserView> setDisplayName(String name) async =>
      UserView.fromJson(await _send('PATCH', '/v1/me', {'displayName': name}));

  /// Changes the display name, the avatar, or both (M3.3).
  Future<UserView> setProfile({String? displayName, int? avatar}) async =>
      UserView.fromJson(
        await _send('PATCH', '/v1/me', {
          'displayName': ?displayName,
          'avatar': ?avatar,
        }),
      );

  Future<RoomView> createRoom({
    GameMode mode = GameMode.oneVsOne,
    int seats = 2,
    int stake = 0,
    int entry = 0,
    RulesConfig? rules,
  }) async => RoomView.fromJson(
    await _send('POST', '/v1/rooms', {
      'mode': mode.name,
      'seats': seats,
      'stake': stake,
      'entry': entry,
      'rules': ?rules?.toJson(),
    }),
  );

  Future<RoomView> getRoom(String code) async =>
      RoomView.fromJson(await _send('GET', '/v1/rooms/$code'));

  Future<MatchVerification> verifyMatch(String matchId) async =>
      MatchVerification.fromJson(
        await _send('GET', '/v1/matches/$matchId/verify'),
      );

  /// Coin balance and the daily reward (M3.4).
  Future<CoinsView> coins() async =>
      CoinsView.fromJson(await _send('GET', '/v1/coins'));

  /// Claims today's reward. Throws [ApiError] already_claimed (409) when it
  /// was claimed today.
  Future<CoinGrantView> claimDailyReward() async =>
      CoinGrantView.fromJson(await _send('POST', '/v1/coins/daily'));

  /// Open coin entries and paid stakes.
  Future<TablesView> tables() async =>
      TablesView.fromJson(await _send('GET', '/v1/tables'));

  /// POST /v1/me/date-of-birth. Once only. Under MIN_AGE the server answers
  /// 403 age_required and still stores the date.
  Future<UserView> setDateOfBirth(String dateOfBirth) async =>
      UserView.fromJson(
        await _send('POST', '/v1/me/date-of-birth', {
          'dateOfBirth': dateOfBirth,
        }),
      );

  /// UGX balance. Needs a phone login. Age is not required to read it.
  Future<int> walletBalance() async {
    final body = await _send('GET', '/v1/wallet');
    final balance = body['balance'];
    if (balance is! int) throw ProtocolException('balance must be an integer');
    return balance;
  }

  /// Newest first. [limit] is 1 to 200.
  Future<List<WalletEntryView>> walletHistory({int limit = 50}) async {
    final body = await _send('GET', '/v1/wallet/history?limit=$limit');
    return [
      for (final entry in body['entries'] as List)
        WalletEntryView.fromJson((entry as Map).cast()),
    ];
  }

  /// Starts a deposit. With the fake provider, [confirmDeposit] completes it.
  Future<PaymentView> deposit({
    required int amount,
    required String msisdn,
    String provider = 'fake',
  }) async => PaymentView.fromJson(
    await _send('POST', '/v1/wallet/deposits', {
      'amount': amount,
      'msisdn': msisdn,
      'provider': provider,
    }),
  );

  /// POST /v1/dev/payments/{id}/confirm. 404 when the fake provider is off.
  Future<PaymentView> confirmDeposit(
    String paymentId, {
    String status = 'succeeded',
  }) async => PaymentView.fromJson(
    await _send('POST', '/v1/dev/payments/$paymentId/confirm', {
      'status': status,
    }),
  );

  Future<LimitsView> limits() async =>
      LimitsView.fromJson(await _send('GET', '/v1/wallet/limits'));

  Future<LimitsView> setLimits({int? daily, int? weekly, int? monthly}) async =>
      LimitsView.fromJson(
        await _send('PUT', '/v1/wallet/limits', {
          'daily': ?daily,
          'weekly': ?weekly,
          'monthly': ?monthly,
        }),
      );

  /// [period] is `1d`, `7d`, `30d`, `6m` or `permanent`.
  Future<LimitsView> selfExclude(String period) async => LimitsView.fromJson(
    await _send('POST', '/v1/wallet/self-exclusion', {'period': period}),
  );

  /// The caller's last 20 ended matches, newest first.
  Future<List<RecentMatchView>> recentMatches() async {
    final j = await _send('GET', '/v1/matches/recent');
    return [
      for (final m in j['matches'] as List) RecentMatchView.fromJson(m as Json),
    ];
  }

  /// Any JSON route. Throws [ApiError] on an error status.
  Future<Json> request(String method, String path, [Json? body]) =>
      _send(method, path, body);

  Future<Json> _send(String method, String path, [Json? body]) async {
    final req = http.Request(method, baseUrl.resolve(path));
    if (sessionToken != null) {
      req.headers['Authorization'] = 'Bearer $sessionToken';
    }
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final res = await http.Response.fromStream(await _http.send(req));
    final Object? decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final err = decoded is Map ? decoded['error'] : null;
      if (err is Map) {
        throw ApiError(res.statusCode, '${err['code']}', '${err['message']}');
      }
      throw ApiError(res.statusCode, 'http_${res.statusCode}', res.body);
    }
    return _asJson(decoded);
  }

  // --- Web socket -------------------------------------------------------------

  /// Opens GET /v1/ws with the session token. Replaces any open socket.
  Future<void> connect() async {
    final token = sessionToken;
    if (token == null) throw StateError('login first');
    await disconnect();
    final scheme = baseUrl.scheme == 'https' ? 'wss' : 'ws';
    final uri = baseUrl
        .resolve('/v1/ws')
        .replace(scheme: scheme, queryParameters: {'token': token});
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;
    _sub = channel.stream.listen(
      (frame) {
        if (frame is! String) return;
        final ServerMessage msg;
        try {
          msg = ServerMessage.decode(frame);
        } on ProtocolException {
          return;
        }
        if (msg is UnknownServerMessage) return;
        _log.add(msg);
        _messages.add(msg);
      },
      onDone: () {
        if (identical(_channel, channel)) _channel = null;
      },
    );
  }

  /// Closes the socket, as if the network dropped.
  Future<void> disconnect() async {
    final channel = _channel;
    _channel = null;
    await _sub?.cancel();
    _sub = null;
    await channel?.sink.close();
  }

  /// Closes the socket and the HTTP client.
  Future<void> close() async {
    await disconnect();
    await _messages.close();
    if (_ownsHttp) _http.close();
  }

  int _nextCseq() => ++_cseq;

  int _sendMessage(ClientMessage Function(int cseq) build) {
    final channel = _channel;
    if (channel == null) throw StateError('not connected');
    final cseq = _nextCseq();
    channel.sink.add(build(cseq).encode());
    return cseq;
  }

  /// Each send returns the cseq it used.
  int joinRoom(String roomCode, {String? clientSeed, int? lastSeq}) =>
      _sendMessage(
        (c) => JoinRoomMessage(
          roomCode: roomCode,
          clientSeed: clientSeed,
          lastSeq: lastSeq,
          cseq: c,
        ),
      );
  int startGame() => _sendMessage((c) => StartGameMessage(cseq: c));
  int roll() => _sendMessage((c) => RollMessage(cseq: c));
  int move(List<Move> moves) =>
      _sendMessage((c) => MoveMessage(moves: moves, cseq: c));
  int leaveRoom() => _sendMessage((c) => LeaveRoomMessage(cseq: c));
  int emote(String id) => _sendMessage((c) => EmoteMessage(id: id, cseq: c));
  int ping() => _sendMessage((c) => PingMessage(cseq: c));
  int queueJoin({
    GameMode mode = GameMode.oneVsOne,
    int entry = 0,
    int stake = 0,
    String? clientSeed,
  }) => _sendMessage(
    (c) => QueueJoinMessage(
      mode: mode,
      entry: entry,
      stake: stake,
      clientSeed: clientSeed,
      cseq: c,
    ),
  );
  int queueLeave() => _sendMessage((c) => QueueLeaveMessage(cseq: c));

  /// Sends a raw frame, for tests of bad input.
  void sendRaw(String frame) {
    final channel = _channel;
    if (channel == null) throw StateError('not connected');
    channel.sink.add(frame);
  }

  /// The first message of type [T] received after [after] messages in
  /// [received] (default: any time) that matches [where].
  Future<T> next<T extends ServerMessage>({
    bool Function(T message)? where,
    int? after,
    Duration timeout = const Duration(seconds: 10),
  }) {
    bool matches(ServerMessage m) => m is T && (where == null || where(m));
    final start = after ?? 0;
    for (var i = start; i < _log.length; i++) {
      if (matches(_log[i])) return Future.value(_log[i] as T);
    }
    return messages.firstWhere(matches).then((m) => m as T).timeout(timeout);
  }
}

Json _asJson(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw ProtocolException('expected a JSON object');
}

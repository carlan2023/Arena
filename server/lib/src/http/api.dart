import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpConnectionInfo;

import 'package:arena_auth/arena_auth.dart';
import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_wallet/arena_wallet.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../config.dart';
import '../clock.dart';
import '../rate_limit.dart';
import '../rooms/room.dart' show validSeats;
import '../rooms/room_manager.dart';
import '../store/match_log.dart';
import 'landing.dart';

/// An error that becomes `{"error": {"code", "message"}}`.
class HttpError implements Exception {
  HttpError(this.status, this.code, this.message);
  final int status;
  final String code;
  final String message;
}

/// Every JSON route in docs/contracts/protocol.md except the web socket.
class Api {
  Api({
    required this.config,
    required this.clock,
    required this.auth,
    required this.users,
    required this.ledger,
    required this.payments,
    required this.paymentStore,
    required this.limits,
    required this.rooms,
    required this.matchLog,
    required this.coins,
    this.fakePayments,
  }) : _roomCreates = RateLimiter(
         limit: config.roomCreatesPerHour,
         window: const Duration(hours: 1),
         clock: clock,
       ),
       _guests = RateLimiter(
         limit: config.guestsPerHour,
         window: const Duration(hours: 1),
         clock: clock,
       );

  final ServerConfig config;
  final Clock clock;
  final AuthService auth;
  final UserStore users;
  final Ledger ledger;
  final PaymentsService payments;
  final PaymentStore paymentStore;
  final LimitsService limits;
  final RoomManager rooms;
  final MatchLog matchLog;
  final CoinService coins;

  /// Set when PAYMENTS_PROVIDER=fake; enables the dev confirm route.
  final FakePaymentProvider? fakePayments;
  final RateLimiter _roomCreates;
  final RateLimiter _guests;

  Router router() {
    final r = Router(
      notFoundHandler: (_) =>
          _errorResponse(HttpError(404, 'not_found', 'no such route')),
    );
    r.get(
      '/health',
      (Request req) => _json({'ok': true, 'version': config.appVersion}),
    );
    r.post('/v1/auth/login', _wrap(_login, authed: false));
    r.post('/v1/auth/guest', _wrap(_guest, authed: false));
    r.get('/v1/me', _wrap(_me));
    r.patch('/v1/me', _wrap(_patchMe));
    r.post('/v1/me/date-of-birth', _wrap(_dateOfBirth));
    r.get('/v1/coins', _wrap(_coins));
    r.post('/v1/coins/daily', _wrap(_claimDaily));
    r.get('/v1/tables', _wrap(_tables));
    r.post('/v1/rooms', _wrap(_createRoom));
    r.get('/v1/rooms/<code>', _wrap(_getRoom));
    r.get('/v1/wallet', _wrap(_wallet));
    r.get('/v1/wallet/history', _wrap(_history));
    r.get('/v1/wallet/limits', _wrap(_getLimits));
    r.put('/v1/wallet/limits', _wrap(_setLimits));
    r.post('/v1/wallet/self-exclusion', _wrap(_selfExclude));
    r.post('/v1/wallet/deposits', _wrap(_deposit));
    r.get('/v1/wallet/deposits/<id>', _wrap(_getDeposit));
    // D28: MTN sometimes calls back with PUT.
    r.post('/v1/payments/callback/<provider>', _wrap(_callback, authed: false));
    r.put('/v1/payments/callback/<provider>', _wrap(_callback, authed: false));
    r.post('/v1/dev/payments/<id>/confirm', _wrap(_devConfirm));
    r.get('/v1/matches/recent', _wrap(_recentMatches));
    r.get('/v1/matches/<id>/verify', _wrap(_verify));
    r.get(
      '/r/<code>',
      (Request req, String code) => landingPage(
        code: code.toUpperCase(),
        room: rooms.room(code),
        config: config,
      ),
    );
    return r;
  }

  /// Resolves the bearer token to a user, or null.
  Future<User?> userFor(String? token) async {
    if (token == null || token.isEmpty) return null;
    try {
      return await auth.authenticate(token);
    } on Object {
      return null;
    }
  }

  Handler _wrap(
    FutureOr<Object?> Function(Request req, User? user, List<String> params)
    handler, {
    bool authed = true,
  }) {
    return (Request req) async {
      try {
        User? user;
        if (authed) {
          final header = req.headers['authorization'] ?? '';
          final token = header.startsWith('Bearer ')
              ? header.substring(7)
              : null;
          user = await userFor(token);
          if (user == null) {
            throw HttpError(401, ErrorCodes.unauthorized, 'log in first');
          }
        }
        final params = req.params.values.toList();
        final result = await handler(req, user, params);
        if (result is Response) return result;
        return _json(result);
      } on HttpError catch (e) {
        return _errorResponse(e);
      } on PaymentException catch (e) {
        return _errorResponse(
          HttpError(e.code == 'not_found' ? 404 : 400, e.code, e.message),
        );
      } on SelfExcludedException {
        return _errorResponse(
          HttpError(
            403,
            ErrorCodes.selfExcluded,
            'self exclusion is in effect',
          ),
        );
      } on LimitExceededException catch (e) {
        return _errorResponse(
          HttpError(
            403,
            ErrorCodes.limitExceeded,
            '${e.window} deposit limit of ${e.limit} UGX is reached '
            '(${e.used} already used)',
          ),
        );
      } catch (e, st) {
        // ignore: avoid_print
        print('ERROR ${req.method} ${req.url.path}: $e\n$st');
        return _errorResponse(
          HttpError(500, ErrorCodes.internal, 'internal error'),
        );
      }
    };
  }

  // --- Auth ------------------------------------------------------------------

  Future<Object?> _login(Request req, User? _, List<String> _) async {
    final body = await _body(req);
    final idToken = body['idToken'];
    if (idToken is! String || idToken.isEmpty) {
      throw HttpError(400, ErrorCodes.badRequest, 'idToken is required');
    }
    try {
      final (token, user) = await auth.login(idToken);
      return {'sessionToken': token, 'user': await _user(user)};
    } on AuthException catch (e) {
      throw HttpError(401, ErrorCodes.unauthorized, e.message);
    }
  }

  /// D33: free play needs no phone. Limited per client address.
  Future<Object?> _guest(Request req, User? _, List<String> _) async {
    if (!_guests.allow(_clientAddress(req))) {
      throw HttpError(429, ErrorCodes.rateLimited, 'too many guest accounts');
    }
    final (token, user) = await auth.guest();
    return {'sessionToken': token, 'user': await _user(user)};
  }

  String _clientAddress(Request req) {
    final forwarded = req.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = req.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  /// Paid play and the wallet need a verified phone (D33).
  void _requirePhone(User user) {
    if (user.isGuest) {
      throw HttpError(
        403,
        ErrorCodes.phoneRequired,
        'log in with your phone number to use the wallet and paid tables',
      );
    }
  }

  DateTime get _now =>
      DateTime.fromMillisecondsSinceEpoch(clock.nowMs(), isUtc: true);

  /// Deposits and a stake above 0 need a stored date of birth of at least
  /// [ServerConfig.minAge] years. Reading the wallet does not.
  void _requireAdult(User user) {
    final dob = user.dateOfBirth;
    if (dob == null || !isOldEnough(dob, _now, config.minAge)) {
      throw HttpError(
        403,
        ErrorCodes.ageRequired,
        'you must be ${config.minAge} or older',
      );
    }
  }

  Future<Object?> _me(Request req, User? user, List<String> _) => _user(user!);

  Future<Object?> _patchMe(Request req, User? user, List<String> _) async {
    final body = await _body(req);
    final name = body['displayName'];
    final avatar = body['avatar'];
    if ((name == null && avatar == null) ||
        (name != null && name is! String) ||
        (avatar != null && avatar is! int)) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'send a displayName string, an avatar number, or both',
      );
    }
    try {
      // Both are checked before either is saved.
      if (name is String) normalizeDisplayName(name);
      if (avatar is int) checkAvatar(avatar);
      var updated = user!;
      if (name is String) updated = await users.setDisplayName(user.id, name);
      if (avatar is int) updated = await users.setAvatar(user.id, avatar);
      return await _user(updated);
    } on ArgumentError catch (e) {
      throw HttpError(400, ErrorCodes.badRequest, '${e.message}');
    } on StateError catch (e) {
      throw HttpError(404, 'not_found', e.message);
    }
  }

  Future<Object?> _dateOfBirth(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    final body = await _body(req);
    final raw = body['dateOfBirth'];
    if (raw is! String) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'dateOfBirth must be yyyy-mm-dd',
      );
    }
    final dob = parseDateOfBirth(raw);
    if (dob == null) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'dateOfBirth must be a real date, yyyy-mm-dd',
      );
    }
    if (dob.isAfter(utcDate(_now))) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'date of birth cannot be in the future',
      );
    }
    try {
      final updated = await users.setDateOfBirth(user.id, dob);
      if (!isOldEnough(dob, _now, config.minAge)) {
        throw HttpError(
          403,
          ErrorCodes.ageRequired,
          'you must be ${config.minAge} or older',
        );
      }
      return await _user(updated);
    } on DateOfBirthAlreadySetException {
      throw HttpError(
        409,
        ErrorCodes.alreadySet,
        'date of birth is already set',
      );
    } on StateError catch (e) {
      throw HttpError(404, 'not_found', e.message);
    }
  }

  /// The user with their coin balance. The signup grant (D36) is made here,
  /// once per account, so accounts from before coins existed get it too.
  Future<Json> _user(User u) async {
    await coins.grantSignup(u.id);
    return UserView(
      id: u.id,
      phone: u.phone,
      displayName: u.displayName,
      avatar: u.avatar,
      coins: await coins.balance(u.id),
      dateOfBirth: u.dateOfBirth == null
          ? null
          : formatDateOfBirth(u.dateOfBirth!),
    ).toJson();
  }

  // --- Coins (M3.4) ------------------------------------------------------------

  Future<Object?> _coins(Request req, User? user, List<String> _) async {
    await coins.grantSignup(user!.id);
    final daily = await coins.dailyStatus(user.id);
    return CoinsView(
      balance: await coins.balance(user.id),
      dailyReward: DailyRewardView(
        available: daily.available,
        amount: daily.amount,
        streak: daily.streak,
        nextAt: daily.nextAt,
      ),
    ).toJson();
  }

  Future<Object?> _claimDaily(Request req, User? user, List<String> _) async {
    try {
      final grant = await coins.claimDaily(user!.id);
      return CoinGrantView(
        balance: grant.balance,
        granted: grant.granted,
        streak: grant.streak,
      ).toJson();
    } on AlreadyClaimedException catch (e) {
      throw HttpError(
        409,
        ErrorCodes.alreadyClaimed,
        'already claimed today; next at ${e.nextAt.toIso8601String()}',
      );
    }
  }

  Future<Object?> _recentMatches(
    Request req,
    User? user,
    List<String> _,
  ) async {
    final matches = await matchLog.recentMatches(user!.id);
    return {
      'matches': [
        for (final m in matches)
          RecentMatchView(
            matchId: m.matchId,
            mode: parseMode(m.mode),
            stake: m.stake,
            entry: m.entry,
            abandoned: m.status == MatchStatus.abandoned,
            endedAt: m.endedAt,
            rank: m.players.where((p) => p.userId == user.id).first.place,
            players: [
              for (final p in m.players)
                RecentPlayerView(
                  seat: p.seat,
                  displayName: p.displayName,
                  avatar: p.avatar,
                  isBot: p.isBot,
                  rank: p.place,
                ),
            ],
          ).toJson(),
      ],
    };
  }

  // --- Rooms -----------------------------------------------------------------

  Future<Object?> _createRoom(Request req, User? user, List<String> _) async {
    final body = await _body(req);
    final mode = GameMode.values
        .where((m) => m.name == body['mode'])
        .firstOrNull;
    final seats = body['seats'];
    final stake = body['stake'] ?? 0;
    final entry = body['entry'] ?? 0;
    final rulesJson = body['rules'];
    if (mode == null || seats is! int || stake is! int || entry is! int) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'mode, seats, stake and entry must be valid',
      );
    }
    if (!validSeats(mode, seats)) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        '${mode.name} does not allow $seats seats',
      );
    }
    if (rulesJson != null && rulesJson is! Map) {
      throw HttpError(400, ErrorCodes.badRequest, 'rules must be an object');
    }
    RulesConfig rules;
    try {
      rules = rulesJson == null
          ? const RulesConfig()
          : RulesConfig.fromJson((rulesJson as Map).cast());
    } catch (e) {
      throw HttpError(400, ErrorCodes.badRequest, 'bad rules: $e');
    }
    if (entry > 0 && stake > 0) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'a room cannot take both coins and a stake',
      );
    }
    if (entry > 0 && !const CoinTableSettings().allows(entry)) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'that coin table is not open',
      );
    }
    if (stake > 0) {
      _requirePhone(user!);
      _requireAdult(user);
      await limits.checkPlay(user.id);
    }
    if (stake > 0 && !config.paidTablesEnabled) {
      throw HttpError(
        403,
        ErrorCodes.paidTablesDisabled,
        'paid tables are not open yet',
      );
    }
    if (!_roomCreates.allow(user!.id)) {
      throw HttpError(
        429,
        ErrorCodes.rateLimited,
        'too many rooms created, try again later',
      );
    }
    try {
      final room = rooms.createRoom(
        ownerUserId: user.id,
        mode: mode,
        seats: seats,
        stake: stake,
        entry: entry,
        rules: rules,
      );
      return rooms.view(room).toJson();
    } on RoomException catch (e) {
      throw HttpError(400, e.code, e.message);
    }
  }

  Object? _tables(Request req, User? _, List<String> _) => TablesView(
    coin: const CoinTableSettings().entries,
    paid: CoinTableSettings.paidStakes,
    paidEnabled: config.paidTablesEnabled,
  ).toJson();

  Object? _getRoom(Request req, User? _, List<String> params) {
    final room = rooms.room(params[0]);
    if (room == null) {
      throw HttpError(404, ErrorCodes.roomNotFound, 'no such room');
    }
    return rooms.view(room).toJson();
  }

  // --- Wallet ----------------------------------------------------------------

  Future<Object?> _wallet(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    return {
      'balance': await ledger.balance(AccountId.wallet(user.id)),
      'currency': 'UGX',
    };
  }

  Future<Object?> _history(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    final raw = req.url.queryParameters['limit'];
    final limit = raw == null ? 50 : int.tryParse(raw);
    if (limit == null || limit < 1 || limit > 200) {
      throw HttpError(400, ErrorCodes.badRequest, 'limit must be 1 to 200');
    }
    final entries = await ledger.history(
      AccountId.wallet(user.id),
      limit: limit,
    );
    return {
      'entries': [
        for (final e in entries)
          WalletEntryView(
            txId: e.txId,
            kind: e.kind,
            amount: e.amount,
            balanceAfter: e.balanceAfter,
            at: e.at,
          ).toJson(),
      ],
    };
  }

  Future<Object?> _getLimits(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    return _limitsJson(await limits.limits(user.id));
  }

  Future<Object?> _setLimits(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    final body = await _body(req);
    final daily = body['daily'];
    final weekly = body['weekly'];
    final monthly = body['monthly'];
    if (daily == null && weekly == null && monthly == null) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'send a daily, weekly or monthly limit',
      );
    }
    for (final value in [daily, weekly, monthly]) {
      if (value != null && value is! int) {
        throw HttpError(
          400,
          ErrorCodes.badRequest,
          'limits must be whole numbers of UGX',
        );
      }
    }
    try {
      return _limitsJson(
        await limits.setLimits(
          user.id,
          daily: daily as int?,
          weekly: weekly as int?,
          monthly: monthly as int?,
        ),
      );
    } on ArgumentError catch (e) {
      throw HttpError(400, ErrorCodes.badRequest, '${e.message}');
    }
  }

  Future<Object?> _selfExclude(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    final body = await _body(req);
    final raw = body['period'];
    final period = raw is String ? exclusionPeriodFromApi(raw) : null;
    if (period == null) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'period must be 1d, 7d, 30d, 6m or permanent',
      );
    }
    return _limitsJson(await limits.selfExclude(user.id, period));
  }

  Json _limitsJson(PlayerLimits row) => LimitsView(
    daily: row.daily,
    weekly: row.weekly,
    monthly: row.monthly,
    pending: !row.hasPending || row.pendingAt == null
        ? null
        : PendingLimitsView(
            at: row.pendingAt!,
            daily: row.pendingDaily,
            weekly: row.pendingWeekly,
            monthly: row.pendingMonthly,
          ),
    excludedUntil: row.excludedUntil,
    permanent: row.permanent,
  ).toJson();

  Future<Object?> _deposit(Request req, User? user, List<String> _) async {
    _requirePhone(user!);
    _requireAdult(user);
    final body = await _body(req);
    final amount = body['amount'];
    final msisdn = body['msisdn'];
    final provider = body['provider'];
    if (amount is! int || msisdn is! String || provider is! String) {
      throw HttpError(
        400,
        ErrorCodes.badRequest,
        'amount, msisdn and provider are required',
      );
    }
    if (!const {'fake', 'mtn', 'airtel'}.contains(provider)) {
      throw HttpError(400, ErrorCodes.badRequest, 'unknown provider');
    }
    // With fake payments every deposit goes to the fake provider, whichever
    // network the player picked.
    final name = config.fakePayments ? 'fake' : provider;
    final payment = await payments.startDeposit(
      userId: user.id,
      provider: name,
      amount: amount,
      msisdn: msisdn,
    );
    return _payment(payment);
  }

  Future<Object?> _getDeposit(Request req, User? user, List<String> p) async {
    var payment = await _ownPayment(user!, p[0]);
    if (payment.status == PaymentStatus.pending) {
      try {
        payment = await payments.refresh(payment.id);
      } on PaymentException {
        rethrow;
      } on Object catch (e) {
        // Provider unreachable: report the stored state.
        // ignore: avoid_print
        print('refresh ${payment.id} failed: $e');
      }
    }
    return _payment(payment);
  }

  Future<Payment> _ownPayment(User user, String id) async {
    final payment = await paymentStore.byId(id);
    if (payment == null || payment.userId != user.id) {
      throw HttpError(404, 'not_found', 'no such payment');
    }
    return payment;
  }

  Future<Object?> _callback(Request req, User? _, List<String> p) async {
    final body = await req.readAsString();
    await payments.handleCallback(p[0], req.headers, body);
    return {'ok': true};
  }

  Future<Object?> _devConfirm(Request req, User? user, List<String> p) async {
    final fake = fakePayments;
    if (fake == null) throw HttpError(404, 'not_found', 'no such route');
    final payment = await _ownPayment(user!, p[0]);
    final body = await _body(req, allowEmpty: true);
    final status = body['status'] == 'failed'
        ? PaymentStatus.failed
        : PaymentStatus.succeeded;
    if (payment.status == PaymentStatus.pending) {
      fake.complete(payment.providerRef ?? payment.id, status: status);
    }
    return _payment(await payments.refresh(payment.id));
  }

  Json _payment(Payment p) => PaymentView(
    id: p.id,
    provider: p.provider,
    amount: p.amount,
    status: p.status.name,
    createdAt: p.createdAt,
  ).toJson();

  // --- Matches ---------------------------------------------------------------

  Future<Object?> _verify(Request req, User? _, List<String> p) async {
    final match = await matchLog.loadMatch(p[0]);
    if (match == null) throw HttpError(404, 'not_found', 'no such match');
    final seed = match.serverSeed;
    if (seed == null) {
      throw HttpError(409, ErrorCodes.wrongPhase, 'the match is still running');
    }
    return MatchVerification(
      serverSeed: seed,
      serverSeedHash: match.serverSeedHash,
      clientSeed: match.clientSeed,
      rolls: match.rolls,
    ).toJson();
  }

  // --- Helpers ---------------------------------------------------------------

  Future<Json> _body(Request req, {bool allowEmpty = false}) async {
    final text = await req.readAsString();
    if (text.trim().isEmpty && allowEmpty) return {};
    try {
      final v = jsonDecode(text);
      if (v is Map) return v.cast<String, Object?>();
    } on FormatException {
      // Falls through.
    }
    throw HttpError(400, ErrorCodes.badRequest, 'body must be a JSON object');
  }
}

Response _json(Object? body, {int status = 200}) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Response _errorResponse(HttpError e) => _json({
  'error': {'code': e.code, 'message': e.message},
}, status: e.status);

/// Logs method, path, status and time. Never logs the query string, which can
/// hold the session token on /v1/ws.
Middleware logRequestPaths(void Function(String line) log) {
  return (inner) => (req) async {
    final sw = Stopwatch()..start();
    final res = await inner(req);
    log(
      '${req.method} /${req.url.path} ${res.statusCode} '
      '${sw.elapsedMilliseconds}ms',
    );
    return res;
  };
}

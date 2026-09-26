import 'dart:io';
import 'dart:math';

import 'package:arena_auth/arena_auth.dart' as auth;
import 'package:arena_auth/arena_auth.dart'
    show
        AuthService,
        FakeTokenVerifier,
        FirebaseTokenVerifier,
        InMemoryUserStore,
        PostgresUserStore,
        SessionTokens,
        TokenVerifier,
        UserStore;
import 'package:arena_wallet/arena_wallet.dart' as wallet;
import 'package:arena_wallet/arena_wallet.dart'
    show
        AirtelMoneyProvider,
        FakePaymentProvider,
        InMemoryLedger,
        InMemoryPaymentStore,
        Ledger,
        MtnMomoProvider,
        PaymentProvider,
        PaymentStore,
        PaymentsService,
        PostgresLedger,
        PostgresPaymentStore;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../config.dart';
import 'bot.dart';
import 'clock.dart';
import 'http/api.dart';
import 'http/ws.dart';
import 'rooms/room_manager.dart';
import 'store/live_store.dart';
import 'store/match_log.dart';
import 'store/migrations.dart';
import 'store/postgres_match_log.dart';

/// Replacements for the parts [startServer] would otherwise build from the
/// config. Tests use them to inject a fake clock or pre-made stores.
class ServerOverrides {
  const ServerOverrides({
    this.clock,
    this.random,
    this.tokenVerifier,
    this.chooseMoves,
    this.liveStore,
    this.matchLog,
    this.users,
    this.ledger,
    this.paymentStore,
    this.log,
  });

  final Clock? clock;
  final Random? random;
  final TokenVerifier? tokenVerifier;
  final MoveChooser? chooseMoves;
  final LiveRoomStore? liveStore;
  final MatchLog? matchLog;
  final UserStore? users;
  final Ledger? ledger;
  final PaymentStore? paymentStore;

  /// Request and error log lines. Default: print. Pass `(_) {}` for silence.
  final void Function(String line)? log;
}

/// A server listening on [baseUrl]. Close it when done.
class RunningServer {
  RunningServer._({
    required this.server,
    required this.config,
    required this.clock,
    required this.rooms,
    required this.auth,
    required this.users,
    required this.ledger,
    required this.payments,
    required this.paymentStore,
    required this.matchLog,
    required this.liveStore,
    required this.fakePayments,
    required Pool? pool,
  }) : _pool = pool;

  final HttpServer server;
  final ServerConfig config;
  final Clock clock;
  final RoomManager rooms;
  final AuthService auth;
  final UserStore users;
  final Ledger ledger;
  final PaymentsService payments;
  final PaymentStore paymentStore;
  final MatchLog matchLog;
  final LiveRoomStore liveStore;

  /// The fake provider when PAYMENTS_PROVIDER=fake.
  final FakePaymentProvider? fakePayments;
  final Pool? _pool;

  int get port => server.port;

  /// For example http://127.0.0.1:54321.
  Uri get baseUrl => Uri(
    scheme: 'http',
    host: server.address.isLoopback ? '127.0.0.1' : server.address.address,
    port: server.port,
  );

  /// Stops timers, drains queued writes and closes every connection.
  Future<void> close() async {
    rooms.dispose();
    await server.close(force: true);
    await rooms.flush();
    await liveStore.close();
    await _pool?.close();
  }
}

/// Builds every service from [config] and starts listening. With no
/// DATABASE_URL and no REDIS_URL everything lives in memory, which is what
/// tests use: `startServer(ServerConfig.forTests())`.
Future<RunningServer> startServer(
  ServerConfig config, {
  ServerOverrides overrides = const ServerOverrides(),
}) async {
  final log = overrides.log ?? print;
  final clock = overrides.clock ?? const SystemClock();
  DateTime now() =>
      DateTime.fromMillisecondsSinceEpoch(clock.nowMs(), isUtc: true);

  Pool? pool;
  final dbUrl = config.databaseUrl;
  if (dbUrl != null) {
    pool = openPool(dbUrl);
    final applied = await runMigrations(pool, [
      ...auth.migrations,
      ...wallet.migrations,
      ...serverMigrations,
    ]);
    if (applied.isNotEmpty) log('applied migrations: ${applied.join(', ')}');
  }

  final users =
      overrides.users ??
      (pool != null ? PostgresUserStore(pool) : InMemoryUserStore(clock: now));
  final ledger =
      overrides.ledger ??
      (pool != null ? PostgresLedger(pool) : InMemoryLedger(clock: now));
  final paymentStore =
      overrides.paymentStore ??
      (pool != null
          ? PostgresPaymentStore(pool)
          : InMemoryPaymentStore(clock: now));
  final matchLog =
      overrides.matchLog ??
      (pool != null ? PostgresMatchLog(pool) : InMemoryMatchLog());

  final redisUrl = config.redisUrl;
  final liveStore =
      overrides.liveStore ??
      (redisUrl != null
          ? await RedisLiveRoomStore.connect(redisUrl, ttl: config.liveRoomTtl)
          : InMemoryLiveRoomStore());

  final TokenVerifier verifier =
      overrides.tokenVerifier ??
      switch (config.authProvider) {
        AuthProvider.fake => FakeTokenVerifier(),
        AuthProvider.firebase => FirebaseTokenVerifier(
          projectId: config.firebaseProjectId!,
        ),
      };
  final authService = AuthService(
    verifier: verifier,
    users: users,
    sessions: SessionTokens(secret: config.sessionSecret, clock: now),
  );

  FakePaymentProvider? fake;
  final providers = <String, PaymentProvider>{};
  String callbackUrl(String name) =>
      '${config.publicBaseUrl}/v1/payments/callback/$name';
  for (final name in config.paymentProviders) {
    switch (name) {
      case 'fake':
        providers['fake'] = fake = FakePaymentProvider();
      case 'mtn':
        final mtn = config.mtn!;
        providers['mtn'] = MtnMomoProvider(
          subscriptionKey: mtn.subscriptionKey,
          apiUser: mtn.apiUser,
          apiKey: mtn.apiKey,
          targetEnvironment: mtn.targetEnvironment,
          callbackUrl: mtn.callbackUrl,
          baseUrl: mtn.baseUrl,
          currency: mtn.currency,
        );
      case 'airtel':
        final airtel = config.airtel!;
        providers['airtel'] = AirtelMoneyProvider(
          clientId: airtel.clientId,
          clientSecret: airtel.clientSecret,
          callbackUrl: callbackUrl('airtel'),
          callbackSecret: airtel.callbackSecret,
          baseUrl: airtel.baseUrl,
        );
    }
  }
  final payments = PaymentsService(
    providers: providers,
    store: paymentStore,
    ledger: ledger,
    clock: now,
    log: (m) => log('payments: $m'),
  );

  final rooms = RoomManager(
    clock: clock,
    chooseMoves: overrides.chooseMoves ?? normalBotChooser(overrides.random),
    settings: RoomSettings(
      turnTimeout: config.turnTimeout,
      reconnectGrace: config.reconnectGrace,
      botDelay: config.botDelay,
      roomIdle: config.roomIdle,
      publicBaseUrl: config.publicBaseUrl,
    ),
    liveStore: liveStore,
    matchLog: matchLog,
    random: overrides.random,
    logError: (m, e, st) => log('ERROR $m: $e${st == null ? '' : '\n$st'}'),
  );
  final restored = await rooms.restore();
  if (restored > 0) log('restored $restored live rooms');

  final api = Api(
    config: config,
    clock: clock,
    auth: authService,
    users: users,
    ledger: ledger,
    payments: payments,
    paymentStore: paymentStore,
    rooms: rooms,
    matchLog: matchLog,
    fakePayments: fake,
  );
  final router = api.router()
    ..get(
      '/v1/ws',
      webSocketRoute(
        rooms: rooms,
        clock: clock,
        messagesPerSecond: config.wsMessagesPerSecond,
        authenticate: (token) async {
          final user = await api.userFor(token);
          return user == null
              ? null
              : (id: user.id, displayName: user.displayName);
        },
      ),
    );

  final handler = const Pipeline()
      .addMiddleware(logRequestPaths(log))
      .addHandler(router.call);
  final server = await shelf_io.serve(handler, config.host, config.port);
  server.autoCompress = true;

  return RunningServer._(
    server: server,
    config: config,
    clock: clock,
    rooms: rooms,
    auth: authService,
    users: users,
    ledger: ledger,
    payments: payments,
    paymentStore: paymentStore,
    matchLog: matchLog,
    liveStore: liveStore,
    fakePayments: fake,
    pool: pool,
  );
}

/// Server settings. This is the only place that reads the environment; every
/// secret comes from here and is passed on through constructors.
library;

import 'dart:convert';
import 'dart:math';

class ConfigException implements Exception {
  ConfigException(this.message);
  final String message;
  @override
  String toString() => 'ConfigException: $message';
}

enum AuthProvider { fake, firebase }

class MtnSettings {
  const MtnSettings({
    required this.subscriptionKey,
    required this.apiUser,
    required this.apiKey,
    required this.targetEnvironment,
    required this.baseUrl,
    required this.currency,
    required this.callbackUrl,
  });
  final String subscriptionKey;
  final String apiUser;
  final String apiKey;
  final String targetEnvironment;
  final String baseUrl;
  final String currency;

  /// Public URL of the MoMo callback route.
  final String callbackUrl;
}

class AirtelSettings {
  const AirtelSettings({
    required this.clientId,
    required this.clientSecret,
    required this.baseUrl,
    this.callbackSecret,
  });
  final String clientId;
  final String clientSecret;
  final String baseUrl;
  final String? callbackSecret;
}

class ServerConfig {
  ServerConfig({
    this.host = '0.0.0.0',
    this.port = 8080,
    this.publicBaseUrl = 'http://localhost:8080',
    this.appVersion = 'dev',
    this.appDownloadUrl,
    this.databaseUrl,
    this.redisUrl,
    required this.sessionSecret,
    this.randomSessionSecret = false,
    this.authProvider = AuthProvider.fake,
    this.firebaseProjectId,
    this.paymentProviders = const ['fake'],
    this.mtn,
    this.airtel,
    this.turnTimeout = const Duration(seconds: 20),
    this.reconnectGrace = const Duration(seconds: 60),
    this.botDelay = const Duration(milliseconds: 800),
    this.roomIdle = const Duration(minutes: 30),
    this.liveRoomTtl = const Duration(hours: 6),
    this.roomCreatesPerHour = 10,
    this.guestsPerHour = 30,
    this.wsMessagesPerSecond = 20,
    this.paidTablesEnabled = false,
  }) {
    _validate();
  }

  /// Settings for tests: an ephemeral port on localhost, memory stores, fake
  /// login and payments, and a random session secret.
  factory ServerConfig.forTests({
    Duration turnTimeout = const Duration(seconds: 20),
    Duration reconnectGrace = const Duration(seconds: 60),
    Duration botDelay = const Duration(milliseconds: 800),
    Duration roomIdle = const Duration(minutes: 30),
    int roomCreatesPerHour = 10,
    int guestsPerHour = 1000,
    int wsMessagesPerSecond = 20,
    String? databaseUrl,
    String? redisUrl,
  }) {
    final rng = Random.secure();
    return ServerConfig(
      host: '127.0.0.1',
      port: 0,
      publicBaseUrl: 'http://localhost',
      sessionSecret: List<int>.generate(32, (_) => rng.nextInt(256)),
      turnTimeout: turnTimeout,
      reconnectGrace: reconnectGrace,
      botDelay: botDelay,
      roomIdle: roomIdle,
      roomCreatesPerHour: roomCreatesPerHour,
      guestsPerHour: guestsPerHour,
      wsMessagesPerSecond: wsMessagesPerSecond,
      databaseUrl: databaseUrl,
      redisUrl: redisUrl,
    );
  }

  /// Reads the variables documented in server/.env.example.
  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    String? opt(String key) {
      final v = env[key]?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    String req(String key) =>
        opt(key) ?? (throw ConfigException('$key is required'));

    int intOf(String key, int fallback) {
      final v = opt(key);
      if (v == null) return fallback;
      final n = int.tryParse(v);
      if (n == null || n < 0) {
        throw ConfigException('$key must be a whole number');
      }
      return n;
    }

    final auth = switch (opt('AUTH_PROVIDER') ?? 'fake') {
      'fake' => AuthProvider.fake,
      'firebase' => AuthProvider.firebase,
      final other => throw ConfigException('unknown AUTH_PROVIDER $other'),
    };

    final secret = opt('SESSION_SECRET');
    final allFake =
        auth == AuthProvider.fake &&
        (opt('PAYMENTS_PROVIDER') ?? 'fake') == 'fake';
    if (secret == null && !allFake) {
      throw ConfigException(
        'SESSION_SECRET is required (at least 32 bytes, for example '
        '`openssl rand -base64 48`)',
      );
    }

    final providers = (opt('PAYMENTS_PROVIDER') ?? 'fake')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final publicBaseUrl = (opt('PUBLIC_BASE_URL') ?? 'http://localhost:8080')
        .replaceAll(RegExp(r'/+$'), '');

    return ServerConfig(
      host: opt('HOST') ?? '0.0.0.0',
      port: intOf('PORT', 8080),
      publicBaseUrl: publicBaseUrl,
      appVersion: opt('APP_VERSION') ?? 'dev',
      appDownloadUrl: opt('APP_DOWNLOAD_URL'),
      databaseUrl: opt('DATABASE_URL'),
      redisUrl: opt('REDIS_URL'),
      // Fully fake setups may run without a secret: a random one is made at
      // start, so sessions end when the server restarts.
      sessionSecret: secret == null ? _randomSecret() : utf8.encode(secret),
      randomSessionSecret: secret == null,
      authProvider: auth,
      firebaseProjectId: opt('FIREBASE_PROJECT_ID'),
      paymentProviders: providers,
      mtn: providers.contains('mtn')
          ? MtnSettings(
              subscriptionKey: req('MOMO_SUBSCRIPTION_KEY'),
              apiUser: req('MOMO_API_USER'),
              apiKey: req('MOMO_API_KEY'),
              targetEnvironment: opt('MOMO_TARGET_ENVIRONMENT') ?? 'sandbox',
              baseUrl:
                  opt('MOMO_BASE_URL') ??
                  'https://sandbox.momodeveloper.mtn.com',
              currency: opt('MOMO_CURRENCY') ?? 'EUR',
              callbackUrl:
                  opt('MOMO_CALLBACK_URL') ??
                  '$publicBaseUrl/v1/payments/callback/mtn',
            )
          : null,
      airtel: providers.contains('airtel')
          ? AirtelSettings(
              clientId: req('AIRTEL_CLIENT_ID'),
              clientSecret: req('AIRTEL_CLIENT_SECRET'),
              baseUrl:
                  opt('AIRTEL_BASE_URL') ?? 'https://openapiuat.airtel.africa',
              callbackSecret: opt('AIRTEL_CALLBACK_SECRET'),
            )
          : null,
      turnTimeout: Duration(seconds: intOf('TURN_SECONDS', 20)),
      reconnectGrace: Duration(seconds: intOf('RECONNECT_GRACE_SECONDS', 60)),
      botDelay: Duration(milliseconds: intOf('BOT_DELAY_MS', 800)),
      roomIdle: Duration(minutes: intOf('ROOM_IDLE_MINUTES', 30)),
      liveRoomTtl: Duration(hours: intOf('LIVE_ROOM_TTL_HOURS', 6)),
      roomCreatesPerHour: intOf('ROOM_CREATES_PER_HOUR', 10),
      guestsPerHour: intOf('GUESTS_PER_HOUR', 30),
      wsMessagesPerSecond: intOf('WS_MESSAGES_PER_SECOND', 20),
    );
  }

  /// True when SESSION_SECRET was not set and a random one is in use.
  final bool randomSessionSecret;

  final String host;

  /// 0 picks a free port.
  final int port;

  /// Used for room links (`$publicBaseUrl/r/CODE`) and payment callbacks.
  final String publicBaseUrl;
  final String appVersion;

  /// Where the landing page sends people without the app.
  final String? appDownloadUrl;

  /// Null keeps users, wallet and match log in memory.
  final String? databaseUrl;

  /// Null keeps live rooms in memory only.
  final String? redisUrl;
  final List<int> sessionSecret;
  final AuthProvider authProvider;
  final String? firebaseProjectId;

  /// `fake`, or any of `mtn` and `airtel`.
  final List<String> paymentProviders;
  final MtnSettings? mtn;
  final AirtelSettings? airtel;

  final Duration turnTimeout;
  final Duration reconnectGrace;
  final Duration botDelay;
  final Duration roomIdle;
  final Duration liveRoomTtl;
  final int roomCreatesPerHour;

  /// Guest accounts one client address may start per hour (D33).
  final int guestsPerHour;
  final int wsMessagesPerSecond;

  /// Paid tables are refused with paid_tables_disabled until M3.9.
  final bool paidTablesEnabled;

  bool get fakePayments => paymentProviders.contains('fake');

  void _validate() {
    if (sessionSecret.length < 32) {
      throw ConfigException('SESSION_SECRET must be at least 32 bytes');
    }
    if (paymentProviders.isEmpty) {
      throw ConfigException('PAYMENTS_PROVIDER is empty');
    }
    for (final p in paymentProviders) {
      if (!const {'fake', 'mtn', 'airtel'}.contains(p)) {
        throw ConfigException('unknown payment provider $p');
      }
    }
    if (fakePayments && paymentProviders.length > 1) {
      throw ConfigException(
        'PAYMENTS_PROVIDER=fake cannot be mixed with real providers',
      );
    }
    if (authProvider == AuthProvider.fake && !fakePayments) {
      throw ConfigException(
        'refusing to start: AUTH_PROVIDER=fake with a real PAYMENTS_PROVIDER '
        'would let anyone log in as any phone number and move real money',
      );
    }
    if (authProvider == AuthProvider.firebase && firebaseProjectId == null) {
      throw ConfigException('AUTH_PROVIDER=firebase needs FIREBASE_PROJECT_ID');
    }
    if (paymentProviders.contains('mtn') && mtn == null) {
      throw ConfigException('PAYMENTS_PROVIDER=mtn needs the MOMO_* settings');
    }
    if (paymentProviders.contains('airtel') && airtel == null) {
      throw ConfigException(
        'PAYMENTS_PROVIDER=airtel needs the AIRTEL_* settings',
      );
    }
    if (turnTimeout <= Duration.zero || reconnectGrace <= Duration.zero) {
      throw ConfigException(
        'TURN_SECONDS and RECONNECT_GRACE_SECONDS must be above 0',
      );
    }
  }
}

List<int> _randomSecret() {
  final rng = Random.secure();
  return List<int>.generate(32, (_) => rng.nextInt(256));
}

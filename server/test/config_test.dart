import 'package:arena_server/arena_server.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'a-test-secret-that-is-long-enough-32b';

  test('defaults', () {
    final c = ServerConfig.fromEnvironment({'SESSION_SECRET': secret});
    expect(c.port, 8080);
    expect(c.authProvider, AuthProvider.fake);
    expect(c.paymentProviders, ['fake']);
    expect(c.turnTimeout, const Duration(seconds: 20));
    expect(c.reconnectGrace, const Duration(seconds: 60));
    expect(c.botDelay, const Duration(milliseconds: 800));
    expect(c.roomIdle, const Duration(minutes: 30));
    expect(c.appVersion, 'dev');
    expect(c.databaseUrl, isNull);
    expect(c.paidTablesEnabled, isFalse);
  });

  test('reads every setting', () {
    final c = ServerConfig.fromEnvironment({
      'SESSION_SECRET': secret,
      'PORT': '9000',
      'PUBLIC_BASE_URL': 'https://arena.example/',
      'TURN_SECONDS': '5',
      'RECONNECT_GRACE_SECONDS': '10',
      'BOT_DELAY_MS': '100',
      'ROOM_IDLE_MINUTES': '2',
      'APP_VERSION': '1.2.3',
      'AUTH_PROVIDER': 'firebase',
      'FIREBASE_PROJECT_ID': 'arena-ug',
      'PAYMENTS_PROVIDER': 'mtn,airtel',
      'MOMO_SUBSCRIPTION_KEY': 'k',
      'MOMO_API_USER': 'u',
      'MOMO_API_KEY': 'p',
      'AIRTEL_CLIENT_ID': 'i',
      'AIRTEL_CLIENT_SECRET': 's',
    });
    expect(c.port, 9000);
    expect(c.publicBaseUrl, 'https://arena.example');
    expect(c.turnTimeout, const Duration(seconds: 5));
    expect(c.botDelay, const Duration(milliseconds: 100));
    expect(c.appVersion, '1.2.3');
    expect(c.mtn!.currency, 'EUR');
    expect(
      c.mtn!.callbackUrl,
      'https://arena.example/v1/payments/callback/mtn',
    );
    expect(c.airtel!.clientId, 'i');
  });

  test('a fully fake setup may run without a secret', () {
    final c = ServerConfig.fromEnvironment({});
    expect(c.randomSessionSecret, isTrue);
    expect(c.sessionSecret, hasLength(32));
    expect(
      ServerConfig.fromEnvironment({
        'SESSION_SECRET': secret,
      }).randomSessionSecret,
      isFalse,
    );
  });

  test('MOMO_CALLBACK_URL overrides the default callback', () {
    final c = ServerConfig.fromEnvironment({
      'SESSION_SECRET': secret,
      'AUTH_PROVIDER': 'firebase',
      'FIREBASE_PROJECT_ID': 'arena-ug',
      'PAYMENTS_PROVIDER': 'mtn',
      'MOMO_SUBSCRIPTION_KEY': 'k',
      'MOMO_API_USER': 'u',
      'MOMO_API_KEY': 'p',
      'MOMO_CALLBACK_URL': 'https://cb.example/momo',
    });
    expect(c.mtn!.callbackUrl, 'https://cb.example/momo');
  });

  test('refuses unsafe or incomplete settings', () {
    void refuses(Map<String, String> env) => expect(
      () => ServerConfig.fromEnvironment(env),
      throwsA(isA<ConfigException>()),
      reason: '$env',
    );
    refuses({'AUTH_PROVIDER': 'firebase', 'FIREBASE_PROJECT_ID': 'x'});
    refuses({'SESSION_SECRET': 'short'});
    refuses({'SESSION_SECRET': secret, 'AUTH_PROVIDER': 'magic'});
    refuses({'SESSION_SECRET': secret, 'AUTH_PROVIDER': 'firebase'});
    refuses({'SESSION_SECRET': secret, 'PAYMENTS_PROVIDER': 'mtn'});
    // Fake login with real money is refused even when fully configured.
    refuses({
      'SESSION_SECRET': secret,
      'PAYMENTS_PROVIDER': 'airtel',
      'AIRTEL_CLIENT_ID': 'i',
      'AIRTEL_CLIENT_SECRET': 's',
    });
    refuses({'SESSION_SECRET': secret, 'PAYMENTS_PROVIDER': 'fake,mtn'});
    refuses({'SESSION_SECRET': secret, 'TURN_SECONDS': 'soon'});
    refuses({'SESSION_SECRET': secret, 'TURN_SECONDS': '0'});
  });
}

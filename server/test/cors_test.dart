import 'package:arena_server/arena_server.dart';
import 'package:arena_server/src/http/cors.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  test('origin patterns', () {
    expect(
      originAllowed('https://arena-cddfa.web.app', kDefaultAllowedOrigins),
      isTrue,
    );
    expect(
      originAllowed('http://localhost:5000', kDefaultAllowedOrigins),
      isTrue,
    );
    expect(originAllowed('http://localhost', kDefaultAllowedOrigins), isTrue);
    expect(
      originAllowed('http://localhost.evil.com', kDefaultAllowedOrigins),
      isFalse,
    );
    expect(
      originAllowed('http://localhost:80x', kDefaultAllowedOrigins),
      isFalse,
    );
    expect(
      originAllowed('https://evil.web.app', kDefaultAllowedOrigins),
      isFalse,
    );
  });

  test(
    'guest limit counts the hop our proxy added, not spoofed ones',
    () async {
      final server = await startServer(
        ServerConfig.forTests(guestsPerHour: 1),
        overrides: ServerOverrides(log: (_) {}),
      );
      addTearDown(server.close);
      Future<int> guest(String xff) async => (await http.post(
        server.baseUrl.resolve('/v1/auth/guest'),
        headers: {'x-forwarded-for': xff},
      )).statusCode;
      expect(await guest('9.9.9.1, 5.5.5.5'), 200);
      // A different spoofed first hop does not reset the limit.
      expect(await guest('9.9.9.2, 5.5.5.5'), 429);
      expect(await guest('9.9.9.2, 6.6.6.6'), 200);
    },
  );

  group('server', () {
    late RunningServer server;
    setUp(
      () async => server = await startServer(
        ServerConfig.forTests(),
        overrides: ServerOverrides(log: (_) {}),
      ),
    );
    tearDown(() => server.close());

    test('preflight and allow-origin for the web app only', () async {
      final url = server.baseUrl.resolve('/v1/rooms');
      final pre = http.Request('OPTIONS', url)
        ..headers['origin'] = 'https://arena-cddfa.web.app'
        ..headers['access-control-request-method'] = 'POST';
      final res = await http.Response.fromStream(await pre.send());
      expect(res.statusCode, 204);
      expect(
        res.headers['access-control-allow-origin'],
        'https://arena-cddfa.web.app',
      );
      expect(
        res.headers['access-control-allow-headers'],
        contains('authorization'),
      );

      final bad = http.Request('OPTIONS', url)
        ..headers['origin'] = 'https://evil.example';
      expect((await bad.send()).statusCode, 403);

      final health = await http.get(
        server.baseUrl.resolve('/health'),
        headers: {'origin': 'http://localhost:5000'},
      );
      expect(
        health.headers['access-control-allow-origin'],
        'http://localhost:5000',
      );
      final plain = await http.get(server.baseUrl.resolve('/health'));
      expect(plain.headers['access-control-allow-origin'], isNull);
    });

    test('the web socket refuses other browser origins', () async {
      final res = await http.get(
        server.baseUrl.resolve('/v1/ws?token=x'),
        headers: {'origin': 'https://evil.example'},
      );
      expect(res.statusCode, 403);
    });
  });
}

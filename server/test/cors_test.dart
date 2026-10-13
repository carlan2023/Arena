import 'dart:io';

import 'package:arena_server/arena_server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

void main() {
  group('OriginPolicy', () {
    final policy = OriginPolicy(ServerConfig.defaultAllowedOrigins);

    test('allows the web app and local development', () {
      expect(policy.allows('https://arena-cddfa.web.app'), isTrue);
      expect(policy.allows('https://arena-cddfa.firebaseapp.com'), isTrue);
      expect(policy.allows('HTTPS://Arena-CDDFA.web.app/'), isTrue);
      expect(policy.allows('http://localhost:5000'), isTrue);
      expect(policy.allows('http://localhost'), isTrue);
    });

    test('refuses everything else', () {
      expect(policy.allows('https://evil.example'), isFalse);
      expect(policy.allows('http://arena-cddfa.web.app'), isFalse);
      expect(
        policy.allows('https://arena-cddfa.web.app.evil.example'),
        isFalse,
      );
      expect(policy.allows('http://localhost.evil.example'), isFalse);
      expect(policy.allows('http://localhost:80x'), isFalse);
      expect(policy.allows('https://localhost:5000'), isFalse);
      expect(policy.allows('null'), isFalse);
    });
  });

  group('server', () {
    late RunningServer server;
    const web = 'https://arena-cddfa.web.app';

    setUp(() async {
      server = await startServer(
        ServerConfig.forTests(),
        overrides: ServerOverrides(log: (_) {}),
      );
    });
    tearDown(() => server.close());

    Future<http.StreamedResponse> preflight(String origin, String path) {
      final req = http.Request('OPTIONS', server.baseUrl.resolve(path))
        ..headers.addAll({
          'origin': origin,
          'access-control-request-method': 'POST',
          'access-control-request-headers': 'authorization, content-type',
        });
      return req.send();
    }

    test('answers the preflight for the web app', () async {
      final res = await preflight(web, '/v1/auth/guest');
      expect(res.statusCode, 204);
      expect(res.headers['access-control-allow-origin'], web);
      expect(res.headers['access-control-allow-methods'], contains('POST'));
      expect(
        res.headers['access-control-allow-headers'],
        contains('authorization'),
      );
    });

    test('refuses the preflight for other origins', () async {
      final res = await preflight('https://evil.example', '/v1/auth/guest');
      expect(res.statusCode, 403);
      expect(res.headers['access-control-allow-origin'], isNull);
    });

    test('adds the allow header to real responses, errors included', () async {
      final ok = await http.post(
        server.baseUrl.resolve('/v1/auth/guest'),
        headers: {'origin': web},
      );
      expect(ok.statusCode, 200);
      expect(ok.headers['access-control-allow-origin'], web);

      final denied = await http.get(
        server.baseUrl.resolve('/v1/me'),
        headers: {'origin': web},
      );
      expect(denied.statusCode, 401);
      expect(denied.headers['access-control-allow-origin'], web);

      final other = await http.get(
        server.baseUrl.resolve('/health'),
        headers: {'origin': 'https://evil.example'},
      );
      expect(other.statusCode, 200);
      expect(other.headers['access-control-allow-origin'], isNull);
    });

    test('requests without an Origin are unchanged', () async {
      final res = await http.get(server.baseUrl.resolve('/health'));
      expect(res.statusCode, 200);
      expect(res.headers['access-control-allow-origin'], isNull);
    });

    test('the web socket checks the origin', () async {
      final token = (await server.auth.guest()).$1;
      final url = server.baseUrl
          .replace(scheme: 'ws', path: '/v1/ws', query: 'token=$token')
          .toString();
      final ok = await WebSocket.connect(url, headers: {'origin': web});
      await ok.close();
      await expectLater(
        WebSocket.connect(url, headers: {'origin': 'https://evil.example'}),
        throwsA(isA<WebSocketException>()),
      );
      final native = await WebSocket.connect(url);
      await native.close();
    });
  });
}

import 'dart:convert';

import 'package:arena/online/api.dart';
import 'package:arena/online/auth.dart';
import 'package:arena/online/config.dart';
import 'package:arena/online/phone.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('phone numbers', () {
    test('Ugandan mobile numbers become E.164', () {
      for (final input in [
        '0772123456',
        '772123456',
        '256772123456',
        '+256 772 123 456',
        '(0772) 123-456',
      ]) {
        expect(normalizeUgandanPhone(input), '+256772123456', reason: input);
      }
    });

    test('anything else is refused', () {
      for (final input in ['', '12345', '0412123456', '+254772123456', 'abc']) {
        expect(normalizeUgandanPhone(input), isNull, reason: input);
      }
    });
  });

  group('room codes and links', () {
    test('codes use the protocol alphabet', () {
      expect(isRoomCode('ABC234'), isTrue);
      expect(isRoomCode('ABC23'), isFalse);
      expect(isRoomCode('ABCIO1'), isFalse, reason: 'I, O and 1 are left out');
    });

    test('invite links in both forms', () {
      expect(
        roomCodeFromLink(Uri.parse('https://arena.example/r/ABC234')),
        'ABC234',
      );
      expect(roomCodeFromLink(Uri.parse('arena://r/abc234')), 'ABC234');
      expect(
        roomCodeFromLink(Uri.parse('https://arena.example/x/ABC234')),
        isNull,
      );
      expect(roomCodeFromLink(Uri.parse('arena://r/NOPE')), isNull);
      expect(roomCodeFromLink(Uri.parse('mailto:a@b.c')), isNull);
    });
  });

  group('fake phone auth (D16)', () {
    test('123456 gives a fake token, anything else fails', () async {
      const auth = FakePhoneAuth();
      await auth.sendCode('+256772123456');
      expect(
        await auth.verifyCode('+256772123456', '123456'),
        'fake:+256772123456',
      );
      expect(
        () => auth.verifyCode('+256772123456', '000000'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('AuthController', () {
    late FakeApi api;
    late MemorySessionStore store;
    late ProviderContainer c;

    setUp(() {
      api = FakeApi();
      store = MemorySessionStore();
      c = ProviderContainer(
        overrides: [
          arenaApiProvider.overrideWithValue(api),
          sessionStoreProvider.overrideWithValue(store),
        ],
      );
    });
    tearDown(() => c.dispose());

    test('starts from the saved session', () async {
      store.session = session;
      expect((await c.read(authProvider.future))?.token, 'tok-1');
    });

    test('login, name, logout', () async {
      expect(await c.read(authProvider.future), isNull);
      final s = await c
          .read(authProvider.notifier)
          .login('+256772000001', '123456');
      expect(api.calls, ['login fake:+256772000001']);
      expect(s.hasName, isFalse);
      expect(store.session?.token, 'tok-1');

      await c.read(authProvider.notifier).setDisplayName('Amina');
      expect(c.read(authProvider).value!.user.displayName, 'Amina');
      expect(store.session!.hasName, isTrue);

      await c.read(authProvider.notifier).logout();
      expect(c.read(authProvider).value, isNull);
      expect(store.session, isNull);
    });

    test('a wrong code never reaches the server', () async {
      await c.read(authProvider.future);
      await expectLater(
        c.read(authProvider.notifier).login('+256772000001', '111111'),
        throwsA(isA<AuthException>()),
      );
      expect(api.calls, isEmpty);
    });
  });

  test('prefs store round trips and survives junk', () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsSessionStore();
    expect(await store.load(), isNull);
    await store.save(session);
    final back = await store.load();
    expect(back!.token, 'tok-1');
    expect(back.user.displayName, 'Amina');
    await store.save(null);
    expect(await store.load(), isNull);

    SharedPreferences.setMockInitialValues({'arena.session': '{bad'});
    expect(await PrefsSessionStore().load(), isNull);
  });

  test('HTTP api uses the protocol routes and bearer token', () async {
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add('${req.method} ${req.url.path} ${req.headers['Authorization']}');
      final body = switch (req.url.path) {
        '/v1/auth/login' => {'sessionToken': 'tok-9', 'user': me.toJson()},
        '/v1/me' => me.toJson(),
        _ => lobbyRoom().toJson(),
      };
      if (req.url.path == '/v1/rooms') {
        final sent = jsonDecode(req.body) as Map;
        expect(sent['mode'], 'teams');
        expect(sent['seats'], 4);
        expect(sent['stake'], 0);
      }
      return http.Response(jsonEncode(body), 200);
    });
    final api = HttpArenaApi(
      Uri.parse('http://localhost:8080'),
      httpClient: client,
    );
    final s = await api.login('fake:+256772000001');
    expect(s.token, 'tok-9');
    await api.setDisplayName('tok-9', 'Amina');
    final room = await api.createRoom('tok-9', mode: GameMode.teams, seats: 4);
    expect(room.code, code);
    await api.getRoom('tok-9', code);
    expect(seen, [
      'POST /v1/auth/login null',
      'PATCH /v1/me Bearer tok-9',
      'POST /v1/rooms Bearer tok-9',
      'GET /v1/rooms/$code Bearer tok-9',
    ]);
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:arena_protocol/client.dart';
import 'package:arena_protocol/fair_dice.dart';
import 'package:arena_server/arena_server.dart';
import 'package:http/http.dart' as http;
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  late RunningServer server;
  final clients = <ArenaClient>[];

  Future<ArenaClient> loggedIn(String phone) async {
    final c = ArenaClient(baseUrl: server.baseUrl);
    clients.add(c);
    await c.login('fake:$phone');
    return c;
  }

  setUp(() async {
    server = await startServer(
      ServerConfig.forTests(roomCreatesPerHour: 3, wsMessagesPerSecond: 10000),
      overrides: ServerOverrides(log: (_) {}),
    );
  });

  tearDown(() async {
    for (final c in clients) {
      await c.close();
    }
    clients.clear();
    await server.close();
  });

  group('http', () {
    test('health', () async {
      final res = await http.get(server.baseUrl.resolve('/health'));
      expect(res.statusCode, 200);
      expect(jsonDecode(res.body), {'ok': true, 'version': 'dev'});
    });

    test('login, me and display name', () async {
      final c = await loggedIn('+256772000001');
      expect(c.user!.phone, '+256772000001');
      expect((await c.me()).id, c.user!.id);
      expect((await c.setDisplayName('  Allan ')).displayName, 'Allan');
      await expectLater(
        c.setDisplayName(''),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)),
      );
    });

    test('guests play free rooms but not the wallet or paid tables', () async {
      final g = ArenaClient(baseUrl: server.baseUrl);
      clients.add(g);
      final user = await g.guest();
      expect(user.isGuest, isTrue);
      expect(user.displayName, startsWith('Player '));
      expect((await g.setDisplayName('Nakato')).displayName, 'Nakato');
      final room = await g.createRoom(mode: GameMode.oneVsOne, seats: 2);
      expect(room.code, hasLength(6));
      Matcher phoneRequired() => throwsA(
        isA<ApiError>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.code, 'code', 'phone_required'),
      );
      await expectLater(g.request('GET', '/v1/wallet'), phoneRequired());
      await expectLater(
        g.request('GET', '/v1/wallet/history'),
        phoneRequired(),
      );
      await expectLater(
        g.request('POST', '/v1/wallet/deposits', {
          'amount': 5000,
          'msisdn': '256700000001',
          'provider': 'fake',
        }),
        phoneRequired(),
      );
      await expectLater(
        g.createRoom(mode: GameMode.oneVsOne, seats: 2, stake: 1000),
        phoneRequired(),
      );
      final phoneUser = await loggedIn('+256772000009');
      expect(phoneUser.user!.isGuest, isFalse);
      expect((await phoneUser.request('GET', '/v1/wallet'))['balance'], 0);
    });

    test('guest accounts are rate limited per address', () async {
      await server.close();
      server = await startServer(
        ServerConfig.forTests(guestsPerHour: 2),
        overrides: ServerOverrides(log: (_) {}),
      );
      for (var i = 0; i < 2; i++) {
        final g = ArenaClient(baseUrl: server.baseUrl);
        clients.add(g);
        await g.guest();
      }
      final g = ArenaClient(baseUrl: server.baseUrl);
      clients.add(g);
      await expectLater(
        g.guest(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 429)),
      );
    });

    test('bad login and missing token give 401', () async {
      final c = ArenaClient(baseUrl: server.baseUrl);
      clients.add(c);
      await expectLater(
        c.login('nonsense'),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'unauthorized')),
      );
      await expectLater(
        c.me(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)),
      );
    });

    test('rooms: create, get, validation, paid refused, rate limit', () async {
      final c = await loggedIn('+256772000002');
      final room = await c.createRoom(mode: GameMode.freeForAll, seats: 4);
      expect(room.link, 'http://localhost/r/${room.code}');
      expect(room.ownerUserId, c.user!.id);
      expect(room.status, RoomStatus.waiting);
      expect((await c.getRoom(room.code.toLowerCase())).code, room.code);
      await expectLater(
        c.getRoom('ZZZZZZ'),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', 'room_not_found'),
        ),
      );
      await expectLater(
        c.createRoom(mode: GameMode.teams, seats: 2),
        throwsA(isA<ApiError>().having((e) => e.code, 'code', 'bad_request')),
      );
      await expectLater(
        c.createRoom(stake: 1000),
        throwsA(
          isA<ApiError>().having((e) => e.code, 'code', 'paid_tables_disabled'),
        ),
      );
      await c.createRoom();
      await c.createRoom();
      await expectLater(
        c.createRoom(),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 429)),
      );
    });

    test('landing page', () async {
      final c = await loggedIn('+256772000003');
      final room = await c.createRoom();
      final res = await http.get(server.baseUrl.resolve('/r/${room.code}'));
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/html'));
      expect(res.body, contains('arena://r/${room.code}'));
      final bad = await http.get(server.baseUrl.resolve('/r/<script>'));
      expect(bad.statusCode, 404);
      expect(bad.body, isNot(contains('<script>')));
    });

    test('fake deposit reaches the wallet once', () async {
      final c = await loggedIn('+256772000004');
      expect(await c.request('GET', '/v1/wallet'), {
        'balance': 0,
        'currency': 'UGX',
      });
      final p = PaymentView.fromJson(
        await c.request('POST', '/v1/wallet/deposits', {
          'amount': 5000,
          'msisdn': '256772000004',
          'provider': 'mtn',
        }),
      );
      expect(p.status, 'pending');
      expect(p.provider, 'fake');
      final confirmed = await c.request(
        'POST',
        '/v1/dev/payments/${p.id}/confirm',
      );
      expect(confirmed['status'], 'succeeded');
      await c.request('POST', '/v1/dev/payments/${p.id}/confirm');
      // A duplicate callback is accepted and changes nothing.
      final body = server.fakePayments!.callbackBody(p.id);
      for (final method in ['POST', 'PUT']) {
        final res = http.Request(
          method,
          server.baseUrl.resolve('/v1/payments/callback/fake'),
        )..body = body;
        final sent = await http.Response.fromStream(await res.send());
        expect(sent.statusCode, 200);
      }
      expect((await c.request('GET', '/v1/wallet'))['balance'], 5000);
      final history = await c.request('GET', '/v1/wallet/history?limit=10');
      final entries = history['entries'] as List;
      expect(entries, hasLength(1));
      expect(
        WalletEntryView.fromJson((entries.single as Map).cast()).kind,
        'deposit',
      );
      final got = await c.request('GET', '/v1/wallet/deposits/${p.id}');
      expect(got['status'], 'succeeded');

      // Another user cannot see it.
      final other = await loggedIn('+256772000005');
      await expectLater(
        other.request('GET', '/v1/wallet/deposits/${p.id}'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
      );
      await expectLater(
        c.request('POST', '/v1/wallet/deposits', {
          'amount': 10,
          'msisdn': '256772000004',
          'provider': 'mtn',
        }),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 400)),
      );
    });

    test('verify before the end is refused, unknown match is 404', () async {
      final c = await loggedIn('+256772000006');
      await expectLater(
        c.verifyMatch('00000000-0000-4000-8000-000000000000'),
        throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
      );
    });
  });

  group('web socket', () {
    test('a bad token is refused before the upgrade', () async {
      final res = await http.get(server.baseUrl.resolve('/v1/ws?token=nope'));
      expect(res.statusCode, 401);
    });

    test('bad frames get bad_request with the ref', () async {
      final c = await loggedIn('+256772000007');
      await c.connect();
      c.sendRaw('{"type":"nope","cseq":9}');
      final err = await c.next<ErrorMessage>();
      expect((err.code, err.ref), ('bad_request', 9));
      c.ping();
      expect((await c.next<PongMessage>()).ref, 1);
    });

    test('two players finish a game and verify the dice', () async {
      final a = await loggedIn('+256772000010');
      final b = await loggedIn('+256772000011');
      final room = await a.createRoom();
      await a.connect();
      await b.connect();
      a.joinRoom(room.code, clientSeed: 'alpha');
      await a.next<RoomStateMessage>();
      b.joinRoom(room.code, clientSeed: 'beta');

      final done = Future.wait([_autoPlay(a), _autoPlay(b)]);
      final over = await a.next<GameOverMessage>(
        timeout: const Duration(seconds: 60),
      );
      await done;
      expect(over.clientSeed, 'alpha:beta');
      final start = a.received.whereType<RoomStateMessage>().last;
      expect(start.room.matchId, over.matchId);

      final v = await a.verifyMatch(over.matchId);
      expect(v.serverSeed, over.serverSeed);
      expect(v.serverSeedHash, start.serverSeedHash);
      final seen = [
        for (final d in a.received.whereType<DiceMessage>()) d.values,
      ];
      expect(v.rolls, seen);
      expect(
        verifyRolls(
          serverSeedHex: v.serverSeed,
          serverSeedHash: v.serverSeedHash,
          clientSeed: v.clientSeed,
          rolls: v.rolls,
        ),
        isTrue,
      );
      // seq has no gaps for either player.
      for (final c in [a, b]) {
        final seqs = [for (final m in c.received) ?_seqOf(m)];
        final broadcast = seqs.toSet().toList()..sort();
        expect(broadcast.last - broadcast.first + 1, broadcast.length);
      }
    });

    test('reconnect after a dropped socket', () async {
      final a = await loggedIn('+256772000020');
      final b = await loggedIn('+256772000021');
      final room = await a.createRoom();
      await a.connect();
      await b.connect();
      a.joinRoom(room.code);
      await a.next<RoomStateMessage>();
      b.joinRoom(room.code);
      await b.next<RoomStateMessage>(where: (m) => m.state != null);

      await b.disconnect();
      final down = await a.next<PlayerStatusMessage>();
      expect((down.seat, down.connected), (1, false));
      expect(down.graceDeadline, isNotNull);

      await b.connect();
      final ref = b.joinRoom(room.code);
      final snap = await b.next<RoomStateMessage>(where: (m) => m.ref == ref);
      expect(snap.you.seat, 1);
      expect(snap.state, isNotNull);
      final up = await a.next<PlayerStatusMessage>(where: (m) => m.connected);
      expect(up.seat, 1);
    });
  });
}

int? _seqOf(ServerMessage m) => switch (m) {
  RoomStateMessage(:final seq) ||
  DiceMessage(:final seq) ||
  StatePatchMessage(:final seq) ||
  PlayerStatusMessage(:final seq) ||
  EmoteEvent(:final seq) ||
  GameOverMessage(:final seq) => seq,
  _ => null,
};

/// Plays every decision for this client as soon as it is theirs.
Future<void> _autoPlay(ArenaClient c) async {
  PlayerColor? me;
  var lastActed = -1;
  await for (final m in c.messages) {
    GameState? state;
    int? seq;
    switch (m) {
      case RoomStateMessage():
        me = m.you.color ?? me;
        state = m.state;
        seq = m.seq;
      case DiceMessage():
        state = m.state;
        seq = m.seq;
      case StatePatchMessage():
        state = m.state;
        seq = m.seq;
      case GameOverMessage():
        return;
      case ErrorMessage():
        fail('server error ${m.code}: ${m.message}');
      default:
        continue;
    }
    if (state == null || me == null || state.current != me) continue;
    if (seq <= lastActed) continue;
    lastActed = seq;
    if (state.phase == TurnPhase.awaitingRoll) {
      c.roll();
    } else if (state.phase == TurnPhase.awaitingMove) {
      c.move(legalSequences(state).first);
    }
  }
}

// Checkpoint 4: two headless clients play a full game through the server,
// from room creation to a win, with one forced disconnect and reconnect.
// Also checks the fair dice proof and a fake deposit reaching the wallet.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:math';

import 'package:arena_protocol/client.dart';
import 'package:arena_protocol/fair_dice.dart';
import 'package:arena_server/arena_server.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

/// Plays one seat: rolls on its turn and answers each roll with a legal
/// sequence from the engine. Acts at most once per decision.
class Player {
  Player(this.name, this.client, this.random);

  final String name;
  final ArenaClient client;
  final Random random;
  PlayerColor? color;
  String? lastDecision;
  StreamSubscription<ServerMessage>? _sub;
  final errors = <ErrorMessage>[];

  void listen() {
    _sub?.cancel();
    _sub = client.messages.listen((m) {
      switch (m) {
        case RoomStateMessage(:final you, :final state):
          color = you.color ?? color;
          if (state != null) _act(state);
        case DiceMessage(:final state):
          _act(state);
        case StatePatchMessage(:final state):
          _act(state);
        case ErrorMessage():
          errors.add(m);
        default:
      }
    });
  }

  void stop() => _sub?.cancel();

  void _act(GameState state) {
    final me = color;
    if (me == null || state.current != me) return;
    final key =
        '${state.rollNumber}:${state.phase.name}:${state.remainingDice.length}';
    if (key == lastDecision) return;
    if (state.phase == TurnPhase.awaitingRoll) {
      lastDecision = key;
      client.roll();
    } else if (state.phase == TurnPhase.awaitingMove) {
      final options = legalSequences(state);
      if (options.isEmpty || options.first.isEmpty) return;
      lastDecision = key;
      client.move(options[random.nextInt(options.length)]);
    }
  }
}

void main() {
  late RunningServer server;

  setUp(() async {
    server = await startServer(
      ServerConfig.forTests(
        turnTimeout: const Duration(seconds: 30),
        reconnectGrace: const Duration(seconds: 60),
        botDelay: const Duration(milliseconds: 1),
        roomIdle: const Duration(minutes: 30),
        roomCreatesPerHour: 100,
        wsMessagesPerSecond: 1000,
        databaseUrl: null,
        redisUrl: null,
      ),
    );
  });

  tearDown(() => server.close());

  test(
    'two clients play a full 1v1 game with a disconnect and reconnect',
    () async {
      final alice = ArenaClient(baseUrl: server.baseUrl);
      final bob = ArenaClient(baseUrl: server.baseUrl);
      await alice.login('fake:+256700000001');
      // Bob plays as a guest: free rooms need no phone (D33).
      final bobUser = await bob.guest();
      expect(bobUser.isGuest, isTrue);

      final room = await alice.createRoom(mode: GameMode.oneVsOne, seats: 2);
      expect(room.code, hasLength(6));
      expect(room.link, endsWith('/r/${room.code}'));

      final a = Player('alice', alice, Random(1))..listen();
      final b = Player('bob', bob, Random(2))..listen();
      await alice.connect();
      await bob.connect();
      alice.joinRoom(room.code, clientSeed: 'alice-seed');
      final lobby = await alice.next<RoomStateMessage>();
      expect(lobby.serverSeedHash, isNotNull);
      bob.joinRoom(room.code, clientSeed: 'bob-seed');

      // Let the game run until bob has seen a good number of rolls, then drop him.
      await bob.next<DiceMessage>(
        where: (m) => m.rollNumber >= 20,
        timeout: const Duration(seconds: 30),
      );
      b.stop();
      final dropAt = alice.received.length;
      await bob.disconnect();
      await alice.next<PlayerStatusMessage>(
        where: (m) => !m.connected,
        after: dropAt,
      );

      // Reconnect within the grace period and get a full snapshot back.
      final before = bob.received.length;
      b.listen();
      await bob.connect();
      bob.joinRoom(room.code, lastSeq: 0);
      final snapshot = await bob.next<RoomStateMessage>(
        where: (m) => m.state != null,
        after: before,
      );
      expect(snapshot.you.color, b.color);
      await alice.next<PlayerStatusMessage>(
        where: (m) => m.connected,
        after: dropAt,
      );

      final over = await alice.next<GameOverMessage>(
        timeout: const Duration(minutes: 2),
      );
      expect(over.winners, hasLength(1));
      expect([a.color, b.color], contains(over.winners.single));
      expect(a.errors.where((e) => e.code == ErrorCodes.illegalMove), isEmpty);
      expect(b.errors.where((e) => e.code == ErrorCodes.illegalMove), isEmpty);

      // Every roll can be checked against the revealed seed.
      expect(hashServerSeed(fromHex(over.serverSeed)), lobby.serverSeedHash);
      final proof = await alice.verifyMatch(over.matchId);
      expect(
        verifyRolls(
          serverSeedHex: proof.serverSeed,
          serverSeedHash: proof.serverSeedHash,
          clientSeed: proof.clientSeed,
          rolls: proof.rolls,
        ),
        isTrue,
      );
      final dice = alice.received.whereType<DiceMessage>().toList();
      expect(dice.length, greaterThan(40));
      final bobAfter = bob.received.skip(before).whereType<StatePatchMessage>();
      expect(bobAfter.where((p) => p.color == b.color && !p.auto), isNotEmpty);
      for (final d in dice) {
        expect(proof.rolls[d.rollNumber], d.values);
      }

      // The winning state really is a finished game.
      final last = alice.received.whereType<StatePatchMessage>().last.state;
      expect(isGameOver(last), isTrue);

      await alice.close();
      await bob.close();
    },
  );

  test('a fake deposit shows up in the wallet once', () async {
    final alice = ArenaClient(baseUrl: server.baseUrl);
    await alice.login('fake:+256700000001');
    final payment = await alice.request('POST', '/v1/wallet/deposits', {
      'amount': 5000,
      'msisdn': '256700000001',
      'provider': 'fake',
    });
    expect(payment['status'], 'pending');
    final id = payment['id'] as String;
    await alice.request('POST', '/v1/dev/payments/$id/confirm');
    await alice.request('POST', '/v1/dev/payments/$id/confirm');
    final wallet = await alice.request('GET', '/v1/wallet');
    expect(wallet['balance'], 5000);
    final done = await alice.request('GET', '/v1/wallet/deposits/$id');
    expect(done['status'], 'succeeded');
    await alice.close();
  });
}

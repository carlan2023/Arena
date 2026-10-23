import 'package:arena_protocol/arena_protocol.dart';
import 'package:arena_server/src/rooms/matchmaker.dart';
import 'package:arena_server/src/rooms/room_manager.dart';
import 'package:arena_server/src/store/match_log.dart';
import 'package:arena_wallet/arena_wallet.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

import 'support/room_harness.dart';

void main() {
  late InMemoryLedger ledger;
  late Harness h;

  setUp(() {
    ledger = InMemoryLedger();
    h = Harness(
      allowTable: openCoinTables,
      settlement: SettlementService(ledger: ledger),
      balances: (userId) async => (
        await ledger.balance(AccountId.wallet(userId)),
        await ledger.balance(AccountId.wallet(userId, Currency.coin)),
      ),
      settings: const RoomSettings(
        turnTimeout: Duration(hours: 1),
        botDelay: Duration(hours: 1),
        reconnectGrace: Duration(seconds: 1),
      ),
    );
  });

  Future<void> fund(String userId, int amount) => ledger.post(
    LedgerTransaction(
      idempotencyKey: 'fund:$userId',
      kind: 'coin_signup',
      transfers: [
        Transfer(
          from: const AccountId.revenue(Currency.coin),
          to: AccountId.wallet(userId, Currency.coin),
          amount: amount,
        ),
      ],
    ),
  );

  Future<int> coins(String userId) =>
      ledger.balance(AccountId.wallet(userId, Currency.coin));

  Future<int> house() => ledger.balance(const AccountId.revenue(Currency.coin));

  void queue(
    TestConnection c, {
    GameMode mode = GameMode.oneVsOne,
    int entry = 50,
    int stake = 0,
  }) => h.send(
    c,
    (n) => QueueJoinMessage(
      mode: mode,
      entry: entry,
      stake: stake,
      clientSeed: 'seed${c.userId}',
      cseq: n,
    ),
  );

  test('entries are taken when a private room starts', () async {
    await fund('a', 500);
    await fund('b', 500);
    final room = h.openRoom(['a', 'b'], entry: 50);
    expect(room.status, RoomStatus.waiting);
    await h.drain();
    expect(room.status, RoomStatus.playing);
    expect(room.stakesHeld, isTrue);
    expect(await coins('a'), 450);
    expect(await coins('b'), 450);
    expect(
      await ledger.balance(AccountId.pot(room.matchId!, Currency.coin)),
      100,
    );
    final update = h.conns['a']!.last<WalletUpdateMessage>();
    expect((update.reason, update.coins, update.balance), ('stake', 450, 0));
  });

  test('a short wallet is removed and nobody is charged', () async {
    await fund('rich', 500);
    await fund('poor', 40);
    final room = h.openRoom(['rich', 'poor'], entry: 50);
    await h.drain();
    expect(room.status, RoomStatus.waiting);
    expect(room.stakesHeld, isFalse);
    expect(room.seatOfUser('poor'), isNull);
    expect(room.seatOfUser('rich'), isNotNull);
    expect(await coins('rich'), 500);
    expect(await coins('poor'), 40);
    expect(h.conns['poor']!.lastError!.code, ErrorCodes.insufficientFunds);
    expect(await ledger.metadataFor('stake:${room.matchId}'), isNull);
  });

  test('the winner takes the pot and the match log keeps the entry', () async {
    await fund('a', 500);
    await fund('b', 500);
    final room = h.openRoom(['a', 'b'], entry: 50);
    await h.drain();
    h.playToEnd(room);
    expect(room.settling, isTrue);
    await h.drain();
    expect(room.status, RoomStatus.finished);
    expect(room.stakesHeld, isFalse);
    final over = h.conns['a']!.last<GameOverMessage>();
    expect(over.coinsDelta.values.reduce((x, y) => x + y), 0);
    expect(over.coinsDelta.values.toSet(), {50, -50});
    expect(over.walletDelta, isEmpty);
    final winner = over.coinsDelta.entries.firstWhere((e) => e.value == 50).key;
    final loser = over.coinsDelta.entries.firstWhere((e) => e.value == -50).key;
    expect(await coins(winner), 550);
    expect(await coins(loser), 450);
    expect(
      await ledger.balance(AccountId.pot(room.matchId!, Currency.coin)),
      0,
    );
    expect(await house(), -1000);
    expect(await ledger.verifyIntegrity(), isTrue);
    final paid = h.conns[winner]!.all<WalletUpdateMessage>().last;
    expect((paid.reason, paid.coins), ('payout', 550));
    final recent = await h.log.recentMatches(winner);
    expect(recent.single.entry, 50);
  });

  test('abandoning before any move refunds every entry', () async {
    await fund('a', 500);
    await fund('b', 500);
    final room = h.openRoom(['a', 'b'], entry: 50);
    await h.drain();
    expect(room.movesPlayed, 0);
    h.manager.disconnected(h.conns['a']!);
    h.manager.disconnected(h.conns['b']!);
    h.clock.advance(const Duration(seconds: 1));
    await h.drain();
    expect(room.status, RoomStatus.finished);
    expect(await coins('a'), 500);
    expect(await coins('b'), 500);
    expect(await house(), -1000);
    expect(
      await ledger.balance(AccountId.pot(room.matchId!, Currency.coin)),
      0,
    );
    expect(h.conns['a']!.all<GameOverMessage>(), isEmpty);
    expect(h.log.ends.values.single.status, MatchStatus.abandoned);
  });

  test(
    'abandoning after a move pays the ranking instead of refunding',
    () async {
      await fund('a', 500);
      await fund('b', 500);
      final room = h.openRoom(['a', 'b'], entry: 50);
      await h.drain();
      var guard = 0;
      while (room.movesPlayed == 0 &&
          room.status == RoomStatus.playing &&
          guard++ < 20) {
        h.playOne(room);
      }
      expect(room.movesPlayed, greaterThan(0));
      h.manager.disconnected(h.conns['a']!);
      h.manager.disconnected(h.conns['b']!);
      h.clock.advance(const Duration(seconds: 1));
      await h.drain();
      expect(room.status, RoomStatus.finished);
      expect(await coins('a') + await coins('b'), 1000);
      expect({await coins('a'), await coins('b')}, {550, 450});
      expect(h.log.ends.values.single.status, MatchStatus.abandoned);
    },
  );

  test(
    'two quick match players are charged and told their balance on join',
    () async {
      await fund('a', 500);
      await fund('b', 500);
      final a = h.connect('a');
      final b = h.connect('b');
      queue(a);
      expect(a.last<QueueStatusMessage>().state, QueueState.waiting);
      queue(b);
      await h.drain();
      expect(a.last<QueueStatusMessage>().state, QueueState.matched);
      expect(
        b.last<QueueStatusMessage>().roomCode,
        a.last<QueueStatusMessage>().roomCode,
      );
      final room = h.manager.room(a.last<QueueStatusMessage>().roomCode!)!;
      expect(room.status, RoomStatus.playing);
      expect(await coins('a'), 450);
      expect(await coins('b'), 450);
      h.join(a, room.code);
      await h.drain();
      final update = a.last<WalletUpdateMessage>();
      expect((update.reason, update.coins), ('stake', 450));
    },
  );

  test('a quick match against a bot is funded by the house', () async {
    await fund('a', 500);
    final a = h.connect('a');
    queue(a);
    h.clock.advance(const Duration(seconds: 20));
    await h.drain();
    expect(a.last<QueueStatusMessage>().state, QueueState.matched);
    final room = h.manager.room(a.last<QueueStatusMessage>().roomCode!)!;
    expect(room.status, RoomStatus.playing);
    expect(room.seated.map((s) => s.userId), contains('bot:1'));
    expect(await coins('a'), 450);
    expect(await house(), -550);
    expect(
      await ledger.balance(AccountId.pot(room.matchId!, Currency.coin)),
      100,
    );
  });

  test('a quick match player who cannot pay is not seated', () async {
    await fund('rich', 500);
    await fund('poor', 40);
    final rich = h.connect('rich');
    final poor = h.connect('poor');
    queue(rich);
    queue(poor);
    await h.drain();
    expect(poor.lastError!.code, ErrorCodes.insufficientFunds);
    expect(rich.last<QueueStatusMessage>().state, QueueState.matched);
    final room = h.manager.room(rich.last<QueueStatusMessage>().roomCode!)!;
    expect(room.status, RoomStatus.waiting);
    expect(room.seatOfUser('poor'), isNull);
    expect(await coins('rich'), 500);
    expect(await coins('poor'), 40);
  });

  test('unknown coin entries and stakes are refused', () {
    expect(
      () => h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.oneVsOne,
        seats: 2,
        entry: 75,
      ),
      throwsA(isA<RoomException>()),
    );
    expect(
      () => h.manager.createRoom(
        ownerUserId: 'a',
        mode: GameMode.teams,
        seats: 4,
        entry: 50,
      ),
      throwsA(isA<RoomException>()),
    );
    final a = h.connect('a');
    queue(a, entry: 75);
    expect(a.lastError!.code, ErrorCodes.badRequest);
    queue(a, entry: 0, stake: 1000);
    expect(a.lastError!.code, ErrorCodes.paidTablesDisabled);
  });
}

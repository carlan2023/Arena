import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('in memory', () {
    settlementTests(() async => (InMemoryLedger(), () async {}));
  });

  group('Postgres', skip: skipWithoutDatabase, () {
    settlementTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresLedger(db.pool), db.close);
    });
  });
}

void settlementTests(
  Future<(Ledger, Future<void> Function())> Function() create,
) {
  late Ledger ledger;
  late SettlementService settlement;

  setUp(() async {
    final (opened, close) = await create();
    ledger = opened;
    addTearDown(close);
    settlement = SettlementService(ledger: ledger);
  });

  Future<void> fund(
    String userId,
    int amount, [
    Currency currency = Currency.coin,
  ]) {
    return ledger.post(
      LedgerTransaction(
        idempotencyKey: 'fund:$userId:${currency.name}',
        kind: 'coin_signup',
        transfers: [
          Transfer(
            from: AccountId.revenue(currency),
            to: AccountId.wallet(userId, currency),
            amount: amount,
          ),
        ],
      ),
    );
  }

  Future<int> coins(String userId) =>
      ledger.balance(AccountId.wallet(userId, Currency.coin));

  Future<int> houseCoins() =>
      ledger.balance(const AccountId.revenue(Currency.coin));

  MatchStakes coinStakes(String id, List<String> users, {int entry = 50}) =>
      MatchStakes(
        matchId: id,
        currency: Currency.coin,
        perPlayer: entry,
        userIds: users,
      );

  test('1v1 winner takes the pot, loser is down their entry', () async {
    await fund('a', 500);
    await fund('b', 500);
    await settlement.collectStakes(coinStakes('m1', ['a', 'b']));
    expect(await coins('a'), 450);
    expect(await coins('b'), 450);
    expect(await ledger.balance(const AccountId.pot('m1', Currency.coin)), 100);

    final nets = await settlement.settle('m1', ['a', 'b']);
    expect(nets, {'a': 50, 'b': -50});
    expect(await coins('a'), 550);
    expect(await coins('b'), 450);
    expect(await ledger.balance(const AccountId.pot('m1', Currency.coin)), 0);
    expect(await houseCoins(), -1000);
    expect(await settlement.settle('m1', ['a', 'b']), nets);
    expect(await coins('a'), 550);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test(
    'a bot entry comes from the house and a bot win returns there',
    () async {
      await fund('a', 500);
      await settlement.collectStakes(coinStakes('m-bot', ['a', 'bot:1']));
      expect(await coins('a'), 450);
      expect(await houseCoins(), -500 - 50);

      final humanWins = await settlement.settle('m-bot', ['a', 'bot:1']);
      expect(humanWins, {'a': 50});
      expect(await coins('a'), 550);
      // The human took the bot's entry. The house stays down that 50.
      expect(await houseCoins(), -550);

      await fund('c', 200);
      await settlement.collectStakes(coinStakes('m-lose', ['c', 'bot:0']));
      final botWins = await settlement.settle('m-lose', ['bot:0', 'c']);
      expect(botWins, {'c': -50});
      expect(await coins('c'), 150);
      // House paid the bot's 50 and received the pot of 100, so it is
      // -550 from before, -200 for c's grant, -50 for the bot, +100 back.
      expect(await houseCoins(), -700);
      expect(await ledger.verifyIntegrity(), isTrue);
    },
  );

  test(
    'four players: 2nd gets its entry back, winner takes the rest',
    () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await fund(id, 200);
      }
      await settlement.collectStakes(
        coinStakes('m4', ['a', 'b', 'c', 'd'], entry: 200),
      );
      final nets = await settlement.settle('m4', ['a', 'b', 'c', 'd']);
      expect(nets, {'a': 400, 'b': 0, 'c': -200, 'd': -200});
      expect(await coins('a'), 600);
      expect(await coins('b'), 200);
      expect(await coins('c'), 0);
      expect(await coins('d'), 0);
      expect(await ledger.balance(const AccountId.pot('m4', Currency.coin)), 0);
      expect(await ledger.verifyIntegrity(), isTrue);
    },
  );

  test(
    'four players with bots: a bot in 2nd sends that entry to the house',
    () async {
      await fund('a', 1000);
      await fund('b', 1000);
      await settlement.collectStakes(
        coinStakes('m4b', ['a', 'bot:1', 'b', 'bot:3'], entry: 50),
      );
      final nets = await settlement.settle('m4b', ['a', 'bot:1', 'b', 'bot:3']);
      expect(nets, {'a': 100, 'b': -50});
      expect(await coins('a'), 1100);
      expect(await coins('b'), 950);
      // House paid two bot entries (100) and got 2nd's 50 back.
      expect(await houseCoins(), -2000 - 100 + 50);
      expect(await ledger.verifyIntegrity(), isTrue);
    },
  );

  test('a short wallet charges nobody', () async {
    await fund('a', 500);
    await fund('b', 40);
    await expectLater(
      settlement.collectStakes(coinStakes('m-short', ['a', 'b'])),
      throwsA(
        isA<InsufficientFundsException>().having(
          (e) => e.account.ref,
          'user',
          'b',
        ),
      ),
    );
    expect(await coins('a'), 500);
    expect(await coins('b'), 40);
    expect(
      await ledger.balance(const AccountId.pot('m-short', Currency.coin)),
      0,
    );
    expect(
      await ledger.metadataFor(SettlementService.stakeKey('m-short')),
      isNull,
    );
  });

  test('collect, settle and refund are safe to repeat', () async {
    await fund('a', 500);
    await fund('b', 500);
    final stakes = coinStakes('m-once', ['a', 'b']);
    await Future.wait([
      settlement.collectStakes(stakes),
      settlement.collectStakes(stakes),
    ]);
    expect(await coins('a'), 450);
    await settlement.refund('m-once');
    await settlement.refund('m-once');
    expect(await coins('a'), 500);
    expect(await coins('b'), 500);
    expect(
      await ledger.balance(const AccountId.pot('m-once', Currency.coin)),
      0,
    );
    await expectLater(
      settlement.settle('m-once', ['a', 'b']),
      throwsA(isA<StateError>()),
    );
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test(
    'refund after settle is refused, and a missing match refunds nothing',
    () async {
      await fund('a', 80);
      await fund('b', 80);
      await settlement.collectStakes(coinStakes('m-set', ['a', 'b']));
      await settlement.settle('m-set', ['b', 'a']);
      await expectLater(settlement.refund('m-set'), throwsA(isA<StateError>()));
      expect(await coins('b'), 80 + 50);
      await settlement.refund('never');
      expect(await ledger.verifyIntegrity(), isTrue);
    },
  );

  test('an abandoned game can be refunded before any payout', () async {
    await fund('a', 500);
    await fund('b', 500);
    await settlement.collectStakes(
      coinStakes('m-back', ['a', 'bot:0', 'b', 'bot:1']),
    );
    expect(await coins('a'), 450);
    await settlement.refund('m-back');
    expect(await coins('a'), 500);
    expect(await coins('b'), 500);
    // The two bot entries went out and came back. Only the grants remain.
    expect(await houseCoins(), -1000);
    expect(
      await ledger.balance(const AccountId.pot('m-back', Currency.coin)),
      0,
    );
  });

  test('UGX 1v1 matches the README section 10 example', () async {
    Future<void> ugx(String userId) => ledger.post(
      LedgerTransaction(
        idempotencyKey: 'ugx:$userId',
        kind: 'deposit',
        transfers: [
          Transfer(
            from: const AccountId.providerClearing('fake'),
            to: AccountId.wallet(userId),
            amount: 5000,
          ),
        ],
      ),
    );
    await ugx('winner');
    await ugx('loser');
    await settlement.collectStakes(
      const MatchStakes(
        matchId: 'paid',
        currency: Currency.ugx,
        perPlayer: 5000,
        userIds: ['winner', 'loser'],
      ),
    );
    final nets = await settlement.settle('paid', ['winner', 'loser']);
    expect(nets, {'winner': 3230, 'loser': -5000});
    expect(await ledger.balance(const AccountId.wallet('winner')), 8230);
    expect(await ledger.balance(const AccountId.wallet('loser')), 0);
    expect(await ledger.balance(const AccountId.revenue()), 840);
    expect(await ledger.balance(const AccountId.taxPayable()), 360);
    expect(await ledger.balance(const AccountId.taxWithheld()), 570);
    expect(await ledger.balance(const AccountId.pot('paid')), 0);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('bad stakes and a ranking that drops a player are refused', () async {
    await expectLater(
      settlement.collectStakes(
        const MatchStakes(
          matchId: 'x',
          currency: Currency.coin,
          perPlayer: 40,
          userIds: ['a', 'b'],
        ),
      ),
      throwsArgumentError,
    );
    await fund('a', 50);
    await fund('b', 50);
    await settlement.collectStakes(coinStakes('ok', ['a', 'b']));
    await expectLater(settlement.settle('ok', ['a']), throwsArgumentError);
    expect(await ledger.verifyIntegrity(), isTrue);
  });
}

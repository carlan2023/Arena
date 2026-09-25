import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

const alice = AccountId.wallet('alice');
const bob = AccountId.wallet('bob');
const mtn = AccountId.providerClearing('mtn');
const pot = AccountId.pot('match-1');
const revenue = AccountId.revenue();

LedgerTransaction deposit(String key, AccountId to, int amount) =>
    LedgerTransaction(
      idempotencyKey: key,
      kind: 'deposit',
      transfers: [Transfer(from: mtn, to: to, amount: amount)],
    );

LedgerTransaction move(String key, AccountId from, AccountId to, int amount) =>
    LedgerTransaction(
      idempotencyKey: key,
      kind: 'stake',
      transfers: [Transfer(from: from, to: to, amount: amount)],
    );

void main() {
  group('InMemoryLedger', () {
    ledgerTests(() async => (InMemoryLedger(), () async {}));
  });

  group('PostgresLedger', skip: skipWithoutDatabase, () {
    ledgerTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresLedger(db.pool), db.close);
    });
    postgresConcurrencyTests();
  });

  test('AccountId keys', () {
    expect(alice.key, 'wallet:alice:ugx');
    expect(
      const AccountId.wallet('alice', Currency.coin).key,
      'wallet:alice:coin',
    );
    expect(mtn.key, 'providerClearing:mtn:ugx');
    expect(revenue.key, 'revenue:house:ugx');
    expect(const AccountId.revenue(Currency.coin).key, 'revenue:house:coin');
    expect(const AccountId.taxWithheld().key, 'taxWithheld:house:ugx');
    expect(const AccountId.taxPayable().key, 'taxPayable:house:ugx');
    expect(pot.key, 'pot:match-1:ugx');
  });
}

void ledgerTests(Future<(Ledger, Future<void> Function())> Function() create) {
  late Ledger ledger;

  setUp(() async {
    final (l, close) = await create();
    ledger = l;
    addTearDown(close);
  });

  test('a deposit credits the wallet and debits the provider', () async {
    final result = await ledger.post(deposit('d1', alice, 5000));
    expect(result.duplicate, isFalse);
    expect(await ledger.balance(alice), 5000);
    expect(await ledger.balance(mtn), -5000);
    expect(await ledger.balance(bob), 0);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('posting the same key again is a no-op with the first txId', () async {
    final first = await ledger.post(deposit('d1', alice, 5000));
    final second = await ledger.post(deposit('d1', alice, 5000));
    expect(second.duplicate, isTrue);
    expect(second.txId, first.txId);
    expect(await ledger.balance(alice), 5000);
  });

  test('refuses to take a wallet below zero, recording nothing', () async {
    await ledger.post(deposit('d1', alice, 1000));
    await expectLater(
      ledger.post(move('s1', alice, pot, 1500)),
      throwsA(
        isA<InsufficientFundsException>()
            .having((e) => e.account, 'account', alice)
            .having((e) => e.balance, 'balance', 1000)
            .having((e) => e.needed, 'needed', 1500),
      ),
    );
    expect(await ledger.balance(alice), 1000);
    expect(await ledger.balance(pot), 0);
    expect(await ledger.history(alice), hasLength(1));
    // The refused key can be used again.
    await ledger.post(deposit('d2', alice, 500));
    expect(
      (await ledger.post(move('s1', alice, pot, 1500))).duplicate,
      isFalse,
    );
    expect(await ledger.balance(alice), 0);
  });

  test('refuses to take a pot below zero', () async {
    await expectLater(
      ledger.post(move('p1', pot, alice, 1)),
      throwsA(isA<InsufficientFundsException>()),
    );
  });

  test('all transfers or none', () async {
    await ledger.post(deposit('d1', alice, 5000));
    await expectLater(
      ledger.post(
        LedgerTransaction(
          idempotencyKey: 'stakes',
          kind: 'stake',
          transfers: const [
            Transfer(from: alice, to: pot, amount: 5000),
            Transfer(from: bob, to: pot, amount: 5000),
          ],
        ),
      ),
      throwsA(isA<InsufficientFundsException>()),
    );
    expect(await ledger.balance(alice), 5000);
    expect(await ledger.balance(pot), 0);
  });

  test('checks the balance after all transfers, per account', () async {
    await ledger.post(deposit('d1', alice, 1000));
    // Out then back in within one transaction: net 0 is fine.
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: 'roundtrip',
        kind: 'refund',
        transfers: const [
          Transfer(from: pot, to: alice, amount: 500),
          Transfer(from: alice, to: pot, amount: 500),
        ],
      ),
    );
    expect(await ledger.balance(alice), 1000);
    expect(await ledger.balance(pot), 0);
    // Two debits that together exceed the balance are refused.
    await expectLater(
      ledger.post(
        LedgerTransaction(
          idempotencyKey: 'double',
          kind: 'stake',
          transfers: const [
            Transfer(from: alice, to: pot, amount: 600),
            Transfer(from: alice, to: revenue, amount: 600),
          ],
        ),
      ),
      throwsA(
        isA<InsufficientFundsException>().having(
          (e) => e.needed,
          'needed',
          1200,
        ),
      ),
    );
  });

  test('settles the README example into the right accounts', () async {
    await ledger.post(deposit('d1', alice, 5000));
    await ledger.post(deposit('d2', bob, 5000));
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: 'stake:m1',
        kind: 'stake',
        transfers: const [
          Transfer(from: alice, to: pot, amount: 5000),
          Transfer(from: bob, to: pot, amount: 5000),
        ],
      ),
    );
    final p = computePayout(
      stakePerPlayer: 5000,
      players: 2,
      settings: const PayoutSettings(),
    );
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: 'settle:m1',
        kind: 'payout',
        transfers: [
          Transfer(from: pot, to: revenue, amount: p.rake),
          Transfer(
            from: pot,
            to: const AccountId.taxWithheld(),
            amount: p.withheld,
          ),
          Transfer(from: pot, to: alice, amount: p.toWinner),
          Transfer(
            from: revenue,
            to: const AccountId.taxPayable(),
            amount: p.rakeTax,
          ),
        ],
      ),
    );
    expect(await ledger.balance(pot), 0);
    expect(await ledger.balance(alice), 8230);
    expect(await ledger.balance(bob), 0);
    expect(await ledger.balance(revenue), 840);
    expect(await ledger.balance(const AccountId.taxWithheld()), 570);
    expect(await ledger.balance(const AccountId.taxPayable()), 360);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('coins are a separate currency granted from house revenue', () async {
    const coins = AccountId.wallet('alice', Currency.coin);
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: 'grant:1',
        kind: 'coin_grant',
        transfers: const [
          Transfer(
            from: AccountId.revenue(Currency.coin),
            to: coins,
            amount: 100,
          ),
        ],
      ),
    );
    expect(await ledger.balance(coins), 100);
    expect(await ledger.balance(alice), 0);
    expect(await ledger.balance(const AccountId.revenue(Currency.coin)), -100);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('refuses invalid transactions', () async {
    Future<void> bad(LedgerTransaction tx) =>
        expectLater(ledger.post(tx), throwsArgumentError);
    await bad(
      const LedgerTransaction(idempotencyKey: 'x', kind: 'k', transfers: []),
    );
    await bad(move('', mtn, alice, 1));
    await bad(move('x', mtn, alice, 0));
    await bad(move('x', mtn, alice, -5));
    await bad(move('x', alice, alice, 5));
    await bad(
      move('x', mtn, const AccountId.wallet('alice', Currency.coin), 5),
    );
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('history is newest first with running balances', () async {
    await ledger.post(deposit('d1', alice, 5000));
    await ledger.post(move('s1', alice, pot, 2000));
    await ledger.post(deposit('d2', alice, 700));
    final history = await ledger.history(alice);
    expect(history.map((e) => e.amount), [700, -2000, 5000]);
    expect(history.map((e) => e.balanceAfter), [3700, 3000, 5000]);
    expect(history.map((e) => e.kind), ['deposit', 'stake', 'deposit']);
    expect(history.every((e) => e.account == alice), isTrue);
    expect(history.every((e) => e.at.isUtc), isTrue);
    expect(await ledger.history(alice, limit: 2), hasLength(2));
    expect(await ledger.history(bob), isEmpty);
  });

  test('entries of one transaction share its txId', () async {
    final r = await ledger.post(move('m', mtn, alice, 10));
    expect((await ledger.history(alice)).single.txId, r.txId);
    expect((await ledger.history(mtn)).single.txId, r.txId);
  });

  test('concurrent posts never overdraw and each key posts once', () async {
    await ledger.post(deposit('d1', alice, 1000));
    final results = await Future.wait([
      for (var i = 0; i < 20; i++)
        ledger
            .post(move('spend:$i', alice, pot, 100))
            .then<bool>((_) => true)
            .catchError(
              (Object _) => false,
              test: (e) => e is InsufficientFundsException,
            ),
    ]);
    expect(results.where((ok) => ok), hasLength(10));
    expect(await ledger.balance(alice), 0);
    expect(await ledger.balance(pot), 1000);

    final same = await Future.wait([
      for (var i = 0; i < 10; i++) ledger.post(deposit('same', bob, 300)),
    ]);
    expect(same.map((r) => r.txId).toSet(), hasLength(1));
    expect(same.where((r) => !r.duplicate), hasLength(1));
    expect(await ledger.balance(bob), 300);
    expect(await ledger.verifyIntegrity(), isTrue);
  });
}

void postgresConcurrencyTests() {
  late TestDatabase db;
  late PostgresLedger ledger;

  setUp(() async {
    db = await TestDatabase.open(migrations);
    ledger = PostgresLedger(db.pool);
  });
  tearDown(() => db.close());

  test('opposite transfers at once do not deadlock', () async {
    await ledger.post(deposit('a', alice, 10000));
    await ledger.post(deposit('b', bob, 10000));
    await Future.wait([
      for (var i = 0; i < 20; i++)
        i.isEven
            ? ledger.post(move('ab$i', alice, bob, 10))
            : ledger.post(move('ba$i', bob, alice, 10)),
    ]).timeout(const Duration(seconds: 20));
    expect(await ledger.balance(alice), 10000);
    expect(await ledger.balance(bob), 10000);
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('two ledgers on separate pools share one idempotency key', () async {
    final other = await TestDatabase.reuse(db);
    addTearDown(other.close);
    final l2 = PostgresLedger(other.pool);
    final results = await Future.wait([
      for (var i = 0; i < 6; i++)
        (i.isEven ? ledger : l2).post(deposit('shared', alice, 250)),
    ]);
    expect(results.where((r) => !r.duplicate), hasLength(1));
    expect(await ledger.balance(alice), 250);
  });

  test('verifyIntegrity notices tampering', () async {
    await ledger.post(deposit('d1', alice, 5000));
    expect(await ledger.verifyIntegrity(), isTrue);
    await db.pool.execute(
      'UPDATE ledger_entries SET amount = amount + 1 '
      'WHERE id = (SELECT max(id) FROM ledger_entries)',
    );
    expect(await ledger.verifyIntegrity(), isFalse);
  });

  test('verifyIntegrity notices a negative wallet', () async {
    await ledger.post(deposit('d1', alice, 5000));
    await db.pool.execute(
      "UPDATE ledger_entries SET amount = -amount, balance_after = -balance_after",
    );
    expect(await ledger.verifyIntegrity(), isFalse);
  });

  test('metadata is stored as jsonb', () async {
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: 'meta',
        kind: 'deposit',
        transfers: const [Transfer(from: mtn, to: alice, amount: 1)],
        metadata: {'paymentId': 'p1', 'n': 2},
      ),
    );
    final row = await db.pool.execute(
      "SELECT metadata->>'paymentId', (metadata->>'n')::int "
      "FROM ledger_transactions WHERE idempotency_key = 'meta'",
    );
    expect(row.first, ['p1', 2]);
  });
}

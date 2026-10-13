import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('in memory', () {
    coinTests(() async => (InMemoryLedger(), () async {}));
  });

  group('Postgres', skip: skipWithoutDatabase, () {
    coinTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresLedger(db.pool), db.close);
    });
  });

  test('daily amounts rise by 20 to day 7, then stay', () {
    const s = CoinSettings();
    expect(
      [for (var d = 1; d <= 9; d++) s.dailyAmount(d)],
      [100, 120, 140, 160, 180, 200, 220, 220, 220],
    );
  });
}

void coinTests(Future<(Ledger, Future<void> Function())> Function() create) {
  late Ledger ledger;
  late CoinService coins;
  // 10:00 in Kampala on 13 Oct 2026.
  var now = DateTime.utc(2026, 10, 13, 7);

  setUp(() async {
    final (l, close) = await create();
    ledger = l;
    addTearDown(close);
    now = DateTime.utc(2026, 10, 13, 7);
    coins = CoinService(ledger: ledger, clock: () => now);
  });

  test('the signup grant is paid once', () async {
    expect(await coins.grantSignup('a'), 500);
    expect(await coins.grantSignup('a'), 0);
    expect(await coins.balance('a'), 500);
    expect(await coins.balance('b'), 0);
    expect(await ledger.balance(const AccountId.revenue(Currency.coin)), -500);
    expect(await ledger.balance(const AccountId.wallet('a')), 0, reason: 'UGX');
    expect(await ledger.verifyIntegrity(), isTrue);
  });

  test('the tutorial grant is paid once', () async {
    expect(await coins.grantTutorial('a'), 50);
    expect(await coins.grantTutorial('a'), 0);
    expect(await coins.balance('a'), 50);
  });

  test('a daily claim, then not again until Kampala midnight', () async {
    var status = await coins.dailyStatus('a');
    expect((status.available, status.amount, status.streak), (true, 100, 0));
    expect(status.nextAt, now);

    final grant = await coins.claimDaily('a');
    expect((grant.granted, grant.streak, grant.balance), (100, 1, 100));

    status = await coins.dailyStatus('a');
    expect((status.available, status.amount, status.streak), (false, 120, 1));
    // Midnight in Kampala is 21:00 UTC the day before.
    expect(status.nextAt, DateTime.utc(2026, 10, 13, 21));
    await expectLater(
      coins.claimDaily('a'),
      throwsA(
        isA<AlreadyClaimedException>().having(
          (e) => e.nextAt,
          'nextAt',
          DateTime.utc(2026, 10, 13, 21),
        ),
      ),
    );

    now = DateTime.utc(2026, 10, 13, 20, 59);
    expect((await coins.dailyStatus('a')).available, isFalse);
    now = DateTime.utc(2026, 10, 13, 21);
    expect((await coins.dailyStatus('a')).available, isTrue);
    expect((await coins.claimDaily('a')).granted, 120);
  });

  test('the streak grows to 220 and a missed day resets it', () async {
    final granted = <int>[];
    for (var day = 0; day < 9; day++) {
      now = DateTime.utc(2026, 10, 13 + day, 7);
      granted.add((await coins.claimDaily('a')).granted);
    }
    expect(granted, [100, 120, 140, 160, 180, 200, 220, 220, 220]);
    expect((await coins.dailyStatus('a')).streak, 9);

    // 22 Oct skipped.
    now = DateTime.utc(2026, 10, 23, 7);
    final status = await coins.dailyStatus('a');
    expect((status.available, status.amount, status.streak), (true, 100, 0));
    final grant = await coins.claimDaily('a');
    expect((grant.granted, grant.streak), (100, 1));
    expect(await coins.balance('a'), 1560 + 100);
  });

  test('two claims at once grant once', () async {
    final results = await Future.wait([
      for (var i = 0; i < 4; i++)
        coins.claimDaily('a').then<Object>((g) => g, onError: (Object e) => e),
    ]);
    expect(results.whereType<DailyRewardGrant>(), hasLength(1));
    expect(results.whereType<AlreadyClaimedException>(), hasLength(3));
    expect(await coins.balance('a'), 100);
  });
}

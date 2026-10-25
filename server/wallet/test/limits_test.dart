import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('in memory', () {
    limitTests(
      () async => (InMemoryLimitStore(), InMemoryPaymentStore(), () async {}),
    );
  });

  group('Postgres', skip: skipWithoutDatabase, () {
    limitTests(() async {
      final db = await TestDatabase.open(migrations);
      return (
        PostgresLimitStore(db.pool),
        PostgresPaymentStore(db.pool),
        db.close,
      );
    });
  });

  test('Kampala windows start at local midnight, Monday and the 1st', () {
    // 23 Oct 2026 12:00 UTC is 15:00 in Kampala, a Friday.
    final now = DateTime.utc(2026, 10, 23, 12);
    expect(kampalaDayStart(now), DateTime.utc(2026, 10, 22, 21));
    expect(kampalaWeekStart(now), DateTime.utc(2026, 10, 18, 21));
    expect(kampalaMonthStart(now), DateTime.utc(2026, 9, 30, 21));
  });
}

void limitTests(
  Future<(LimitStore, PaymentStore, Future<void> Function())> Function() create,
) {
  const settings = LimitSettings(houseDailyCap: 10000);
  const user = 'user-1';
  late LimitStore store;
  late PaymentStore payments;
  late LimitsService service;
  var now = DateTime.utc(2026, 10, 23, 12);

  setUp(() async {
    final (openedStore, openedPayments, close) = await create();
    addTearDown(close);
    store = openedStore;
    payments = openedPayments;
    now = DateTime.utc(2026, 10, 23, 12);
    service = LimitsService(
      store: store,
      payments: payments,
      settings: settings,
      clock: () => now,
    );
  });

  test('an unset player is at the house caps', () async {
    final row = await service.limits(user);
    expect(row.daily, 10000);
    expect(row.weekly, 70000);
    expect(row.monthly, 300000);
    expect(row.hasPending, isFalse);
    expect(row.permanent, isFalse);
    expect(await store.byUser(user), isNull);
  });

  test('a lower limit applies at once and a raise waits 24 hours', () async {
    final lowered = await service.setLimits(user, daily: 1000);
    expect(lowered.daily, 1000);
    expect(lowered.hasPending, isFalse);

    final raised = await service.setLimits(user, daily: 2000);
    expect(raised.daily, 1000);
    expect(raised.pendingDaily, 2000);
    expect(raised.pendingAt, now);

    now = now.add(const Duration(hours: 23));
    expect((await service.limits(user)).daily, 1000);

    now = now.add(const Duration(hours: 1));
    final applied = await service.limits(user);
    expect(applied.daily, 2000);
    expect(applied.hasPending, isFalse);
    expect((await service.limits(user)).daily, 2000);
  });

  test(
    'a lower limit does not restart a raise that is already waiting',
    () async {
      await service.setLimits(user, daily: 1000);
      final raised = await service.setLimits(user, daily: 2000);
      now = now.add(const Duration(hours: 1));
      final lowered = await service.setLimits(user, weekly: 50000);
      expect(lowered.weekly, 50000);
      expect(lowered.daily, 1000);
      expect(lowered.pendingDaily, 2000);
      expect(lowered.pendingAt, raised.pendingAt);

      now = raised.pendingAt!.add(const Duration(hours: 24));
      expect((await service.limits(user)).daily, 2000);
    },
  );

  test('asking for a higher number again restarts the 24 hours', () async {
    await service.setLimits(user, daily: 1000);
    await service.setLimits(user, daily: 2000);
    now = now.add(const Duration(hours: 23));
    final again = await service.setLimits(user, daily: 3000);
    expect(again.pendingDaily, 3000);
    expect(again.pendingAt, now);
    now = now.add(const Duration(hours: 23));
    expect((await service.limits(user)).daily, 1000);
    now = now.add(const Duration(hours: 1));
    expect((await service.limits(user)).daily, 3000);
  });

  test('a limit above the cap or out of order is refused', () async {
    await service.setLimits(user, daily: 1000);
    await expectLater(
      service.setLimits(user, daily: 10001),
      throwsArgumentError,
    );
    await expectLater(
      service.setLimits(user, weekly: 500),
      throwsArgumentError,
    );
    expect((await service.limits(user)).daily, 1000);
    expect((await service.limits(user)).weekly, 70000);
  });

  test('pending and succeeded deposits count, failed ones do not', () async {
    await service.setLimits(user, daily: 1000);
    await payments.create(_payment(user, 400, PaymentStatus.pending, now));
    await payments.create(
      _payment(user, 9000, PaymentStatus.failed, now, id: 'failed'),
    );
    await service.checkDeposit(user, 600);
    await expectLater(
      service.checkDeposit(user, 601),
      throwsA(
        isA<LimitExceededException>()
            .having((e) => e.window, 'window', 'daily')
            .having((e) => e.limit, 'limit', 1000)
            .having((e) => e.used, 'used', 400)
            .having((e) => e.userId, 'userId', user),
      ),
    );

    final yesterday = DateTime.utc(2026, 10, 22, 20);
    await payments.create(
      _payment(user, 1000, PaymentStatus.succeeded, yesterday, id: 'old'),
    );
    await service.checkDeposit(user, 600);
  });

  test('a refused deposit is not stored', () async {
    await service.selfExclude(user, ExclusionPeriod.oneDay);
    final ledger = InMemoryLedger(clock: () => now);
    final deposits = PaymentsService(
      providers: {'fake': FakePaymentProvider()},
      store: payments,
      ledger: ledger,
      limits: service,
      clock: () => now,
    );
    await expectLater(
      deposits.startDeposit(
        userId: user,
        provider: 'fake',
        amount: 500,
        msisdn: '256700000001',
      ),
      throwsA(
        isA<SelfExcludedException>().having((e) => e.userId, 'user', user),
      ),
    );
    expect(await payments.openDepositsSince(user, DateTime.utc(2000)), 0);
  });

  test(
    'self exclusion blocks deposits and paid play, not a coin charge',
    () async {
      final excluded = await service.selfExclude(
        user,
        ExclusionPeriod.sevenDays,
      );
      expect(excluded.excludedUntil, now.add(const Duration(days: 7)));
      await expectLater(
        service.checkDeposit(user, 500),
        throwsA(isA<SelfExcludedException>()),
      );
      await expectLater(
        service.checkPlay(user),
        throwsA(isA<SelfExcludedException>()),
      );

      final shorter = await service.selfExclude(user, ExclusionPeriod.oneDay);
      expect(shorter.excludedUntil, excluded.excludedUntil);

      final longer = await service.selfExclude(
        user,
        ExclusionPeriod.thirtyDays,
      );
      expect(longer.excludedUntil, now.add(const Duration(days: 30)));

      final permanent = await service.selfExclude(
        user,
        ExclusionPeriod.permanent,
      );
      expect(permanent.permanent, isTrue);
      expect(permanent.excludedUntil, isNull);
      final kept = await service.selfExclude(user, ExclusionPeriod.oneDay);
      expect(kept.permanent, isTrue);

      final ledger = InMemoryLedger(clock: () => now);
      final settlement = SettlementService(ledger: ledger, limits: service);
      await expectLater(
        settlement.collectStakes(
          const MatchStakes(
            matchId: 'paid-1',
            currency: Currency.ugx,
            perPlayer: 1000,
            userIds: [user, 'other'],
          ),
        ),
        throwsA(isA<SelfExcludedException>()),
      );
      await expectLater(
        settlement.collectStakes(
          const MatchStakes(
            matchId: 'coin-1',
            currency: Currency.coin,
            perPlayer: 50,
            userIds: [user, 'other'],
          ),
        ),
        throwsA(isA<InsufficientFundsException>()),
      );
    },
  );

  test('six months is a calendar six months', () async {
    final row = await service.selfExclude(user, ExclusionPeriod.sixMonths);
    expect(row.excludedUntil, DateTime.utc(2027, 4, 23, 12));
  });
}

Payment _payment(
  String userId,
  int amount,
  PaymentStatus status,
  DateTime at, {
  String? id,
}) => Payment(
  id: id ?? 'pay-$amount-${at.millisecondsSinceEpoch}',
  userId: userId,
  provider: 'fake',
  amount: amount,
  msisdn: '256700000001',
  status: status,
  createdAt: at,
);

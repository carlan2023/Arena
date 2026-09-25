import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('InMemoryPaymentStore', () {
    paymentStoreTests(() async => (InMemoryPaymentStore(), () async {}));
  });

  group('PostgresPaymentStore', skip: skipWithoutDatabase, () {
    paymentStoreTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresPaymentStore(db.pool), db.close);
    });
  });
}

Payment newPayment(String id, {String provider = 'mtn'}) => Payment(
  id: id,
  userId: 'user-1',
  provider: provider,
  amount: 5000,
  msisdn: '256772123456',
  status: PaymentStatus.pending,
  createdAt: DateTime.utc(2026, 9, 25, 12),
);

void paymentStoreTests(
  Future<(PaymentStore, Future<void> Function())> Function() create,
) {
  late PaymentStore store;

  setUp(() async {
    final (s, close) = await create();
    store = s;
    addTearDown(close);
  });

  test('create and read back', () async {
    final created = await store.create(newPayment('p1'));
    expect(created.id, 'p1');
    expect(created.providerRef, isNull);
    expect(created.createdAt, DateTime.utc(2026, 9, 25, 12));
    final read = (await store.byId('p1'))!;
    expect(read.userId, 'user-1');
    expect(read.amount, 5000);
    expect(read.msisdn, '256772123456');
    expect(read.status, PaymentStatus.pending);
    expect(read.settledAt, isNull);
    expect(await store.byId('nope'), isNull);
  });

  test('provider refs are looked up per provider', () async {
    await store.create(newPayment('p1'));
    await store.create(newPayment('p2', provider: 'airtel'));
    expect((await store.setProviderRef('p1', 'ref-1')).providerRef, 'ref-1');
    expect((await store.byProviderRef('mtn', 'ref-1'))?.id, 'p1');
    expect(await store.byProviderRef('airtel', 'ref-1'), isNull);
    await expectLater(store.setProviderRef('nope', 'x'), throwsStateError);
  });

  test('settle is compare and set', () async {
    await store.create(newPayment('p1'));
    final settled = await store.settle('p1', PaymentStatus.succeeded);
    expect(settled?.status, PaymentStatus.succeeded);
    expect(settled?.settledAt, isNotNull);
    expect(await store.settle('p1', PaymentStatus.succeeded), isNull);
    expect(await store.settle('p1', PaymentStatus.failed), isNull);
    expect((await store.byId('p1'))!.status, PaymentStatus.succeeded);
    expect(await store.settle('nope', PaymentStatus.failed), isNull);
  });

  test('racing settles: exactly one wins', () async {
    await store.create(newPayment('p1'));
    final results = await Future.wait([
      for (var i = 0; i < 8; i++) store.settle('p1', PaymentStatus.succeeded),
    ]);
    expect(results.whereType<Payment>(), hasLength(1));
  });
}

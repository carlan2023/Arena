import 'dart:convert';

import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

typedef Backend = (PaymentStore, Ledger, Future<void> Function());

void main() {
  group('in memory', () {
    serviceTests(
      () async => (InMemoryPaymentStore(), InMemoryLedger(), () async {}),
    );
  });

  group('postgres', skip: skipWithoutDatabase, () {
    serviceTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresPaymentStore(db.pool), PostgresLedger(db.pool), db.close);
    });
  });
}

/// Fails the first settle, as if the process died after the ledger post.
class CrashingStore implements PaymentStore {
  final PaymentStore inner;
  bool crashNextSettle = false;

  CrashingStore(this.inner);

  @override
  Future<Payment> create(Payment payment) => inner.create(payment);
  @override
  Future<Payment?> byId(String id) => inner.byId(id);
  @override
  Future<Payment?> byProviderRef(String provider, String providerRef) =>
      inner.byProviderRef(provider, providerRef);
  @override
  Future<Payment> setProviderRef(String id, String providerRef) =>
      inner.setProviderRef(id, providerRef);
  @override
  Future<Payment?> settle(String id, PaymentStatus status) {
    if (crashNextSettle) {
      crashNextSettle = false;
      throw StateError('crash');
    }
    return inner.settle(id, status);
  }
}

void serviceTests(Future<Backend> Function() create) {
  late CrashingStore store;
  late Ledger ledger;
  late FakePaymentProvider fake;
  late PaymentsService service;
  late List<String> logs;

  const user = 'user-1';
  const wallet = AccountId.wallet(user);

  setUp(() async {
    final (s, l, close) = await create();
    addTearDown(close);
    store = CrashingStore(s);
    ledger = l;
    fake = FakePaymentProvider();
    logs = [];
    service = PaymentsService(
      providers: {'fake': fake},
      store: store,
      ledger: ledger,
      log: logs.add,
    );
  });

  Future<Payment> start({int amount = 5000}) => service.startDeposit(
    userId: user,
    provider: 'fake',
    amount: amount,
    msisdn: '256772123456',
  );

  Future<Payment?> callback(String paymentId) =>
      service.handleCallback('fake', {}, fake.callbackBody(paymentId));

  Future<void> expectCreditedOnce(int amount) async {
    expect(await ledger.balance(wallet), amount);
    expect(await ledger.history(wallet), hasLength(amount == 0 ? 0 : 1));
    expect(await ledger.verifyIntegrity(), isTrue);
  }

  test('startDeposit asks the provider and stays pending', () async {
    final payment = await start();
    expect(payment.status, PaymentStatus.pending);
    expect(
      payment.id,
      matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab]')),
    );
    expect(payment.providerRef, payment.id);
    expect(payment.userId, user);
    final request = fake.requests.single;
    expect(request.paymentId, payment.id);
    expect(request.amount, 5000);
    expect(request.msisdn, '256772123456');
    expect(request.currency, 'UGX');
    await expectCreditedOnce(0);
  });

  test('startDeposit checks provider, amount and msisdn', () async {
    Future<void> bad(String provider, int amount, String msisdn) => expectLater(
      service.startDeposit(
        userId: user,
        provider: provider,
        amount: amount,
        msisdn: msisdn,
      ),
      throwsA(
        isA<PaymentException>().having((e) => e.code, 'code', 'bad_request'),
      ),
    );
    await bad('mtn', 5000, '256772123456');
    await bad('fake', 499, '256772123456');
    await bad('fake', 5000001, '256772123456');
    await bad('fake', 5000, '0772123456');
    await bad('fake', 5000, '+256772123456');
    await bad('fake', 5000, '25677212345');
    await bad('fake', 5000, '2567721234567');
    expect(fake.requests, isEmpty);
    expect((await start(amount: 500)).status, PaymentStatus.pending);
    expect((await start(amount: 5000000)).status, PaymentStatus.pending);
  });

  test('a definite rejection fails the payment', () async {
    fake.failNextRequest = const ProviderRejectedException('bad number');
    final payment = await start();
    expect(payment.status, PaymentStatus.failed);
    expect((await store.byId(payment.id))!.status, PaymentStatus.failed);
  });

  test('an unknown request outcome stays pending', () async {
    fake.failNextRequest = const ProviderUnavailableException('timeout');
    final payment = await start();
    expect(payment.status, PaymentStatus.pending);
    expect((await service.refresh(payment.id)).status, PaymentStatus.pending);
  });

  test('a confirmed callback credits the wallet', () async {
    final payment = await start();
    fake.complete(payment.id);
    final settled = await callback(payment.id);
    expect(settled?.status, PaymentStatus.succeeded);
    expect(settled?.settledAt, isNotNull);
    await expectCreditedOnce(5000);
    expect(
      await ledger.balance(const AccountId.providerClearing('fake')),
      -5000,
    );
    final entry = (await ledger.history(wallet)).single;
    expect(entry.kind, 'deposit');
  });

  test('a duplicated callback credits once', () async {
    final payment = await start();
    fake.complete(payment.id);
    final body = fake.callbackBody(payment.id);
    final first = await service.handleCallback('fake', {}, body);
    final second = await service.handleCallback('fake', {}, body);
    expect(first?.status, PaymentStatus.succeeded);
    expect(second?.status, PaymentStatus.succeeded);
    await expectCreditedOnce(5000);
  });

  test('racing callbacks credit once', () async {
    final payment = await start();
    fake.complete(payment.id);
    final body = fake.callbackBody(payment.id);
    final results = await Future.wait([
      for (var i = 0; i < 10; i++) service.handleCallback('fake', {}, body),
      for (var i = 0; i < 5; i++) service.refresh(payment.id),
    ]);
    expect(results.every((p) => p?.status == PaymentStatus.succeeded), isTrue);
    await expectCreditedOnce(5000);
  });

  test('a callback after a refresh credits once', () async {
    final payment = await start();
    fake.complete(payment.id);
    expect((await service.refresh(payment.id)).status, PaymentStatus.succeeded);
    expect((await callback(payment.id))?.status, PaymentStatus.succeeded);
    expect((await service.refresh(payment.id)).status, PaymentStatus.succeeded);
    await expectCreditedOnce(5000);
  });

  test('a callback is only a hint: the provider status decides', () async {
    final payment = await start();
    final forged = jsonEncode({
      'ref': payment.id,
      'status': 'succeeded',
      'amount': 5000,
    });
    final result = await service.handleCallback('fake', {}, forged);
    expect(result?.status, PaymentStatus.pending);
    await expectCreditedOnce(0);
  });

  test('a failed payment is never credited', () async {
    final payment = await start();
    fake.complete(payment.id, status: PaymentStatus.failed);
    expect((await callback(payment.id))?.status, PaymentStatus.failed);
    fake.complete(payment.id);
    expect((await callback(payment.id))?.status, PaymentStatus.failed);
    expect((await service.refresh(payment.id)).status, PaymentStatus.failed);
    await expectCreditedOnce(0);
  });

  test('a different confirmed amount is not credited', () async {
    final payment = await start();
    fake.complete(payment.id, amount: 50000);
    expect((await callback(payment.id))?.status, PaymentStatus.pending);
    await expectCreditedOnce(0);
    expect(logs.any((l) => l.contains('REVIEW')), isTrue);
  });

  test('a crash between ledger post and settle is repaired', () async {
    final payment = await start();
    fake.complete(payment.id);
    store.crashNextSettle = true;
    await expectLater(callback(payment.id), throwsStateError);
    expect((await store.byId(payment.id))!.status, PaymentStatus.pending);
    await expectCreditedOnce(5000);

    expect((await callback(payment.id))?.status, PaymentStatus.succeeded);
    await expectCreditedOnce(5000);
  });

  test(
    'a succeeded payment missing its credit is credited on refresh',
    () async {
      final payment = await start();
      await store.settle(payment.id, PaymentStatus.succeeded);
      await expectCreditedOnce(0);
      expect(
        (await service.refresh(payment.id)).status,
        PaymentStatus.succeeded,
      );
      await expectCreditedOnce(5000);
      await service.refresh(payment.id);
      await expectCreditedOnce(5000);
    },
  );

  test('a failed status check leaves the payment pending', () async {
    final payment = await start();
    fake.failStatusChecks = const ProviderUnavailableException('down');
    expect((await service.refresh(payment.id)).status, PaymentStatus.pending);
    expect(logs, isNotEmpty);
  });

  test('bad callbacks', () async {
    await expectLater(
      service.handleCallback('fake', {}, 'garbage'),
      throwsA(
        isA<PaymentException>().having((e) => e.code, 'code', 'bad_callback'),
      ),
    );
    await expectLater(
      service.handleCallback('mtn', {}, '{}'),
      throwsA(
        isA<PaymentException>().having((e) => e.code, 'code', 'bad_request'),
      ),
    );
    final unknown = jsonEncode({'ref': 'nope', 'status': 'succeeded'});
    expect(await service.handleCallback('fake', {}, unknown), isNull);
  });

  test('a callback to another provider does not match the payment', () async {
    final other = FakePaymentProvider(name: 'other');
    service = PaymentsService(
      providers: {'fake': fake, 'other': other},
      store: store,
      ledger: ledger,
      log: logs.add,
    );
    final payment = await start();
    fake.complete(payment.id);
    expect(
      await service.handleCallback('other', {}, fake.callbackBody(payment.id)),
      isNull,
    );
    await expectCreditedOnce(0);
  });

  test('refresh of an unknown payment is not_found', () async {
    await expectLater(
      service.refresh('nope'),
      throwsA(
        isA<PaymentException>().having((e) => e.code, 'code', 'not_found'),
      ),
    );
  });
}

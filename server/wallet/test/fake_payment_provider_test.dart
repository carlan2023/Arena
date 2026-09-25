import 'package:arena_wallet/arena_wallet.dart';
import 'package:test/test.dart';

void main() {
  late FakePaymentProvider fake;
  const request = DepositRequest(
    paymentId: 'p1',
    amount: 5000,
    msisdn: '256772123456',
  );

  setUp(() => fake = FakePaymentProvider());

  test('records requests and starts pending', () async {
    expect(fake.name, 'fake');
    expect((await fake.requestDeposit(request)).providerRef, 'p1');
    expect(fake.requests.single.amount, 5000);
    final status = await fake.checkStatus('p1');
    expect(status.status, PaymentStatus.pending);
    expect(status.amount, 5000);
  });

  test('complete sets the status and callbackBody matches it', () async {
    await fake.requestDeposit(request);
    fake.complete('p1');
    expect((await fake.checkStatus('p1')).status, PaymentStatus.succeeded);
    final event = fake.parseCallback({}, fake.callbackBody('p1'))!;
    expect(event.providerRef, 'p1');
    expect(event.status, PaymentStatus.succeeded);
    expect(event.amount, 5000);

    fake.complete('p1', status: PaymentStatus.failed, amount: 1);
    final failed = await fake.checkStatus('p1');
    expect(failed.status, PaymentStatus.failed);
    expect(failed.amount, 1);
  });

  test('unknown refs and bad bodies', () async {
    expect(() => fake.complete('nope'), throwsStateError);
    await expectLater(
      fake.checkStatus('nope'),
      throwsA(isA<ProviderUnavailableException>()),
    );
    for (final bad in [
      '',
      'x',
      '[]',
      '{"ref":"p1"}',
      '{"ref":"p1","status":"odd"}',
    ]) {
      expect(fake.parseCallback({}, bad), isNull, reason: bad);
    }
  });

  test('failNextRequest throws once', () async {
    fake.failNextRequest = const ProviderRejectedException('no');
    await expectLater(
      fake.requestDeposit(request),
      throwsA(isA<ProviderRejectedException>()),
    );
    await fake.requestDeposit(request);
    expect(fake.requests, hasLength(1));
  });
}

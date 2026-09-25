import 'dart:convert';

import 'package:arena_wallet/arena_wallet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const base = 'https://sandbox.momodeveloper.mtn.com';
const ref = '0b6f7a52-3c1e-4d1a-9a5b-2f0e5c1d7e11';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late int tokenCalls;
  late DateTime now;
  late MtnMomoProvider mtn;

  setUp(() {
    requests = [];
    tokenCalls = 0;
    now = DateTime.utc(2026, 9, 25, 12);
    respond = (_) => http.Response('', 202);
    final client = MockClient((request) async {
      if (request.url.path == '/collection/token/') {
        tokenCalls++;
        expect(request.method, 'POST');
        expect(
          request.headers['Authorization'],
          'Basic ${base64.encode(utf8.encode('user:key'))}',
        );
        expect(request.headers['Ocp-Apim-Subscription-Key'], 'sub');
        return http.Response(
          jsonEncode({
            'access_token': 'tok$tokenCalls',
            'token_type': 'access_token',
            'expires_in': 3600,
          }),
          200,
        );
      }
      requests.add(request);
      return respond(request);
    });
    mtn = MtnMomoProvider(
      subscriptionKey: 'sub',
      apiUser: 'user',
      apiKey: 'key',
      targetEnvironment: 'sandbox',
      callbackUrl: 'https://arena.example/v1/payments/callback/mtn',
      httpClient: client,
      clock: () => now,
    );
  });

  const deposit = DepositRequest(
    paymentId: ref,
    amount: 5000,
    msisdn: '256772123456',
  );

  test('requesttopay sends the documented request', () async {
    final ack = await mtn.requestDeposit(deposit);
    expect(ack.providerRef, ref);
    final r = requests.single;
    expect(r.method, 'POST');
    expect(r.url.toString(), '$base/collection/v1_0/requesttopay');
    expect(r.headers['Authorization'], 'Bearer tok1');
    expect(r.headers['X-Reference-Id'], ref);
    expect(r.headers['X-Target-Environment'], 'sandbox');
    expect(
      r.headers['X-Callback-Url'],
      'https://arena.example/v1/payments/callback/mtn',
    );
    expect(r.headers['Ocp-Apim-Subscription-Key'], 'sub');
    final body = jsonDecode(r.body);
    expect(body['amount'], '5000');
    expect(body['currency'], 'EUR');
    expect(body['externalId'], ref);
    expect(body['payer'], {'partyIdType': 'MSISDN', 'partyId': '256772123456'});
  });

  test('the access token is cached until a minute before expiry', () async {
    await mtn.requestDeposit(deposit);
    await mtn.requestDeposit(deposit);
    expect(tokenCalls, 1);
    now = now.add(const Duration(seconds: 3540));
    await mtn.requestDeposit(deposit);
    expect(tokenCalls, 2);
    expect(requests.last.headers['Authorization'], 'Bearer tok2');
  });

  test('409 means already accepted', () async {
    respond = (_) => http.Response('{"code":"RESOURCE_ALREADY_EXIST"}', 409);
    expect((await mtn.requestDeposit(deposit)).providerRef, ref);
  });

  test('4xx is a rejection, 5xx and network errors are unknown', () async {
    respond = (_) => http.Response('{"code":"PAYER_NOT_FOUND"}', 400);
    await expectLater(
      mtn.requestDeposit(deposit),
      throwsA(isA<ProviderRejectedException>()),
    );
    respond = (_) => http.Response('oops', 500);
    await expectLater(
      mtn.requestDeposit(deposit),
      throwsA(isA<ProviderUnavailableException>()),
    );
    respond = (_) => throw http.ClientException('connection reset');
    await expectLater(
      mtn.requestDeposit(deposit),
      throwsA(isA<ProviderUnavailableException>()),
    );
  });

  test('checkStatus maps MTN statuses', () async {
    var answer = <String, Object?>{};
    respond = (r) {
      expect(r.method, 'GET');
      expect(r.url.toString(), '$base/collection/v1_0/requesttopay/$ref');
      expect(r.headers['X-Target-Environment'], 'sandbox');
      return http.Response(jsonEncode(answer), 200);
    };
    answer = {
      'amount': '5000',
      'currency': 'EUR',
      'financialTransactionId': '123',
      'externalId': ref,
      'status': 'SUCCESSFUL',
    };
    var status = await mtn.checkStatus(ref);
    expect(status.status, PaymentStatus.succeeded);
    expect(status.amount, 5000);
    expect(status.providerRef, ref);

    answer = {
      'amount': '5000',
      'status': 'FAILED',
      'reason': 'APPROVAL_REJECTED',
    };
    status = await mtn.checkStatus(ref);
    expect(status.status, PaymentStatus.failed);
    expect(status.reason, 'APPROVAL_REJECTED');

    answer = {
      'status': 'FAILED',
      'reason': {'code': 'EXPIRED', 'message': 'x'},
    };
    expect((await mtn.checkStatus(ref)).reason, 'EXPIRED');

    answer = {'amount': '5000', 'status': 'PENDING'};
    expect((await mtn.checkStatus(ref)).status, PaymentStatus.pending);
  });

  test('checkStatus errors leave the outcome unknown', () async {
    for (final response in [
      http.Response('{"code":"RESOURCE_NOT_FOUND"}', 404),
      http.Response('', 500),
      http.Response('not json', 200),
    ]) {
      respond = (_) => response;
      await expectLater(
        mtn.checkStatus(ref),
        throwsA(isA<ProviderUnavailableException>()),
      );
    }
  });

  test('parses a callback by externalId', () {
    final event = mtn.parseCallback(
      {},
      jsonEncode({
        'financialTransactionId': '2004871870',
        'externalId': ref,
        'amount': '5000',
        'currency': 'EUR',
        'payer': {'partyIdType': 'MSISDN', 'partyId': '256772123456'},
        'payeeNote': 'Arena deposit',
        'payerMessage': 'Arena deposit',
        'status': 'SUCCESSFUL',
      }),
    )!;
    expect(event.providerRef, ref);
    expect(event.status, PaymentStatus.succeeded);
    expect(event.amount, 5000);
    for (final bad in ['', 'nope', '{}', '{"externalId": 5, "status": "X"}']) {
      expect(mtn.parseCallback({}, bad), isNull, reason: bad);
    }
  });
}

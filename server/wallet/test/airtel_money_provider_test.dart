import 'dart:convert';

import 'package:arena_wallet/arena_wallet.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const base = 'https://openapiuat.airtel.africa';
const ref = '0b6f7a52-3c1e-4d1a-9a5b-2f0e5c1d7e11';

void main() {
  late List<http.Request> requests;
  late http.Response Function(http.Request) respond;
  late int tokenCalls;
  late AirtelMoneyProvider airtel;

  http.Response ok(Map<String, Object?> data) => http.Response(
    jsonEncode({
      'data': data,
      'status': {
        'code': '200',
        'message': 'SUCCESS',
        'result_code': 'ESB000010',
        'success': true,
      },
    }),
    200,
  );

  AirtelMoneyProvider provider({String? callbackSecret}) {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/oauth2/token') {
        tokenCalls++;
        expect(jsonDecode(request.body), {
          'client_id': 'id',
          'client_secret': 'secret',
          'grant_type': 'client_credentials',
        });
        return http.Response(
          jsonEncode({
            'access_token': 'tok$tokenCalls',
            'expires_in': '180',
            'token_type': 'bearer',
          }),
          200,
        );
      }
      requests.add(request);
      return respond(request);
    });
    return AirtelMoneyProvider(
      clientId: 'id',
      clientSecret: 'secret',
      callbackUrl: 'https://arena.example/v1/payments/callback/airtel',
      callbackSecret: callbackSecret,
      httpClient: client,
    );
  }

  setUp(() {
    requests = [];
    tokenCalls = 0;
    respond = (_) => ok({
      'transaction': {'id': ref, 'status': 'Success.'},
    });
    airtel = provider();
  });

  const deposit = DepositRequest(
    paymentId: ref,
    amount: 5000,
    msisdn: '256752123456',
  );

  test('payment request strips 256 and uses the payment id', () async {
    expect((await airtel.requestDeposit(deposit)).providerRef, ref);
    await airtel.requestDeposit(deposit);
    expect(tokenCalls, 1);
    final r = requests.first;
    expect(r.method, 'POST');
    expect(r.url.toString(), '$base/merchant/v1/payments/');
    expect(r.headers['Authorization'], 'Bearer tok1');
    expect(r.headers['X-Country'], 'UG');
    expect(r.headers['X-Currency'], 'UGX');
    final body = jsonDecode(r.body);
    expect(body['subscriber'], {
      'country': 'UG',
      'currency': 'UGX',
      'msisdn': '752123456',
    });
    expect(body['transaction'], {
      'amount': 5000,
      'country': 'UG',
      'currency': 'UGX',
      'id': ref,
    });
  });

  test('a success false answer or 4xx is a rejection', () async {
    respond = (_) => http.Response(
      jsonEncode({
        'data': {},
        'status': {
          'code': '200',
          'message': 'Invalid msisdn',
          'response_code': 'DP00800001001',
          'success': false,
        },
      }),
      200,
    );
    await expectLater(
      airtel.requestDeposit(deposit),
      throwsA(isA<ProviderRejectedException>()),
    );
    respond = (_) => http.Response('{}', 401);
    await expectLater(
      airtel.requestDeposit(deposit),
      throwsA(isA<ProviderRejectedException>()),
    );
    respond = (_) => http.Response('', 503);
    await expectLater(
      airtel.requestDeposit(deposit),
      throwsA(isA<ProviderUnavailableException>()),
    );
  });

  test('checkStatus maps TS, TF, TIP and TA', () async {
    var code = 'TS';
    respond = (r) {
      expect(r.method, 'GET');
      expect(r.url.toString(), '$base/standard/v1/payments/$ref');
      return ok({
        'transaction': {
          'airtel_money_id': 'MP210603',
          'id': ref,
          'message': 'msg $code',
          'status': code,
        },
      });
    };
    final expected = {
      'TS': PaymentStatus.succeeded,
      'TF': PaymentStatus.failed,
      'TIP': PaymentStatus.pending,
      'TA': PaymentStatus.pending,
    };
    for (final entry in expected.entries) {
      code = entry.key;
      final status = await airtel.checkStatus(ref);
      expect(status.status, entry.value, reason: code);
      expect(status.reason, 'msg $code');
      expect(status.amount, isNull);
    }
    respond = (_) => http.Response('', 500);
    await expectLater(
      airtel.checkStatus(ref),
      throwsA(isA<ProviderUnavailableException>()),
    );
  });

  Map<String, Object?> transaction(String code) => {
    'id': ref,
    'message': 'Paid UGX 5,000',
    'status_code': code,
    'airtel_money_id': 'MP210603.1234.L06941',
  };

  test('parses a callback', () {
    final event = airtel.parseCallback(
      {},
      jsonEncode({'transaction': transaction('TS')}),
    )!;
    expect(event.providerRef, ref);
    expect(event.status, PaymentStatus.succeeded);
    expect(
      airtel
          .parseCallback({}, jsonEncode({'transaction': transaction('TF')}))!
          .status,
      PaymentStatus.failed,
    );
    for (final bad in [
      '',
      '{}',
      '{"transaction": []}',
      '{"transaction": {}}',
    ]) {
      expect(airtel.parseCallback({}, bad), isNull, reason: bad);
    }
  });

  test('checks the hash when a callback secret is set', () {
    final signed = provider(callbackSecret: 'cb-secret');
    final t = transaction('TS');
    final hash = AirtelMoneyProvider.callbackHash('cb-secret', t);
    expect(
      signed.parseCallback({}, jsonEncode({'transaction': t, 'hash': hash})),
      isNotNull,
    );
    expect(
      signed.parseCallback({}, jsonEncode({'transaction': t, 'hash': 'bad'})),
      isNull,
    );
    expect(signed.parseCallback({}, jsonEncode({'transaction': t})), isNull);
  });
}

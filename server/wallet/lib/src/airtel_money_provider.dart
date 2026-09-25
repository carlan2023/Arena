import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'payment.dart';
import 'provider_http.dart';

/// Airtel Money Collections, /merchant/v1/payments/. The payment id is the
/// transaction.id. Payload encryption, needed in production, is not in M2.
class AirtelMoneyProvider implements PaymentProvider {
  final String clientId;
  final String clientSecret;

  /// Documentation only: Airtel's callback URL is set on its portal.
  final String callbackUrl;

  /// When set, callbacks must carry a matching `hash`: base64 HMAC SHA256 of
  /// the callback's transaction object, keyed with this secret.
  final String? callbackSecret;
  final String baseUrl;
  final String country;
  final String currency;
  final http.Client _http;
  final DateTime Function() _clock;

  CachedToken? _token;
  Future<CachedToken>? _tokenInFlight;

  AirtelMoneyProvider({
    required this.clientId,
    required this.clientSecret,
    required this.callbackUrl,
    this.callbackSecret,
    this.baseUrl = 'https://openapiuat.airtel.africa',
    this.country = 'UG',
    this.currency = 'UGX',
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  @override
  String get name => 'airtel';

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<String> _accessToken() async {
    final token = _token;
    if (token != null && token.validAt(_clock())) return token.value;
    final fresh = await (_tokenInFlight ??= _fetchToken().whenComplete(
      () => _tokenInFlight = null,
    ));
    _token = fresh;
    return fresh.value;
  }

  Future<CachedToken> _fetchToken() async {
    final response = await sendToProvider(
      name,
      () => _http.post(
        _uri('/auth/oauth2/token'),
        headers: {'Content-Type': 'application/json', 'Accept': '*/*'},
        body: jsonEncode({
          'client_id': clientId,
          'client_secret': clientSecret,
          'grant_type': 'client_credentials',
        }),
      ),
    );
    if (response.statusCode != 200) {
      throwForStatus(name, 'token', response);
    }
    final json = jsonObject(response.body);
    final value = json?['access_token'];
    if (value is! String || value.isEmpty) {
      throw ProviderUnavailableException('$name token: no access_token');
    }
    final expiresIn = parseAmount(json!['expires_in']) ?? 180;
    final early = expiresIn > 120 ? 60 : 0;
    return CachedToken(
      value,
      _clock().add(Duration(seconds: expiresIn - early)),
    );
  }

  Future<Map<String, String>> _headers() async => {
    'Content-Type': 'application/json',
    'Accept': '*/*',
    'X-Country': country,
    'X-Currency': currency,
    'Authorization': 'Bearer ${await _accessToken()}',
  };

  /// Airtel wants the number without the country code.
  static String localMsisdn(String msisdn) =>
      msisdn.startsWith('256') ? msisdn.substring(3) : msisdn;

  @override
  Future<ProviderAck> requestDeposit(DepositRequest request) async {
    final headers = await _headers();
    final body = jsonEncode({
      'reference': 'Arena deposit',
      'subscriber': {
        'country': country,
        'currency': currency,
        'msisdn': localMsisdn(request.msisdn),
      },
      'transaction': {
        'amount': request.amount,
        'country': country,
        'currency': currency,
        'id': request.paymentId,
      },
    });
    final response = await sendToProvider(
      name,
      () => _http.post(
        _uri('/merchant/v1/payments/'),
        headers: headers,
        body: body,
      ),
    );
    if (response.statusCode != 200) {
      throwForStatus(name, 'payment', response);
    }
    final json = jsonObject(response.body);
    final status = json?['status'];
    if (status is Map && status['success'] == false) {
      throw ProviderRejectedException(
        '$name payment: ${status['response_code']} ${status['message']}',
      );
    }
    return ProviderAck(request.paymentId);
  }

  @override
  Future<ProviderStatus> checkStatus(String providerRef) async {
    final response = await sendToProvider(
      name,
      () async => _http.get(
        _uri('/standard/v1/payments/$providerRef'),
        headers: await _headers(),
      ),
    );
    if (response.statusCode != 200) {
      throw ProviderUnavailableException(
        '$name status: HTTP ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonObject(response.body);
    final data = json?['data'];
    final transaction = data is Map ? data['transaction'] : null;
    final status = transaction is Map ? transaction['status'] : null;
    if (status is! String) {
      throw ProviderUnavailableException('$name status: unreadable answer');
    }
    final message = transaction!['message'];
    return ProviderStatus(
      providerRef: providerRef,
      status: _status(status),
      reason: message is String ? message : null,
    );
  }

  @override
  CallbackEvent? parseCallback(Map<String, String> headers, String body) {
    final json = jsonObject(body);
    final transaction = json?['transaction'];
    if (transaction is! Map<String, Object?>) return null;
    final secret = callbackSecret;
    if (secret != null && json!['hash'] != callbackHash(secret, transaction)) {
      return null;
    }
    final ref = transaction['id'];
    final status = transaction['status_code'];
    if (ref is! String || ref.isEmpty || status is! String) return null;
    return CallbackEvent(
      providerRef: ref,
      status: _status(status),
      amount: parseAmount(transaction['amount']),
    );
  }

  /// base64 HMAC SHA256 of the compact JSON of [transaction].
  static String callbackHash(String secret, Map<String, Object?> transaction) =>
      base64.encode(
        Hmac(
          sha256,
          utf8.encode(secret),
        ).convert(utf8.encode(jsonEncode(transaction))).bytes,
      );

  static PaymentStatus _status(String status) => switch (status) {
    'TS' => PaymentStatus.succeeded,
    'TF' => PaymentStatus.failed,
    _ => PaymentStatus.pending, // TIP, TA and anything unknown
  };
}

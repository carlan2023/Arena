import 'dart:convert';

import 'package:http/http.dart' as http;

import 'payment.dart';
import 'provider_http.dart';

/// MTN MoMo Collections API, requesttopay. The payment id is both the
/// X-Reference-Id and the externalId, so callbacks and status checks lead
/// back to it. MTN callbacks are not signed; the service confirms every one
/// with checkStatus.
class MtnMomoProvider implements PaymentProvider {
  final String subscriptionKey;
  final String apiUser;
  final String apiKey;

  /// "sandbox" or the production environment name MTN assigns, for example
  /// "mtnuganda".
  final String targetEnvironment;
  final String callbackUrl;
  final String baseUrl;

  /// The sandbox only accepts EUR; production Uganda uses UGX.
  final String currency;
  final http.Client _http;
  final DateTime Function() _clock;

  CachedToken? _token;
  Future<CachedToken>? _tokenInFlight;

  MtnMomoProvider({
    required this.subscriptionKey,
    required this.apiUser,
    required this.apiKey,
    required this.targetEnvironment,
    required this.callbackUrl,
    this.baseUrl = 'https://sandbox.momodeveloper.mtn.com',
    this.currency = 'EUR',
    http.Client? httpClient,
    DateTime Function()? clock,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now;

  @override
  String get name => 'mtn';

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
    final basic = base64.encode(utf8.encode('$apiUser:$apiKey'));
    final response = await sendToProvider(
      name,
      () => _http.post(
        _uri('/collection/token/'),
        headers: {
          'Authorization': 'Basic $basic',
          'Ocp-Apim-Subscription-Key': subscriptionKey,
        },
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
    final expiresIn = parseAmount(json!['expires_in']) ?? 3600;
    // Renew a minute early.
    return CachedToken(value, _clock().add(Duration(seconds: expiresIn - 60)));
  }

  Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await _accessToken()}',
    'X-Target-Environment': targetEnvironment,
    'Ocp-Apim-Subscription-Key': subscriptionKey,
  };

  @override
  Future<ProviderAck> requestDeposit(DepositRequest request) async {
    final headers = {
      ...await _headers(),
      'X-Reference-Id': request.paymentId,
      'Content-Type': 'application/json',
      if (callbackUrl.isNotEmpty) 'X-Callback-Url': callbackUrl,
    };
    final body = jsonEncode({
      'amount': '${request.amount}',
      'currency': currency,
      'externalId': request.paymentId,
      'payer': {'partyIdType': 'MSISDN', 'partyId': request.msisdn},
      'payerMessage': 'Arena deposit',
      'payeeNote': 'Arena deposit',
    });
    final response = await sendToProvider(
      name,
      () => _http.post(
        _uri('/collection/v1_0/requesttopay'),
        headers: headers,
        body: body,
      ),
    );
    // 409 means this reference was already accepted, for example on a retry.
    if (response.statusCode != 202 && response.statusCode != 409) {
      throwForStatus(name, 'requesttopay', response);
    }
    return ProviderAck(request.paymentId);
  }

  @override
  Future<ProviderStatus> checkStatus(String providerRef) async {
    final response = await sendToProvider(
      name,
      () async => _http.get(
        _uri('/collection/v1_0/requesttopay/$providerRef'),
        headers: await _headers(),
      ),
    );
    if (response.statusCode != 200) {
      throw ProviderUnavailableException(
        '$name status: HTTP ${response.statusCode} ${response.body}',
      );
    }
    final json = jsonObject(response.body);
    final status = json?['status'];
    if (status is! String) {
      throw ProviderUnavailableException('$name status: unreadable answer');
    }
    return ProviderStatus(
      providerRef: providerRef,
      status: _status(status),
      reason: _reason(json!['reason']),
      amount: parseAmount(json['amount']),
    );
  }

  @override
  CallbackEvent? parseCallback(Map<String, String> headers, String body) {
    final json = jsonObject(body);
    if (json == null) return null;
    final ref = json['externalId'] ?? json['referenceId'];
    final status = json['status'];
    if (ref is! String || ref.isEmpty || status is! String) return null;
    return CallbackEvent(
      providerRef: ref,
      status: _status(status),
      amount: parseAmount(json['amount']),
    );
  }

  static PaymentStatus _status(String status) => switch (status.toUpperCase()) {
    'SUCCESSFUL' => PaymentStatus.succeeded,
    'FAILED' || 'REJECTED' || 'TIMEOUT' || 'EXPIRED' => PaymentStatus.failed,
    _ => PaymentStatus.pending,
  };

  static String? _reason(Object? reason) => switch (reason) {
    String s => s,
    {'code': final Object code} => '$code',
    {'message': final Object message} => '$message',
    _ => null,
  };
}

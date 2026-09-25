import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'payment.dart';

const providerTimeout = Duration(seconds: 30);

/// Runs one provider request. Network errors and timeouts become
/// ProviderUnavailableException.
Future<http.Response> sendToProvider(
  String provider,
  Future<http.Response> Function() request,
) async {
  try {
    return await request().timeout(providerTimeout);
  } on TimeoutException {
    throw ProviderUnavailableException('$provider: timed out');
  } on http.ClientException catch (e) {
    throw ProviderUnavailableException('$provider: ${e.message}');
  }
}

/// 4xx is a definite rejection, anything else outside 2xx is unknown.
Never throwForStatus(String provider, String what, http.Response response) {
  final message =
      '$provider $what: HTTP ${response.statusCode} ${response.body}';
  if (response.statusCode >= 400 && response.statusCode < 500) {
    throw ProviderRejectedException(message);
  }
  throw ProviderUnavailableException(message);
}

/// The decoded JSON object, or null.
Map<String, Object?>? jsonObject(String body) {
  try {
    final value = jsonDecode(body);
    return value is Map<String, Object?> ? value : null;
  } on FormatException {
    return null;
  }
}

/// Reads an amount given as a number or a numeric string. Null if absent or
/// not a whole number.
int? parseAmount(Object? value) {
  if (value is int) return value;
  if (value is double && value == value.roundToDouble()) return value.toInt();
  if (value is String) {
    final n = num.tryParse(value.trim());
    if (n != null && n == n.roundToDouble()) return n.toInt();
  }
  return null;
}

/// A cached OAuth style bearer token.
class CachedToken {
  final String value;
  final DateTime expiresAt;

  const CachedToken(this.value, this.expiresAt);

  bool validAt(DateTime now) => now.isBefore(expiresAt);
}

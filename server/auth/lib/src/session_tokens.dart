import 'dart:convert';

import 'package:crypto/crypto.dart';

/// HMAC SHA256 signed session tokens: base64url(payload).base64url(sig),
/// payload {"uid", "exp"} with exp in epoch seconds, no base64 padding.
class SessionTokens {
  final Hmac _hmac;
  final Duration ttl;
  final DateTime Function() _clock;

  SessionTokens({
    required List<int> secret,
    this.ttl = const Duration(days: 30),
    DateTime Function()? clock,
  }) : _hmac = Hmac(sha256, _checkSecret(secret)),
       _clock = clock ?? DateTime.now;

  static List<int> _checkSecret(List<int> secret) {
    if (secret.length < 32) {
      throw ArgumentError.value(
        '${secret.length} bytes',
        'secret',
        'must be at least 32 bytes',
      );
    }
    return List.unmodifiable(secret);
  }

  String issue(String userId) {
    final exp = _clock().add(ttl).millisecondsSinceEpoch ~/ 1000;
    final payload = _encode(
      utf8.encode(jsonEncode({'uid': userId, 'exp': exp})),
    );
    return '$payload.${_encode(_hmac.convert(utf8.encode(payload)).bytes)}';
  }

  /// The user id, or null if the token is bad or expired.
  String? verify(String token) {
    final dot = token.indexOf('.');
    if (dot <= 0 || dot != token.lastIndexOf('.')) return null;
    final payload = token.substring(0, dot);
    final List<int> signature;
    try {
      signature = _decode(token.substring(dot + 1));
    } on FormatException {
      return null;
    }
    final expected = _hmac.convert(utf8.encode(payload)).bytes;
    if (!_constantTimeEquals(expected, signature)) return null;

    try {
      final claims = jsonDecode(utf8.decode(_decode(payload)));
      if (claims is! Map) return null;
      final uid = claims['uid'];
      final exp = claims['exp'];
      if (uid is! String || uid.isEmpty || exp is! int) return null;
      if (exp <= _clock().millisecondsSinceEpoch ~/ 1000) return null;
      return uid;
    } on FormatException {
      return null;
    }
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decode(String text) {
    if (text.contains('=')) throw const FormatException('padding');
    return base64Url.decode(base64Url.normalize(text));
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

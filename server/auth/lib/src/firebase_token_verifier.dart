import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import 'identity.dart';

/// Verifies Firebase ID tokens: RS256 JWTs signed with one of Google's
/// securetoken keys, published as x509 certificates.
class FirebaseTokenVerifier implements TokenVerifier {
  static const certsUrl =
      'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
  static const clockSkew = Duration(seconds: 60);

  /// Unknown key ids trigger a refetch at most this often.
  static const _minRefetchGap = Duration(seconds: 60);

  final String projectId;
  final http.Client _http;
  final DateTime Function() _clock;
  final Uri _certsUri;

  Map<String, RSAPublicKey> _keys = const {};
  DateTime _keysExpireAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _lastFetch;
  Future<void>? _inFlight;

  FirebaseTokenVerifier({
    required this.projectId,
    http.Client? httpClient,
    DateTime Function()? clock,
    String certsUrl = FirebaseTokenVerifier.certsUrl,
  }) : _http = httpClient ?? http.Client(),
       _clock = clock ?? DateTime.now,
       _certsUri = Uri.parse(certsUrl);

  @override
  Future<VerifiedIdentity> verify(String idToken) async {
    final parts = idToken.split('.');
    if (parts.length != 3) throw const AuthException('Malformed token');

    final header = _decodeJson(parts[0]);
    final claims = _decodeJson(parts[1]);
    final signature = _decodeBytes(parts[2]);

    if (header['alg'] != 'RS256') {
      throw const AuthException('Token must be signed with RS256');
    }
    final kid = header['kid'];
    if (kid is! String || kid.isEmpty) {
      throw const AuthException('Token has no key id');
    }

    _checkClaims(claims);

    final key = await _keyFor(kid);
    if (key == null) throw const AuthException('Unknown signing key');
    final signed = Uint8List.fromList(utf8.encode('${parts[0]}.${parts[1]}'));
    if (!verifyRs256(key, signed, signature)) {
      throw const AuthException('Bad signature');
    }

    final phone = claims['phone_number'];
    return VerifiedIdentity(
      uid: claims['sub'] as String,
      phoneNumber: phone is String && phone.isNotEmpty ? phone : null,
    );
  }

  void _checkClaims(Map<String, Object?> claims) {
    final nowSeconds = _clock().millisecondsSinceEpoch ~/ 1000;
    final skew = clockSkew.inSeconds;

    if (claims['aud'] != projectId) {
      throw const AuthException('Wrong audience');
    }
    if (claims['iss'] != 'https://securetoken.google.com/$projectId') {
      throw const AuthException('Wrong issuer');
    }
    final sub = claims['sub'];
    if (sub is! String || sub.isEmpty || sub.length > 128) {
      throw const AuthException('Bad subject');
    }
    final exp = claims['exp'];
    if (exp is! num || exp + skew <= nowSeconds) {
      throw const AuthException('Token expired');
    }
    final iat = claims['iat'];
    if (iat is! num || iat - skew > nowSeconds) {
      throw const AuthException('Token issued in the future');
    }
    final authTime = claims['auth_time'];
    if (authTime is! num || authTime - skew > nowSeconds) {
      throw const AuthException('Bad auth_time');
    }
  }

  Future<RSAPublicKey?> _keyFor(String kid) async {
    final now = _clock();
    if (!now.isBefore(_keysExpireAt)) {
      await _refresh();
    } else if (!_keys.containsKey(kid) &&
        (_lastFetch == null || now.difference(_lastFetch!) >= _minRefetchGap)) {
      await _refresh();
    }
    return _keys[kid];
  }

  Future<void> _refresh() {
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    final http.Response response;
    try {
      response = await _http.get(_certsUri);
    } catch (e) {
      throw AuthException('Could not fetch signing keys: $e');
    }
    if (response.statusCode != 200) {
      throw AuthException(
        'Could not fetch signing keys: HTTP ${response.statusCode}',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map) throw const AuthException('Bad signing key document');
    final keys = <String, RSAPublicKey>{};
    body.forEach((kid, pem) {
      if (kid is String && pem is String) {
        keys[kid] = publicKeyFromCertificatePem(pem);
      }
    });
    final now = _clock();
    _keys = keys;
    _lastFetch = now;
    _keysExpireAt = now.add(
      Duration(seconds: _maxAge(response.headers['cache-control'])),
    );
  }

  static int _maxAge(String? cacheControl) {
    if (cacheControl == null) return 0;
    final match = RegExp(r'max-age=(\d+)').firstMatch(cacheControl);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  static Map<String, Object?> _decodeJson(String part) {
    try {
      final value = jsonDecode(utf8.decode(_decodeBytes(part)));
      if (value is Map<String, Object?>) return value;
    } on FormatException {
      // fall through
    }
    throw const AuthException('Malformed token');
  }

  static Uint8List _decodeBytes(String part) {
    try {
      return base64Url.decode(base64Url.normalize(part));
    } on FormatException {
      throw const AuthException('Malformed token');
    }
  }
}

/// RSASSA-PKCS1-v1_5 with SHA-256.
bool verifyRs256(RSAPublicKey key, Uint8List message, Uint8List signature) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(false, PublicKeyParameter<RSAPublicKey>(key));
  try {
    return signer.verifySignature(message, RSASignature(signature));
  } catch (_) {
    return false;
  }
}

const _rsaEncryptionOid = '1.2.840.113549.1.1.1';

/// Reads the RSA public key out of a PEM encoded x509 certificate.
RSAPublicKey publicKeyFromCertificatePem(String pem) {
  final base64Body = pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  try {
    final der = base64.decode(base64Body);
    final certificate = ASN1Parser(der).nextObject() as ASN1Sequence;
    final tbs = certificate.elements.first as ASN1Sequence;
    for (final element in tbs.elements) {
      final key = _rsaKeyFromSpki(element);
      if (key != null) return key;
    }
  } catch (e) {
    throw AuthException('Bad certificate: $e');
  }
  throw const AuthException('Certificate has no RSA key');
}

/// SubjectPublicKeyInfo ::= SEQUENCE { algorithm SEQUENCE { oid, params },
/// subjectPublicKey BIT STRING (RSAPublicKey SEQUENCE { n, e }) }
RSAPublicKey? _rsaKeyFromSpki(ASN1Object element) {
  if (element is! ASN1Sequence || element.elements.length != 2) return null;
  final algorithm = element.elements[0];
  final bits = element.elements[1];
  if (algorithm is! ASN1Sequence || bits is! ASN1BitString) return null;
  if (algorithm.elements.isEmpty) return null;
  final oid = algorithm.elements.first;
  if (oid is! ASN1ObjectIdentifier || oid.identifier != _rsaEncryptionOid) {
    return null;
  }
  final rsa =
      ASN1Parser(Uint8List.fromList(bits.stringValue)).nextObject()
          as ASN1Sequence;
  final n = (rsa.elements[0] as ASN1Integer).valueAsBigInteger;
  final e = (rsa.elements[1] as ASN1Integer).valueAsBigInteger;
  return RSAPublicKey(n, e);
}

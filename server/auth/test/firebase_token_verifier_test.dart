import 'dart:convert';

import 'package:arena_auth/arena_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

import 'support/rsa.dart';

const projectId = 'arena-test';

void main() {
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> keys;
  late AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> otherKeys;
  late Map<String, String> certs;
  late int fetches;
  late int maxAge;
  late int status;
  late DateTime now;
  late FirebaseTokenVerifier verifier;

  int seconds(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  String encode(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

  String token({
    Map<String, Object?> header = const {},
    Map<String, Object?> claims = const {},
    RSAPrivateKey? signWith,
  }) {
    final h = encode({'alg': 'RS256', 'kid': 'k1', 'typ': 'JWT', ...header});
    final c = encode(
      {
        'iss': 'https://securetoken.google.com/$projectId',
        'aud': projectId,
        'sub': 'firebase-uid-1',
        'iat': seconds(now) - 10,
        'auth_time': seconds(now) - 10,
        'exp': seconds(now) + 3600,
        'phone_number': '+256772123456',
        ...claims,
      }..removeWhere((_, v) => v == null),
    );
    final sig = signRs256(signWith ?? keys.privateKey, utf8.encode('$h.$c'));
    return '$h.$c.${base64Url.encode(sig).replaceAll('=', '')}';
  }

  setUpAll(() {
    keys = generateRsaKeyPair();
    otherKeys = generateRsaKeyPair();
  });

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 12);
    certs = {'k1': certificatePem(keys.publicKey)};
    fetches = 0;
    maxAge = 3600;
    status = 200;
    final client = MockClient((request) async {
      expect(request.url.toString(), FirebaseTokenVerifier.certsUrl);
      fetches++;
      return http.Response(
        jsonEncode(certs),
        status,
        headers: {'cache-control': 'public, max-age=$maxAge, must-revalidate'},
      );
    });
    verifier = FirebaseTokenVerifier(
      projectId: projectId,
      httpClient: client,
      clock: () => now,
    );
  });

  Future<void> rejects(String idToken) =>
      expectLater(verifier.verify(idToken), throwsA(isA<AuthException>()));

  test('reads the key out of a certificate', () {
    final key = publicKeyFromCertificatePem(certificatePem(keys.publicKey));
    expect(key.modulus, keys.publicKey.modulus);
    expect(key.exponent, keys.publicKey.exponent);
  });

  test('accepts a valid token', () async {
    final identity = await verifier.verify(token());
    expect(identity.uid, 'firebase-uid-1');
    expect(identity.phoneNumber, '+256772123456');
  });

  test('phone number is optional', () async {
    final identity = await verifier.verify(
      token(claims: {'phone_number': null}),
    );
    expect(identity.phoneNumber, isNull);
  });

  test('rejects a token signed by another key', () async {
    await rejects(token(signWith: otherKeys.privateKey));
  });

  test('rejects algorithms other than RS256', () async {
    await rejects(token(header: {'alg': 'HS256'}));
    await rejects(token(header: {'alg': 'none'}));
  });

  test('rejects an unknown or missing key id', () async {
    await rejects(token(header: {'kid': 'nope'}));
    await rejects(token(header: {'kid': null}));
  });

  test('rejects wrong audience, issuer or subject', () async {
    await rejects(token(claims: {'aud': 'other'}));
    await rejects(
      token(claims: {'iss': 'https://securetoken.google.com/other'}),
    );
    await rejects(token(claims: {'sub': ''}));
    await rejects(token(claims: {'sub': null}));
  });

  test('allows 60 seconds of skew on exp and iat', () async {
    await verifier.verify(token(claims: {'exp': seconds(now) - 59}));
    await rejects(token(claims: {'exp': seconds(now) - 60}));
    await verifier.verify(
      token(claims: {'iat': seconds(now) + 60, 'auth_time': seconds(now)}),
    );
    await rejects(token(claims: {'iat': seconds(now) + 61}));
  });

  test('rejects auth_time in the future or missing', () async {
    await rejects(token(claims: {'auth_time': seconds(now) + 61}));
    await rejects(token(claims: {'auth_time': null}));
  });

  test('rejects malformed tokens', () async {
    for (final bad in ['', 'a.b', 'a.b.c', '!.!.!', '${token()}.x']) {
      await rejects(bad);
    }
  });

  test('caches keys for max-age', () async {
    await verifier.verify(token());
    await verifier.verify(token());
    expect(fetches, 1);
    now = now.add(const Duration(seconds: 3599));
    await verifier.verify(token());
    expect(fetches, 1);
    now = now.add(const Duration(seconds: 1));
    await verifier.verify(token());
    expect(fetches, 2);
  });

  test('concurrent first calls share one fetch', () async {
    await Future.wait([for (var i = 0; i < 5; i++) verifier.verify(token())]);
    expect(fetches, 1);
  });

  test('refetches for a new key id, at most once a minute', () async {
    await verifier.verify(token());
    certs = {...certs, 'k2': certificatePem(otherKeys.publicKey)};
    final rotated = token(
      header: {'kid': 'k2'},
      signWith: otherKeys.privateKey,
    );
    // The first fetch was just now, so an unknown kid does not refetch yet.
    await rejects(rotated);
    expect(fetches, 1);
    now = now.add(const Duration(seconds: 60));
    expect((await verifier.verify(rotated)).uid, 'firebase-uid-1');
    expect(fetches, 2);
  });

  test('a failed key fetch is an AuthException', () async {
    status = 500;
    await rejects(token());
  });
}

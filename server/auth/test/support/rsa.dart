import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRsaKeyPair() {
  final random = FortunaRandom()
    ..seed(
      KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        ),
      ),
    );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        random,
      ),
    );
  return generator.generateKeyPair();
}

Uint8List signRs256(RSAPrivateKey key, List<int> message) {
  final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(key));
  return signer.generateSignature(Uint8List.fromList(message)).bytes;
}

/// A minimal x509 certificate PEM holding [key]. Only the structure matters to
/// the verifier; the certificate's own signature is not checked.
String certificatePem(RSAPublicKey key) {
  ASN1Sequence algorithm(String oid) => ASN1Sequence()
    ..add(ASN1ObjectIdentifier.fromComponentString(oid))
    ..add(ASN1Null());
  ASN1Sequence name() => ASN1Sequence()
    ..add(
      ASN1Set()..add(
        ASN1Sequence()
          ..add(ASN1ObjectIdentifier.fromComponentString('2.5.4.3'))
          ..add(ASN1UTF8String('test')),
      ),
    );

  final rsaKey = ASN1Sequence()
    ..add(ASN1Integer(key.modulus!))
    ..add(ASN1Integer(key.exponent!));
  final spki = ASN1Sequence()
    ..add(algorithm('1.2.840.113549.1.1.1'))
    ..add(ASN1BitString(rsaKey.encodedBytes));
  final version = ASN1Object.preEncoded(
    0xa0,
    ASN1Integer.fromInt(2).encodedBytes,
  );
  final tbs = ASN1Sequence()
    ..add(version)
    ..add(ASN1Integer.fromInt(1))
    ..add(algorithm('1.2.840.113549.1.1.11'))
    ..add(name())
    ..add(
      ASN1Sequence()
        ..add(ASN1UtcTime(DateTime.utc(2026)))
        ..add(ASN1UtcTime(DateTime.utc(2027))),
    )
    ..add(name())
    ..add(spki);
  final certificate = ASN1Sequence()
    ..add(tbs)
    ..add(algorithm('1.2.840.113549.1.1.11'))
    ..add(ASN1BitString([0, 1, 2, 3]));
  final body = base64.encode(certificate.encodedBytes);
  final lines = [
    for (var i = 0; i < body.length; i += 64)
      body.substring(i, min(i + 64, body.length)),
  ];
  return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
}

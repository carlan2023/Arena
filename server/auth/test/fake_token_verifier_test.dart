import 'package:arena_auth/arena_auth.dart';
import 'package:test/test.dart';

void main() {
  final verifier = FakeTokenVerifier();

  test('accepts fake:<phone>', () async {
    final identity = await verifier.verify('fake:+256772123456');
    expect(identity.uid, 'fake-256772123456');
    expect(identity.phoneNumber, '+256772123456');
  });

  test('rejects anything else', () async {
    for (final bad in [
      '',
      'fake:',
      'fake:256772123456',
      'fake:+12345678',
      'fake:+1234567890123456',
      'fake:+2567721234a6',
      'real:+256772123456',
      'fake:+256772123456 ',
    ]) {
      await expectLater(
        verifier.verify(bad),
        throwsA(isA<AuthException>()),
        reason: bad,
      );
    }
  });
}

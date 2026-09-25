import 'identity.dart';

/// Accepts `fake:<phone>` where phone is + and 9 to 15 digits. The uid is
/// `fake-<phone digits>`. Only for AUTH_PROVIDER=fake.
class FakeTokenVerifier implements TokenVerifier {
  static final _pattern = RegExp(r'^fake:(\+(\d{9,15}))$');

  @override
  Future<VerifiedIdentity> verify(String idToken) async {
    final match = _pattern.firstMatch(idToken);
    if (match == null) {
      throw const AuthException('Not a fake token');
    }
    return VerifiedIdentity(
      uid: 'fake-${match.group(2)}',
      phoneNumber: match.group(1),
    );
  }
}

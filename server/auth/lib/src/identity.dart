/// Who a verified identity token belongs to.
class VerifiedIdentity {
  final String uid;
  final String? phoneNumber;

  const VerifiedIdentity({required this.uid, this.phoneNumber});

  @override
  String toString() => 'VerifiedIdentity($uid, $phoneNumber)';
}

class AuthException implements Exception {
  final String message;

  const AuthException(this.message);

  @override
  String toString() => 'AuthException: $message';
}

abstract interface class TokenVerifier {
  /// Verifies an identity token from the phone. Throws AuthException if
  /// invalid or expired.
  Future<VerifiedIdentity> verify(String idToken);
}

import 'identity.dart';
import 'session_tokens.dart';
import 'user.dart';

/// Glue used by the server's /v1/auth/login route and bearer token check.
class AuthService {
  final TokenVerifier verifier;
  final UserStore users;
  final SessionTokens sessions;

  AuthService({
    required this.verifier,
    required this.users,
    required this.sessions,
  });

  /// Throws AuthException when the identity token is not accepted.
  Future<(String sessionToken, User user)> login(String idToken) async {
    final identity = await verifier.verify(idToken);
    final user = await users.upsertByIdentity(identity);
    return (sessions.issue(user.id), user);
  }

  /// Starts a guest account: no phone, a default name, free play only.
  /// Paid play and the wallet need a phone login (D33).
  Future<(String sessionToken, User user)> guest() async {
    final user = await users.upsertByIdentity(
      VerifiedIdentity(uid: 'guest-${newUserId()}'),
    );
    return (sessions.issue(user.id), user);
  }

  /// The user behind a session token, or null.
  Future<User?> authenticate(String sessionToken) async {
    final userId = sessions.verify(sessionToken);
    if (userId == null) return null;
    return users.byId(userId);
  }
}

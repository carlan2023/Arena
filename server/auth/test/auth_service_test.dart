import 'package:arena_auth/arena_auth.dart';
import 'package:test/test.dart';

void main() {
  late AuthService auth;

  setUp(() {
    auth = AuthService(
      verifier: FakeTokenVerifier(),
      users: InMemoryUserStore(),
      sessions: SessionTokens(secret: List<int>.generate(32, (i) => i * 3)),
    );
  });

  test('login creates the user and a session that authenticates', () async {
    final (token, user) = await auth.login('fake:+256772123456');
    expect(user.phone, '+256772123456');
    expect((await auth.authenticate(token))?.id, user.id);

    final (_, again) = await auth.login('fake:+256772123456');
    expect(again.id, user.id);
  });

  test('login refuses a bad identity token', () async {
    await expectLater(auth.login('nope'), throwsA(isA<AuthException>()));
  });

  test('authenticate returns null for a bad session token', () async {
    expect(await auth.authenticate('nope'), isNull);
  });

  test('authenticate returns null for a token of an unknown user', () async {
    final sessions = SessionTokens(
      secret: List<int>.generate(32, (i) => i * 3),
    );
    expect(await auth.authenticate(sessions.issue('ghost')), isNull);
  });
}

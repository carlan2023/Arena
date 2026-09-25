import 'dart:convert';

import 'package:arena_auth/arena_auth.dart';
import 'package:test/test.dart';

void main() {
  final secret = List<int>.generate(32, (i) => i);
  var now = DateTime.utc(2026, 9, 25, 12);
  SessionTokens tokens({List<int>? key}) =>
      SessionTokens(secret: key ?? secret, clock: () => now);

  setUp(() => now = DateTime.utc(2026, 9, 25, 12));

  test('issues a token that verifies to the user id', () {
    final t = tokens();
    final token = t.issue('user-1');
    expect(t.verify(token), 'user-1');
    expect(token, isNot(contains('=')));
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[0]))),
    );
    expect(payload, {
      'uid': 'user-1',
      'exp': now.add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
    });
  });

  test('rejects an expired token', () {
    final t = tokens();
    final token = t.issue('user-1');
    now = now.add(const Duration(days: 30));
    expect(t.verify(token), isNull);
  });

  test('rejects a tampered payload or signature', () {
    final t = tokens();
    final token = t.issue('user-1');
    final parts = token.split('.');
    final forged = base64Url
        .encode(utf8.encode(jsonEncode({'uid': 'user-2', 'exp': 9999999999})))
        .replaceAll('=', '');
    expect(t.verify('$forged.${parts[1]}'), isNull);
    final sig = parts[1];
    final flipped =
        sig.substring(0, sig.length - 2) +
        (sig[sig.length - 2] == 'A' ? 'B' : 'A') +
        sig[sig.length - 1];
    expect(t.verify('${parts[0]}.$flipped'), isNull);
  });

  test('rejects a token signed with another secret', () {
    final other = tokens(key: List<int>.filled(32, 7));
    expect(tokens().verify(other.issue('user-1')), isNull);
  });

  test('rejects garbage', () {
    final t = tokens();
    for (final bad in ['', '.', 'abc', 'a.b.c', '!!!.???', 'e30.']) {
      expect(t.verify(bad), isNull, reason: bad);
    }
  });

  test('needs a secret of at least 32 bytes', () {
    expect(
      () => SessionTokens(secret: List<int>.filled(31, 1)),
      throwsArgumentError,
    );
  });
}

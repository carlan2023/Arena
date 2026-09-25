import 'package:arena_auth/arena_auth.dart';
import 'package:test/test.dart';

import 'support/postgres.dart';

void main() {
  group('InMemoryUserStore', () {
    userStoreTests(() async => (InMemoryUserStore(), () async {}));
  });

  group('PostgresUserStore', skip: skipWithoutDatabase, () {
    userStoreTests(() async {
      final db = await TestDatabase.open(migrations);
      return (PostgresUserStore(db.pool), db.close);
    });

    test('concurrent first logins create one user', () async {
      final db = await TestDatabase.open(migrations);
      addTearDown(db.close);
      final store = PostgresUserStore(db.pool);
      const identity = VerifiedIdentity(uid: 'u', phoneNumber: '+256700000001');
      final users = await Future.wait([
        for (var i = 0; i < 8; i++) store.upsertByIdentity(identity),
      ]);
      expect(users.map((u) => u.id).toSet(), hasLength(1));
    });
  });

  test('defaultDisplayName', () {
    expect(
      defaultDisplayName(
        const VerifiedIdentity(uid: 'x', phoneNumber: '+256772123456'),
      ),
      'Player 3456',
    );
    expect(
      defaultDisplayName(const VerifiedIdentity(uid: 'abcdefXYZ9')),
      'Player XYZ9',
    );
    expect(defaultDisplayName(const VerifiedIdentity(uid: 'ab')), 'Player ab');
  });

  test('newUserId is a UUID v4', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    for (var i = 0; i < 50; i++) {
      expect(newUserId(), matches(pattern));
    }
  });
}

void userStoreTests(
  Future<(UserStore, Future<void> Function())> Function() create,
) {
  late UserStore store;

  setUp(() async {
    final (s, close) = await create();
    store = s;
    addTearDown(close);
  });

  test('creates a user on first login with a default name', () async {
    final user = await store.upsertByIdentity(
      const VerifiedIdentity(
        uid: 'fake-256772123456',
        phoneNumber: '+256772123456',
      ),
    );
    expect(user.phone, '+256772123456');
    expect(user.displayName, 'Player 3456');
    expect(user.createdAt.isUtc, isTrue);
    expect(await store.byId(user.id), user);
  });

  test('the same phone is the same user, even with another uid', () async {
    final a = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'uid-a', phoneNumber: '+256772123456'),
    );
    final b = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'uid-b', phoneNumber: '+256772123456'),
    );
    expect(b.id, a.id);
    final c = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'uid-a', phoneNumber: '+256772000000'),
    );
    expect(c.id, isNot(a.id));
  });

  test('without a phone the uid is the key', () async {
    final a = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'no-phone-uid-1'),
    );
    expect(a.phone, '');
    expect(a.displayName, 'Player id-1');
    final again = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'no-phone-uid-1'),
    );
    expect(again.id, a.id);
    final other = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'no-phone-uid-2'),
    );
    expect(other.id, isNot(a.id));
  });

  test('byId returns null for an unknown id', () async {
    expect(await store.byId('nobody'), isNull);
  });

  test('setDisplayName trims and saves', () async {
    final user = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'u', phoneNumber: '+256772123456'),
    );
    final renamed = await store.setDisplayName(user.id, '  Nakato  ');
    expect(renamed.displayName, 'Nakato');
    expect((await store.byId(user.id))!.displayName, 'Nakato');
    final long = await store.setDisplayName(user.id, 'é' * 24);
    expect(long.displayName, 'é' * 24);
  });

  test('setDisplayName checks the length and the user', () async {
    final user = await store.upsertByIdentity(
      const VerifiedIdentity(uid: 'u', phoneNumber: '+256772123456'),
    );
    for (final bad in ['', '   ', 'a' * 25, 'bad\nname']) {
      await expectLater(
        store.setDisplayName(user.id, bad),
        throwsArgumentError,
        reason: bad,
      );
    }
    await expectLater(store.setDisplayName('nobody', 'Name'), throwsStateError);
  });
}

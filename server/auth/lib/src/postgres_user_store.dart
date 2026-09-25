import 'package:postgres/postgres.dart';

import 'identity.dart';
import 'user.dart';

/// Users in the `users` table (migration auth_001_users).
class PostgresUserStore implements UserStore {
  final Pool _pool;

  PostgresUserStore(Pool pool) : _pool = pool;

  static const _columns = 'id, phone, display_name, created_at';

  @override
  Future<User> upsertByIdentity(VerifiedIdentity identity) async {
    final phone = identity.phoneNumber ?? '';
    // The DO UPDATE is there so RETURNING gives back the existing row.
    final conflict = phone.isNotEmpty
        ? "ON CONFLICT (phone) WHERE phone <> '' "
              'DO UPDATE SET firebase_uid = EXCLUDED.firebase_uid'
        : "ON CONFLICT (firebase_uid) WHERE phone = '' "
              'DO UPDATE SET phone = users.phone';
    final result = await _pool.execute(
      Sql.named(
        'INSERT INTO users (id, phone, firebase_uid, display_name) '
        'VALUES (@id, @phone, @uid, @name) $conflict RETURNING $_columns',
      ),
      parameters: {
        'id': newUserId(),
        'phone': phone,
        'uid': identity.uid,
        'name': defaultDisplayName(identity),
      },
    );
    return _user(result.first);
  }

  @override
  Future<User?> byId(String id) async {
    final result = await _pool.execute(
      Sql.named('SELECT $_columns FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    return result.isEmpty ? null : _user(result.first);
  }

  @override
  Future<User> setDisplayName(String id, String displayName) async {
    final name = normalizeDisplayName(displayName);
    final result = await _pool.execute(
      Sql.named(
        'UPDATE users SET display_name = @name WHERE id = @id '
        'RETURNING $_columns',
      ),
      parameters: {'id': id, 'name': name},
    );
    if (result.isEmpty) throw StateError('Unknown user $id');
    return _user(result.first);
  }

  static User _user(ResultRow row) => User(
    id: row[0] as String,
    phone: row[1] as String,
    displayName: row[2] as String,
    createdAt: (row[3] as DateTime).toUtc(),
  );
}

import 'dart:io';
import 'dart:math';

import 'package:arena_auth/arena_auth.dart';
import 'package:postgres/postgres.dart';

/// The DATABASE_URL, or null when Postgres tests should be skipped.
String? get databaseUrl {
  final url = Platform.environment['DATABASE_URL'];
  return url == null || url.isEmpty ? null : url;
}

/// A skip reason for Postgres tests, or null when they can run.
Object get skipWithoutDatabase =>
    databaseUrl == null ? 'DATABASE_URL is not set' : false;

/// A pool bound to a fresh schema of its own, with [migrations] applied.
class TestDatabase {
  final Pool pool;
  final String schema;
  final Endpoint _endpoint;
  final Connection? _admin;

  TestDatabase._(this.pool, this.schema, this._endpoint, this._admin);

  static Pool _pool(Endpoint endpoint, String schema) => Pool.withEndpoints(
    [endpoint],
    settings: PoolSettings(
      maxConnectionCount: 8,
      sslMode: SslMode.disable,
      onOpen: (c) => c.execute('SET search_path TO $schema'),
    ),
  );

  /// A second pool on the same schema. Closing it leaves the schema.
  static Future<TestDatabase> reuse(TestDatabase db) async => TestDatabase._(
    _pool(db._endpoint, db.schema),
    db.schema,
    db._endpoint,
    null,
  );

  static Future<TestDatabase> open(List<Migration> migrations) async {
    final uri = Uri.parse(databaseUrl!);
    final userInfo = uri.userInfo.split(':');
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.first,
      username: Uri.decodeComponent(userInfo.first),
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
    );
    final schema =
        'test_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 30)}';
    const ssl = ConnectionSettings(sslMode: SslMode.disable);
    final admin = await Connection.open(endpoint, settings: ssl);
    await admin.execute('CREATE SCHEMA $schema');
    await admin.execute('SET search_path TO $schema');
    for (final migration in migrations) {
      await admin.runTx((tx) async {
        await tx.execute(migration.sql, queryMode: QueryMode.simple);
      });
    }
    return TestDatabase._(_pool(endpoint, schema), schema, endpoint, admin);
  }

  Future<void> close() async {
    await pool.close();
    final admin = _admin;
    if (admin == null) return;
    await admin.execute('DROP SCHEMA $schema CASCADE');
    await admin.close();
  }
}

import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';

/// The DATABASE_URL, or null when Postgres tests should be skipped.
String? get databaseUrl {
  final url = Platform.environment['DATABASE_URL'];
  return url == null || url.isEmpty ? null : url;
}

Object get skipWithoutDatabase =>
    databaseUrl == null ? 'DATABASE_URL is not set' : false;

/// A pool bound to a fresh schema of its own, dropped on [close], so tests do
/// not collide with other packages on a shared database.
class TestSchema {
  TestSchema._(this.pool, this.name, this._admin);

  final Pool pool;
  final String name;
  final Connection _admin;

  static Future<TestSchema> open() async {
    final uri = Uri.parse(databaseUrl!);
    final userInfo = uri.userInfo.split(':');
    final endpoint = Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.first,
      username: Uri.decodeComponent(userInfo.first),
      password: userInfo.length > 1 ? Uri.decodeComponent(userInfo[1]) : null,
    );
    final name =
        'srv_test_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 30)}';
    final admin = await Connection.open(
      endpoint,
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    await admin.execute('CREATE SCHEMA $name');
    final pool = Pool.withEndpoints(
      [endpoint],
      settings: PoolSettings(
        maxConnectionCount: 4,
        sslMode: SslMode.disable,
        onOpen: (c) => c.execute('SET search_path TO $name'),
      ),
    );
    return TestSchema._(pool, name, admin);
  }

  Future<void> close() async {
    await pool.close();
    await _admin.execute('DROP SCHEMA $name CASCADE');
    await _admin.close();
  }
}

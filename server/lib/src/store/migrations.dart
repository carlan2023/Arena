import 'package:arena_auth/arena_auth.dart' show Migration;
import 'package:postgres/postgres.dart';

/// The game server's own schema: rooms, matches, players and the move log.
const List<Migration> serverMigrations = [
  Migration(
    id: 'server_001_match_log',
    sql: '''
CREATE TABLE rooms (
  id uuid PRIMARY KEY,
  code text NOT NULL,
  mode text NOT NULL,
  seats int NOT NULL,
  stake bigint NOT NULL DEFAULT 0,
  rules jsonb NOT NULL,
  owner_user_id text NOT NULL,
  status text NOT NULL DEFAULT 'waiting',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX rooms_code_idx ON rooms (code);

CREATE TABLE matches (
  id uuid PRIMARY KEY,
  room_id uuid NOT NULL REFERENCES rooms (id),
  mode text NOT NULL,
  rules jsonb NOT NULL,
  stake bigint NOT NULL DEFAULT 0,
  rake bigint NOT NULL DEFAULT 0,
  server_seed text,
  server_seed_hash text NOT NULL,
  client_seed text NOT NULL,
  status text NOT NULL CHECK (status IN ('playing', 'finished', 'abandoned')),
  started_at timestamptz NOT NULL,
  ended_at timestamptz
);
CREATE INDEX matches_room_idx ON matches (room_id);

CREATE TABLE match_players (
  match_id uuid NOT NULL REFERENCES matches (id),
  seat int NOT NULL,
  user_id text NOT NULL,
  color text NOT NULL,
  is_bot boolean NOT NULL DEFAULT false,
  forfeited boolean NOT NULL DEFAULT false,
  finish_place int,
  PRIMARY KEY (match_id, seat)
);
CREATE INDEX match_players_user_idx ON match_players (user_id);

CREATE TABLE moves (
  match_id uuid NOT NULL REFERENCES matches (id),
  idx int NOT NULL,
  kind text NOT NULL,
  seat int NOT NULL,
  color text NOT NULL,
  data jsonb NOT NULL,
  auto boolean NOT NULL DEFAULT false,
  at timestamptz NOT NULL,
  PRIMARY KEY (match_id, idx)
);
''',
  ),
];

/// Any fixed number; identifies the migration advisory lock.
const int _migrationLockKey = 7231948;

/// Applies every migration not yet in `schema_migrations`, in list order, each
/// in its own transaction, under a Postgres advisory lock so two servers
/// starting at once cannot race. Returns the ids applied.
Future<List<String>> runMigrations(
  Pool pool,
  List<Migration> migrations,
) async {
  final ids = migrations.map((m) => m.id).toList();
  if (ids.toSet().length != ids.length) {
    throw ArgumentError('duplicate migration ids');
  }
  return pool.withConnection((conn) async {
    await conn.execute(
      Sql.named('SELECT pg_advisory_lock(@k)'),
      parameters: {'k': _migrationLockKey},
    );
    try {
      await conn.execute('''
CREATE TABLE IF NOT EXISTS schema_migrations (
  id text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
)''');
      final done = {
        for (final row in await conn.execute(
          'SELECT id FROM schema_migrations',
        ))
          row[0] as String,
      };
      final applied = <String>[];
      for (final m in migrations) {
        if (done.contains(m.id)) continue;
        await conn.runTx((tx) async {
          await tx.execute(m.sql, queryMode: QueryMode.simple);
          await tx.execute(
            Sql.named('INSERT INTO schema_migrations (id) VALUES (@id)'),
            parameters: {'id': m.id},
          );
        });
        applied.add(m.id);
      }
      return applied;
    } finally {
      await conn.execute(
        Sql.named('SELECT pg_advisory_unlock(@k)'),
        parameters: {'k': _migrationLockKey},
      );
    }
  });
}

/// Opens a pool from a postgres:// URL. Without an sslmode parameter the
/// connection is unencrypted, which suits a local or docker database; managed
/// databases should set `?sslmode=require`.
Pool openPool(String databaseUrl) {
  final uri = Uri.parse(databaseUrl);
  final url = uri.queryParameters.containsKey('sslmode')
      ? databaseUrl
      : uri
            .replace(
              queryParameters: {...uri.queryParameters, 'sslmode': 'disable'},
            )
            .toString();
  return Pool.withUrl(url);
}

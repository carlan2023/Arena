import 'migration.dart';

/// Schema for arena_auth, applied before arena_wallet's.
const List<Migration> migrations = [
  Migration(
    id: 'auth_001_users',
    sql: '''
CREATE TABLE users (
  id text PRIMARY KEY,
  phone text NOT NULL,
  firebase_uid text NOT NULL,
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_phone_key ON users (phone) WHERE phone <> '';
CREATE UNIQUE INDEX users_uid_without_phone_key ON users (firebase_uid) WHERE phone = '';
CREATE INDEX users_firebase_uid_idx ON users (firebase_uid);
''',
  ),
];

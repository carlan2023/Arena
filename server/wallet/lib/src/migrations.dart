import 'package:arena_auth/arena_auth.dart' show Migration;

/// Schema for arena_wallet, applied after arena_auth's.
const List<Migration> migrations = [
  Migration(
    id: 'wallet_001_ledger',
    sql: '''
CREATE TABLE ledger_accounts (
  id bigserial PRIMARY KEY,
  kind text NOT NULL,
  ref text NOT NULL,
  currency text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (kind, ref, currency)
);
CREATE TABLE ledger_transactions (
  id text PRIMARY KEY,
  idempotency_key text NOT NULL UNIQUE,
  kind text NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ledger_entries (
  id bigserial PRIMARY KEY,
  tx_id text NOT NULL REFERENCES ledger_transactions (id),
  account_id bigint NOT NULL REFERENCES ledger_accounts (id),
  amount bigint NOT NULL CHECK (amount <> 0),
  balance_after bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ledger_entries_account_idx ON ledger_entries (account_id, id);
CREATE INDEX ledger_entries_tx_idx ON ledger_entries (tx_id);
''',
  ),
  Migration(
    id: 'wallet_002_payments',
    sql: '''
CREATE TABLE payments (
  id text PRIMARY KEY,
  user_id text NOT NULL,
  provider text NOT NULL,
  provider_ref text,
  amount bigint NOT NULL CHECK (amount > 0),
  msisdn text NOT NULL,
  status text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  settled_at timestamptz,
  UNIQUE (provider, provider_ref)
);
CREATE INDEX payments_user_idx ON payments (user_id, created_at);
CREATE INDEX payments_pending_idx ON payments (created_at) WHERE status = 'pending';
''',
  ),
];

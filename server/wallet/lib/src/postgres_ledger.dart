import 'package:postgres/postgres.dart';

import 'ids.dart';
import 'ledger.dart';

/// The ledger in `ledger_accounts`, `ledger_transactions` and
/// `ledger_entries` (migration wallet_001_ledger).
///
/// A post inserts its transaction row first, so a second post with the same
/// key waits for the first and then sees it. It then locks every account it
/// touches with FOR UPDATE in sorted key order, which serialises posts per
/// account without deadlocks, and computes balances from the entries.
class PostgresLedger implements Ledger {
  final Pool _pool;

  PostgresLedger(Pool pool) : _pool = pool;

  static const _uniqueViolation = '23505';

  @override
  Future<PostResult> post(LedgerTransaction tx) async {
    tx.validate();
    final existing = await _txIdFor(_pool, tx.idempotencyKey);
    if (existing != null) return PostResult(txId: existing, duplicate: true);
    try {
      return await _pool.runTx((s) => _post(s, tx));
    } on ServerException catch (e) {
      if (e.code != _uniqueViolation) rethrow;
      final txId = await _txIdFor(_pool, tx.idempotencyKey);
      if (txId == null) rethrow;
      return PostResult(txId: txId, duplicate: true);
    }
  }

  Future<PostResult> _post(TxSession s, LedgerTransaction tx) async {
    final txId = newUuidV4();
    final inserted = await s.execute(
      Sql.named(
        'INSERT INTO ledger_transactions (id, idempotency_key, kind, metadata) '
        'VALUES (@id, @key, @kind, @meta) '
        'ON CONFLICT (idempotency_key) DO NOTHING RETURNING id',
      ),
      parameters: {
        'id': txId,
        'key': tx.idempotencyKey,
        'kind': tx.kind,
        'meta': TypedValue(Type.jsonb, tx.metadata),
      },
    );
    if (inserted.isEmpty) {
      // Another post with this key committed while we waited.
      return PostResult(
        txId: (await _txIdFor(s, tx.idempotencyKey))!,
        duplicate: true,
      );
    }

    final net = tx.netChanges();
    final accounts = net.keys.toList()..sort();
    final ids = <AccountId, int>{};
    final balances = <AccountId, int>{};
    for (final account in accounts) {
      final id = ids[account] = await _lockAccount(s, account);
      balances[account] = await _balanceById(s, id);
    }
    for (final account in accounts) {
      final balance = balances[account]!;
      final change = net[account]!;
      if (account.kind.mustStayNonNegative && balance + change < 0) {
        // Throwing rolls back the transaction row too.
        throw InsufficientFundsException(
          account: account,
          balance: balance,
          needed: -change,
        );
      }
    }

    Future<void> add(AccountId account, int amount) async {
      final after = balances[account] = balances[account]! + amount;
      await s.execute(
        Sql.named(
          'INSERT INTO ledger_entries (tx_id, account_id, amount, balance_after) '
          'VALUES (@tx, @account, @amount, @after)',
        ),
        parameters: {
          'tx': txId,
          'account': ids[account],
          'amount': amount,
          'after': after,
        },
      );
    }

    for (final t in tx.transfers) {
      await add(t.from, -t.amount);
      await add(t.to, t.amount);
    }
    return PostResult(txId: txId, duplicate: false);
  }

  static Future<String?> _txIdFor(Session s, String key) async {
    final result = await s.execute(
      Sql.named(
        'SELECT id FROM ledger_transactions WHERE idempotency_key = @key',
      ),
      parameters: {'key': key},
    );
    return result.isEmpty ? null : result.first[0] as String;
  }

  static Map<String, Object> _accountParams(AccountId a) => {
    'kind': a.kind.name,
    'ref': a.ref,
    'currency': a.currency.name,
  };

  static Future<int> _lockAccount(Session s, AccountId account) async {
    await s.execute(
      Sql.named(
        'INSERT INTO ledger_accounts (kind, ref, currency) '
        'VALUES (@kind, @ref, @currency) ON CONFLICT DO NOTHING',
      ),
      parameters: _accountParams(account),
    );
    final result = await s.execute(
      Sql.named(
        'SELECT id FROM ledger_accounts '
        'WHERE kind = @kind AND ref = @ref AND currency = @currency FOR UPDATE',
      ),
      parameters: _accountParams(account),
    );
    return result.first[0] as int;
  }

  static Future<int> _balanceById(Session s, int accountId) async {
    final result = await s.execute(
      Sql.named(
        'SELECT COALESCE(SUM(amount), 0)::bigint FROM ledger_entries '
        'WHERE account_id = @id',
      ),
      parameters: {'id': accountId},
    );
    return result.first[0] as int;
  }

  @override
  Future<int> balance(AccountId account) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT COALESCE(SUM(e.amount), 0)::bigint FROM ledger_entries e '
        'JOIN ledger_accounts a ON a.id = e.account_id '
        'WHERE a.kind = @kind AND a.ref = @ref AND a.currency = @currency',
      ),
      parameters: _accountParams(account),
    );
    return result.first[0] as int;
  }

  @override
  Future<List<LedgerEntry>> history(AccountId account, {int limit = 50}) async {
    final result = await _pool.execute(
      Sql.named(
        'SELECT e.tx_id, e.amount, e.balance_after, t.kind, e.created_at '
        'FROM ledger_entries e '
        'JOIN ledger_accounts a ON a.id = e.account_id '
        'JOIN ledger_transactions t ON t.id = e.tx_id '
        'WHERE a.kind = @kind AND a.ref = @ref AND a.currency = @currency '
        'ORDER BY e.id DESC LIMIT @limit',
      ),
      parameters: {..._accountParams(account), 'limit': limit},
    );
    return [
      for (final row in result)
        LedgerEntry(
          txId: row[0] as String,
          account: account,
          amount: row[1] as int,
          balanceAfter: row[2] as int,
          kind: row[3] as String,
          at: (row[4] as DateTime).toUtc(),
        ),
    ];
  }

  @override
  Future<bool> verifyIntegrity() async {
    final unbalanced = await _pool.execute(
      'SELECT 1 FROM ledger_entries e '
      'JOIN ledger_accounts a ON a.id = e.account_id '
      'GROUP BY e.tx_id, a.currency HAVING SUM(e.amount) <> 0 LIMIT 1',
    );
    if (unbalanced.isNotEmpty) return false;

    final badRunning = await _pool.execute(
      'SELECT 1 FROM (SELECT balance_after, '
      'SUM(amount) OVER (PARTITION BY account_id ORDER BY id) AS running '
      'FROM ledger_entries) x WHERE balance_after <> running LIMIT 1',
    );
    if (badRunning.isNotEmpty) return false;

    final negative = await _pool.execute(
      Sql.named(
        'SELECT 1 FROM ledger_entries e '
        'JOIN ledger_accounts a ON a.id = e.account_id '
        'WHERE a.kind IN (@wallet, @pot) '
        'GROUP BY e.account_id HAVING SUM(e.amount) < 0 LIMIT 1',
      ),
      parameters: {
        'wallet': AccountKind.wallet.name,
        'pot': AccountKind.pot.name,
      },
    );
    return negative.isEmpty;
  }
}

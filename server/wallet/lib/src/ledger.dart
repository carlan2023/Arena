import 'ids.dart';

enum Currency { ugx, coin }

enum AccountKind {
  wallet,
  pot,
  revenue,
  providerClearing,
  taxWithheld,
  taxPayable;

  /// Wallet and pot balances may never go below zero.
  bool get mustStayNonNegative => this == wallet || this == pot;
}

/// wallet: ref = userId. pot: ref = matchId. revenue and tax accounts:
/// ref = "house". providerClearing: ref = provider name, for example "mtn".
class AccountId implements Comparable<AccountId> {
  final AccountKind kind;
  final String ref;
  final Currency currency;

  const AccountId(this.kind, this.ref, this.currency);

  const AccountId.wallet(String userId, [Currency currency = Currency.ugx])
    : this(AccountKind.wallet, userId, currency);
  const AccountId.pot(String matchId, [Currency currency = Currency.ugx])
    : this(AccountKind.pot, matchId, currency);
  const AccountId.revenue([Currency currency = Currency.ugx])
    : this(AccountKind.revenue, 'house', currency);
  const AccountId.providerClearing(String provider)
    : this(AccountKind.providerClearing, provider, Currency.ugx);
  const AccountId.taxWithheld()
    : this(AccountKind.taxWithheld, 'house', Currency.ugx);
  const AccountId.taxPayable()
    : this(AccountKind.taxPayable, 'house', Currency.ugx);

  /// For example `wallet:<userId>:ugx`.
  String get key => '${kind.name}:$ref:${currency.name}';

  @override
  int compareTo(AccountId other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) =>
      other is AccountId &&
      other.kind == kind &&
      other.ref == ref &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(kind, ref, currency);

  @override
  String toString() => key;
}

/// One movement of money: debit [from], credit [to]. Recorded as a balanced
/// pair of entries: -amount on from, +amount on to.
class Transfer {
  final AccountId from;
  final AccountId to;
  final int amount;

  const Transfer({required this.from, required this.to, required this.amount});

  @override
  String toString() => 'Transfer($from -> $to, $amount)';
}

class LedgerTransaction {
  /// Unique. Posting the same key again is a no-op that returns the first
  /// result.
  final String idempotencyKey;

  /// deposit, stake, payout, rake, tax, refund, coin_grant ...
  final String kind;

  /// At least one.
  final List<Transfer> transfers;
  final Map<String, Object?> metadata;

  const LedgerTransaction({
    required this.idempotencyKey,
    required this.kind,
    required this.transfers,
    this.metadata = const {},
  });

  /// Throws ArgumentError for a transaction that can never be posted.
  void validate() {
    if (idempotencyKey.isEmpty) {
      throw ArgumentError.value(idempotencyKey, 'idempotencyKey', 'is empty');
    }
    if (kind.isEmpty) throw ArgumentError.value(kind, 'kind', 'is empty');
    if (transfers.isEmpty) {
      throw ArgumentError.value(transfers, 'transfers', 'is empty');
    }
    for (final t in transfers) {
      if (t.amount <= 0) {
        throw ArgumentError.value(t, 'transfers', 'amount must be above 0');
      }
      if (t.from == t.to) {
        throw ArgumentError.value(t, 'transfers', 'from equals to');
      }
      if (t.from.currency != t.to.currency) {
        throw ArgumentError.value(t, 'transfers', 'currencies differ');
      }
    }
  }

  /// The net change per account.
  Map<AccountId, int> netChanges() {
    final net = <AccountId, int>{};
    for (final t in transfers) {
      net[t.from] = (net[t.from] ?? 0) - t.amount;
      net[t.to] = (net[t.to] ?? 0) + t.amount;
    }
    return net;
  }
}

class LedgerEntry {
  final String txId;
  final AccountId account;
  final int amount;
  final int balanceAfter;
  final String kind;
  final DateTime at;

  const LedgerEntry({
    required this.txId,
    required this.account,
    required this.amount,
    required this.balanceAfter,
    required this.kind,
    required this.at,
  });

  @override
  String toString() =>
      'LedgerEntry($txId, $account, $amount, after $balanceAfter, $kind)';
}

class PostResult {
  final String txId;
  final bool duplicate;

  const PostResult({required this.txId, required this.duplicate});

  @override
  String toString() => 'PostResult($txId, duplicate: $duplicate)';
}

class InsufficientFundsException implements Exception {
  final AccountId account;
  final int balance;

  /// What the transaction takes out of [account] in total.
  final int needed;

  const InsufficientFundsException({
    required this.account,
    required this.balance,
    required this.needed,
  });

  @override
  String toString() =>
      'InsufficientFundsException: $account has $balance, needs $needed';
}

abstract interface class Ledger {
  /// Atomic. All transfers or none. Throws InsufficientFundsException if any
  /// wallet or pot account would go below zero, and ArgumentError for an
  /// invalid transaction. Other accounts may go negative.
  Future<PostResult> post(LedgerTransaction tx);

  /// Sum of entries.
  Future<int> balance(AccountId account);

  /// Newest first.
  Future<List<LedgerEntry>> history(AccountId account, {int limit = 50});

  /// Every transaction sums to zero per currency, every balanceAfter matches
  /// the running sum, and no wallet or pot balance is negative.
  Future<bool> verifyIntegrity();
}

class InMemoryLedger implements Ledger {
  final DateTime Function() _clock;
  final _entries = <LedgerEntry>[];
  final _txIdByKey = <String, String>{};

  InMemoryLedger({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  // No awaits inside, so each post runs to completion before the next.
  @override
  Future<PostResult> post(LedgerTransaction tx) async {
    tx.validate();
    final existing = _txIdByKey[tx.idempotencyKey];
    if (existing != null) return PostResult(txId: existing, duplicate: true);

    final balances = <AccountId, int>{};
    int balanceOf(AccountId a) => balances[a] ??= _balance(a);
    tx.netChanges().forEach((account, change) {
      final balance = balanceOf(account);
      if (account.kind.mustStayNonNegative && balance + change < 0) {
        throw InsufficientFundsException(
          account: account,
          balance: balance,
          needed: -change,
        );
      }
    });

    final txId = newUuidV4();
    final at = _clock().toUtc();
    void add(AccountId account, int amount) {
      final after = balances[account] = balanceOf(account) + amount;
      _entries.add(
        LedgerEntry(
          txId: txId,
          account: account,
          amount: amount,
          balanceAfter: after,
          kind: tx.kind,
          at: at,
        ),
      );
    }

    for (final t in tx.transfers) {
      add(t.from, -t.amount);
      add(t.to, t.amount);
    }
    _txIdByKey[tx.idempotencyKey] = txId;
    return PostResult(txId: txId, duplicate: false);
  }

  int _balance(AccountId account) => _entries
      .where((e) => e.account == account)
      .fold(0, (sum, e) => sum + e.amount);

  @override
  Future<int> balance(AccountId account) async => _balance(account);

  @override
  Future<List<LedgerEntry>> history(
    AccountId account, {
    int limit = 50,
  }) async =>
      _entries.reversed.where((e) => e.account == account).take(limit).toList();

  @override
  Future<bool> verifyIntegrity() async {
    final perTx = <(String, Currency), int>{};
    final running = <AccountId, int>{};
    for (final e in _entries) {
      final k = (e.txId, e.account.currency);
      perTx[k] = (perTx[k] ?? 0) + e.amount;
      final after = running[e.account] = (running[e.account] ?? 0) + e.amount;
      if (after != e.balanceAfter) return false;
    }
    if (perTx.values.any((sum) => sum != 0)) return false;
    return !running.entries.any(
      (e) => e.key.kind.mustStayNonNegative && e.value < 0,
    );
  }
}

# Contract: wallet, payments and login interfaces

Status: frozen on 25 Sep 2026 for M2. Owner: Wallet. Changes go through the supervisor and are logged in docs/decisions.md.

Two Dart packages, both owned by Wallet, both used by the server package:

| Folder | Pub name | Holds |
|---|---|---|
| server/auth | `arena_auth` | Token verifier, session tokens, user store |
| server/wallet | `arena_wallet` | Ledger, payment providers, payments service |

Each package has an in memory implementation of every store for tests and local runs, and a Postgres implementation. Postgres tests run only when `DATABASE_URL` is set and are skipped otherwise, so `dart test` passes with no database. Outside services have a fake implementation. No key, password or token is ever in the repo; everything is read from the environment by the server's config and passed in through constructors.

Money is always an `int` in the smallest unit. UGX has no minor unit, so 5,000 UGX is `5000`. Coins use the same ledger with currency `COIN`. No doubles anywhere near money.

## Migrations

Each package exports `const List<Migration> migrations` where `class Migration { final String id; final String sql; }`. ids are prefixed by package, for example `auth_001_users`, `wallet_001_ledger`. The server applies every package's list in order (auth, wallet, server) inside a transaction per migration and records ids in a `schema_migrations` table. The `Migration` class lives in arena_auth and arena_wallet re-exports it, so there is one type.

## arena_auth

```dart
class VerifiedIdentity { final String uid; final String? phoneNumber; }
class AuthException implements Exception { final String message; }

abstract interface class TokenVerifier {
  /// Verifies an identity token from the phone. Throws AuthException if invalid or expired.
  Future<VerifiedIdentity> verify(String idToken);
}

/// Firebase ID tokens: RS256 JWT, kid looked up in Google's securetoken x509 certs
/// (cached per Cache-Control max-age), aud == projectId,
/// iss == https://securetoken.google.com/<projectId>, exp in the future, iat in the past,
/// sub non empty. phone_number claim becomes phoneNumber.
class FirebaseTokenVerifier implements TokenVerifier {
  FirebaseTokenVerifier({required String projectId, http.Client? httpClient, DateTime Function()? clock});
}

/// Accepts "fake:<phone>" where phone is + and 9 to 15 digits. uid is "fake-<phone digits>".
/// Used when AUTH_PROVIDER=fake. The app's fake login sends this after the code 123456.
class FakeTokenVerifier implements TokenVerifier {}

/// HMAC SHA256 signed session tokens: base64url(payload).base64url(sig), payload {"uid","exp"}.
class SessionTokens {
  SessionTokens({required List<int> secret, Duration ttl = const Duration(days: 30), DateTime Function()? clock});
  String issue(String userId);
  String? verify(String token); // userId, or null if bad or expired
}

class User { final String id; final String phone; final String displayName; final DateTime createdAt; }

abstract interface class UserStore {
  /// Creates the user on first login, keyed by phone (or uid when no phone). Returns the user.
  Future<User> upsertByIdentity(VerifiedIdentity identity);
  Future<User?> byId(String id);
  Future<User> setDisplayName(String id, String displayName); // 1 to 24 characters, trimmed
}
class InMemoryUserStore implements UserStore {}
class PostgresUserStore implements UserStore { PostgresUserStore(Pool pool); }

/// Glue used by the server's /v1/auth/login route.
class AuthService {
  AuthService({required TokenVerifier verifier, required UserStore users, required SessionTokens sessions});
  Future<(String sessionToken, User user)> login(String idToken);
  Future<User?> authenticate(String sessionToken);
}
```

Default display name for a new user: "Player " plus the last 4 digits of the phone.

## arena_wallet: ledger (M2.9)

```dart
enum Currency { ugx, coin }
enum AccountKind { wallet, pot, revenue, providerClearing, taxWithheld, taxPayable }

class AccountId {
  final AccountKind kind; final String ref; final Currency currency;
  // wallet: ref = userId. pot: ref = matchId. revenue and tax accounts: ref = "house".
  // providerClearing: ref = provider name, for example "mtn".
  String get key; // "wallet:<ref>:ugx"
}

/// One movement of money: debit `from`, credit `to`. Always recorded as a balanced pair
/// of entries: -amount on from, +amount on to. amount > 0. Both accounts share a currency.
class Transfer { final AccountId from; final AccountId to; final int amount; }

class LedgerTransaction {
  final String idempotencyKey;          // unique. Posting the same key again is a no-op that returns the first result
  final String kind;                    // deposit, stake, payout, rake, tax, refund, coin_grant ...
  final List<Transfer> transfers;       // at least one
  final Map<String, Object?> metadata;
}

class LedgerEntry { final String txId; final AccountId account; final int amount; final int balanceAfter; final String kind; final DateTime at; }
class PostResult { final String txId; final bool duplicate; }

class InsufficientFundsException implements Exception { final AccountId account; final int balance; final int needed; }

abstract interface class Ledger {
  /// Atomic. All transfers or none. Throws InsufficientFundsException if any wallet or pot
  /// account would go below zero. providerClearing and revenue style accounts may go negative
  /// as needed (providerClearing is money owed by the provider).
  Future<PostResult> post(LedgerTransaction tx);
  Future<int> balance(AccountId account);                 // sum of entries, nothing cached that can disagree
  Future<List<LedgerEntry>> history(AccountId account, {int limit = 50}); // newest first
  Future<bool> verifyIntegrity();                         // every tx sums to zero per currency
}
class InMemoryLedger implements Ledger {}
class PostgresLedger implements Ledger { PostgresLedger(Pool pool); } // SELECT ... FOR UPDATE on the account rows it debits
```

Tables: `ledger_accounts(id, kind, ref, currency, created_at, unique(kind, ref, currency))`, `ledger_transactions(id, idempotency_key unique, kind, metadata jsonb, created_at)`, `ledger_entries(id, tx_id, account_id, amount bigint, created_at)`. Balances come from entries alone.

Settlement helpers for M3.9, written now so the tests pin the README section 10 example:

```dart
class PayoutSettings { final int rakeBasisPoints; final int rakeTaxBasisPoints; final int winningsWithholdingBasisPoints; }
// defaults 1200, 3000, 1500
class Payout { final int pot, rake, grossToWinner, netGain, withheld, toWinner, rakeTax, houseKeeps; }
Payout computePayout({required int stakePerPlayer, required int players, required PayoutSettings settings});
```

`computePayout(stakePerPlayer: 5000, players: 2, settings: defaults)` must give pot 10000, rake 1200, grossToWinner 8800, netGain 3800, withheld 570, toWinner 8230, rakeTax 360, houseKeeps 840. Rounding: every percentage is floored to whole UGX.

## arena_wallet: payments (M2.10, M2.11)

```dart
enum PaymentStatus { pending, succeeded, failed }

class DepositRequest { final String paymentId; final int amount; final String msisdn; final String currency; }
class ProviderAck { final String providerRef; }            // provider's id for the request
class ProviderStatus { final String providerRef; final PaymentStatus status; final String? reason; }
class CallbackEvent { final String providerRef; final PaymentStatus status; final int? amount; }

abstract interface class PaymentProvider {
  String get name;                                           // fake, mtn, airtel
  Future<ProviderAck> requestDeposit(DepositRequest request);
  Future<ProviderStatus> checkStatus(String providerRef);
  /// Parses and checks a callback. Returns null for a body it cannot trust or read.
  CallbackEvent? parseCallback(Map<String, String> headers, String body);
}

class FakePaymentProvider implements PaymentProvider {}      // records requests, confirms when told to
class MtnMomoProvider implements PaymentProvider {           // Collections API, requesttopay
  MtnMomoProvider({required String subscriptionKey, required String apiUser, required String apiKey,
      required String targetEnvironment, required String callbackUrl, String baseUrl = 'https://sandbox.momodeveloper.mtn.com',
      http.Client? httpClient});
}
class AirtelMoneyProvider implements PaymentProvider {        // Collections, /merchant/v1/payments/
  AirtelMoneyProvider({required String clientId, required String clientSecret, required String callbackUrl,
      String baseUrl = 'https://openapiuat.airtel.africa', String country = 'UG', String currency = 'UGX', http.Client? httpClient});
}

class Payment { final String id; final String userId; final String provider; final String? providerRef;
  final int amount; final String msisdn; final PaymentStatus status; final DateTime createdAt; final DateTime? settledAt; }

abstract interface class PaymentStore {                       // InMemoryPaymentStore, PostgresPaymentStore
  Future<Payment> create(Payment payment);
  Future<Payment?> byId(String id);
  Future<Payment?> byProviderRef(String provider, String providerRef);
  Future<Payment> setProviderRef(String id, String providerRef);
  /// Moves pending to succeeded or failed. Returns null if the payment was not pending
  /// (compare and set), which is how a duplicate callback is detected.
  Future<Payment?> settle(String id, PaymentStatus status);
}

class PaymentsService {
  PaymentsService({required Map<String, PaymentProvider> providers, required PaymentStore store, required Ledger ledger});
  Future<Payment> startDeposit({required String userId, required String provider, required int amount, required String msisdn});
  /// Idempotent. A callback received twice credits once.
  Future<Payment?> handleCallback(String provider, Map<String, String> headers, String body);
  /// Asks the provider about a pending payment and settles it the same way as a callback.
  Future<Payment> refresh(String paymentId);
}
```

Crediting rule: the wallet is credited only after the provider confirms success, through a ledger transaction with idempotency key `deposit:<paymentId>` moving the amount from `providerClearing:<provider>:ugx` to `wallet:<userId>:ugx`. Duplicate protection has two layers: the store's compare and set settle, and the ledger's idempotency key. Tests must show that a duplicated callback, two callbacks racing, and a callback after a refresh all credit exactly once.

Deposit limits: amount between 500 and 5,000,000 UGX; msisdn is 256 followed by 9 digits.

## Amendments at freeze (25 Sep 2026)

These settle the review round and override anything above that disagrees.

1. Crediting order: post the ledger transaction `deposit:<paymentId>` first, then settle the payment. After any settle attempt, if the stored payment is succeeded, post the deposit transaction again; the idempotency key makes it a no-op. A crash between the two writes is repaired by the next callback or refresh.
2. Callbacks are hints. `handleCallback` finds the payment from the callback, then asks the provider with `checkStatus` and settles on that answer. Only the fake provider's callback is trusted as is. AirtelMoneyProvider takes an optional `String? callbackSecret` and checks the hash when set.
3. `paymentId` is a UUID v4 and is the provider reference for every provider: MTN X-Reference-Id and externalId, Airtel transaction.id, fake ref. The service looks payments up by paymentId first. providerRef stays in the store.
4. MtnMomoProvider takes `String currency = 'EUR'` because the sandbox only accepts EUR. The ledger still records UGX. Airtel strips the 256 prefix from the msisdn; the callback URL is set on the Airtel portal, so the callbackUrl parameter is documentation only. Airtel status TS is succeeded, TF failed, TIP and TA pending. Airtel production payload encryption is not in M2.
5. A failed requestDeposit marks the payment failed only on a definite provider rejection (4xx). Timeouts and 5xx leave it pending for refresh.
6. If the provider confirms a different amount, nothing is credited; the payment stays pending and is logged for review. The ledger only ever credits the stored amount.
7. FakePaymentProvider: `void complete(String providerRef, {PaymentStatus status = PaymentStatus.succeeded, int? amount})` sets what checkStatus returns; `String callbackBody(String providerRef)` builds a matching callback.
8. `class PaymentException implements Exception { final String code; final String message; }` for bad amount, bad msisdn, unknown provider (400 bad_request) and unreadable callbacks (`bad_callback`, 400). handleCallback returns null for an unknown payment (200).
9. Ledger: `ledger_entries.balance_after bigint`, written while the account row is locked; balances are still sum(amount). Missing accounts are created with INSERT ON CONFLICT DO NOTHING, then locked FOR UPDATE in sorted key order. A duplicate key race catches Postgres 23505 and returns the first txId with duplicate true. A post refused for insufficient funds records nothing. The no negative check is on each wallet and pot balance after all transfers. Transfers with from equal to or a different currency than to are refused. History is newest first, entry id as tiebreaker. verifyIntegrity also checks no wallet or pot balance is negative. Coin grants come from `revenue:house:coin`, which may go negative.
10. Firebase: header alg must be RS256, certs from https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com, auth_time in the past, 60 seconds of clock skew on iat and exp. PEM parsing with asn1lib and pointycastle.
11. Session tokens: exp in epoch seconds, base64url without padding, constant time signature compare, secret of at least 32 bytes or ArgumentError.
12. Users: columns include firebase_uid and a unique phone in E.164 (+256...). With no phone, phone is empty and the default name is "Player " plus the last 4 characters of the uid. setDisplayName throws ArgumentError when the trimmed name is not 1 to 24 characters (400) and StateError for an unknown id (404).
13. Settlement (M3): withheld tax moves to taxWithheld, and rake tax moves from revenue to taxPayable.
14. Postgres tests use their own schema per test file, or run with --concurrency=1, so CI's shared database does not collide.

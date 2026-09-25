import 'package:postgres/postgres.dart';

import 'payment.dart';

/// Payments in the `payments` table (migration wallet_002_payments).
class PostgresPaymentStore implements PaymentStore {
  final Pool _pool;

  PostgresPaymentStore(Pool pool) : _pool = pool;

  static const _columns =
      'id, user_id, provider, provider_ref, amount, msisdn, status, '
      'created_at, settled_at';

  @override
  Future<Payment> create(Payment payment) async {
    final result = await _pool.execute(
      Sql.named(
        'INSERT INTO payments (id, user_id, provider, provider_ref, amount, '
        'msisdn, status, created_at, settled_at) VALUES (@id, @user, '
        '@provider, @ref, @amount, @msisdn, @status, @created, @settled) '
        'RETURNING $_columns',
      ),
      parameters: {
        'id': payment.id,
        'user': payment.userId,
        'provider': payment.provider,
        'ref': TypedValue(Type.text, payment.providerRef),
        'amount': payment.amount,
        'msisdn': payment.msisdn,
        'status': payment.status.name,
        'created': TypedValue(Type.timestampTz, payment.createdAt),
        'settled': TypedValue(Type.timestampTz, payment.settledAt),
      },
    );
    return _payment(result.first);
  }

  @override
  Future<Payment?> byId(String id) =>
      _one('SELECT $_columns FROM payments WHERE id = @id', {'id': id});

  @override
  Future<Payment?> byProviderRef(String provider, String providerRef) => _one(
    'SELECT $_columns FROM payments '
    'WHERE provider = @provider AND provider_ref = @ref',
    {'provider': provider, 'ref': providerRef},
  );

  @override
  Future<Payment> setProviderRef(String id, String providerRef) async {
    final payment = await _one(
      'UPDATE payments SET provider_ref = @ref WHERE id = @id '
      'RETURNING $_columns',
      {'id': id, 'ref': providerRef},
    );
    if (payment == null) throw StateError('Unknown payment $id');
    return payment;
  }

  @override
  Future<Payment?> settle(String id, PaymentStatus status) {
    if (status == PaymentStatus.pending) {
      throw ArgumentError.value(status, 'status', 'must be final');
    }
    return _one(
      'UPDATE payments SET status = @status, settled_at = now() '
      "WHERE id = @id AND status = 'pending' RETURNING $_columns",
      {'id': id, 'status': status.name},
    );
  }

  Future<Payment?> _one(String sql, Map<String, Object?> parameters) async {
    final result = await _pool.execute(Sql.named(sql), parameters: parameters);
    return result.isEmpty ? null : _payment(result.first);
  }

  static Payment _payment(ResultRow row) => Payment(
    id: row[0] as String,
    userId: row[1] as String,
    provider: row[2] as String,
    providerRef: row[3] as String?,
    amount: row[4] as int,
    msisdn: row[5] as String,
    status: PaymentStatus.values.byName(row[6] as String),
    createdAt: (row[7] as DateTime).toUtc(),
    settledAt: (row[8] as DateTime?)?.toUtc(),
  );
}

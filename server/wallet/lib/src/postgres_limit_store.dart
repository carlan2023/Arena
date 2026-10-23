import 'package:postgres/postgres.dart';

import 'limits.dart';

/// Deposit limits in `player_limits` (migration wallet_003_limits).
class PostgresLimitStore implements LimitStore {
  PostgresLimitStore(Pool pool) : _pool = pool;

  final Pool _pool;

  static const _columns =
      'user_id, daily_limit, weekly_limit, monthly_limit, pending_daily, '
      'pending_weekly, pending_monthly, pending_at, excluded_until, permanent';

  @override
  Future<PlayerLimits?> byUser(String userId) async {
    final result = await _pool.execute(
      Sql.named('SELECT $_columns FROM player_limits WHERE user_id = @user'),
      parameters: {'user': userId},
    );
    return result.isEmpty ? null : _row(result.first);
  }

  @override
  Future<void> save(PlayerLimits limits) async {
    await _pool.execute(
      Sql.named(
        'INSERT INTO player_limits ($_columns) VALUES ('
        '@user, @daily, @weekly, @monthly, @pendDaily, @pendWeekly, '
        '@pendMonthly, @pendAt, @until, @permanent) '
        'ON CONFLICT (user_id) DO UPDATE SET '
        'daily_limit = EXCLUDED.daily_limit, '
        'weekly_limit = EXCLUDED.weekly_limit, '
        'monthly_limit = EXCLUDED.monthly_limit, '
        'pending_daily = EXCLUDED.pending_daily, '
        'pending_weekly = EXCLUDED.pending_weekly, '
        'pending_monthly = EXCLUDED.pending_monthly, '
        'pending_at = EXCLUDED.pending_at, '
        'excluded_until = EXCLUDED.excluded_until, '
        'permanent = EXCLUDED.permanent',
      ),
      parameters: {
        'user': limits.userId,
        'daily': limits.daily,
        'weekly': limits.weekly,
        'monthly': limits.monthly,
        'pendDaily': TypedValue(Type.bigInteger, limits.pendingDaily),
        'pendWeekly': TypedValue(Type.bigInteger, limits.pendingWeekly),
        'pendMonthly': TypedValue(Type.bigInteger, limits.pendingMonthly),
        'pendAt': TypedValue(Type.timestampTz, limits.pendingAt),
        'until': TypedValue(Type.timestampTz, limits.excludedUntil),
        'permanent': limits.permanent,
      },
    );
  }

  static PlayerLimits _row(ResultRow row) => PlayerLimits(
    userId: row[0] as String,
    daily: _int(row[1]),
    weekly: _int(row[2]),
    monthly: _int(row[3]),
    pendingDaily: _intOrNull(row[4]),
    pendingWeekly: _intOrNull(row[5]),
    pendingMonthly: _intOrNull(row[6]),
    pendingAt: (row[7] as DateTime?)?.toUtc(),
    excludedUntil: (row[8] as DateTime?)?.toUtc(),
    permanent: row[9] as bool,
  );

  static int _int(Object? value) {
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    throw StateError('expected an integer, got $value');
  }

  static int? _intOrNull(Object? value) => value == null ? null : _int(value);
}

import 'payment.dart';

/// House caps and the wait before a higher deposit limit applies (D54).
class LimitSettings {
  const LimitSettings({
    this.houseDailyCap = 1000000,
    this.raiseDelay = const Duration(hours: 24),
    this.minAge = 25,
  });

  /// Never above this many UGX in a Kampala day.
  final int houseDailyCap;

  /// A higher limit waits this long. A lower one applies at once.
  final Duration raiseDelay;

  /// Paid play and deposits need a date of birth at least this many years ago.
  final int minAge;

  int get houseWeeklyCap => houseDailyCap * 7;
  int get houseMonthlyCap => houseDailyCap * 30;
}

/// How long a player steps away from deposits and paid tables.
enum ExclusionPeriod { oneDay, sevenDays, thirtyDays, sixMonths, permanent }

/// `1d`, `7d`, `30d`, `6m` or `permanent`. Null when [raw] is none of those.
ExclusionPeriod? exclusionPeriodFromApi(String raw) => switch (raw) {
  '1d' => ExclusionPeriod.oneDay,
  '7d' => ExclusionPeriod.sevenDays,
  '30d' => ExclusionPeriod.thirtyDays,
  '6m' => ExclusionPeriod.sixMonths,
  'permanent' => ExclusionPeriod.permanent,
  _ => null,
};

/// The player is self excluded. [userId] is the account that was refused.
class SelfExcludedException implements Exception {
  const SelfExcludedException(this.userId);

  final String userId;

  @override
  String toString() => 'SelfExcludedException: $userId is self excluded';
}

/// A deposit would pass the player's limit for [window] (daily, weekly or
/// monthly). [used] is what already counts, before this deposit.
class LimitExceededException implements Exception {
  const LimitExceededException({
    required this.userId,
    required this.window,
    required this.limit,
    required this.used,
  });

  final String userId;
  final String window;
  final int limit;
  final int used;

  @override
  String toString() =>
      'LimitExceededException: $userId $window limit $limit used $used';
}

/// One player's deposit limits and self exclusion.
class PlayerLimits {
  const PlayerLimits({
    required this.userId,
    required this.daily,
    required this.weekly,
    required this.monthly,
    this.pendingDaily,
    this.pendingWeekly,
    this.pendingMonthly,
    this.pendingAt,
    this.excludedUntil,
    this.permanent = false,
  });

  final String userId;
  final int daily;
  final int weekly;
  final int monthly;
  final int? pendingDaily;
  final int? pendingWeekly;
  final int? pendingMonthly;

  /// When the pending raise was asked for. Null when nothing is waiting.
  final DateTime? pendingAt;
  final DateTime? excludedUntil;
  final bool permanent;

  bool get hasPending =>
      pendingDaily != null || pendingWeekly != null || pendingMonthly != null;

  /// True while exclusion is in force at [now]. A period that has ended is not.
  bool excludedAt(DateTime now) =>
      permanent || (excludedUntil != null && now.isBefore(excludedUntil!));

  @override
  bool operator ==(Object other) =>
      other is PlayerLimits &&
      other.userId == userId &&
      other.daily == daily &&
      other.weekly == weekly &&
      other.monthly == monthly &&
      other.pendingDaily == pendingDaily &&
      other.pendingWeekly == pendingWeekly &&
      other.pendingMonthly == pendingMonthly &&
      other.pendingAt == pendingAt &&
      other.excludedUntil == excludedUntil &&
      other.permanent == permanent;

  @override
  int get hashCode => Object.hash(
    userId,
    daily,
    weekly,
    monthly,
    pendingDaily,
    pendingWeekly,
    pendingMonthly,
    pendingAt,
    excludedUntil,
    permanent,
  );
}

abstract interface class LimitStore {
  /// Null when the player has never changed a limit or exclusion.
  Future<PlayerLimits?> byUser(String userId);

  Future<void> save(PlayerLimits limits);
}

class InMemoryLimitStore implements LimitStore {
  final _rows = <String, PlayerLimits>{};

  @override
  Future<PlayerLimits?> byUser(String userId) async => _rows[userId];

  @override
  Future<void> save(PlayerLimits limits) async {
    _rows[limits.userId] = limits;
  }
}

/// Kampala is UTC+3 and has no daylight saving, the same offset coin days use.
const kampalaOffset = Duration(hours: 3);

/// Midnight at the start of the Kampala day that contains [now].
DateTime kampalaDayStart(DateTime now) {
  final local = now.toUtc().add(kampalaOffset);
  return DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).subtract(kampalaOffset);
}

/// Monday 00:00 Kampala of the week that contains [now].
DateTime kampalaWeekStart(DateTime now) {
  final local = now.toUtc().add(kampalaOffset);
  final monday = DateTime.utc(
    local.year,
    local.month,
    local.day,
  ).subtract(Duration(days: local.weekday - DateTime.monday));
  return monday.subtract(kampalaOffset);
}

/// The 1st 00:00 Kampala of the month that contains [now].
DateTime kampalaMonthStart(DateTime now) {
  final local = now.toUtc().add(kampalaOffset);
  return DateTime.utc(local.year, local.month, 1).subtract(kampalaOffset);
}

/// Deposit limits and self exclusion (M3.11).
///
/// A player who has never set a limit is at the house caps. Reading applies
/// a raise whose 24 hours have passed and stores the result. Pending and
/// succeeded deposits count toward the limit. Failed ones do not. Coin
/// charges do not call this.
class LimitsService {
  LimitsService({
    required LimitStore store,
    required PaymentStore payments,
    this.settings = const LimitSettings(),
    DateTime Function()? clock,
  }) : _store = store,
       _payments = payments,
       _clock = clock ?? DateTime.now;

  final LimitStore _store;
  final PaymentStore _payments;
  final LimitSettings settings;
  final DateTime Function() _clock;

  PlayerLimits _defaults(String userId) => PlayerLimits(
    userId: userId,
    daily: settings.houseDailyCap,
    weekly: settings.houseWeeklyCap,
    monthly: settings.houseMonthlyCap,
  );

  /// The limits in force now. A due raise is saved before this returns.
  Future<PlayerLimits> limits(String userId) async {
    final stored = await _store.byUser(userId);
    final base = stored ?? _defaults(userId);
    final applied = _applyPending(base, _clock().toUtc());
    if (stored != null && applied != stored) {
      await _store.save(applied);
    }
    return applied;
  }

  /// Omitted fields stay as they are. A value above the current one waits
  /// [LimitSettings.raiseDelay]; a lower or equal value applies at once and
  /// does not restart the wait on a raise that is already pending.
  /// ArgumentError when a value is outside 1..the house cap, or when the
  /// daily, weekly and monthly targets are out of order.
  Future<PlayerLimits> setLimits(
    String userId, {
    int? daily,
    int? weekly,
    int? monthly,
  }) async {
    if (daily == null && weekly == null && monthly == null) {
      throw ArgumentError('set at least one of daily, weekly and monthly');
    }
    final current = await limits(userId);
    var nextDaily = current.daily;
    var nextWeekly = current.weekly;
    var nextMonthly = current.monthly;
    var pendDaily = current.pendingDaily;
    var pendWeekly = current.pendingWeekly;
    var pendMonthly = current.pendingMonthly;
    var raised = false;

    void apply(
      int? requested,
      int currentValue,
      int cap,
      String name,
      void Function(int value) setCurrent,
      void Function(int? value) setPending,
    ) {
      if (requested == null) return;
      if (requested < 1 || requested > cap) {
        throw ArgumentError('$name must be from 1 to $cap UGX');
      }
      if (requested <= currentValue) {
        setCurrent(requested);
        setPending(null);
      } else {
        setPending(requested);
        raised = true;
      }
    }

    apply(
      daily,
      current.daily,
      settings.houseDailyCap,
      'daily',
      (v) => nextDaily = v,
      (v) => pendDaily = v,
    );
    apply(
      weekly,
      current.weekly,
      settings.houseWeeklyCap,
      'weekly',
      (v) => nextWeekly = v,
      (v) => pendWeekly = v,
    );
    apply(
      monthly,
      current.monthly,
      settings.houseMonthlyCap,
      'monthly',
      (v) => nextMonthly = v,
      (v) => pendMonthly = v,
    );

    final targetDaily = pendDaily ?? nextDaily;
    final targetWeekly = pendWeekly ?? nextWeekly;
    final targetMonthly = pendMonthly ?? nextMonthly;
    if (targetDaily > targetWeekly || targetWeekly > targetMonthly) {
      throw ArgumentError(
        'daily cannot exceed weekly, and weekly cannot exceed monthly',
      );
    }

    final anyPending =
        pendDaily != null || pendWeekly != null || pendMonthly != null;
    final now = _clock().toUtc();
    final next = PlayerLimits(
      userId: userId,
      daily: nextDaily,
      weekly: nextWeekly,
      monthly: nextMonthly,
      pendingDaily: pendDaily,
      pendingWeekly: pendWeekly,
      pendingMonthly: pendMonthly,
      pendingAt: !anyPending
          ? null
          : raised
          ? now
          : (current.pendingAt ?? now),
      excludedUntil: current.excludedUntil,
      permanent: current.permanent,
    );
    await _store.save(next);
    return next;
  }

  /// Starts or lengthens exclusion. A shorter period while a longer one is
  /// running changes nothing, and a permanent exclusion stays permanent.
  Future<PlayerLimits> selfExclude(
    String userId,
    ExclusionPeriod period,
  ) async {
    final current = await limits(userId);
    final now = _clock().toUtc();
    if (current.permanent) return current;
    if (period == ExclusionPeriod.permanent) {
      final next = PlayerLimits(
        userId: userId,
        daily: current.daily,
        weekly: current.weekly,
        monthly: current.monthly,
        pendingDaily: current.pendingDaily,
        pendingWeekly: current.pendingWeekly,
        pendingMonthly: current.pendingMonthly,
        pendingAt: current.pendingAt,
        permanent: true,
      );
      await _store.save(next);
      return next;
    }
    final end = switch (period) {
      ExclusionPeriod.oneDay => now.add(const Duration(days: 1)),
      ExclusionPeriod.sevenDays => now.add(const Duration(days: 7)),
      ExclusionPeriod.thirtyDays => now.add(const Duration(days: 30)),
      ExclusionPeriod.sixMonths => DateTime.utc(
        now.year,
        now.month + 6,
        now.day,
        now.hour,
        now.minute,
        now.second,
        now.millisecond,
        now.microsecond,
      ),
      ExclusionPeriod.permanent => now,
    };
    if (current.excludedAt(now) && !end.isAfter(current.excludedUntil!)) {
      return current;
    }
    final next = PlayerLimits(
      userId: userId,
      daily: current.daily,
      weekly: current.weekly,
      monthly: current.monthly,
      pendingDaily: current.pendingDaily,
      pendingWeekly: current.pendingWeekly,
      pendingMonthly: current.pendingMonthly,
      pendingAt: current.pendingAt,
      excludedUntil: end,
    );
    await _store.save(next);
    return next;
  }

  /// Throws [SelfExcludedException] or [LimitExceededException]. Called before
  /// a deposit is stored, so a refusal leaves no payment row.
  Future<void> checkDeposit(String userId, int amount) async {
    final row = await limits(userId);
    final now = _clock().toUtc();
    if (row.excludedAt(now)) throw SelfExcludedException(userId);
    Future<void> window(String name, int limit, DateTime since) async {
      final used = await _payments.openDepositsSince(userId, since);
      if (used + amount > limit) {
        throw LimitExceededException(
          userId: userId,
          window: name,
          limit: limit,
          used: used,
        );
      }
    }

    await window('daily', row.daily, kampalaDayStart(now));
    await window('weekly', row.weekly, kampalaWeekStart(now));
    await window('monthly', row.monthly, kampalaMonthStart(now));
  }

  /// Throws [SelfExcludedException]. Deposit limits are not applied to a stake.
  Future<void> checkPlay(String userId) async {
    final row = await limits(userId);
    if (row.excludedAt(_clock().toUtc())) throw SelfExcludedException(userId);
  }

  PlayerLimits _applyPending(PlayerLimits row, DateTime now) {
    final at = row.pendingAt;
    if (at == null || !row.hasPending) return row;
    if (now.isBefore(at.add(settings.raiseDelay))) return row;
    return PlayerLimits(
      userId: row.userId,
      daily: row.pendingDaily ?? row.daily,
      weekly: row.pendingWeekly ?? row.weekly,
      monthly: row.pendingMonthly ?? row.monthly,
      excludedUntil: row.excludedUntil,
      permanent: row.permanent,
    );
  }
}

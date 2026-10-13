import 'ledger.dart';

/// Coin amounts (D36, D42). Coins are play money: they are granted from the
/// house coin account and can never be bought or cashed out.
class CoinSettings {
  const CoinSettings({
    this.signup = 500,
    this.dailyBase = 100,
    this.dailyStep = 20,
    this.dailyMaxDay = 7,
    this.tutorial = 50,
    this.dayOffset = const Duration(hours: 3),
  });

  /// Granted once, on an account's first login. Guests included.
  final int signup;

  /// The daily reward on the first day of a streak, and what each further
  /// day adds, up to [dailyMaxDay] (100, 120, ... 220).
  final int dailyBase;
  final int dailyStep;
  final int dailyMaxDay;

  /// For finishing all tutorial lessons, once per account.
  final int tutorial;

  /// Days run from midnight in Kampala, UTC+3, which has no daylight saving.
  final Duration dayOffset;

  /// The reward on day [streak] of a streak, counting from 1.
  int dailyAmount(int streak) =>
      dailyBase + dailyStep * (streak.clamp(1, dailyMaxDay) - 1);
}

class DailyRewardStatus {
  const DailyRewardStatus({
    required this.available,
    required this.amount,
    required this.streak,
    required this.nextAt,
  });

  /// True when today's reward has not been claimed.
  final bool available;

  /// What the next claim gives: today's if [available], else tomorrow's if the
  /// streak is kept.
  final int amount;

  /// Days in a row claimed so far, today included once claimed. 0 when the
  /// streak was broken.
  final int streak;

  /// When the next claim opens: now if [available], else the next midnight.
  final DateTime nextAt;
}

class DailyRewardGrant {
  const DailyRewardGrant({
    required this.balance,
    required this.granted,
    required this.streak,
  });
  final int balance;
  final int granted;
  final int streak;
}

class AlreadyClaimedException implements Exception {
  const AlreadyClaimedException(this.nextAt);
  final DateTime nextAt;
  @override
  String toString() => 'AlreadyClaimedException: next claim at $nextAt';
}

/// Coin grants (M3.4). Each grant is a ledger transfer from the house coin
/// account with an idempotency key, so a repeated or concurrent request
/// grants once.
class CoinService {
  CoinService({
    required this.ledger,
    this.settings = const CoinSettings(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Ledger ledger;
  final CoinSettings settings;
  final DateTime Function() _clock;

  static const _house = AccountId.revenue(Currency.coin);
  static AccountId _wallet(String userId) =>
      AccountId.wallet(userId, Currency.coin);

  /// Returns the coins granted: [CoinSettings.signup] the first time, then 0.
  Future<int> grantSignup(String userId) =>
      _grant(userId, 'coins:signup:$userId', 'coin_signup', settings.signup);

  /// Returns the coins granted: [CoinSettings.tutorial] the first time, then
  /// 0.
  Future<int> grantTutorial(String userId) => _grant(
    userId,
    'coins:tutorial:$userId',
    'coin_tutorial',
    settings.tutorial,
  );

  Future<int> balance(String userId) => ledger.balance(_wallet(userId));

  Future<DailyRewardStatus> dailyStatus(String userId) async {
    final today = _day(_clock());
    final claimed = await _streakOn(userId, today);
    if (claimed != null) {
      return DailyRewardStatus(
        available: false,
        amount: settings.dailyAmount(claimed + 1),
        streak: claimed,
        nextAt: _startOf(today.add(const Duration(days: 1))),
      );
    }
    final yesterday = await _streakOn(
      userId,
      today.subtract(const Duration(days: 1)),
    );
    return DailyRewardStatus(
      available: true,
      amount: settings.dailyAmount((yesterday ?? 0) + 1),
      streak: yesterday ?? 0,
      nextAt: _clock().toUtc(),
    );
  }

  /// Throws [AlreadyClaimedException] when today's reward was claimed.
  Future<DailyRewardGrant> claimDaily(String userId) async {
    final today = _day(_clock());
    final tomorrow = _startOf(today.add(const Duration(days: 1)));
    if (await _streakOn(userId, today) != null) {
      throw AlreadyClaimedException(tomorrow);
    }
    final yesterday = await _streakOn(
      userId,
      today.subtract(const Duration(days: 1)),
    );
    final streak = (yesterday ?? 0) + 1;
    final amount = settings.dailyAmount(streak);
    final result = await ledger.post(
      LedgerTransaction(
        idempotencyKey: _dailyKey(userId, today),
        kind: 'coin_daily',
        transfers: [
          Transfer(from: _house, to: _wallet(userId), amount: amount),
        ],
        metadata: {'streak': streak, 'day': _dayName(today)},
      ),
    );
    // A claim from another request got there first.
    if (result.duplicate) throw AlreadyClaimedException(tomorrow);
    return DailyRewardGrant(
      balance: await balance(userId),
      granted: amount,
      streak: streak,
    );
  }

  Future<int> _grant(String userId, String key, String kind, int amount) async {
    if (amount <= 0) return 0;
    final result = await ledger.post(
      LedgerTransaction(
        idempotencyKey: key,
        kind: kind,
        transfers: [
          Transfer(from: _house, to: _wallet(userId), amount: amount),
        ],
      ),
    );
    return result.duplicate ? 0 : amount;
  }

  /// The streak recorded by the claim on [day], or null if none.
  Future<int?> _streakOn(String userId, DateTime day) async {
    final meta = await ledger.metadataFor(_dailyKey(userId, day));
    if (meta == null) return null;
    return (meta['streak'] as num?)?.toInt() ?? 1;
  }

  /// The Kampala calendar day of [t], as a UTC midnight date.
  DateTime _day(DateTime t) {
    final local = t.toUtc().add(settings.dayOffset);
    return DateTime.utc(local.year, local.month, local.day);
  }

  /// The UTC moment the Kampala [day] starts.
  DateTime _startOf(DateTime day) => day.subtract(settings.dayOffset);

  static String _dayName(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static String _dailyKey(String userId, DateTime day) =>
      'coins:daily:$userId:${_dayName(day)}';
}

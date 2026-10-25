import 'ledger.dart';
import 'limits.dart';
import 'payout.dart';

/// Coin table entries (D37). 0 is a free table.
class CoinTableSettings {
  const CoinTableSettings({this.entries = const [0, 50, 200, 1000]});

  final List<int> entries;

  bool allows(int entry) => entries.contains(entry);

  /// UGX stakes from D38. Rooms still refuse them until paid tables are on.
  static const List<int> paidStakes = [1000, 2000, 5000, 10000, 20000, 50000];
}

/// Bot seats use `bot:<seat>` and have no account (D50, D53).
bool isBotUser(String userId) => userId.startsWith('bot:');

/// One match's entries, taken from every seat when the game starts.
class MatchStakes {
  const MatchStakes({
    required this.matchId,
    required this.currency,
    required this.perPlayer,
    required this.userIds,
  });

  final String matchId;
  final Currency currency;

  /// Coins or UGX each seat puts in, bots included.
  final int perPlayer;

  /// Every seat, in seat order. Bot ids are funded by the house account.
  final List<String> userIds;
}

class _Plan {
  const _Plan({required this.transfers, required this.nets});
  final List<Transfer> transfers;
  final Map<String, int> nets;
}

/// Collects entries into a match pot and pays them out (M3.4, D37, D53).
///
/// A bot has no wallet. The house account of the same currency pays the bot's
/// entry, and anything a bot wins goes back to the house. Human coin pots
/// have no house share: the winner takes the pot, and in a game of four or
/// more the second place gets its entry back first. UGX follows README
/// section 10. Paid rooms are not opened by this service.
///
/// A UGX stake checks self exclusion when [limits] is set. A coin charge
/// does not: coin tables stay open during an exclusion (M3.11).
class SettlementService {
  SettlementService({
    required this.ledger,
    this.payout = const PayoutSettings(),
    this.coins = const CoinTableSettings(),
    this.limits,
  });

  final Ledger ledger;
  final PayoutSettings payout;
  final CoinTableSettings coins;

  /// Checked for UGX stakes only. Null in tests that do not cover exclusion.
  final LimitsService? limits;

  static String stakeKey(String matchId) => 'stake:$matchId';
  static String settleKey(String matchId) => 'settle:$matchId';
  static String refundKey(String matchId) => 'refund:$matchId';

  /// Moves each entry into the match pot. All or nothing: a wallet that
  /// cannot pay throws [InsufficientFundsException] and nothing is posted.
  /// Posting the same match again does nothing.
  Future<void> collectStakes(MatchStakes stakes) async {
    _checkStakes(stakes);
    final id = stakes.matchId;
    if (await ledger.metadataFor(refundKey(id)) != null) {
      throw StateError('match $id was refunded');
    }
    if (await ledger.metadataFor(stakeKey(id)) != null) return;
    final guard = limits;
    if (guard != null && stakes.currency == Currency.ugx) {
      for (final userId in stakes.userIds) {
        if (!isBotUser(userId)) await guard.checkPlay(userId);
      }
    }
    final pot = AccountId.pot(id, stakes.currency);
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: stakeKey(id),
        kind: 'stake',
        transfers: [
          for (final userId in stakes.userIds)
            Transfer(
              from: _purse(userId, stakes.currency),
              to: pot,
              amount: stakes.perPlayer,
            ),
        ],
        metadata: {
          'currency': stakes.currency.name,
          'perPlayer': stakes.perPlayer,
          'userIds': [...stakes.userIds],
        },
      ),
    );
  }

  /// Pays the pot out by [ranking] (first is the winner, forfeits last).
  /// Returns each human's net change for the match, stake included. Bots are
  /// left out. Repeating a settle returns the same map and moves nothing.
  Future<Map<String, int>> settle(String matchId, List<String> ranking) async {
    final saved = await ledger.metadataFor(settleKey(matchId));
    if (saved != null) return _readNets(saved['nets']);
    if (await ledger.metadataFor(refundKey(matchId)) != null) {
      throw StateError('match $matchId was refunded');
    }
    final stake = await ledger.metadataFor(stakeKey(matchId));
    if (stake == null) throw StateError('match $matchId has no stakes');
    final currency = _currency(stake['currency']);
    final perPlayer = _asInt(stake['perPlayer']);
    final userIds = _stringList(stake['userIds']);
    _checkRanking(ranking, userIds);
    final plan = currency == Currency.coin
        ? _coinPlan(matchId, ranking, perPlayer)
        : _ugxPlan(matchId, ranking, perPlayer);
    final result = await ledger.post(
      LedgerTransaction(
        idempotencyKey: settleKey(matchId),
        kind: 'payout',
        transfers: plan.transfers,
        metadata: {'nets': plan.nets},
      ),
    );
    if (result.duplicate) {
      final again = await ledger.metadataFor(settleKey(matchId));
      return _readNets(again?['nets']);
    }
    return plan.nets;
  }

  /// Sends every entry back. Only before [settle]. A second refund does
  /// nothing. A match that was never charged is left alone.
  Future<void> refund(String matchId) async {
    if (await ledger.metadataFor(settleKey(matchId)) != null) {
      throw StateError('match $matchId is already settled');
    }
    if (await ledger.metadataFor(refundKey(matchId)) != null) return;
    final stake = await ledger.metadataFor(stakeKey(matchId));
    if (stake == null) return;
    final currency = _currency(stake['currency']);
    final perPlayer = _asInt(stake['perPlayer']);
    final userIds = _stringList(stake['userIds']);
    final pot = AccountId.pot(matchId, currency);
    await ledger.post(
      LedgerTransaction(
        idempotencyKey: refundKey(matchId),
        kind: 'refund',
        transfers: [
          for (final userId in userIds)
            Transfer(
              from: pot,
              to: _purse(userId, currency),
              amount: perPlayer,
            ),
        ],
      ),
    );
  }

  void _checkStakes(MatchStakes stakes) {
    if (stakes.matchId.isEmpty) {
      throw ArgumentError.value(stakes.matchId, 'matchId');
    }
    if (stakes.perPlayer <= 0) {
      throw ArgumentError.value(stakes.perPlayer, 'perPlayer');
    }
    if (stakes.userIds.length < 2) {
      throw ArgumentError.value(stakes.userIds, 'userIds');
    }
    if (stakes.userIds.toSet().length != stakes.userIds.length) {
      throw ArgumentError('userIds must be unique');
    }
    if (stakes.currency == Currency.ugx && stakes.userIds.any(isBotUser)) {
      throw ArgumentError('paid tables have no bots');
    }
    if (stakes.currency == Currency.coin && !coins.allows(stakes.perPlayer)) {
      throw ArgumentError.value(stakes.perPlayer, 'perPlayer');
    }
  }

  _Plan _coinPlan(String matchId, List<String> ranking, int perPlayer) {
    final potSize = perPlayer * ranking.length;
    final credits = <String, int>{};
    void add(String userId, int amount) {
      if (amount <= 0) return;
      credits[userId] = (credits[userId] ?? 0) + amount;
    }

    // Four or more: 2nd place gets its entry back, the winner takes the rest.
    // Fewer seats: the winner takes the whole pot (D37).
    if (ranking.length >= 4) {
      add(ranking[1], perPlayer);
      add(ranking.first, potSize - perPlayer);
    } else {
      add(ranking.first, potSize);
    }
    final pot = AccountId.pot(matchId, Currency.coin);
    return _Plan(
      transfers: [
        for (final credit in credits.entries)
          Transfer(
            from: pot,
            to: _purse(credit.key, Currency.coin),
            amount: credit.value,
          ),
      ],
      nets: _humanNets(ranking, perPlayer, credits),
    );
  }

  _Plan _ugxPlan(String matchId, List<String> ranking, int perPlayer) {
    final result = computePayout(
      stakePerPlayer: perPlayer,
      players: ranking.length,
      settings: payout,
    );
    final pot = AccountId.pot(matchId, Currency.ugx);
    final winner = ranking.first;
    return _Plan(
      transfers: [
        if (result.toWinner > 0)
          Transfer(
            from: pot,
            to: AccountId.wallet(winner),
            amount: result.toWinner,
          ),
        if (result.withheld > 0)
          Transfer(
            from: pot,
            to: const AccountId.taxWithheld(),
            amount: result.withheld,
          ),
        if (result.rake > 0)
          Transfer(
            from: pot,
            to: const AccountId.revenue(),
            amount: result.rake,
          ),
        if (result.rakeTax > 0)
          Transfer(
            from: const AccountId.revenue(),
            to: const AccountId.taxPayable(),
            amount: result.rakeTax,
          ),
      ],
      nets: _humanNets(ranking, perPlayer, {winner: result.toWinner}),
    );
  }

  /// What each human receives now, minus the entry already taken.
  Map<String, int> _humanNets(
    List<String> ranking,
    int perPlayer,
    Map<String, int> credits,
  ) {
    final nets = <String, int>{};
    for (final userId in ranking) {
      if (isBotUser(userId)) continue;
      nets[userId] = (credits[userId] ?? 0) - perPlayer;
    }
    return nets;
  }

  AccountId _purse(String userId, Currency currency) => isBotUser(userId)
      ? AccountId.revenue(currency)
      : AccountId.wallet(userId, currency);
}

void _checkRanking(List<String> ranking, List<String> userIds) {
  if (ranking.length != userIds.length ||
      ranking.toSet().length != ranking.length ||
      !ranking.toSet().containsAll(userIds)) {
    throw ArgumentError('ranking must list each staked player once');
  }
}

Currency _currency(Object? name) {
  for (final currency in Currency.values) {
    if (currency.name == name) return currency;
  }
  throw StateError('bad stake currency $name');
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw StateError('expected an integer, got $value');
}

List<String> _stringList(Object? raw) => [
  for (final value in raw as List) value as String,
];

Map<String, int> _readNets(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final entry in raw.entries)
      entry.key as String: _asInt(entry.value as Object?),
  };
}

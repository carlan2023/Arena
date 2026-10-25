import 'package:arena_protocol/client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ludo_engine/ludo_engine.dart';

import 'auth.dart';
import 'config.dart';

/// The HTTP routes the app uses (protocol.md). Faked in tests.
abstract interface class ArenaApi {
  Future<Session> login(String idToken);

  /// A guest account for free play, no phone needed (D33).
  Future<Session> guest();
  Future<UserView> me(String token);
  Future<UserView> setDisplayName(String token, String name);

  /// Changes the name, the avatar or both (M3.3).
  Future<UserView> setProfile(String token, {String? name, int? avatar});

  /// The player's last 20 ended matches, newest first.
  Future<List<RecentMatchView>> recentMatches(String token);

  /// Coin balance and the daily reward (M3.4).
  Future<CoinsView> coins(String token);

  /// Throws [ApiError] already_claimed when today's reward was claimed.
  Future<CoinGrantView> claimDailyReward(String token);
  Future<RoomView> createRoom(
    String token, {
    required GameMode mode,
    required int seats,
    int entry = 0,
  });
  Future<RoomView> getRoom(String token, String code);

  /// Once only. 403 age_required still stores the date.
  Future<UserView> setDateOfBirth(String token, String dateOfBirth);

  Future<int> walletBalance(String token);
  Future<List<WalletEntryView>> walletHistory(String token, {int limit = 50});
  Future<PaymentView> deposit(
    String token, {
    required int amount,
    required String msisdn,
    String provider = 'fake',
  });

  /// Completes a fake-provider deposit. 404 when that route is off.
  Future<PaymentView> confirmDeposit(String token, String paymentId);
  Future<LimitsView> limits(String token);
  Future<LimitsView> setLimits(
    String token, {
    int? daily,
    int? weekly,
    int? monthly,
  });
  Future<LimitsView> selfExclude(String token, String period);
}

/// Talks to the server through the shared [ArenaClient].
class HttpArenaApi implements ArenaApi {
  HttpArenaApi(this.baseUrl, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final http.Client _http;

  ArenaClient _client(String? token) =>
      ArenaClient(baseUrl: baseUrl, httpClient: _http)..sessionToken = token;

  @override
  Future<Session> login(String idToken) async {
    final c = _client(null);
    final user = await c.login(idToken);
    return Session(token: c.sessionToken!, user: user);
  }

  @override
  Future<Session> guest() async {
    final c = _client(null);
    final user = await c.guest();
    return Session(token: c.sessionToken!, user: user);
  }

  @override
  Future<UserView> me(String token) => _client(token).me();

  @override
  Future<UserView> setDisplayName(String token, String name) =>
      _client(token).setDisplayName(name);

  @override
  Future<UserView> setProfile(String token, {String? name, int? avatar}) =>
      _client(token).setProfile(displayName: name, avatar: avatar);

  @override
  Future<List<RecentMatchView>> recentMatches(String token) =>
      _client(token).recentMatches();

  @override
  Future<CoinsView> coins(String token) => _client(token).coins();

  @override
  Future<CoinGrantView> claimDailyReward(String token) =>
      _client(token).claimDailyReward();

  @override
  Future<RoomView> createRoom(
    String token, {
    required GameMode mode,
    required int seats,
    int entry = 0,
  }) => _client(token).createRoom(mode: mode, seats: seats, entry: entry);

  @override
  Future<RoomView> getRoom(String token, String code) =>
      _client(token).getRoom(code);

  @override
  Future<UserView> setDateOfBirth(String token, String dateOfBirth) =>
      _client(token).setDateOfBirth(dateOfBirth);

  @override
  Future<int> walletBalance(String token) => _client(token).walletBalance();

  @override
  Future<List<WalletEntryView>> walletHistory(String token, {int limit = 50}) =>
      _client(token).walletHistory(limit: limit);

  @override
  Future<PaymentView> deposit(
    String token, {
    required int amount,
    required String msisdn,
    String provider = 'fake',
  }) => _client(
    token,
  ).deposit(amount: amount, msisdn: msisdn, provider: provider);

  @override
  Future<PaymentView> confirmDeposit(String token, String paymentId) =>
      _client(token).confirmDeposit(paymentId);

  @override
  Future<LimitsView> limits(String token) => _client(token).limits();

  @override
  Future<LimitsView> setLimits(
    String token, {
    int? daily,
    int? weekly,
    int? monthly,
  }) =>
      _client(token).setLimits(daily: daily, weekly: weekly, monthly: monthly);

  @override
  Future<LimitsView> selfExclude(String token, String period) =>
      _client(token).selfExclude(period);
}

final arenaApiProvider = Provider<ArenaApi>(
  (ref) => HttpArenaApi(Uri.parse(kServerUrl)),
);

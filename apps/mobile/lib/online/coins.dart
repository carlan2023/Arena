import 'package:arena_protocol/arena_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'auth.dart';

/// The coin balance and daily reward of the current session. Null before the
/// player first goes online, since free play starts no account (D33).
final coinsProvider = AsyncNotifierProvider<CoinsController, CoinsView?>(
  CoinsController.new,
);

class CoinsController extends AsyncNotifier<CoinsView?> {
  @override
  Future<CoinsView?> build() async {
    final session = await ref.watch(authProvider.future);
    if (session == null) return null;
    return ref.read(arenaApiProvider).coins(session.token);
  }

  /// Claims today's reward and returns it, or null when it was already
  /// claimed, for example on another phone. The balance is refreshed either
  /// way.
  Future<CoinGrantView?> claimDaily() async {
    final session = await ref.read(authProvider.notifier).ensureSession();
    final api = ref.read(arenaApiProvider);
    CoinGrantView? grant;
    try {
      grant = await api.claimDailyReward(session.token);
    } on ApiError catch (e) {
      if (e.code != ErrorCodes.alreadyClaimed) rethrow;
    }
    state = AsyncData(await api.coins(session.token));
    return grant;
  }
}

import 'clock.dart';

/// Allows at most [limit] hits per key in any sliding [window].
class RateLimiter {
  RateLimiter({required this.limit, required this.window, required this.clock});

  final int limit;
  final Duration window;
  final Clock clock;
  final Map<String, List<int>> _hits = {};

  /// Records a hit and returns whether it is allowed. Refused hits are not
  /// counted.
  bool allow(String key) {
    final now = clock.nowMs();
    final start = now - window.inMilliseconds;
    final hits = _hits.putIfAbsent(key, () => []);
    hits.removeWhere((t) => t <= start);
    if (hits.length >= limit) return false;
    hits.add(now);
    if (_hits.length > 10000) {
      _hits.removeWhere((_, v) => v.isEmpty || v.last <= start);
    }
    return true;
  }
}

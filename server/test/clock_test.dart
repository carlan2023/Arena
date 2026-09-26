import 'package:arena_server/arena_server.dart';
import 'package:arena_server/src/rate_limit.dart';
import 'package:test/test.dart';

void main() {
  test('FakeClock fires due timers in time order, including new ones', () {
    final clock = FakeClock(0);
    final fired = <String>[];
    clock.schedule(const Duration(seconds: 2), () => fired.add('b'));
    clock.schedule(const Duration(seconds: 1), () {
      fired.add('a');
      clock.schedule(const Duration(milliseconds: 500), () => fired.add('a2'));
    });
    final c = clock.schedule(const Duration(seconds: 1), () => fired.add('x'));
    c.cancel();
    clock.advance(const Duration(seconds: 3));
    expect(fired, ['a', 'a2', 'b']);
    expect(clock.nowMs(), 3000);
    expect(clock.pendingTimers, 0);
  });

  test('RateLimiter allows limit hits per sliding window', () {
    final clock = FakeClock(0);
    final limiter = RateLimiter(
      limit: 2,
      window: const Duration(seconds: 1),
      clock: clock,
    );
    expect(
      [limiter.allow('k'), limiter.allow('k'), limiter.allow('k')],
      [true, true, false],
    );
    expect(limiter.allow('other'), isTrue);
    clock.advance(const Duration(milliseconds: 1001));
    expect(limiter.allow('k'), isTrue);
  });
}

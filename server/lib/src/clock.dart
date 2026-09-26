import 'dart:async';

/// A cancellable scheduled callback.
abstract interface class TimerHandle {
  void cancel();
}

/// Time and timers for the game loop, injectable so tests run fast.
abstract interface class Clock {
  /// Epoch milliseconds.
  int nowMs();

  TimerHandle schedule(Duration delay, void Function() callback);
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  TimerHandle schedule(Duration delay, void Function() callback) =>
      _SystemTimer(Timer(delay, callback));
}

class _SystemTimer implements TimerHandle {
  _SystemTimer(this._timer);
  final Timer _timer;
  @override
  void cancel() => _timer.cancel();
}

/// A clock that only moves when told to. [advance] runs due callbacks in time
/// order, including ones scheduled by other callbacks.
class FakeClock implements Clock {
  FakeClock([int startMs = 1790000000000]) : _now = startMs;

  int _now;
  int _nextId = 0;
  final List<_FakeTimer> _timers = [];

  @override
  int nowMs() => _now;

  @override
  TimerHandle schedule(Duration delay, void Function() callback) {
    final t = _FakeTimer(
      this,
      _now + delay.inMilliseconds,
      _nextId++,
      callback,
    );
    _timers.add(t);
    return t;
  }

  /// Number of timers still waiting.
  int get pendingTimers => _timers.length;

  /// Moves time forward by [by], firing every timer that falls due.
  void advance(Duration by) {
    final end = _now + by.inMilliseconds;
    while (true) {
      _FakeTimer? next;
      for (final t in _timers) {
        if (t.due > end) continue;
        if (next == null ||
            t.due < next.due ||
            (t.due == next.due && t.id < next.id)) {
          next = t;
        }
      }
      if (next == null) break;
      _timers.remove(next);
      if (next.due > _now) _now = next.due;
      next.callback();
    }
    _now = end;
  }
}

class _FakeTimer implements TimerHandle {
  _FakeTimer(this.clock, this.due, this.id, this.callback);
  final FakeClock clock;
  final int due;
  final int id;
  final void Function() callback;
  @override
  void cancel() => clock._timers.remove(this);
}

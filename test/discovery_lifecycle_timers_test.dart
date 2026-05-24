import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_lifecycle_timers.dart';

void main() {
  group('DiscoveryLifecycleTimers', () {
    test(
      'restarting timers cancels previous timers for each lifecycle seam',
      () {
        final createdTimers = <_FakeTimer>[];
        final timers = DiscoveryLifecycleTimers(
          timerFactory: (interval, onTick) {
            final timer = _FakeTimer(interval: interval, onTick: onTick);
            createdTimers.add(timer);
            return timer;
          },
        );
        var autoRefreshTicks = 0;
        var presenceExpiryTicks = 0;

        timers.restartAutoRefresh(
          interval: const Duration(seconds: 5),
          onTick: () => autoRefreshTicks += 1,
        );
        timers.restartAutoRefresh(
          interval: const Duration(seconds: 10),
          onTick: () => autoRefreshTicks += 10,
        );
        timers.restartPresenceExpiry(
          interval: const Duration(seconds: 2),
          onTick: () => presenceExpiryTicks += 1,
        );

        expect(createdTimers[0].isActive, isFalse);
        expect(createdTimers[1].isActive, isTrue);
        expect(createdTimers[2].isActive, isTrue);

        createdTimers[0].fire();
        createdTimers[1].fire();
        createdTimers[2].fire();

        expect(autoRefreshTicks, 10);
        expect(presenceExpiryTicks, 1);

        timers.cancelAll();

        expect(createdTimers.every((timer) => !timer.isActive), isTrue);
      },
    );

    test('clipboard polling runs an immediate snapshot tick', () {
      final timers = DiscoveryLifecycleTimers(
        timerFactory: (interval, onTick) =>
            _FakeTimer(interval: interval, onTick: onTick),
      );
      var ticks = 0;

      timers.startClipboardPolling(
        interval: const Duration(seconds: 2),
        onTick: () => ticks += 1,
      );

      expect(ticks, 1);
    });
  });
}

class _FakeTimer implements Timer {
  _FakeTimer({required this.interval, required this.onTick});

  final Duration interval;
  final void Function(Timer timer) onTick;
  var _isActive = true;
  var _tick = 0;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;

  void fire() {
    if (!_isActive) {
      return;
    }
    _tick += 1;
    onTick(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }
}

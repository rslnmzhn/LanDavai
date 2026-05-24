import 'dart:async';

class DiscoveryLifecycleTimers {
  DiscoveryLifecycleTimers({TimerFactory? timerFactory})
    : _timerFactory = timerFactory ?? _defaultTimerFactory;

  final TimerFactory _timerFactory;
  Timer? _autoRefreshTimer;
  Timer? _clipboardPollTimer;
  Timer? _presenceExpiryTimer;

  void restartAutoRefresh({
    required Duration interval,
    required void Function() onTick,
  }) {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = _timerFactory(interval, (_) => onTick());
  }

  void startClipboardPolling({
    required Duration interval,
    required void Function() onTick,
  }) {
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = _timerFactory(interval, (_) => onTick());
    onTick();
  }

  void restartPresenceExpiry({
    required Duration interval,
    required void Function() onTick,
  }) {
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = _timerFactory(interval, (_) => onTick());
  }

  void cancelAll() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = null;
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = null;
  }
}

typedef TimerFactory =
    Timer Function(Duration interval, void Function(Timer timer) onTick);

Timer _defaultTimerFactory(
  Duration interval,
  void Function(Timer timer) onTick,
) {
  return Timer.periodic(interval, onTick);
}

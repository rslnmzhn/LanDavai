import 'dart:async';

class LanDiscoveryLifecycleState {
  Timer? _heartbeatTimer;
  bool _started = false;
  String _localPeerId = '';

  bool get isStarted => _started;
  String get localPeerId => _localPeerId;

  bool tryStart({
    required String localPeerId,
    required void Function(String message) log,
  }) {
    if (_started) {
      log('start() ignored: service already running');
      return false;
    }

    _started = true;
    _localPeerId = localPeerId.trim();
    return true;
  }

  void markStartFailed() {
    _started = false;
    _localPeerId = '';
    cancelHeartbeat();
  }

  void replaceHeartbeat({
    required Duration interval,
    required Future<void> Function() onHeartbeat,
  }) {
    cancelHeartbeat();
    _heartbeatTimer = Timer.periodic(interval, (_) => onHeartbeat());
  }

  void cancelHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void beginStop({required void Function(String message) log}) {
    log('Stopping UDP discovery');
    cancelHeartbeat();
  }

  void completeStop({
    required void Function() clearConfiguredTargets,
    required void Function() clearSenderAllowlist,
    required void Function() clearIncomingDispatcher,
  }) {
    _started = false;
    _localPeerId = '';
    clearConfiguredTargets();
    clearSenderAllowlist();
    clearIncomingDispatcher();
  }
}

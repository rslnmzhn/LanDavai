import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/data/lan_discovery_lifecycle_state.dart';

void main() {
  test('guards duplicate starts and trims local peer id', () {
    final logs = <String>[];
    final state = LanDiscoveryLifecycleState();

    final firstStart = state.tryStart(
      localPeerId: ' local-peer ',
      log: logs.add,
    );
    final secondStart = state.tryStart(
      localPeerId: 'other-peer',
      log: logs.add,
    );

    expect(firstStart, isTrue);
    expect(secondStart, isFalse);
    expect(state.isStarted, isTrue);
    expect(state.localPeerId, 'local-peer');
    expect(logs, contains('start() ignored: service already running'));
  });

  test('runs stop cleanup hooks after service-owned transport stop', () async {
    final calls = <String>[];
    final state = LanDiscoveryLifecycleState();
    state.tryStart(localPeerId: 'local-peer', log: (_) {});

    state.beginStop(log: (_) => calls.add('log'));
    calls.add('transport');
    state.completeStop(
      clearConfiguredTargets: () => calls.add('targets'),
      clearSenderAllowlist: () => calls.add('allowlist'),
      clearIncomingDispatcher: () => calls.add('dispatcher'),
    );

    expect(state.isStarted, isFalse);
    expect(state.localPeerId, isEmpty);
    expect(calls, <String>[
      'log',
      'transport',
      'targets',
      'allowlist',
      'dispatcher',
    ]);
  });

  test('cancels heartbeat on stop', () async {
    var heartbeatCount = 0;
    final state = LanDiscoveryLifecycleState();
    state.tryStart(localPeerId: 'local-peer', log: (_) {});
    state.replaceHeartbeat(
      interval: const Duration(milliseconds: 10),
      onHeartbeat: () async {
        heartbeatCount += 1;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 35));
    expect(heartbeatCount, greaterThan(0));

    state.beginStop(log: (_) {});
    state.completeStop(
      clearConfiguredTargets: () {},
      clearSenderAllowlist: () {},
      clearIncomingDispatcher: () {},
    );
    final stoppedCount = heartbeatCount;

    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(heartbeatCount, stoppedCount);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_send_view.dart';

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets(
    'send view shows QR, horizontal device list, and send actions after handshake',
    (tester) async {
      harness.controller.setTestDevices(<DiscoveredDevice>[
        DiscoveredDevice(
          ip: '192.168.0.20',
          macAddress: 'aa:bb:cc:00:00:20',
          deviceName: 'Peer A',
          isNearbyTransferAvailable: true,
          nearbyTransferPort: 45321,
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 10),
        ),
      ]);
      final lanAdapter = FakeNearbyTransferTransportAdapter();
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
      );
      addTearDown(store.dispose);

      await store.prepareSendFlow();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: store,
              builder: (context, _) {
                return NearbyTransferSendView(
                  store: store,
                  onDisconnectRequested: () async {},
                );
              },
            ),
          ),
        ),
      );
      await _pumpForUi(tester);

      expect(find.byKey(const Key('nearby-transfer-qr-image')), findsOneWidget);
      expect(
        find.byKey(const Key('nearby-transfer-device-chip-row')),
        findsOneWidget,
      );
      expect(find.text('Peer A'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('nearby-transfer-device-chip-row')),
          matching: find.byType(Scrollbar),
        ),
        findsNothing,
      );

      lanAdapter.emit(
        const NearbyTransferConnectedEvent(
          peer: NearbyTransferPeerDevice(
            deviceId: 'peer-a',
            displayName: 'Peer A',
            host: '192.168.0.20',
          ),
          sessionId: 'session-a',
        ),
      );
      await _pumpForUi(tester);
      lanAdapter.emit(const NearbyTransferHandshakeAcceptedEvent());
      await _pumpForUi(tester);

      expect(find.text('Выбрать файлы'), findsOneWidget);
      expect(find.text('Выбрать папку'), findsOneWidget);
      expect(lanAdapter.sendHandshakeOfferCalls, 1);
      expect(lanAdapter.lastVerificationCode, hasLength(6));

      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      await _pumpForUi(tester, frames: 2);
    },
  );
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

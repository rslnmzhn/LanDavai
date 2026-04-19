import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_receive_view.dart';

import 'test_support/fake_nearby_transfer.dart';
import 'test_support/localized_test_app.dart';
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
    'receive view shows structured folder offer and allows navigation after handshake',
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
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpForUi(tester, frames: 4);
      });

      await store.prepareReceiveFlow();

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: store,
              builder: (context, _) {
                return NearbyTransferReceiveView(
                  store: store,
                  onDisconnectRequested: () async {},
                );
              },
            ),
          ),
        ),
      );
      await _pumpForUi(tester);

      expect(
        find.text(
          'Сканирование QR на этом устройстве недоступно. Используйте список устройств ниже.',
        ),
        findsOneWidget,
      );
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
      lanAdapter.emit(
        const NearbyTransferHandshakeOfferEvent(
          verificationCode: <String>['1', '2'],
        ),
      );
      await _pumpForUi(tester);

      expect(
        find.text('Введите двузначный код с устройства отправителя'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nearby-transfer-code-input')),
        findsOneWidget,
      );
      expect(find.text('Подтвердить код'), findsOneWidget);
      expect(
        find.byKey(const Key('nearby-transfer-scanner-stage')),
        findsNothing,
      );

      await tester.enterText(
        find.byKey(const Key('nearby-transfer-code-input')),
        '12',
      );
      await tester.tap(find.text('Подтвердить код'));
      await _pumpForUi(tester);

      expect(lanAdapter.sendHandshakeAcceptedCalls, 1);
      lanAdapter.emit(
        const NearbyTransferIncomingSelectionOfferedEvent(
          requestId: 'offer-1',
          label: 'Trip',
          roots: <NearbyTransferRemoteOfferNode>[
            NearbyTransferRemoteOfferNode(
              id: 'dir:Trip',
              name: 'Trip',
              relativePath: 'Trip',
              kind: NearbyTransferRemoteOfferNodeKind.directory,
              sizeBytes: 6144,
              previewKind: NearbyTransferRemotePreviewKind.none,
              children: <NearbyTransferRemoteOfferNode>[
                NearbyTransferRemoteOfferNode(
                  id: 'image-1',
                  name: 'photo.png',
                  relativePath: 'Trip/photo.png',
                  kind: NearbyTransferRemoteOfferNodeKind.file,
                  sizeBytes: 2048,
                  previewKind: NearbyTransferRemotePreviewKind.image,
                ),
                NearbyTransferRemoteOfferNode(
                  id: 'doc-1',
                  name: 'report.pdf',
                  relativePath: 'Trip/report.pdf',
                  kind: NearbyTransferRemoteOfferNodeKind.file,
                  sizeBytes: 4096,
                  previewKind: NearbyTransferRemotePreviewKind.none,
                ),
              ],
            ),
          ],
        ),
      );
      await _pumpForUi(tester);

      expect(find.text('Trip'), findsWidgets);
      expect(find.text('photo.png'), findsNothing);
      expect(find.text('report.pdf'), findsNothing);
      expect(find.text('Скачать выбранные'), findsOneWidget);
      expect(find.text('Предпросмотр'), findsNothing);
      expect(
        find.byKey(
          const ValueKey<String>('nearby-transfer-open-folder-button-dir:Trip'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('nearby-transfer-checkbox-dir:Trip')),
        findsOneWidget,
      );

      store.openIncomingDirectory('dir:Trip');
      await _pumpForUi(tester);

      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('nearby-transfer-checkbox-image-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('nearby-transfer-preview-badge-image-1'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('nearby-transfer-preview-button-image-1'),
        ),
        findsOneWidget,
      );

      await store.resetForEntrySelection();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester, frames: 2);
    },
  );
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_send_view.dart';

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
      final prepareCompletion = Completer<void>();
      final lanAdapter = FakeNearbyTransferTransportAdapter(
        onSendSelection: (adapter, selection) async {
          adapter.emit(
            NearbyTransferSelectionPreparationStartedEvent(
              label: selection.label,
              totalItemCount: selection.entries.length,
              totalBytes: selection.entries.fold<int>(
                0,
                (sum, entry) => sum + entry.sizeBytes,
              ),
            ),
          );
          adapter.emit(
            const NearbyTransferSelectionPreparationProgressEvent(
              label: 'Trip',
              completedItemCount: 1,
              totalItemCount: 2,
              preparedBytes: 2048,
              totalBytes: 2176,
              currentRelativePath: 'Trip/photo.png',
            ),
          );
          await prepareCompletion.future;
          adapter.emit(
            const NearbyTransferSelectionPreparationCompletedEvent(
              requestId: 'offer-1',
              label: 'Trip',
              totalItemCount: 2,
              totalBytes: 2176,
            ),
          );
        },
      );
      final store = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: lanAdapter,
        filePicker: StubNearbyTransferFilePicker(
          fileSelection: const NearbyTransferSelection(
            label: 'Trip',
            entries: <NearbyTransferPickedEntry>[
              NearbyTransferPickedEntry(
                sourcePath: '/tmp/Trip/photo.png',
                relativePath: 'Trip/photo.png',
                sizeBytes: 2048,
              ),
              NearbyTransferPickedEntry(
                sourcePath: '/tmp/Trip/docs/notes.txt',
                relativePath: 'Trip/docs/notes.txt',
                sizeBytes: 128,
              ),
            ],
          ),
          directorySelection: const NearbyTransferSelection(
            label: 'Trip',
            entries: <NearbyTransferPickedEntry>[
              NearbyTransferPickedEntry(
                sourcePath: '/tmp/Trip/photo.png',
                relativePath: 'Trip/photo.png',
                sizeBytes: 2048,
              ),
            ],
          ),
        ),
      );
      addTearDown(store.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpForUi(tester, frames: 4);
      });

      await store.prepareSendFlow();

      await tester.pumpWidget(
        buildLocalizedTestApp(
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
      expect(find.byKey(const Key('nearby-transfer-qr-image')), findsNothing);
      expect(lanAdapter.sendHandshakeOfferCalls, 1);
      expect(lanAdapter.lastVerificationCode, hasLength(2));
      expect(store.outgoingSelectionLabel, isNull);

      await tester.tap(find.text('Выбрать файлы'));
      await _pumpForUi(tester, frames: 2);

      expect(find.text('Выбрано для отправки'), findsOneWidget);
      expect(find.text('Trip'), findsWidgets);
      expect(find.text('Подготавливаем 1 из 2 элементов...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('photo.png'), findsNothing);

      prepareCompletion.complete();
      await _pumpForUi(tester);

      expect(find.text('Trip'), findsWidgets);
      expect(find.text('Выбрано для отправки'), findsOneWidget);
      expect(find.byType(Chip), findsAtLeastNWidgets(1));
      expect(store.isPreparingOutgoingSelection, isFalse);
      expect(store.outgoingSelectionRoots, <String>['Trip']);
      expect(store.outgoingSelectionItemCount, 2);

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

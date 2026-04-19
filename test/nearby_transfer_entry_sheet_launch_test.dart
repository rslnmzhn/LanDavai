import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_session_store.dart';
import 'package:landa/features/nearby_transfer/presentation/nearby_transfer_entry_sheet.dart';

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
    'entry flow uses a compact launcher sheet and opens dedicated full screens for receive and send',
    (tester) async {
      final receiveStore = await _pumpLauncher(tester, harness);
      addTearDown(receiveStore.dispose);

      await tester.tap(find.byKey(const Key('nearby-sheet-launch-button')));
      await _pumpForUi(tester);

      expect(
        find.byKey(const Key('nearby-transfer-launcher-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nearby-transfer-fullscreen-page')),
        findsNothing,
      );
      expect(find.text('Принять файлы'), findsOneWidget);
      expect(find.text('Отдать файлы'), findsOneWidget);
      expect(find.text('Peer A'), findsNothing);

      await tester.tap(find.text('Принять файлы'));
      await _pumpForUi(tester, frames: 12);

      expect(
        find.byKey(const Key('nearby-transfer-launcher-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nearby-transfer-fullscreen-page')),
        findsOneWidget,
      );
      expect(find.text('Peer A'), findsOneWidget);
      expect(find.text('Передача рядом'), findsOneWidget);

      await receiveStore.resetForEntrySelection();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester, frames: 4);

      final sendStore = await _pumpLauncher(tester, harness);
      addTearDown(sendStore.dispose);

      await tester.tap(find.byKey(const Key('nearby-sheet-launch-button')));
      await _pumpForUi(tester);

      expect(
        find.byKey(const Key('nearby-transfer-launcher-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('nearby-transfer-fullscreen-page')),
        findsNothing,
      );

      await tester.tap(find.text('Отдать файлы'));
      await _pumpForUi(tester, frames: 12);

      expect(
        find.byKey(const Key('nearby-transfer-launcher-sheet')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('nearby-transfer-fullscreen-page')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('nearby-transfer-qr-image')), findsOneWidget);
      expect(find.text('Peer A'), findsOneWidget);
      expect(find.text('Выбрать файлы'), findsNothing);

      await sendStore.resetForEntrySelection();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester, frames: 4);
    },
  );
}

Future<NearbyTransferSessionStore> _pumpLauncher(
  WidgetTester tester,
  TestDiscoveryControllerHarness harness,
) async {
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
  final store = buildTestNearbyTransferStore(readModel: harness.readModel);
  await tester.pumpWidget(
    buildLocalizedTestApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ElevatedButton(
              key: const Key('nearby-sheet-launch-button'),
              onPressed: () {
                showNearbyTransferEntrySheet(
                  context: context,
                  sessionStore: store,
                );
              },
              child: const Text('launch'),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

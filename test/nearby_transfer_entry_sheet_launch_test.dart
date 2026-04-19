import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
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
    'entry flow opens compact chooser before the full receive screen',
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
      final store = buildTestNearbyTransferStore(readModel: harness.readModel);
      const launchButtonKey = Key('nearby-sheet-launch-button');
      addTearDown(store.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpForUi(tester, frames: 4);
      });

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  key: launchButtonKey,
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

      await tester.tap(find.byKey(launchButtonKey));
      await _pumpForUi(tester);

      expect(find.text('Принять файлы'), findsOneWidget);
      expect(find.text('Отдать файлы'), findsOneWidget);
      expect(find.text('Peer A'), findsNothing);

      await tester.tap(find.text('Принять файлы'));
      await _pumpForUi(tester, frames: 12);

      expect(find.text('Peer A'), findsOneWidget);
      expect(find.text('Nearby transfer'), findsOneWidget);

      await store.resetForEntrySelection();
    },
  );
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
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
    'entry sheet disconnects active session and reopening starts without stale state',
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

      final firstAdapter = FakeNearbyTransferTransportAdapter();
      final firstStore = buildTestNearbyTransferStore(
        readModel: harness.readModel,
        lanAdapter: firstAdapter,
      );
      final secondStore = buildTestNearbyTransferStore(
        readModel: harness.readModel,
      );
      addTearDown(firstStore.dispose);
      addTearDown(secondStore.dispose);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpForUi(tester, frames: 4);
      });

      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(body: NearbyTransferEntrySheet(store: firstStore)),
        ),
      );
      await _pumpForUi(tester);

      expect(find.text('Передача рядом'), findsOneWidget);
      expect(find.text('Принять файлы'), findsOneWidget);
      expect(find.text('Отдать файлы'), findsOneWidget);

      await tester.tap(find.text('Принять файлы'));
      await _pumpForUi(tester);

      expect(find.text('Peer A'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Peer A'));
      await tester.pump();

      firstAdapter.emit(
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

      await tester.tap(find.widgetWithText(OutlinedButton, 'Отключиться'));
      await _pumpForUi(tester);

      expect(find.text('Разорвать соединение?'), findsOneWidget);
      await tester.tap(find.text('Разорвать'));
      await _pumpForUi(tester, frames: 20);

      expect(find.text('Peer A'), findsOneWidget);

      await firstStore.resetForEntrySelection();
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpForUi(tester, frames: 2);
      await tester.pumpWidget(
        buildLocalizedTestApp(
          home: Scaffold(body: NearbyTransferEntrySheet(store: secondStore)),
        ),
      );
      await _pumpForUi(tester);

      expect(find.text('Передача рядом'), findsOneWidget);
      expect(find.text('Соединение подтверждено.'), findsNothing);

      await tester.tap(find.text('Принять файлы'));
      await _pumpForUi(tester);

      expect(
        find.byWidgetPredicate(
          (widget) => widget is ChoiceChip && widget.selected,
        ),
        findsNothing,
      );
      expect(find.text('Peer A'), findsOneWidget);

      await secondStore.resetForEntrySelection();
    },
  );
}

Future<void> _pumpForUi(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/app/discovery_page_entry.dart';
import 'package:landa/features/discovery/presentation/discovery_page.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

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
    'DiscoveryPage renders with injected dependencies and does not own controller disposal',
    (tester) async {
      final desktopWindowService = TrackingDesktopWindowService();
      final transferStorageService = TransferStorageService();

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPage(
            controller: harness.controller,
            readModel: harness.readModel,
            sharedCacheCatalogBridge: harness.sharedCacheCatalogBridge,
            desktopWindowService: desktopWindowService,
            transferStorageService: transferStorageService,
            isBoundaryReady: false,
          ),
        ),
      );

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(harness.controller.disposeCalls, 0);
      expect(desktopWindowService.setMinimizeCalls, 0);
    },
  );

  testWidgets(
    'DiscoveryPageEntry starts injected controller above the screen lifecycle',
    (tester) async {
      final desktopWindowService = TrackingDesktopWindowService();

      await tester.pumpWidget(
        MaterialApp(
          home: DiscoveryPageEntry(
            controller: harness.controller,
            readModel: harness.readModel,
            sharedCacheCatalogBridge: harness.sharedCacheCatalogBridge,
            desktopWindowService: desktopWindowService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Landa devices'), findsOneWidget);
      expect(harness.controller.startCalls, 1);
      expect(harness.sharedCacheCatalogBridge.shareableVideoListCalls, 1);
      expect(desktopWindowService.setMinimizeCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();

      expect(harness.controller.disposeCalls, 0);
    },
  );
}

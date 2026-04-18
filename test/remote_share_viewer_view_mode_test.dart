import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

import 'test_support/remote_share_viewer_test_support.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    harness.discoveryNetworkInterfaceCatalog.replaceInterfaces(
      const <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Office LAN',
          index: 1,
          ipv4Addresses: <String>['192.168.1.10'],
        ),
      ],
    );
    await harness.discoveryNetworkScopeStore.refresh();
    harness.controller.setTestDevices(<DiscoveredDevice>[
      DiscoveredDevice(
        ip: '192.168.1.44',
        deviceName: 'Remote A',
        isAppDetected: true,
        isReachable: true,
        lastSeen: DateTime(2026, 1, 1, 10),
      ),
    ]);
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets(
    'view mode toggle switches between structured and flat projections',
    (tester) async {
      await setLargeSurface(tester);
      registerWidgetCleanup(tester);

      await seedRemoteCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        files: <String>['report.pdf', 'photo.jpg'],
      );

      final coordinator = TestRemoteShareTransferCoordinator(
        previewPathProvider: () async => null,
        sharedCacheCatalog: harness.sharedCacheCatalog,
        sharedCacheIndexStore: harness.sharedCacheIndexStore,
        previewCacheOwner: harness.previewCacheOwner,
        downloadHistoryBoundary: harness.downloadHistoryBoundary,
        settings: harness.readModel.settings,
      );
      addTearDown(coordinator.dispose);

      await pumpRemoteBrowser(
        tester,
        coordinator: coordinator,
        browser: harness.remoteShareBrowser,
        harness: harness,
      );

      expect(find.text('Docs'), findsWidgets);
      expect(
        find.byKey(const Key('remote-download-flat-category-filter-bar')),
        findsNothing,
      );

      await switchToFlatMode(tester);

      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      expect(
        find.byKey(const Key('remote-download-flat-category-filter-bar')),
        findsOneWidget,
      );

      await switchToStructuredMode(tester);

      expect(find.text('Docs'), findsWidgets);
      expect(
        find.byKey(const Key('remote-download-flat-category-filter-bar')),
        findsNothing,
      );
    },
  );
}

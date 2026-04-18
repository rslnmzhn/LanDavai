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
    'structured mode navigates folders and download starts for selected file',
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

      await tester.tap(find.text('Docs').first);
      await pumpForUi(tester, frames: 8);

      expect(find.text('report.pdf'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const Key('remote-download-select-192.168.1.44|cache-a|report.pdf'),
        ),
      );
      await pumpForUi(tester, frames: 4);

      await tester.tap(find.text('Скачать выбранные (1)'));
      await pumpForUi(tester, frames: 8);

      expect(coordinator.downloadCalls, 1);
      expect(coordinator.lastSelectedByCache, <String, Set<String>>{
        'cache-a': <String>{'report.pdf'},
      });
    },
  );
}

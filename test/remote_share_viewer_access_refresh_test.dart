import 'package:flutter_test/flutter_test.dart';

import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
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
    'remote download browser refreshes in place after access snapshot approval',
    (tester) async {
      await setLargeSurface(tester);
      registerWidgetCleanup(tester);

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

      expect(find.text('report.txt'), findsNothing);

      await harness.remoteShareBrowser.applyAccessSnapshot(
        ownerIp: '192.168.1.44',
        ownerDisplayName: 'Remote A',
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        entries: <SharedCatalogEntryItem>[
          SharedCatalogEntryItem(
            cacheId: 'cache-a',
            displayName: 'Docs',
            itemCount: 1,
            totalBytes: 12,
            files: <SharedCatalogFileItem>[
              SharedCatalogFileItem(relativePath: 'report.txt', sizeBytes: 12),
            ],
          ),
        ],
      );
      await pumpForUi(tester, frames: 12);

      expect(find.text('Docs'), findsWidgets);
      await tester.tap(find.text('Docs').first);
      await pumpForUi(tester, frames: 8);
      expect(find.text('report.txt'), findsOneWidget);
    },
  );
}

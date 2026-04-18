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
      DiscoveredDevice(
        ip: '192.168.1.55',
        deviceName: 'Remote B',
        isAppDetected: true,
        isReachable: true,
        lastSeen: DateTime(2026, 1, 1, 10),
      ),
    ]);
    addTearDown(() async {
      await harness.dispose();
    });
  });

  test(
    'remote share projection keeps per-device owner choices and access command wiring',
    () async {
      await seedRemoteCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        filePath: 'report.txt',
      );
      await seedRemoteCatalog(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.55',
        ownerName: 'Remote B',
        cacheId: 'cache-b',
        displayName: 'Media',
        filePath: 'movie.mp4',
        requestId: 'request-2',
        startBrowse: false,
      );

      final projection = harness.remoteShareBrowser.currentBrowseProjection;
      expect(
        projection.owners.map((owner) => owner.name).toList(growable: false),
        <String>['Remote A', 'Remote B'],
      );
      expect(
        projection.owners.map((owner) => owner.ip).toList(growable: false),
        <String>['192.168.1.44', '192.168.1.55'],
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

      await coordinator.requestRemoteShareAccess(
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
      );

      expect(coordinator.accessRequestCalls, 1);
      expect(coordinator.lastAccessRequestOwnerIp, '192.168.1.44');
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
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

  test(
    'remote share browser keeps structured and flat projections aligned',
    () async {
      await seedRemoteCatalogWithFiles(
        browser: harness.remoteShareBrowser,
        ownerIp: '192.168.1.44',
        ownerName: 'Remote A',
        cacheId: 'cache-a',
        displayName: 'Docs',
        files: <String>['report.pdf', 'photo.jpg'],
      );

      final structuredRoot = harness.remoteShareBrowser.buildExplorerDirectory(
        filterKey: '192.168.1.44',
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      expect(
        structuredRoot.entries.folders.map((folder) => folder.name).toList(),
        contains('Docs'),
      );

      final docsFolder = structuredRoot.entries.folders.firstWhere(
        (folder) => folder.name == 'Docs',
      );
      final structuredDocs = harness.remoteShareBrowser.buildExplorerDirectory(
        filterKey: '192.168.1.44',
        folderPath: docsFolder.folderPath,
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      expect(
        structuredDocs.entries.files
            .map((file) => file.virtualPath.split('/').last)
            .toSet(),
        <String>{'report.pdf', 'photo.jpg'},
      );

      final flatRoot = harness.remoteShareBrowser.buildExplorerDirectory(
        filterKey: '192.168.1.44',
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.flat,
        showAllFlatCategories: true,
      );
      expect(
        flatRoot.entries.files
            .map((file) => file.virtualPath.split('/').last)
            .toSet(),
        <String>{'report.pdf', 'photo.jpg'},
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';

import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';

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
    'remote download browser applies access snapshots into the active browse projection',
    () async {
      expect(
        harness.remoteShareBrowser.currentBrowseProjection.options,
        isEmpty,
      );
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

      final projection = harness.remoteShareBrowser.currentBrowseProjection;
      expect(projection.options, hasLength(1));
      expect(
        projection.options.single.entry.files.single.relativePath,
        'report.txt',
      );

      final structuredRoot = harness.remoteShareBrowser.buildExplorerDirectory(
        filterKey: '192.168.1.44',
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      expect(
        structuredRoot.entries.folders.map((folder) => folder.name),
        contains('Docs'),
      );
    },
  );
}

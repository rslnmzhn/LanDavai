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
    'structured mode exposes file tokens that resolve to the current download target',
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
      final docsFolder = structuredRoot.entries.folders.firstWhere(
        (folder) => folder.name == 'Docs',
      );

      final docsDirectory = harness.remoteShareBrowser.buildExplorerDirectory(
        filterKey: '192.168.1.44',
        folderPath: docsFolder.folderPath,
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      final report = docsDirectory.entries.files.firstWhere(
        (file) => file.virtualPath.split('/').last == 'report.pdf',
      );
      final target = harness.remoteShareBrowser.resolveDownloadToken(
        report.sourceToken!,
      );

      expect(target, isNotNull);
      expect(target!.ownerIp, '192.168.1.44');
      expect(target.ownerName, 'Remote A');
      expect(target.selectedRelativePathsByCache, <String, Set<String>>{
        'cache-a': <String>{'report.pdf'},
      });
      expect(target.selectedFolderPrefixesByCache, isEmpty);
      expect(target.sharedLabelsByCache, <String, String>{'cache-a': 'Docs'});
    },
  );
}

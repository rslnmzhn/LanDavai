import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';

import 'test_support/stub_discovery_network_interface_catalog.dart';

void main() {
  test(
    'groups raw interfaces by subnet and defaults to the all scope',
    () async {
      final catalog = StubDiscoveryNetworkInterfaceCatalog(
        const <DiscoveryRawNetworkInterface>[
          DiscoveryRawNetworkInterface(
            name: 'Ethernet',
            index: 1,
            ipv4Addresses: <String>['192.168.1.10'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'vEthernet (Default Switch)',
            index: 2,
            ipv4Addresses: <String>['192.168.1.11'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Tailscale',
            index: 3,
            ipv4Addresses: <String>['100.90.1.10'],
          ),
        ],
      );
      final store = buildTestDiscoveryNetworkScopeStore(
        interfaceCatalog: catalog,
      );

      await store.refresh();

      expect(store.selectedScopeId, DiscoveryNetworkScopeStore.allScopeId);
      expect(store.ranges, hasLength(2));
      expect(
        store.ranges
            .firstWhere((range) => range.subnetCidr == '192.168.1.0/24')
            .localIps,
        <String>['192.168.1.10', '192.168.1.11'],
      );
      expect(store.activeLocalIps, <String>{
        '192.168.1.10',
        '192.168.1.11',
        '100.90.1.10',
      });
      expect(store.preferredLocalIp, '192.168.1.10');
    },
  );

  test(
    'resets back to the all scope when the selected range disappears',
    () async {
      final catalog = StubDiscoveryNetworkInterfaceCatalog(
        const <DiscoveryRawNetworkInterface>[
          DiscoveryRawNetworkInterface(
            name: 'Ethernet',
            index: 1,
            ipv4Addresses: <String>['192.168.1.10'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Tailscale',
            index: 2,
            ipv4Addresses: <String>['100.90.1.10'],
          ),
        ],
      );
      final store = buildTestDiscoveryNetworkScopeStore(
        interfaceCatalog: catalog,
      );

      await store.refresh();
      final tailscaleRange = store.ranges.singleWhere(
        (range) => range.subnetCidr == '100.90.1.0/24',
      );

      expect(store.selectScope(tailscaleRange.id), isTrue);
      expect(store.activeLocalIps, <String>{'100.90.1.10'});
      expect(store.matchesSelectedScope('100.90.1.77'), isTrue);
      expect(store.matchesSelectedScope('192.168.1.77'), isFalse);

      catalog.replaceInterfaces(const <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Ethernet',
          index: 1,
          ipv4Addresses: <String>['192.168.1.10'],
        ),
      ]);

      await store.refresh();

      expect(store.selectedScopeId, DiscoveryNetworkScopeStore.allScopeId);
      expect(store.activeLocalIps, <String>{'192.168.1.10'});
      expect(store.matchesSelectedScope('192.168.1.77'), isTrue);
    },
  );
}

import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';

class StubDiscoveryNetworkInterfaceCatalog
    implements DiscoveryNetworkInterfaceCatalog {
  StubDiscoveryNetworkInterfaceCatalog([
    List<DiscoveryRawNetworkInterface>? interfaces,
  ]) : _interfaces = List<DiscoveryRawNetworkInterface>.from(
         interfaces ?? defaultInterfaces,
       );

  static const List<DiscoveryRawNetworkInterface> defaultInterfaces =
      <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Ethernet',
          index: 1,
          ipv4Addresses: <String>['192.168.1.10'],
        ),
      ];

  List<DiscoveryRawNetworkInterface> _interfaces;

  void replaceInterfaces(List<DiscoveryRawNetworkInterface> interfaces) {
    _interfaces = List<DiscoveryRawNetworkInterface>.from(interfaces);
  }

  @override
  Future<List<DiscoveryRawNetworkInterface>> loadIpv4Interfaces() async {
    return List<DiscoveryRawNetworkInterface>.from(_interfaces);
  }
}

DiscoveryNetworkScopeStore buildTestDiscoveryNetworkScopeStore({
  DiscoveryNetworkInterfaceCatalog? interfaceCatalog,
}) {
  return DiscoveryNetworkScopeStore(
    interfaceCatalog:
        interfaceCatalog ?? StubDiscoveryNetworkInterfaceCatalog(),
  );
}

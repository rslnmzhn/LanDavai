import 'dart:io';

class DiscoveryRawNetworkInterface {
  const DiscoveryRawNetworkInterface({
    required this.name,
    required this.index,
    required this.ipv4Addresses,
  });

  final String name;
  final int index;
  final List<String> ipv4Addresses;
}

abstract class DiscoveryNetworkInterfaceCatalog {
  Future<List<DiscoveryRawNetworkInterface>> loadIpv4Interfaces();
}

class SystemDiscoveryNetworkInterfaceCatalog
    implements DiscoveryNetworkInterfaceCatalog {
  @override
  Future<List<DiscoveryRawNetworkInterface>> loadIpv4Interfaces() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final snapshots = <DiscoveryRawNetworkInterface>[];
    for (final interface in interfaces) {
      final ipv4Addresses =
          interface.addresses
              .where((address) => address.type == InternetAddressType.IPv4)
              .map((address) => address.address)
              .where((address) => _isValidIpv4(address))
              .toSet()
              .toList(growable: false)
            ..sort(_compareIp);
      if (ipv4Addresses.isEmpty) {
        continue;
      }
      snapshots.add(
        DiscoveryRawNetworkInterface(
          name: interface.name,
          index: interface.index,
          ipv4Addresses: ipv4Addresses,
        ),
      );
    }

    snapshots.sort((a, b) {
      final indexComparison = a.index.compareTo(b.index);
      if (indexComparison != 0) {
        return indexComparison;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return snapshots;
  }

  bool _isValidIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }
    }
    return true;
  }

  int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < 4; i += 1) {
      final comparison = aParts[i].compareTo(bParts[i]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }
}

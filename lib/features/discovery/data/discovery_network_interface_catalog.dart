import 'dart:io';

import 'lan_interface_filter.dart';

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
  SystemDiscoveryNetworkInterfaceCatalog({
    bool? isMobileOverride,
    Future<List<NetworkInterface>> Function()? interfaceLister,
  }) : _isMobileOverride = isMobileOverride,
       _interfaceLister = interfaceLister;

  final bool? _isMobileOverride;
  final Future<List<NetworkInterface>> Function()? _interfaceLister;

  bool get _isMobile =>
      _isMobileOverride ?? (Platform.isAndroid || Platform.isIOS);

  @override
  Future<List<DiscoveryRawNetworkInterface>> loadIpv4Interfaces() async {
    final interfaces = await (_interfaceLister != null
        ? _interfaceLister()
        : NetworkInterface.list(
            type: InternetAddressType.IPv4,
            includeLoopback: false,
            includeLinkLocal: false,
          ));

    final snapshots = <DiscoveryRawNetworkInterface>[];
    for (final interface in interfaces) {
      if (_isMobile && isNonLanInterfaceName(interface.name)) {
        continue;
      }
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

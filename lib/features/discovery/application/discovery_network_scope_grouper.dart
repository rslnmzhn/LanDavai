import '../data/discovery_network_interface_catalog.dart';
import 'discovery_network_scope.dart';

class DiscoveryNetworkScopeGrouper {
  static const String allScopeId = 'all';

  DiscoveryNetworkScopeSnapshot group(
    List<DiscoveryRawNetworkInterface> interfaces,
  ) {
    final rangeById = <String, _RangeBuilder>{};
    final allLocalIps = <String>{};
    String? preferredIp;
    var preferredScore = -100000;

    for (final interface in interfaces) {
      for (final address in interface.ipv4Addresses) {
        final subnetCidr = subnetCidrForIp(address);
        if (subnetCidr == null) {
          continue;
        }
        final score = _scoreAddress(interface.name, address);
        allLocalIps.add(address);
        if (score > preferredScore) {
          preferredScore = score;
          preferredIp = address;
        }
        final rangeId = rangeIdForSubnet(subnetCidr);
        final builder = rangeById.putIfAbsent(
          rangeId,
          () => _RangeBuilder(id: rangeId, subnetCidr: subnetCidr),
        );
        builder.add(ip: address, adapterName: interface.name, score: score);
      }
    }

    final ranges =
        rangeById.values
            .map((builder) => builder.build())
            .toList(growable: false)
          ..sort((a, b) {
            final scoreComparison = _scoreRange(b).compareTo(_scoreRange(a));
            if (scoreComparison != 0) {
              return scoreComparison;
            }
            return a.subnetCidr.compareTo(b.subnetCidr);
          });

    final allIps = allLocalIps.toList(growable: false)..sort(_compareIp);
    return DiscoveryNetworkScopeSnapshot(
      ranges: ranges,
      allLocalIps: allIps,
      preferredIp: preferredIp,
    );
  }

  String? subnetCidrForIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return null;
    }
    final octets = <int>[];
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return null;
      }
      octets.add(octet);
    }
    return '${octets[0]}.${octets[1]}.${octets[2]}.0/24';
  }

  String? rangeIdForIp(String ip) {
    final subnetCidr = subnetCidrForIp(ip);
    if (subnetCidr == null) {
      return null;
    }
    return rangeIdForSubnet(subnetCidr);
  }

  String rangeIdForSubnet(String subnetCidr) => 'subnet:$subnetCidr';

  int _scoreRange(DiscoveryNetworkRange range) {
    final preferredIp = range.preferredIp;
    for (final localIp in range.localIps) {
      if (localIp == preferredIp) {
        return _scoreAddress(
          range.adapterNames.isEmpty ? '' : range.adapterNames.first,
          localIp,
        );
      }
    }
    return -100000;
  }

  int _scoreAddress(String interfaceName, String ip) {
    final lower = interfaceName.toLowerCase();
    var score = 0;

    if (_isLikelyVirtualInterface(lower)) {
      score -= 400;
    } else {
      score += 100;
    }

    if (_isInSubnet(ip, 192, 168)) {
      score += 220;
    } else if (_isInSubnet(ip, 10, null)) {
      score += 170;
    } else if (_isInRange172Private(ip)) {
      score += 120;
    } else if (_isInSubnet(ip, 100, null)) {
      score += 60;
    } else {
      score += 20;
    }

    if (lower.contains('wi-fi') ||
        lower.contains('wifi') ||
        lower.contains('wlan') ||
        lower.contains('ethernet') ||
        lower.contains('eth')) {
      score += 50;
    }

    return score;
  }

  bool _isLikelyVirtualInterface(String lowerName) {
    const hints = <String>[
      'loopback',
      'docker',
      'vmware',
      'virtual',
      'vethernet',
      'hyper-v',
      'vbox',
      'wsl',
      'tailscale',
      'zerotier',
      'hamachi',
      'tun',
      'tap',
      'bridge',
    ];
    return hints.any(lowerName.contains);
  }

  bool _isInSubnet(String ip, int first, int? second) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final firstOctet = int.tryParse(parts[0]);
    final secondOctet = int.tryParse(parts[1]);
    if (firstOctet == null || secondOctet == null) {
      return false;
    }
    if (firstOctet != first) {
      return false;
    }
    if (second != null && secondOctet != second) {
      return false;
    }
    return true;
  }

  bool _isInRange172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) {
      return false;
    }
    return first == 172 && second >= 16 && second <= 31;
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

class _RangeBuilder {
  _RangeBuilder({required this.id, required this.subnetCidr});

  final String id;
  final String subnetCidr;
  final Set<String> _localIps = <String>{};
  final Set<String> _adapterNames = <String>{};
  String? _preferredIp;
  String? _preferredAdapterName;
  var _preferredScore = -100000;

  void add({
    required String ip,
    required String adapterName,
    required int score,
  }) {
    _localIps.add(ip);
    final normalizedName = adapterName.trim();
    if (normalizedName.isNotEmpty) {
      _adapterNames.add(normalizedName);
    }
    if (score > _preferredScore) {
      _preferredScore = score;
      _preferredIp = ip;
      _preferredAdapterName = normalizedName;
    }
  }

  DiscoveryNetworkRange build() {
    final localIps = _localIps.toList(growable: false)..sort(_compareIp);
    final adapterNames = _adapterNames.toList(growable: false)
      ..sort((a, b) {
        if (_preferredAdapterName != null) {
          if (a == _preferredAdapterName) {
            return -1;
          }
          if (b == _preferredAdapterName) {
            return 1;
          }
        }
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return DiscoveryNetworkRange(
      id: id,
      subnetCidr: subnetCidr,
      localIps: localIps,
      adapterNames: adapterNames,
      preferredIp: _preferredIp ?? localIps.first,
    );
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

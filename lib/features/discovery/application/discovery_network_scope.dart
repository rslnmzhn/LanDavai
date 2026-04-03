import 'package:flutter/foundation.dart';

@immutable
class DiscoveryNetworkRange {
  const DiscoveryNetworkRange({
    required this.id,
    required this.subnetCidr,
    required this.localIps,
    required this.adapterNames,
    required this.preferredIp,
  });

  final String id;
  final String subnetCidr;
  final List<String> localIps;
  final List<String> adapterNames;
  final String preferredIp;

  @override
  bool operator ==(Object other) {
    return other is DiscoveryNetworkRange &&
        other.id == id &&
        other.subnetCidr == subnetCidr &&
        listEquals(other.localIps, localIps) &&
        listEquals(other.adapterNames, adapterNames) &&
        other.preferredIp == preferredIp;
  }

  @override
  int get hashCode => Object.hash(
    id,
    subnetCidr,
    Object.hashAll(localIps),
    Object.hashAll(adapterNames),
    preferredIp,
  );
}

@immutable
class DiscoveryNetworkScopeSnapshot {
  const DiscoveryNetworkScopeSnapshot({
    required this.ranges,
    required this.allLocalIps,
    required this.preferredIp,
  });

  final List<DiscoveryNetworkRange> ranges;
  final List<String> allLocalIps;
  final String? preferredIp;

  @override
  bool operator ==(Object other) {
    return other is DiscoveryNetworkScopeSnapshot &&
        listEquals(other.ranges, ranges) &&
        listEquals(other.allLocalIps, allLocalIps) &&
        other.preferredIp == preferredIp;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(ranges),
    Object.hashAll(allLocalIps),
    preferredIp,
  );
}

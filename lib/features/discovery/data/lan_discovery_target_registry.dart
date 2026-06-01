import 'dart:io';

import 'lan_internet_peer_endpoint.dart';

class LanDiscoveryTargetRegistry {
  LanDiscoveryTargetRegistry({
    required bool Function(String ip) isUsableTargetIp,
    required int discoveryPort,
  }) : _isUsableTargetIp = isUsableTargetIp,
       _discoveryPort = discoveryPort;

  final bool Function(String ip) _isUsableTargetIp;
  final int _discoveryPort;

  List<InternetPeerEndpoint> _internetPeers = const <InternetPeerEndpoint>[];
  Set<String> _internetPeerIpAllowlist = <String>{};
  Set<String> _configuredTargetIps = <String>{};

  List<InternetPeerEndpoint> get internetPeers =>
      List<InternetPeerEndpoint>.unmodifiable(_internetPeers);

  Set<String> get internetPeerIpAllowlist =>
      Set<String>.unmodifiable(_internetPeerIpAllowlist);

  Set<String> get configuredTargetIps =>
      Set<String>.unmodifiable(_configuredTargetIps);

  void updateInternetPeers(Iterable<InternetPeerEndpoint> peers) {
    final normalized = <InternetPeerEndpoint>[];
    final ipAllow = <String>{};
    for (final peer in peers) {
      final host = peer.host.trim();
      final friendId = peer.friendId.trim();
      if (host.isEmpty || friendId.isEmpty) {
        continue;
      }
      final parsedIp = InternetAddress.tryParse(host);
      if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
        continue;
      }
      final port = peer.port <= 0 || peer.port > 65535
          ? _discoveryPort
          : peer.port;
      normalized.add(
        InternetPeerEndpoint(
          friendId: friendId,
          host: parsedIp.address,
          port: port,
        ),
      );
      ipAllow.add(parsedIp.address);
    }
    _internetPeers = List<InternetPeerEndpoint>.unmodifiable(normalized);
    _internetPeerIpAllowlist = Set<String>.unmodifiable(ipAllow);
  }

  void updateConfiguredTargetIps(Iterable<String> ips) {
    _configuredTargetIps = Set<String>.unmodifiable(
      ips
          .map((ip) => InternetAddress.tryParse(ip.trim())?.address)
          .whereType<String>()
          .where(_isUsableTargetIp),
    );
  }

  void clearConfiguredTargetIps() {
    _configuredTargetIps = <String>{};
  }
}

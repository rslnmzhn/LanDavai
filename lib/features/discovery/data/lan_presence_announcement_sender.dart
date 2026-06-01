import 'dart:convert';
import 'dart:io';

import 'discovery_transport_adapter.dart';
import 'lan_broadcast_address.dart';
import 'lan_internet_peer_endpoint.dart';
import 'lan_packet_codec.dart' show LanPacketCodec;

class LanPresenceAnnouncementSender {
  const LanPresenceAnnouncementSender({
    required DiscoveryTransportAdapter transportAdapter,
    required LanPacketCodec packetCodec,
    required int discoveryPort,
    required void Function(String message) log,
  }) : _transportAdapter = transportAdapter,
       _packetCodec = packetCodec,
       _discoveryPort = discoveryPort,
       _log = log;

  final DiscoveryTransportAdapter _transportAdapter;
  final LanPacketCodec _packetCodec;
  final int _discoveryPort;
  final void Function(String message) _log;

  Future<void> announce({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
    required Iterable<InternetPeerEndpoint> internetPeers,
    required Iterable<String> configuredTargetIps,
    int? nearbyTransferPort,
  }) async {
    final request = _packetCodec.encodeDiscoveryRequest(
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
      nearbyTransferPort: nearbyTransferPort,
    );
    final bytes = utf8.encode(request);
    final localIps = _transportAdapter.localIps;

    _log('Broadcasting discover packet');
    _transportAdapter.send(
      bytes: bytes,
      address: InternetAddress('255.255.255.255'),
      port: _discoveryPort,
      context: 'discover-broadcast',
    );

    for (final localIp in localIps) {
      final broadcast = lanBroadcastAddressFor(localIp);
      if (broadcast != null) {
        _transportAdapter.send(
          bytes: bytes,
          address: broadcast,
          port: _discoveryPort,
          context: 'discover-subnet',
        );
        _log('Discover packet sent to ${broadcast.address}');
      }
    }

    for (final peer in internetPeers) {
      final address = InternetAddress.tryParse(peer.host);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      _transportAdapter.send(
        bytes: bytes,
        address: address,
        port: peer.port,
        context: 'discover-friend-endpoint',
      );
      _log('Discover packet sent to friend endpoint ${peer.host}:${peer.port}');
    }

    for (final targetIp in configuredTargetIps) {
      final address = InternetAddress.tryParse(targetIp);
      if (address == null || address.type != InternetAddressType.IPv4) {
        continue;
      }
      _transportAdapter.send(
        bytes: bytes,
        address: address,
        port: _discoveryPort,
        context: 'discover-configured-target',
      );
      _log('Discover packet sent to configured target $targetIp');
    }
  }
}

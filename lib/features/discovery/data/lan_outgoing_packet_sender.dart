import 'dart:io';

import 'discovery_transport_adapter.dart';
import 'lan_packet_codec_models.dart';

class LanOutgoingPacketSender {
  const LanOutgoingPacketSender({
    required DiscoveryTransportAdapter transportAdapter,
    required InternetAddress? Function(String rawTargetIp) resolveTargetIp,
    required int port,
    required void Function(String message) log,
  }) : _transportAdapter = transportAdapter,
       _resolveTargetIp = resolveTargetIp,
       _port = port,
       _log = log;

  final DiscoveryTransportAdapter _transportAdapter;
  final InternetAddress? Function(String rawTargetIp) _resolveTargetIp;
  final int _port;
  final void Function(String message) _log;

  Future<void> sendPacket({
    required String prefix,
    required EncodedLanPacket? packet,
    required String targetIp,
  }) async {
    if (packet == null) {
      _log('Skipping $prefix packet: codec rejected payload.');
      return;
    }
    final targetAddress = _resolveTargetIp(targetIp);
    if (targetAddress == null) {
      _log('Skipping $prefix packet: invalid target IP "$targetIp".');
      return;
    }
    _transportAdapter.send(
      bytes: packet.bytes,
      address: targetAddress,
      port: _port,
      context: packet.prefix,
    );
  }

  Future<void> sendPackets({
    required String prefix,
    required List<EncodedLanPacket> packets,
    required String targetIp,
  }) async {
    final targetAddress = _resolveTargetIp(targetIp);
    if (targetAddress == null) {
      _log('Skipping $prefix packet: invalid target IP "$targetIp".');
      return;
    }
    for (final packet in packets) {
      _transportAdapter.send(
        bytes: packet.bytes,
        address: targetAddress,
        port: _port,
        context: packet.prefix,
      );
    }
  }
}

import 'dart:convert';

import 'lan_packet_codec.dart' show LanPacketCodec;
import 'lan_packet_codec_models.dart';
import 'lan_sender_allowlist_policy.dart';

class LanAcceptedIncomingPacket {
  const LanAcceptedIncomingPacket({
    required this.packet,
    required this.senderIp,
    required this.observedAt,
  });

  final LanInboundPacket packet;
  final String senderIp;
  final DateTime observedAt;
}

class LanIncomingDatagramAdmission {
  const LanIncomingDatagramAdmission({
    required LanPacketCodec packetCodec,
    required LanSenderAllowlistPolicy senderAllowlistPolicy,
    required void Function(String message) log,
  }) : _packetCodec = packetCodec,
       _senderAllowlistPolicy = senderAllowlistPolicy,
       _log = log;

  final LanPacketCodec _packetCodec;
  final LanSenderAllowlistPolicy _senderAllowlistPolicy;
  final void Function(String message) _log;

  LanAcceptedIncomingPacket? admit({
    required List<int> bytes,
    required String senderIp,
    required Set<String> localIps,
    required String localInstanceId,
    required Set<String> configuredTargetIps,
    required Set<String> internetPeerIpAllowlist,
    DateTime? observedAt,
  }) {
    if (!_senderAllowlistPolicy.isUsablePacketSenderIp(senderIp)) {
      _log('Ignoring packet from invalid sender IP: $senderIp');
      return null;
    }

    if (localIps.contains(senderIp)) {
      return null;
    }

    final message = utf8.decode(bytes, allowMalformed: true);
    final packet = _packetCodec.decodeIncomingPacket(message);
    if (packet == null || packet.instanceId == localInstanceId) {
      return null;
    }

    final acceptedAt = observedAt ?? DateTime.now();
    if (!_senderAllowlistPolicy.isAllowedSenderForPacket(
      packet: packet,
      senderIp: senderIp,
      localIps: localIps,
      configuredTargetIps: configuredTargetIps,
      internetPeerIpAllowlist: internetPeerIpAllowlist,
      now: acceptedAt,
      log: _log,
    )) {
      _log('Ignoring packet from foreign subnet: $senderIp');
      return null;
    }

    return LanAcceptedIncomingPacket(
      packet: packet,
      senderIp: senderIp,
      observedAt: acceptedAt,
    );
  }
}

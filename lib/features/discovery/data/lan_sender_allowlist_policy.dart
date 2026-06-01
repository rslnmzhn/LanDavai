import 'dart:io';

import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanSenderAllowlistPolicy {
  LanSenderAllowlistPolicy({
    this.presenceAllowedSenderTtl = const Duration(seconds: 20),
  });

  final Duration presenceAllowedSenderTtl;
  final Map<String, DateTime> _presenceAllowedSenders = <String, DateTime>{};

  bool isUsablePacketSenderIp(String ip) {
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return false;
    }
    if (parsed.address == '0.0.0.0' ||
        parsed.isLoopback ||
        parsed.isMulticast) {
      return false;
    }
    return parsed.address != '255.255.255.255';
  }

  bool isAllowedSenderForPacket({
    required LanInboundPacket packet,
    required String senderIp,
    required Set<String> localIps,
    required Set<String> configuredTargetIps,
    required Set<String> internetPeerIpAllowlist,
    DateTime? now,
    void Function(String message)? log,
  }) {
    prunePresenceAllowedSenders(now);
    if (localIps.isEmpty ||
        localIps.any((localIp) => _isSame24Subnet(senderIp, localIp)) ||
        internetPeerIpAllowlist.contains(senderIp) ||
        configuredTargetIps.contains(senderIp) ||
        _presenceAllowedSenders.containsKey(senderIp)) {
      return true;
    }

    if (packet is LanDiscoveryPresencePacket &&
        packet.prefix == lanDiscoverPrefix) {
      log?.call('Allowing discover request from non-local sender: $senderIp');
      return true;
    }

    return false;
  }

  void markPresenceAllowedSender(String senderIp, DateTime observedAt) {
    _presenceAllowedSenders[senderIp] = observedAt;
  }

  void prunePresenceAllowedSenders([DateTime? now]) {
    final observedNow = now ?? DateTime.now();
    _presenceAllowedSenders.removeWhere(
      (_, observedAt) =>
          observedNow.difference(observedAt) > presenceAllowedSenderTtl,
    );
  }

  void clear() {
    _presenceAllowedSenders.clear();
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

  bool _isSame24Subnet(String ip, String baseIp) {
    if (!_isValidIpv4(ip) || !_isValidIpv4(baseIp)) {
      return false;
    }
    final a = ip.split('.');
    final b = baseIp.split('.');
    return a[0] == b[0] && a[1] == b[1] && a[2] == b[2];
  }
}

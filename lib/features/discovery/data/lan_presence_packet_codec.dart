import 'dart:convert';
import 'dart:io';

import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanPresencePacketCodec {
  LanPresencePacketCodec({String? operatingSystem, String? deviceType})
    : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
      _deviceType = deviceType ?? _resolveLocalDeviceType();

  final String _operatingSystem;
  final String _deviceType;

  String encodeDiscoveryRequest({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    return _encodeDiscoveryPacket(
      prefix: lanDiscoverPrefix,
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
    );
  }

  String encodeDiscoveryResponse({
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    return _encodeDiscoveryPacket(
      prefix: lanResponsePrefix,
      instanceId: instanceId,
      deviceName: deviceName,
      localPeerId: localPeerId,
    );
  }

  LanDiscoveryPresencePacket? decodeDiscoveryPacket(String message) {
    final parts = message.split('|');
    if (parts.isEmpty) {
      return null;
    }

    final prefix = parts[0].trim();
    if (prefix != lanDiscoverPrefix && prefix != lanResponsePrefix) {
      return null;
    }

    if (parts.length == 2) {
      final legacyName = parts[1].trim();
      return LanDiscoveryPresencePacket(
        prefix: prefix,
        instanceId: 'legacy',
        deviceName: legacyName.isEmpty ? 'Unknown device' : legacyName,
      );
    }

    if (parts.length >= 3) {
      final instanceId = parts[1].trim();
      final rawPayload = parts.sublist(2).join('|').trim();
      final decodedPayload = _tryDecodeDiscoveryPayload(rawPayload);
      if (decodedPayload != null) {
        return LanDiscoveryPresencePacket(
          prefix: prefix,
          instanceId: instanceId,
          deviceName: decodedPayload.deviceName,
          operatingSystem: decodedPayload.operatingSystem,
          deviceType: decodedPayload.deviceType,
          peerId: decodedPayload.peerId,
        );
      }

      return LanDiscoveryPresencePacket(
        prefix: prefix,
        instanceId: instanceId,
        deviceName: rawPayload.isEmpty ? 'Unknown device' : rawPayload,
      );
    }

    return null;
  }

  String _encodeDiscoveryPacket({
    required String prefix,
    required String instanceId,
    required String deviceName,
    required String localPeerId,
  }) {
    final payload = <String, Object>{
      'name': deviceName,
      'os': _operatingSystem,
      'type': _deviceType,
      'peerId': localPeerId,
    };
    final encodedPayload = base64UrlEncode(utf8.encode(jsonEncode(payload)));
    return '$prefix|$instanceId|$encodedPayload';
  }

  _DiscoveryIdentity? _tryDecodeDiscoveryPayload(String encodedPayload) {
    if (encodedPayload.isEmpty) {
      return null;
    }
    try {
      final bytes = base64Url.decode(encodedPayload);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final rawName = decoded['name'] as String?;
      final rawOs = decoded['os'] as String?;
      final rawType = decoded['type'] as String?;
      final rawPeerId = decoded['peerId'] as String?;
      return _DiscoveryIdentity(
        deviceName: (rawName == null || rawName.trim().isEmpty)
            ? 'Unknown device'
            : rawName.trim(),
        operatingSystem: _normalizeDiscoveryText(rawOs),
        deviceType: _normalizeDiscoveryText(rawType),
        peerId: _normalizeDiscoveryText(rawPeerId),
      );
    } catch (_) {
      return null;
    }
  }

  String? _normalizeDiscoveryText(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static String _resolveLocalDeviceType() {
    if (Platform.isAndroid || Platform.isIOS) {
      return 'phone';
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return 'pc';
    }
    return 'unknown';
  }
}

class _DiscoveryIdentity {
  const _DiscoveryIdentity({
    required this.deviceName,
    this.operatingSystem,
    this.deviceType,
    this.peerId,
  });

  final String deviceName;
  final String? operatingSystem;
  final String? deviceType;
  final String? peerId;
}

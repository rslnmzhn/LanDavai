import 'dart:convert';

import 'nearby_transfer_transport_adapter.dart';

class NearbyTransferQrPayload {
  const NearbyTransferQrPayload({
    required this.deviceId,
    required this.sessionId,
    required this.transportMode,
    required this.transportInfo,
  });

  final String deviceId;
  final String sessionId;
  final NearbyTransferMode transportMode;
  final Map<String, Object?> transportInfo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'deviceId': deviceId,
      'sessionId': sessionId,
      'transportMode': transportMode.name,
      'transportInfo': transportInfo,
    };
  }

  static NearbyTransferQrPayload? fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String?;
    final sessionId = json['sessionId'] as String?;
    final modeName = json['transportMode'] as String?;
    final transportInfo = json['transportInfo'];
    if (deviceId == null ||
        deviceId.trim().isEmpty ||
        sessionId == null ||
        sessionId.trim().isEmpty ||
        modeName == null ||
        transportInfo is! Map<String, dynamic>) {
      return null;
    }

    NearbyTransferMode? mode;
    for (final value in NearbyTransferMode.values) {
      if (value.name == modeName) {
        mode = value;
        break;
      }
    }
    if (mode == null) {
      return null;
    }

    return NearbyTransferQrPayload(
      deviceId: deviceId.trim(),
      sessionId: sessionId.trim(),
      transportMode: mode,
      transportInfo: Map<String, Object?>.from(transportInfo),
    );
  }
}

class NearbyTransferLanFallbackQrConnection {
  const NearbyTransferLanFallbackQrConnection({
    required this.host,
    required this.port,
    required this.sessionId,
  });

  final String host;
  final int port;
  final String sessionId;
}

class NearbyTransferQrCodec {
  static const String schemePrefix = 'landa-nearby://';

  const NearbyTransferQrCodec();

  String encode(NearbyTransferQrPayload payload) {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(payload.toJson())));
    return '$schemePrefix$encoded';
  }

  NearbyTransferQrPayload? decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(schemePrefix)) {
      return null;
    }
    final encoded = trimmed.substring(schemePrefix.length).trim();
    if (encoded.isEmpty) {
      return null;
    }

    try {
      final decoded = utf8.decode(base64Url.decode(encoded));
      final json = jsonDecode(decoded);
      if (json is! Map<String, dynamic>) {
        return null;
      }
      return NearbyTransferQrPayload.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  NearbyTransferLanFallbackQrConnection? decodeLanFallbackConnection(
    String raw,
  ) {
    final payload = decode(raw);
    if (payload == null ||
        payload.transportMode != NearbyTransferMode.lanFallback) {
      return null;
    }

    final host = payload.transportInfo['host'] as String?;
    final rawPort = payload.transportInfo['port'];
    final transportSessionId = payload.transportInfo['sessionId'] as String?;
    final normalizedHost = host?.trim() ?? '';
    final normalizedSessionId = payload.sessionId.trim();
    final normalizedTransportSessionId = transportSessionId?.trim() ?? '';
    final port = rawPort is num ? rawPort.toInt() : null;

    if (normalizedHost.isEmpty ||
        port == null ||
        port <= 0 ||
        port > 65535 ||
        normalizedSessionId.isEmpty ||
        normalizedTransportSessionId.isEmpty ||
        normalizedSessionId != normalizedTransportSessionId) {
      return null;
    }

    return NearbyTransferLanFallbackQrConnection(
      host: normalizedHost,
      port: port,
      sessionId: normalizedSessionId,
    );
  }
}

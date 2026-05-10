import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';
import 'package:landa/features/nearby_transfer/data/qr_payload_codec.dart';

void main() {
  test('encodes and decodes lan fallback payload with direct socket info', () {
    const codec = NearbyTransferQrCodec();
    const payload = NearbyTransferQrPayload(
      deviceId: 'device-a',
      sessionId: 'session-1',
      transportMode: NearbyTransferMode.lanFallback,
      transportInfo: <String, Object?>{
        'host': '192.168.0.23',
        'port': 45321,
        'sessionId': 'session-1',
      },
    );

    final encoded = codec.encode(payload);
    final decoded = codec.decode(encoded);

    expect(decoded, isNotNull);
    expect(decoded!.deviceId, 'device-a');
    expect(decoded.sessionId, 'session-1');
    expect(decoded.transportMode, NearbyTransferMode.lanFallback);
    expect(decoded.transportInfo['host'], '192.168.0.23');
    expect(decoded.transportInfo['port'], 45321);
    expect(decoded.transportInfo['sessionId'], 'session-1');
    final connection = codec.decodeLanFallbackConnection(encoded);
    expect(connection, isNotNull);
    expect(connection!.host, '192.168.0.23');
    expect(connection.port, 45321);
    expect(connection.sessionId, 'session-1');
  });

  test('rejects lan fallback QR payloads with incomplete socket info', () {
    const codec = NearbyTransferQrCodec();
    const missingSessionInfo = NearbyTransferQrPayload(
      deviceId: 'device-a',
      sessionId: 'session-1',
      transportMode: NearbyTransferMode.lanFallback,
      transportInfo: <String, Object?>{
        'host': '192.168.0.23',
        'port': 45321,
      },
    );
    const invalidPort = NearbyTransferQrPayload(
      deviceId: 'device-a',
      sessionId: 'session-1',
      transportMode: NearbyTransferMode.lanFallback,
      transportInfo: <String, Object?>{
        'host': '192.168.0.23',
        'port': 70000,
        'sessionId': 'session-1',
      },
    );
    const mismatchedSession = NearbyTransferQrPayload(
      deviceId: 'device-a',
      sessionId: 'session-1',
      transportMode: NearbyTransferMode.lanFallback,
      transportInfo: <String, Object?>{
        'host': '192.168.0.23',
        'port': 45321,
        'sessionId': 'other-session',
      },
    );

    expect(
      codec.decodeLanFallbackConnection(codec.encode(missingSessionInfo)),
      isNull,
    );
    expect(codec.decodeLanFallbackConnection(codec.encode(invalidPort)), isNull);
    expect(
      codec.decodeLanFallbackConnection(codec.encode(mismatchedSession)),
      isNull,
    );
  });

  test('ignores non nearby-transfer QR payloads', () {
    const codec = NearbyTransferQrCodec();

    expect(codec.decode('https://example.com'), isNull);
    expect(codec.decode(''), isNull);
  });
}

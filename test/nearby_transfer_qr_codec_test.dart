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
  });

  test('ignores non nearby-transfer QR payloads', () {
    const codec = NearbyTransferQrCodec();

    expect(codec.decode('https://example.com'), isNull);
    expect(codec.decode(''), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_capability_service.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_mode_resolver.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_transport_adapter.dart';

void main() {
  test('resolves wifi direct when capability is available', () {
    const resolver = NearbyTransferModeResolver();

    final mode = resolver.resolve(
      const NearbyTransferCapabilitySnapshot(
        wifiDirectSupported: true,
        liveQrScannerSupported: true,
      ),
    );

    expect(mode, NearbyTransferMode.wifiDirect);
  });

  test('falls back to lan when wifi direct is unavailable', () {
    const resolver = NearbyTransferModeResolver();

    final mode = resolver.resolve(
      const NearbyTransferCapabilitySnapshot(
        wifiDirectSupported: false,
        liveQrScannerSupported: false,
      ),
    );

    expect(mode, NearbyTransferMode.lanFallback);
  });
}

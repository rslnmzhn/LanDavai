import 'dart:io';

class NearbyTransferCapabilitySnapshot {
  const NearbyTransferCapabilitySnapshot({
    required this.wifiDirectSupported,
    required this.liveQrScannerSupported,
  });

  final bool wifiDirectSupported;
  final bool liveQrScannerSupported;
}

class NearbyTransferCapabilityService {
  const NearbyTransferCapabilityService({required this.wifiDirectSupported});

  final bool wifiDirectSupported;

  NearbyTransferCapabilitySnapshot snapshot() {
    return NearbyTransferCapabilitySnapshot(
      wifiDirectSupported: wifiDirectSupported,
      liveQrScannerSupported: Platform.isAndroid || Platform.isIOS,
    );
  }
}

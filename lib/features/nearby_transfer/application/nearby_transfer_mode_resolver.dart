import '../data/nearby_transfer_transport_adapter.dart';
import 'nearby_transfer_capability_service.dart';

class NearbyTransferModeResolver {
  const NearbyTransferModeResolver();

  NearbyTransferMode resolve(NearbyTransferCapabilitySnapshot capabilities) {
    return capabilities.wifiDirectSupported
        ? NearbyTransferMode.wifiDirect
        : NearbyTransferMode.lanFallback;
  }
}

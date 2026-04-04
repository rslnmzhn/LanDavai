import '../../discovery/application/discovery_read_model.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferCandidateProjection {
  const NearbyTransferCandidateProjection({
    required DiscoveryReadModel readModel,
  }) : _readModel = readModel;

  final DiscoveryReadModel _readModel;

  List<NearbyTransferCandidateDevice> snapshotCandidates() {
    final devices = _readModel.devices
        .where(
          (device) =>
              device.isAppDetected &&
              device.isReachable &&
              device.isNearbyTransferAvailable &&
              device.nearbyTransferPort != null,
        )
        .toList(growable: false);
    devices.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return List<NearbyTransferCandidateDevice>.unmodifiable(
      devices
          .map(
            (device) => NearbyTransferCandidateDevice(
              id: device.macAddress ?? device.ip,
              deviceId: device.macAddress ?? device.ip,
              displayName: device.displayName,
              host: device.ip,
              port: device.nearbyTransferPort,
            ),
          )
          .toList(growable: false),
    );
  }
}

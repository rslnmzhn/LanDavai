import '../domain/discovered_device.dart';

class DiscoveryPresenceExpiryPolicy {
  const DiscoveryPresenceExpiryPolicy({
    required this.appPresenceTtl,
    required this.nearbyAvailabilityTtl,
  });

  final Duration appPresenceTtl;
  final Duration nearbyAvailabilityTtl;

  DiscoveryPresenceExpiryResult expire({
    required DateTime now,
    required DiscoveredDevice device,
  }) {
    var nextDevice = device;
    final appPresenceObservedAt = nextDevice.appPresenceObservedAt;
    final nearbyAvailabilityObservedAt =
        nextDevice.nearbyAvailabilityObservedAt;

    if (nextDevice.isNearbyTransferAvailable &&
        (nearbyAvailabilityObservedAt == null ||
            now.difference(nearbyAvailabilityObservedAt) >
                nearbyAvailabilityTtl)) {
      nextDevice = nextDevice.copyWith(
        isNearbyTransferAvailable: false,
        nearbyTransferPort: null,
        nearbyAvailabilityObservedAt: null,
      );
    }

    if (nextDevice.isAppDetected &&
        (appPresenceObservedAt == null ||
            now.difference(appPresenceObservedAt) > appPresenceTtl)) {
      final hadFreshReachabilitySignal =
          appPresenceObservedAt != null &&
          nextDevice.lastSeen.isAfter(appPresenceObservedAt);
      nextDevice = nextDevice.copyWith(
        isAppDetected: false,
        appPresenceObservedAt: null,
        isNearbyTransferAvailable: false,
        nearbyTransferPort: null,
        nearbyAvailabilityObservedAt: null,
        isReachable: hadFreshReachabilitySignal
            ? nextDevice.isReachable
            : false,
      );
    }

    return DiscoveryPresenceExpiryResult(
      device: nextDevice,
      shouldRemove: !nextDevice.isAppDetected && !nextDevice.isReachable,
      changed: !identical(nextDevice, device),
    );
  }
}

class DiscoveryPresenceExpiryResult {
  const DiscoveryPresenceExpiryResult({
    required this.device,
    required this.shouldRemove,
    required this.changed,
  });

  final DiscoveredDevice device;
  final bool shouldRemove;
  final bool changed;
}

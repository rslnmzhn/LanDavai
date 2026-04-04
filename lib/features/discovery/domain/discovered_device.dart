enum DeviceCategory { phone, pc, unknown }

class DiscoveredDevice {
  DiscoveredDevice({
    required this.ip,
    required this.lastSeen,
    this.peerId,
    this.macAddress,
    this.aliasName,
    this.deviceName,
    this.operatingSystem,
    this.deviceCategory = DeviceCategory.unknown,
    this.isTrusted = false,
    this.isNearbyTransferAvailable = false,
    this.nearbyTransferPort,
    this.appPresenceObservedAt,
    this.nearbyAvailabilityObservedAt,
    this.isAppDetected = false,
    this.isReachable = false,
  });

  final String ip;
  final String? peerId;
  final String? macAddress;
  final String? aliasName;
  final String? deviceName;
  final String? operatingSystem;
  final DeviceCategory deviceCategory;
  final bool isTrusted;
  final bool isNearbyTransferAvailable;
  final int? nearbyTransferPort;
  final DateTime? appPresenceObservedAt;
  final DateTime? nearbyAvailabilityObservedAt;
  final bool isAppDetected;
  final bool isReachable;
  final DateTime lastSeen;

  String get displayName => aliasName ?? deviceName ?? 'Unknown LAN host';

  DiscoveredDevice copyWith({
    Object? peerId = _unset,
    Object? macAddress = _unset,
    Object? aliasName = _unset,
    Object? deviceName = _unset,
    Object? operatingSystem = _unset,
    DeviceCategory? deviceCategory,
    bool? isTrusted,
    bool? isNearbyTransferAvailable,
    Object? nearbyTransferPort = _unset,
    Object? appPresenceObservedAt = _unset,
    Object? nearbyAvailabilityObservedAt = _unset,
    bool? isAppDetected,
    bool? isReachable,
    DateTime? lastSeen,
  }) {
    return DiscoveredDevice(
      ip: ip,
      peerId: identical(peerId, _unset) ? this.peerId : peerId as String?,
      macAddress: identical(macAddress, _unset)
          ? this.macAddress
          : macAddress as String?,
      aliasName: identical(aliasName, _unset)
          ? this.aliasName
          : aliasName as String?,
      deviceName: identical(deviceName, _unset)
          ? this.deviceName
          : deviceName as String?,
      operatingSystem: identical(operatingSystem, _unset)
          ? this.operatingSystem
          : operatingSystem as String?,
      deviceCategory: deviceCategory ?? this.deviceCategory,
      isTrusted: isTrusted ?? this.isTrusted,
      isNearbyTransferAvailable:
          isNearbyTransferAvailable ?? this.isNearbyTransferAvailable,
      nearbyTransferPort: identical(nearbyTransferPort, _unset)
          ? this.nearbyTransferPort
          : nearbyTransferPort as int?,
      appPresenceObservedAt: identical(appPresenceObservedAt, _unset)
          ? this.appPresenceObservedAt
          : appPresenceObservedAt as DateTime?,
      nearbyAvailabilityObservedAt:
          identical(nearbyAvailabilityObservedAt, _unset)
          ? this.nearbyAvailabilityObservedAt
          : nearbyAvailabilityObservedAt as DateTime?,
      isAppDetected: isAppDetected ?? this.isAppDetected,
      isReachable: isReachable ?? this.isReachable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

const Object _unset = Object();

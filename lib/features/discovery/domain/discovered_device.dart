class DiscoveredDevice {
  DiscoveredDevice({
    required this.ip,
    required this.lastSeen,
    this.macAddress,
    this.aliasName,
    this.deviceName,
    this.isTrusted = false,
    this.isAppDetected = false,
    this.isReachable = false,
  });

  final String ip;
  final String? macAddress;
  final String? aliasName;
  final String? deviceName;
  final bool isTrusted;
  final bool isAppDetected;
  final bool isReachable;
  final DateTime lastSeen;

  String get displayName => aliasName ?? deviceName ?? 'Unknown LAN host';

  DiscoveredDevice copyWith({
    Object? macAddress = _unset,
    Object? aliasName = _unset,
    Object? deviceName = _unset,
    bool? isTrusted,
    bool? isAppDetected,
    bool? isReachable,
    DateTime? lastSeen,
  }) {
    return DiscoveredDevice(
      ip: ip,
      macAddress: identical(macAddress, _unset)
          ? this.macAddress
          : macAddress as String?,
      aliasName: identical(aliasName, _unset)
          ? this.aliasName
          : aliasName as String?,
      deviceName: identical(deviceName, _unset)
          ? this.deviceName
          : deviceName as String?,
      isTrusted: isTrusted ?? this.isTrusted,
      isAppDetected: isAppDetected ?? this.isAppDetected,
      isReachable: isReachable ?? this.isReachable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

const Object _unset = Object();

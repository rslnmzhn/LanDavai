class DiscoveredDevice {
  DiscoveredDevice({
    required this.ip,
    required this.lastSeen,
    this.deviceName,
    this.isAppDetected = false,
    this.isReachable = false,
  });

  final String ip;
  final String? deviceName;
  final bool isAppDetected;
  final bool isReachable;
  final DateTime lastSeen;

  DiscoveredDevice copyWith({
    String? deviceName,
    bool? isAppDetected,
    bool? isReachable,
    DateTime? lastSeen,
  }) {
    return DiscoveredDevice(
      ip: ip,
      deviceName: deviceName ?? this.deviceName,
      isAppDetected: isAppDetected ?? this.isAppDetected,
      isReachable: isReachable ?? this.isReachable,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

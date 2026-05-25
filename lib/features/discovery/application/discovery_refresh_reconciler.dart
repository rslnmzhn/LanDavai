import '../data/device_alias_repository.dart';
import '../domain/discovered_device.dart';
import 'discovery_device_presence_projector.dart';

class DiscoveryRefreshReconcileResult {
  const DiscoveryRefreshReconcileResult({
    required this.devicesByIp,
    required this.seenMacToIp,
    required this.removedIps,
    required this.hasSelectedDevice,
  });

  final Map<String, DiscoveredDevice> devicesByIp;
  final Map<String, String> seenMacToIp;
  final List<String> removedIps;
  final bool hasSelectedDevice;
}

class DiscoveryRefreshReconciler {
  DiscoveryRefreshReconciler({
    required DiscoveryDevicePresenceProjector devicePresenceProjector,
  }) : _devicePresenceProjector = devicePresenceProjector;

  final DiscoveryDevicePresenceProjector _devicePresenceProjector;

  DiscoveryRefreshReconcileResult reconcile({
    required Map<String, DiscoveredDevice> currentDevicesByIp,
    required Map<String, String?> hosts,
    required DateTime observedAt,
    required String? selectedDeviceIp,
  }) {
    final nextDevicesByIp = Map<String, DiscoveredDevice>.of(
      currentDevicesByIp,
    );
    final seenMacToIp = _buildSeenMacToIp(hosts);

    for (final host in hosts.entries) {
      final ip = host.key;
      final existing =
          nextDevicesByIp[ip] ?? DiscoveredDevice(ip: ip, lastSeen: observedAt);
      final normalizedMac = _devicePresenceProjector.resolveStableDeviceMac(
        ip: ip,
        observedMac: host.value,
        existingMac: existing.macAddress,
      );
      nextDevicesByIp[ip] = existing.copyWith(
        macAddress: normalizedMac ?? existing.macAddress,
        isReachable: true,
        lastSeen: observedAt,
      );
    }

    final removedIps = <String>[];
    final appDeviceIpsToMarkUnreachable = <String>[];
    nextDevicesByIp.forEach((ip, device) {
      if (hosts.containsKey(ip)) {
        return;
      }

      if (!device.isAppDetected) {
        removedIps.add(ip);
        return;
      }

      appDeviceIpsToMarkUnreachable.add(ip);
    });

    for (final ip in removedIps) {
      nextDevicesByIp.remove(ip);
    }
    for (final ip in appDeviceIpsToMarkUnreachable) {
      final device = nextDevicesByIp[ip];
      if (device != null) {
        nextDevicesByIp[ip] = device.copyWith(isReachable: false);
      }
    }

    return DiscoveryRefreshReconcileResult(
      devicesByIp: nextDevicesByIp,
      seenMacToIp: seenMacToIp,
      removedIps: List<String>.unmodifiable(removedIps),
      hasSelectedDevice:
          selectedDeviceIp != null &&
          nextDevicesByIp.containsKey(selectedDeviceIp),
    );
  }

  Map<String, String> _buildSeenMacToIp(Map<String, String?> hosts) {
    final seenMacToIp = <String, String>{};
    for (final host in hosts.entries) {
      final normalizedMac = DeviceAliasRepository.normalizeMac(host.value);
      if (normalizedMac != null) {
        seenMacToIp[normalizedMac] = host.key;
      }
    }
    return seenMacToIp;
  }
}

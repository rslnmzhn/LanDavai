import '../data/device_alias_repository.dart';
import '../data/lan_protocol_events.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';
import 'device_registry.dart';

class AppPresenceProjectionResult {
  const AppPresenceProjectionResult({
    required this.device,
    required this.normalizedMacAddress,
    required this.normalizedPeerId,
  });

  final DiscoveredDevice device;
  final String? normalizedMacAddress;
  final String? normalizedPeerId;
}

class DiscoveryDevicePresenceProjector {
  DiscoveryDevicePresenceProjector({required DeviceRegistry deviceRegistry})
    : _deviceRegistry = deviceRegistry;

  final DeviceRegistry _deviceRegistry;

  AppPresenceProjectionResult projectAppPresence({
    required AppPresenceEvent event,
    required DiscoveredDevice? existing,
    required Iterable<FriendPeer> friends,
  }) {
    final normalizedPeerId = normalizePeerId(event.peerId);
    final normalizedMac = resolveStableDeviceMac(
      ip: event.ip,
      peerId: normalizedPeerId,
      observedMac: null,
      existingMac: existing?.macAddress,
    );
    final detectedOs = normalizeOperatingSystemName(event.operatingSystem);
    final friendName = normalizedPeerId == null
        ? null
        : _displayNameForPeerId(normalizedPeerId, friends);
    final detectedCategory = resolveDeviceCategory(
      deviceType: event.deviceType,
      operatingSystem: detectedOs,
    );

    return AppPresenceProjectionResult(
      device:
          (existing ??
                  DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
              .copyWith(
                peerId: normalizedPeerId ?? existing?.peerId,
                deviceName: friendName ?? event.deviceName,
                operatingSystem: detectedOs ?? existing?.operatingSystem,
                deviceCategory: detectedCategory,
                macAddress: normalizedMac ?? existing?.macAddress,
                isNearbyTransferAvailable: event.nearbyTransferPort != null,
                nearbyTransferPort: event.nearbyTransferPort,
                appPresenceObservedAt: event.observedAt,
                nearbyAvailabilityObservedAt: event.nearbyTransferPort != null
                    ? event.observedAt
                    : null,
                isAppDetected: true,
                isReachable: true,
                lastSeen: event.observedAt,
              ),
      normalizedMacAddress: normalizedMac,
      normalizedPeerId: normalizedPeerId,
    );
  }

  DiscoveredDevice? projectVisibleFriendPeer({
    required String ip,
    required String macAddress,
    required String deviceName,
    required DateTime observedAt,
    required DiscoveredDevice? existing,
    String? peerId,
  }) {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    final trimmedIp = ip.trim();
    if (normalizedMac == null || trimmedIp.isEmpty) {
      return null;
    }

    final normalizedPeerId =
        normalizePeerId(peerId) ?? normalizePeerId(existing?.peerId);
    final trimmedName = deviceName.trim();
    return (existing ?? DiscoveredDevice(ip: trimmedIp, lastSeen: observedAt))
        .copyWith(
          peerId: normalizedPeerId ?? existing?.peerId,
          macAddress: normalizedMac,
          deviceName: trimmedName.isEmpty ? existing?.deviceName : trimmedName,
          appPresenceObservedAt: observedAt,
          isAppDetected: true,
          isReachable: true,
          lastSeen: observedAt,
        );
  }

  String? resolveStableDeviceMac({
    required String ip,
    String? peerId,
    required String? observedMac,
    required String? existingMac,
  }) {
    final normalizedObservedMac = DeviceAliasRepository.normalizeMac(
      observedMac,
    );
    if (normalizedObservedMac != null) {
      return normalizedObservedMac;
    }

    final normalizedPeerId = normalizePeerId(peerId);
    if (normalizedPeerId != null) {
      final knownMac = _deviceRegistry.macForPeerId(normalizedPeerId);
      if (knownMac != null) {
        return knownMac;
      }
    }

    final knownMac = _deviceRegistry.macForIp(ip);
    if (knownMac != null) {
      return knownMac;
    }

    return DeviceAliasRepository.normalizeMac(existingMac);
  }

  static String? normalizeOperatingSystemName(String? raw) {
    if (raw == null) {
      return null;
    }
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final lower = value.toLowerCase();
    if (lower.contains('android')) {
      return 'Android';
    }
    if (lower == 'ios' || lower.contains('iphone') || lower.contains('ipad')) {
      return 'iOS';
    }
    if (lower.contains('windows')) {
      return 'Windows';
    }
    if (lower.contains('mac')) {
      return 'macOS';
    }
    if (lower.contains('linux')) {
      return 'Linux';
    }
    return value;
  }

  static DeviceCategory? resolveDeviceCategory({
    required String? deviceType,
    required String? operatingSystem,
  }) {
    final normalizedType = deviceType?.trim().toLowerCase();
    if (normalizedType == 'phone' ||
        normalizedType == 'mobile' ||
        normalizedType == 'tablet') {
      return DeviceCategory.phone;
    }
    if (normalizedType == 'pc' ||
        normalizedType == 'desktop' ||
        normalizedType == 'laptop') {
      return DeviceCategory.pc;
    }

    final os = operatingSystem?.toLowerCase();
    if (os == null) {
      return null;
    }
    if (os.contains('android') || os.contains('ios')) {
      return DeviceCategory.phone;
    }
    if (os.contains('windows') || os.contains('linux') || os.contains('mac')) {
      return DeviceCategory.pc;
    }
    return null;
  }

  static String? normalizePeerId(String? peerId) {
    final normalized = peerId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String? _displayNameForPeerId(String peerId, Iterable<FriendPeer> friends) {
    for (final peer in friends) {
      if (peer.friendId == peerId) {
        return peer.displayName;
      }
    }
    return null;
  }
}

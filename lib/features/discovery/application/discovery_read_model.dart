import 'package:flutter/foundation.dart';

import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';
import 'discovery_controller.dart';
import 'device_registry.dart';
import 'internet_peer_endpoint_store.dart';
import 'trusted_lan_peer_store.dart';

class DiscoveryReadModel extends ChangeNotifier {
  DiscoveryReadModel({
    required DiscoveryController legacyController,
    required DeviceRegistry deviceRegistry,
    required InternetPeerEndpointStore internetPeerEndpointStore,
    required TrustedLanPeerStore trustedLanPeerStore,
    required SettingsStore settingsStore,
  }) : _legacyController = legacyController,
       _deviceRegistry = deviceRegistry,
       _internetPeerEndpointStore = internetPeerEndpointStore,
       _trustedLanPeerStore = trustedLanPeerStore,
       _settingsStore = settingsStore {
    _legacyController.addListener(_handleDependencyChanged);
    _deviceRegistry.addListener(_handleDependencyChanged);
    _internetPeerEndpointStore.addListener(_handleDependencyChanged);
    _trustedLanPeerStore.addListener(_handleDependencyChanged);
    _settingsStore.addListener(_handleDependencyChanged);
  }

  final DiscoveryController _legacyController;
  final DeviceRegistry _deviceRegistry;
  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final TrustedLanPeerStore _trustedLanPeerStore;
  final SettingsStore _settingsStore;

  AppSettings get settings => _settingsStore.settings;

  List<FriendPeer> get internetPeers => _internetPeerEndpointStore.peers;

  String get localName => _legacyController.localName;

  String? get localIp => _legacyController.localIp;

  bool get isAppInForeground => _legacyController.isAppInForeground;

  List<DiscoveredDevice> get devices => _legacyController.devices
      .map(_canonicalizeDevice)
      .toList(growable: false);

  DiscoveredDevice? get selectedDevice {
    final selectedIp = _legacyController.selectedDevice?.ip;
    if (selectedIp == null) {
      return null;
    }
    for (final device in devices) {
      if (device.ip == selectedIp) {
        return device;
      }
    }
    return null;
  }

  int get appDetectedCount =>
      devices.where((device) => device.isAppDetected).length;

  List<DiscoveredDevice> get friendDevices {
    final values = devices.where((device) => device.isTrusted).toList();
    values.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return List<DiscoveredDevice>.unmodifiable(values);
  }

  DiscoveredDevice _canonicalizeDevice(DiscoveredDevice device) {
    final aliasName = _deviceRegistry.aliasForMac(device.macAddress);
    final isTrusted = device.macAddress == null
        ? device.isTrusted
        : _trustedLanPeerStore.isTrustedMac(device.macAddress);
    return device.copyWith(
      aliasName: aliasName ?? device.aliasName,
      isTrusted: isTrusted,
    );
  }

  void _handleDependencyChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _legacyController.removeListener(_handleDependencyChanged);
    _deviceRegistry.removeListener(_handleDependencyChanged);
    _internetPeerEndpointStore.removeListener(_handleDependencyChanged);
    _trustedLanPeerStore.removeListener(_handleDependencyChanged);
    _settingsStore.removeListener(_handleDependencyChanged);
    super.dispose();
  }
}

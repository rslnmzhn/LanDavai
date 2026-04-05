import 'package:flutter/foundation.dart';

import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';
import 'configured_discovery_targets_store.dart';
import 'discovery_controller.dart';
import 'discovery_network_scope.dart';
import 'discovery_network_scope_store.dart';
import 'device_registry.dart';
import 'internet_peer_endpoint_store.dart';
import 'trusted_lan_peer_store.dart';

class DiscoveryReadModel extends ChangeNotifier {
  DiscoveryReadModel({
    required DiscoveryController legacyController,
    required DeviceRegistry deviceRegistry,
    required InternetPeerEndpointStore internetPeerEndpointStore,
    required TrustedLanPeerStore trustedLanPeerStore,
    required DiscoveryNetworkScopeStore discoveryNetworkScopeStore,
    required SettingsStore settingsStore,
    ConfiguredDiscoveryTargetsStore? configuredDiscoveryTargetsStore,
  }) : _legacyController = legacyController,
       _deviceRegistry = deviceRegistry,
       _internetPeerEndpointStore = internetPeerEndpointStore,
       _trustedLanPeerStore = trustedLanPeerStore,
       _discoveryNetworkScopeStore = discoveryNetworkScopeStore,
       _settingsStore = settingsStore,
       _configuredDiscoveryTargetsStore = configuredDiscoveryTargetsStore {
    _legacyController.addListener(_handleDependencyChanged);
    _deviceRegistry.addListener(_handleDependencyChanged);
    _internetPeerEndpointStore.addListener(_handleDependencyChanged);
    _trustedLanPeerStore.addListener(_handleDependencyChanged);
    _discoveryNetworkScopeStore.addListener(_handleDependencyChanged);
    _configuredDiscoveryTargetsStore?.addListener(_handleDependencyChanged);
    _settingsStore.addListener(_handleDependencyChanged);
  }

  final DiscoveryController _legacyController;
  final DeviceRegistry _deviceRegistry;
  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final TrustedLanPeerStore _trustedLanPeerStore;
  final DiscoveryNetworkScopeStore _discoveryNetworkScopeStore;
  final SettingsStore _settingsStore;
  final ConfiguredDiscoveryTargetsStore? _configuredDiscoveryTargetsStore;

  AppSettings get settings => _settingsStore.settings;

  List<FriendPeer> get internetPeers => _internetPeerEndpointStore.peers;

  String get localName => _legacyController.localName;

  String? get localIp => _legacyController.localIp;

  bool get isAppInForeground => _legacyController.isAppInForeground;

  List<DiscoveryNetworkRange> get availableNetworkRanges =>
      List<DiscoveryNetworkRange>.unmodifiable(
        _discoveryNetworkScopeStore.ranges,
      );

  String get selectedNetworkScopeId =>
      _discoveryNetworkScopeStore.selectedScopeId;

  DiscoveryNetworkRange? get selectedNetworkRange =>
      _discoveryNetworkScopeStore.selectedRange;

  List<DiscoveredDevice> get devices => _legacyController.devices
      .where((device) => _isVisibleInSelectedProjection(device.ip))
      .map(_canonicalizeDevice)
      .toList(growable: false);

  DiscoveredDevice? get selectedDevice {
    final selectedIp = _legacyController.selectedDevice?.ip;
    if (selectedIp == null) {
      return null;
    }
    if (!_isVisibleInSelectedProjection(selectedIp)) {
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

  List<DiscoveredDevice> get remoteClipboardDevices {
    final values = devices.where((device) => device.isAppDetected).toList();
    values.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return List<DiscoveredDevice>.unmodifiable(values);
  }

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

  bool _isVisibleInSelectedProjection(String ip) {
    return _discoveryNetworkScopeStore.matchesSelectedScope(ip) ||
        (_configuredDiscoveryTargetsStore?.containsIp(ip) ?? false);
  }

  @override
  void dispose() {
    _legacyController.removeListener(_handleDependencyChanged);
    _deviceRegistry.removeListener(_handleDependencyChanged);
    _internetPeerEndpointStore.removeListener(_handleDependencyChanged);
    _trustedLanPeerStore.removeListener(_handleDependencyChanged);
    _discoveryNetworkScopeStore.removeListener(_handleDependencyChanged);
    _configuredDiscoveryTargetsStore?.removeListener(_handleDependencyChanged);
    _settingsStore.removeListener(_handleDependencyChanged);
    super.dispose();
  }
}

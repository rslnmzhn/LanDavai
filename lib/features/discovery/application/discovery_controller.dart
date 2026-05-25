import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/app_notification_service.dart';
import '../../../core/utils/path_opener.dart';
import '../../history/application/download_history_boundary.dart';
import '../../history/data/transfer_history_repository.dart';
import '../../nearby_transfer/application/nearby_transfer_availability_store.dart';
import '../../clipboard/application/clipboard_history_store.dart';
import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../clipboard/data/clipboard_capture_service.dart';
import '../../clipboard/data/clipboard_history_repository.dart';
import '../../files/application/preview_cache_owner.dart';
import 'remote_share_media_projection_boundary.dart';
import 'remote_share_browser.dart';
import 'remote_share_packet_route_adapter.dart';
import 'remote_clipboard_request_command.dart';
import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/application/remote_file_preview_transfer_boundary.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import 'configured_discovery_targets_store.dart';
import 'clipboard_packet_route_adapter.dart';
import 'discovery_device_presence_projector.dart';
import 'discovery_friend_request_router.dart';
import 'discovery_refresh_reconciler.dart';
import 'discovery_refresh_runner.dart';
import 'device_registry.dart';
import 'discovery_internet_friend_command_adapter.dart';
import 'discovery_lifecycle_timers.dart';
import 'discovery_settings_command_adapter.dart';
import 'internet_peer_endpoint_store.dart';
import 'local_peer_identity_store.dart';
import 'discovery_presence_expiry_policy.dart';
import 'trusted_lan_peer_store.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_protocol_events.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';
import 'discovery_network_scope_store.dart';
import 'shared_folder_indexing_command.dart';

enum DiscoveryFlowState { idle, discovering }

class ShareableVideoFile {
  const ShareableVideoFile({
    required this.id,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.absolutePath,
    required this.sizeBytes,
  });

  final String id;
  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final String absolutePath;
  final int sizeBytes;

  String get fileName => p.basename(relativePath);
}

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required LanDiscoveryService lanDiscoveryService,
    required NetworkHostScanner networkHostScanner,
    required DeviceRegistry deviceRegistry,
    required InternetPeerEndpointStore internetPeerEndpointStore,
    required TrustedLanPeerStore trustedLanPeerStore,
    required LocalPeerIdentityStore localPeerIdentityStore,
    required DiscoveryNetworkScopeStore discoveryNetworkScopeStore,
    required SettingsStore settingsStore,
    ConfiguredDiscoveryTargetsStore? configuredDiscoveryTargetsStore,
    required AppNotificationService appNotificationService,
    required TransferHistoryRepository transferHistoryRepository,
    DownloadHistoryBoundary? downloadHistoryBoundary,
    required ClipboardHistoryRepository clipboardHistoryRepository,
    required ClipboardCaptureService clipboardCaptureService,
    ClipboardHistoryStore? clipboardHistoryStore,
    RemoteClipboardProjectionStore? remoteClipboardProjectionStore,
    required RemoteShareBrowser remoteShareBrowser,
    required RemoteShareMediaProjectionBoundary
    remoteShareMediaProjectionBoundary,
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required PreviewCacheOwner previewCacheOwner,
    required PathOpener pathOpener,
    NearbyTransferAvailabilityStore? nearbyTransferAvailabilityStore,
    TransferSessionCoordinator? transferSessionCoordinator,
    Duration appPresenceTtl = const Duration(seconds: 12),
    Duration nearbyAvailabilityTtl = const Duration(seconds: 8),
    Duration presenceExpiryCheckInterval = const Duration(seconds: 2),
    Duration androidResumeRestartDelay = defaultAndroidResumeRestartDelay,
    bool Function()? isAndroidProvider,
    DateTime Function()? nowProvider,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _deviceRegistry = deviceRegistry,
       _internetPeerEndpointStore = internetPeerEndpointStore,
       _trustedLanPeerStore = trustedLanPeerStore,
       _localPeerIdentityStore = localPeerIdentityStore,
       _discoveryNetworkScopeStore = discoveryNetworkScopeStore,
       _settingsStore = settingsStore,
       _configuredDiscoveryTargetsStore =
           configuredDiscoveryTargetsStore ??
           ConfiguredDiscoveryTargetsStore.inMemory(),
       _appNotificationService = appNotificationService,
       _remoteShareBrowser = remoteShareBrowser,
       _remoteShareMediaProjectionBoundary = remoteShareMediaProjectionBoundary,
       _sharedCacheCatalog = sharedCacheCatalog,
       _fileHashService = fileHashService,
       _previewCacheOwner = previewCacheOwner,
       _pathOpener = pathOpener,
       _presenceExpiryCheckInterval = presenceExpiryCheckInterval,
       _androidResumeRestartDelay = androidResumeRestartDelay,
       _isAndroid = isAndroidProvider ?? (() => Platform.isAndroid),
       _now = nowProvider ?? DateTime.now,
       _nearbyTransferAvailabilityStore =
           nearbyTransferAvailabilityStore ??
           NearbyTransferAvailabilityStore() {
    _presenceExpiryPolicy = DiscoveryPresenceExpiryPolicy(
      appPresenceTtl: appPresenceTtl,
      nearbyAvailabilityTtl: nearbyAvailabilityTtl,
    );
    _devicePresenceProjector = DiscoveryDevicePresenceProjector(
      deviceRegistry: deviceRegistry,
    );
    _refreshReconciler = DiscoveryRefreshReconciler(
      devicePresenceProjector: _devicePresenceProjector,
    );
    _refreshRunner = DiscoveryRefreshRunner(
      networkHostScanner: networkHostScanner,
      deviceRegistry: deviceRegistry,
      refreshReconciler: _refreshReconciler,
    );
    _sharedFolderIndexingCommand = SharedFolderIndexingCommand(
      upsertOwnerFolderCache: sharedCacheCatalog.upsertOwnerFolderCache,
      localDeviceMacProvider: () => _localDeviceMac,
      settingsProvider: () => _settingsStore.settings,
      ensureSharedStorageAccess:
          _ensureAndroidSharedStorageAccessForFolderCache,
      pickFolderPath: () => FilePicker.platform.getDirectoryPath(),
      loadOwnerCaches: _loadOwnerCaches,
      onStateChanged: _applySharedFolderIndexingState,
      nowProvider: _now,
    );
    _settingsCommandAdapter = DiscoverySettingsCommandAdapter(
      settingsStore: settingsStore,
      onSettingsChanged: (_) {
        _errorMessage = null;
        _restartAutoRefreshTimer();
        unawaited(_cleanupPreviewCacheBySettings());
        unawaited(_trimClipboardHistoryToSettingsLimit());
        notifyListeners();
      },
      onError: (error) {
        _errorMessage = 'Failed to save app settings: $error';
        _log(_errorMessage!);
        notifyListeners();
      },
    );
    _internetFriendCommandAdapter = DiscoveryInternetFriendCommandAdapter(
      internetPeerEndpointStore: internetPeerEndpointStore,
      lanDiscoveryService: lanDiscoveryService,
      log: _log,
    );
    _friendRequestRouter = DiscoveryFriendRequestRouter(
      lanDiscoveryService: lanDiscoveryService,
      fileHashService: fileHashService,
      localNameProvider: () => _localName,
      localDeviceMacProvider: () => _localDeviceMac,
      isTrustedMac: (macAddress) =>
          _trustedLanPeerStore.isTrustedMac(macAddress),
      deviceByIp: (ip) => _devicesByIp[ip],
      rememberVisibleFriendPeer: _rememberVisibleFriendPeer,
      setFriendStatus: _setFriendStatus,
      showFriendRequestNotification: (requesterName) => _appNotificationService
          .showFriendRequestNotification(requesterName: requesterName),
      log: _log,
      nowProvider: _now,
    );
    _downloadHistoryBoundary =
        downloadHistoryBoundary ??
        DownloadHistoryBoundary(
          transferHistoryRepository: transferHistoryRepository,
        );
    _clipboardHistoryStore =
        clipboardHistoryStore ??
        ClipboardHistoryStore(
          clipboardHistoryRepository: clipboardHistoryRepository,
          clipboardCaptureService: clipboardCaptureService,
          transferStorageService: transferStorageService,
        );
    _remoteClipboardProjectionStore =
        remoteClipboardProjectionStore ??
        RemoteClipboardProjectionStore(fileHashService: fileHashService);
    _remoteClipboardRequestCommand = RemoteClipboardRequestCommand(
      remoteClipboardProjectionStore: _remoteClipboardProjectionStore,
      isTrustedMac: (normalizedMac) =>
          _trustedLanPeerStore.isTrustedMac(normalizedMac),
      localDeviceMacProvider: () => _localDeviceMac,
      localNameProvider: () => _localName,
      settingsProvider: () => _settingsStore.settings,
      sendClipboardQuery: lanDiscoveryService.sendClipboardQuery,
      log: _log,
    );
    _clipboardPacketRouteAdapter = ClipboardPacketRouteAdapter(
      lanDiscoveryService: lanDiscoveryService,
      clipboardHistoryStore: _clipboardHistoryStore,
      remoteClipboardProjectionStore: _remoteClipboardProjectionStore,
      settingsProvider: () => _settingsStore.settings,
      localNameProvider: () => _localName,
      localDeviceMacProvider: () => _localDeviceMac,
      isTrustedMac: (normalizedMac) =>
          _trustedLanPeerStore.isTrustedMac(normalizedMac),
      log: _log,
    );
    _remoteSharePacketRouteAdapter = RemoteSharePacketRouteAdapter(
      lanDiscoveryService: lanDiscoveryService,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      remoteShareBrowser: remoteShareBrowser,
      remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
      localNameProvider: () => _localName,
      localDeviceMacProvider: () => _localDeviceMac,
      ownerCachesProvider: () => _ownerCachesSnapshot,
      loadOwnerCaches: _loadOwnerCaches,
      hasSharedStorageAccess: _hasAndroidSharedStorageAccess,
      log: _log,
    );
    _transferSessionCoordinator =
        transferSessionCoordinator ??
        TransferSessionCoordinator(
          lanDiscoveryService: lanDiscoveryService,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          fileTransferService: fileTransferService,
          transferStorageService: transferStorageService,
          downloadHistoryBoundary: _downloadHistoryBoundary,
          appNotificationService: appNotificationService,
          settingsProvider: () => _settingsStore.settings,
          localNameProvider: () => _localName,
          localDeviceMacProvider: () => _localDeviceMac,
          isTrustedSender: (normalizedMac) =>
              _trustedLanPeerStore.isTrustedMac(normalizedMac),
          resolveRemoteOwnerMac:
              ({required String ownerIp, required String cacheId}) =>
                  _resolveRemoteOwnerMac(ownerIp: ownerIp, cacheId: cacheId),
          remoteFilePreviewTransferBoundary: RemoteFilePreviewTransferBoundary(
            lanDiscoveryService: lanDiscoveryService,
            fileHashService: fileHashService,
            previewCacheOwner: previewCacheOwner,
            settingsProvider: () => _settingsStore.settings,
            localNameProvider: () => _localName,
            localDeviceMacProvider: () => _localDeviceMac,
            resolveRemoteOwnerMac:
                ({required String ownerIp, required String cacheId}) =>
                    _resolveRemoteOwnerMac(ownerIp: ownerIp, cacheId: cacheId),
            publishNotice: (notice) {
              _transferSessionCoordinator.publishBoundaryNotice(notice);
            },
          ),
        );
    _discoveryNetworkScopeStore.addListener(_handleNetworkScopeChanged);
    _configuredDiscoveryTargetsStore.addListener(
      _handleConfiguredDiscoveryTargetsChanged,
    );
    _nearbyTransferAvailabilityStore.addListener(
      _handleNearbyTransferAvailabilityChanged,
    );
    _transferSessionCoordinator.addListener(
      _handleTransferSessionCoordinatorChanged,
    );
  }

  static const Duration defaultAndroidResumeRestartDelay = Duration(seconds: 2);
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  final LanDiscoveryService _lanDiscoveryService;
  final DeviceRegistry _deviceRegistry;
  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final TrustedLanPeerStore _trustedLanPeerStore;
  final LocalPeerIdentityStore _localPeerIdentityStore;
  final DiscoveryNetworkScopeStore _discoveryNetworkScopeStore;
  final SettingsStore _settingsStore;
  final ConfiguredDiscoveryTargetsStore _configuredDiscoveryTargetsStore;
  final AppNotificationService _appNotificationService;
  final RemoteShareBrowser _remoteShareBrowser;
  final RemoteShareMediaProjectionBoundary _remoteShareMediaProjectionBoundary;
  final SharedCacheCatalog _sharedCacheCatalog;
  final FileHashService _fileHashService;
  final PreviewCacheOwner _previewCacheOwner;
  final PathOpener _pathOpener;
  final Duration _presenceExpiryCheckInterval;
  final Duration _androidResumeRestartDelay;
  final bool Function() _isAndroid;
  final DateTime Function() _now;
  final DiscoveryLifecycleTimers _lifecycleTimers = DiscoveryLifecycleTimers();
  late final DiscoveryPresenceExpiryPolicy _presenceExpiryPolicy;
  late final DiscoveryDevicePresenceProjector _devicePresenceProjector;
  late final DiscoveryRefreshReconciler _refreshReconciler;
  late final DiscoveryRefreshRunner _refreshRunner;
  late final SharedFolderIndexingCommand _sharedFolderIndexingCommand;
  late final DiscoverySettingsCommandAdapter _settingsCommandAdapter;
  late final DiscoveryInternetFriendCommandAdapter
  _internetFriendCommandAdapter;
  late final DiscoveryFriendRequestRouter _friendRequestRouter;
  final NearbyTransferAvailabilityStore _nearbyTransferAvailabilityStore;
  late final DownloadHistoryBoundary _downloadHistoryBoundary;
  late final ClipboardHistoryStore _clipboardHistoryStore;
  late final RemoteClipboardProjectionStore _remoteClipboardProjectionStore;
  late final RemoteClipboardRequestCommand _remoteClipboardRequestCommand;
  late final ClipboardPacketRouteAdapter _clipboardPacketRouteAdapter;
  late final RemoteSharePacketRouteAdapter _remoteSharePacketRouteAdapter;
  late final TransferSessionCoordinator _transferSessionCoordinator;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  bool _started = false;
  bool _isDiscoveryServiceRunning = false;
  bool _isAppInForeground = true;
  bool _isRefreshInProgress = false;
  bool _isDisposed = false;
  bool _isManualRefreshInProgress = false;
  bool _isAddingShare = false;
  SharedFolderIndexingProgress? _sharedFolderIndexingProgress;
  double? _sharedFolderIndexingVisualProgress;
  bool _pendingDiscoveryRestartAfterRefresh = false;

  DiscoveryFlowState _state = DiscoveryFlowState.idle;
  String? _localIp;
  final String _localName = Platform.localHostname;
  String _localDeviceMac = '02:00:00:00:00:01';
  String _localPeerId = '';
  bool _ownerCacheMacRebindChecked = false;
  bool _isFriendMutationInProgress = false;
  bool _pendingScopeReconfigureAfterRefresh = false;
  String? _selectedDeviceIp;
  String? _errorMessage;
  String? _infoMessage;
  Set<String> _activeDiscoveryLocalIps = <String>{};
  Set<String> _activeDiscoveryConfiguredTargetIps = <String>{};

  DiscoveryFlowState get state => _state;
  bool get isManualRefreshInProgress => _isManualRefreshInProgress;
  bool get isAddingShare => _isAddingShare;
  SharedFolderIndexingProgress? get sharedFolderIndexingProgress =>
      _sharedFolderIndexingProgress;
  double? get sharedFolderIndexingProgressValue =>
      _sharedFolderIndexingVisualProgress;

  String? get localIp => _localIp;
  String get localName => _localName;
  String get localDeviceMac => _localDeviceMac;
  String get localPeerId => _localPeerId;
  bool get isFriendMutationInProgress => _isFriendMutationInProgress;
  List<FriendPeer> get friends => _internetPeerEndpointStore.peers;
  AppSettings get settings => _settingsStore.settings;
  bool get isAppInForeground => _isAppInForeground;
  Duration get activeAutoRefreshInterval => _activeAutoRefreshInterval;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  List<IncomingFriendRequest> get incomingFriendRequests =>
      _friendRequestRouter.incomingFriendRequests;
  String get selectedNetworkScopeId =>
      _discoveryNetworkScopeStore.selectedScopeId;
  List<String> get configuredDiscoveryTargets =>
      _configuredDiscoveryTargetsStore.targets;

  AppSettings get _currentSettings => _settingsStore.settings;

  List<SharedFolderCacheRecord> get _ownerCachesSnapshot =>
      _sharedCacheCatalog.ownerCaches;

  void _handleTransferSessionCoordinatorChanged() {
    final notice = _transferSessionCoordinator.takePendingNotice();
    if (notice != null) {
      if (notice.clearInfo) {
        _infoMessage = null;
      }
      if (notice.clearError) {
        _errorMessage = null;
      }
      if (notice.infoMessage != null) {
        _infoMessage = notice.infoMessage;
      }
      if (notice.errorMessage != null) {
        _errorMessage = notice.errorMessage;
      }
    }
    notifyListeners();
  }

  List<DiscoveredDevice> get devices {
    final values = _devicesByIp.values.toList(growable: false);
    values.sort((a, b) {
      if (a.isAppDetected != b.isAppDetected) {
        return a.isAppDetected ? -1 : 1;
      }
      return _compareIp(a.ip, b.ip);
    });
    return values.map(_projectDeviceFromOwners).toList(growable: false);
  }

  DiscoveredDevice? get selectedDevice {
    final ip = _selectedDeviceIp;
    if (ip == null) {
      return null;
    }
    final device = _devicesByIp[ip];
    if (device == null) {
      return null;
    }
    return _projectDeviceFromOwners(device);
  }

  int get appDetectedCount =>
      _devicesByIp.values.where((d) => d.isAppDetected).length;

  bool hasPendingFriendRequestForDevice(DiscoveredDevice device) {
    return _friendRequestRouter.hasPendingFriendRequestForDevice(device);
  }

  Future<void> start() async {
    if (_started || _isDisposed) {
      _log('start() ignored: controller already started');
      return;
    }

    _localPeerId = await _localPeerIdentityStore.loadOrCreateLocalPeerId();
    await _discoveryNetworkScopeStore.refresh();
    _consumeNetworkScopeState();
    _resolveLocalDeviceMac();
    try {
      await _deviceRegistry.load();
    } catch (error) {
      _log('Failed to load aliases from registry: $error');
    }
    try {
      await _trustedLanPeerStore.load();
      _log(
        'Loaded trusted devices from store. '
        'count=${_trustedLanPeerStore.trustedMacs.length}',
      );
    } catch (error) {
      _log('Failed to load trusted devices from store: $error');
    }
    try {
      await _configuredDiscoveryTargetsStore.load();
    } catch (error) {
      _log('Failed to load configured discovery targets: $error');
    }
    try {
      await _settingsStore.load();
      final settings = _currentSettings;
      _log(
        'Loaded settings. background=${settings.backgroundScanInterval.label}, '
        'notifyDownloadAttempts=${settings.downloadAttemptNotificationsEnabled}, '
        'trayOnClose=${settings.minimizeToTrayOnClose}, '
        'previewMaxSizeGb=${settings.previewCacheMaxSizeGb}, '
        'previewMaxAgeDays=${settings.previewCacheMaxAgeDays}, '
        'clipboardMaxEntries=${settings.clipboardHistoryMaxEntries}, '
        'recacheWorkers=${settings.recacheParallelWorkers}, '
        'configuredTargets=${_configuredDiscoveryTargetsStore.targets.length}',
      );
      unawaited(_cleanupPreviewCacheBySettings());
      unawaited(_trimClipboardHistoryToSettingsLimit());
    } catch (error) {
      _log('Failed to load app settings: $error');
    }
    await _clipboardHistoryStore.load();
    await _loadOwnerCaches();
    await _downloadHistoryBoundary.load();
    try {
      await _internetPeerEndpointStore.load();
    } catch (error) {
      _log('Failed to load friends: $error');
    }

    try {
      _started = true;
      _log('Starting discovery. localName=$_localName localIp=$_localIp');
      _internetFriendCommandAdapter.syncInternetPeers();
      await _ensureDiscoveryScopeApplied();
      await _refresh(isManual: false, refreshNetworkScope: false);
      _restartAutoRefreshTimer();
      _restartPresenceExpiryTimer();
      _startClipboardPolling();
    } catch (error) {
      _started = false;
      _errorMessage = 'LAN discovery error: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> refresh() => _refresh(isManual: true);

  Future<void> selectNetworkScope(String scopeId) async {
    final changed = _discoveryNetworkScopeStore.selectScope(scopeId);
    if (!changed) {
      return;
    }
    if (!_started) {
      return;
    }
    if (_isRefreshInProgress) {
      _pendingScopeReconfigureAfterRefresh = true;
      return;
    }
    await _refresh(isManual: false, refreshNetworkScope: false);
  }

  void clearInfoMessage() {
    _infoMessage = null;
    notifyListeners();
  }

  Future<void> saveFriend({
    required String friendId,
    required String displayName,
    required String endpoint,
    bool isEnabled = true,
  }) async {
    _isFriendMutationInProgress = true;
    notifyListeners();
    final result = await _internetFriendCommandAdapter.saveFriend(
      friendId: friendId,
      displayName: displayName,
      endpoint: endpoint,
      isEnabled: isEnabled,
    );
    _applyFriendCommandResult(result);
  }

  Future<void> removeFriend(String friendId) async {
    _isFriendMutationInProgress = true;
    notifyListeners();
    final result = await _internetFriendCommandAdapter.removeFriend(friendId);
    _applyFriendCommandResult(result);
  }

  Future<void> setFriendEnabled({
    required String friendId,
    required bool enabled,
  }) async {
    final result = await _internetFriendCommandAdapter.setFriendEnabled(
      friendId: friendId,
      enabled: enabled,
    );
    if (result.isSuccess) {
      _errorMessage = null;
    } else {
      _errorMessage = result.errorMessage;
    }
    notifyListeners();
  }

  Future<void> updateBackgroundScanInterval(
    BackgroundScanIntervalOption interval,
  ) async {
    await _settingsCommandAdapter.updateBackgroundScanInterval(interval);
  }

  Future<void> setDownloadAttemptNotificationsEnabled(bool enabled) async {
    await _settingsCommandAdapter.setDownloadAttemptNotificationsEnabled(
      enabled,
    );
  }

  Future<void> setUseStandardAppDownloadFolder(bool enabled) async {
    await _settingsCommandAdapter.setUseStandardAppDownloadFolder(enabled);
  }

  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    await _settingsCommandAdapter.setMinimizeToTrayOnClose(enabled);
  }

  Future<void> setLeftHandedMode(bool enabled) async {
    await _settingsCommandAdapter.setLeftHandedMode(enabled);
  }

  Future<void> setVideoLinkPassword(String value) async {
    await _settingsCommandAdapter.setVideoLinkPassword(value);
  }

  Future<void> setPreviewCacheMaxSizeGb(int value) async {
    await _settingsCommandAdapter.setPreviewCacheMaxSizeGb(value);
  }

  Future<void> setPreviewCacheMaxAgeDays(int value) async {
    await _settingsCommandAdapter.setPreviewCacheMaxAgeDays(value);
  }

  Future<void> setClipboardHistoryMaxEntries(int value) async {
    await _settingsCommandAdapter.setClipboardHistoryMaxEntries(value);
    await _trimClipboardHistoryToSettingsLimit();
  }

  Future<void> setRecacheParallelWorkers(int value) async {
    await _settingsCommandAdapter.setRecacheParallelWorkers(value);
  }

  Future<void> setDebugLogRetainedLines(int value) async {
    await _settingsCommandAdapter.setDebugLogRetainedLines(value);
  }

  void setAppForegroundState(bool isForeground) {
    if (_isAppInForeground == isForeground) {
      return;
    }
    _isAppInForeground = isForeground;
    if (_started && isForeground && _isAndroid()) {
      unawaited(_restartDiscoveryAfterAndroidResume());
    }
    notifyListeners();
  }

  void selectDeviceByIp(String ip) {
    if (_selectedDeviceIp == ip) {
      _selectedDeviceIp = null;
    } else {
      _selectedDeviceIp = ip;
    }
    notifyListeners();
  }

  Future<void> sendFriendRequest(DiscoveredDevice device) async {
    _isFriendMutationInProgress = true;
    notifyListeners();
    final result = await _friendRequestRouter.sendFriendRequest(device);
    _errorMessage = result.errorMessage;
    if (result.infoMessage != null) {
      _infoMessage = result.infoMessage;
    }
    _isFriendMutationInProgress = false;
    notifyListeners();
  }

  Future<void> respondToFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    _isFriendMutationInProgress = true;
    notifyListeners();
    final result = await _friendRequestRouter.respondToFriendRequest(
      requestId: requestId,
      accept: accept,
    );
    _errorMessage = result.errorMessage;
    if (result.infoMessage != null) {
      _infoMessage = result.infoMessage;
    }
    _isFriendMutationInProgress = false;
    notifyListeners();
  }

  Future<void> removeDeviceFromFriends(DiscoveredDevice device) async {
    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      _errorMessage = 'Cannot remove friend until MAC address is known.';
      notifyListeners();
      return;
    }

    _isFriendMutationInProgress = true;
    notifyListeners();
    try {
      await _setFriendStatus(macAddress: mac, isFriend: false);
      _errorMessage = null;
      _infoMessage = '${device.displayName} removed from friends.';
    } catch (error) {
      _errorMessage = 'Failed to remove friend: $error';
      _log(_errorMessage!);
    } finally {
      _isFriendMutationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> requestRemoteClipboardHistory(DiscoveredDevice device) async {
    final result = await _remoteClipboardRequestCommand.request(device);
    _errorMessage = result.errorMessage;
    if (result.infoMessage != null) {
      _infoMessage = result.infoMessage;
    }
    notifyListeners();
  }

  Future<void> loadRemoteShareOptions() async {
    final targets = devices.where((device) => device.isAppDetected).toList();
    try {
      final result = await _remoteShareBrowser.startBrowse(
        targets: targets,
        receiverMacAddress: _localDeviceMac,
        requesterName: _localName,
        requestId: _fileHashService.buildStableId(
          'share-query|${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
        ),
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) {
              return _lanDiscoveryService.sendShareQuery(
                targetIp: targetIp,
                requestId: requestId,
                requesterName: requesterName,
              );
            },
      );
      if (!result.hadTargets) {
        _infoMessage = 'No Landa devices available for shared content.';
      } else if (result.optionCount == 0) {
        _infoMessage = 'No shared folders/files found on LAN devices.';
      }
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to request remote shares: $error';
      _log(_errorMessage!);
    }
    notifyListeners();
  }

  Future<void> renameDeviceAlias({
    required DiscoveredDevice device,
    required String alias,
  }) async {
    final mac = _devicePresenceProjector.resolveStableDeviceMac(
      ip: device.ip,
      observedMac: device.macAddress,
      existingMac: device.macAddress,
    );
    if (mac == null) {
      _errorMessage = 'Cannot rename device until MAC address is known.';
      notifyListeners();
      return;
    }

    final normalizedAlias = alias.trim();
    try {
      await _deviceRegistry.setAlias(macAddress: mac, alias: normalizedAlias);
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to save alias: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> addSharedFolder() async {
    try {
      final result = await _sharedFolderIndexingCommand.run();
      if (!result.cancelled) {
        _infoMessage = result.infoMessage;
        _errorMessage = null;
      }
    } catch (error) {
      _errorMessage = 'Failed to add shared folder: $error';
      _log(_errorMessage!);
    }
    notifyListeners();
  }

  Future<bool> _hasAndroidSharedStorageAccess() async {
    if (!Platform.isAndroid) {
      return true;
    }

    try {
      final granted = await _androidNetworkChannel.invokeMethod<bool>(
        'canAccessSharedStorage',
      );
      return granted ?? false;
    } catch (error) {
      _log('Failed to check shared storage permission: $error');
      return false;
    }
  }

  Future<bool> _ensureAndroidSharedStorageAccessForFolderCache() async {
    if (!Platform.isAndroid) {
      return true;
    }
    if (await _hasAndroidSharedStorageAccess()) {
      return true;
    }

    _errorMessage =
        'Android storage access is required. '
        'Allow "All files access" for Landa in Settings and retry.';
    notifyListeners();

    try {
      await _androidNetworkChannel.invokeMethod<void>(
        'requestSharedStorageAccess',
      );
    } catch (error) {
      _log('Failed to request shared storage permission: $error');
    }

    return _hasAndroidSharedStorageAccess();
  }

  Future<void> addSharedFiles() async {
    _isAddingShare = true;
    notifyListeners();
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      final paths =
          result?.paths.whereType<String>().toList(growable: false) ??
          <String>[];
      if (paths.isEmpty) {
        return;
      }

      await _sharedCacheCatalog.buildOwnerSelectionCache(
        ownerMacAddress: _localDeviceMac,
        filePaths: paths,
        displayName: 'Selected files',
      );
      await _loadOwnerCaches();
      _infoMessage = 'Shared files added.';
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to add shared files: $error';
      _log(_errorMessage!);
    } finally {
      _isAddingShare = false;
      notifyListeners();
    }
  }

  Future<void> sendFilesToSelectedDevice() async {
    final target = selectedDevice;
    if (target == null) {
      _errorMessage = 'Select a target device first.';
      notifyListeners();
      return;
    }

    try {
      final pick = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      final selectedPaths =
          pick?.paths.whereType<String>().toList(growable: false) ?? <String>[];
      if (selectedPaths.isEmpty) {
        return;
      }
      await _transferSessionCoordinator.outgoingTransferSendBoundary
          .sendFilesToDevice(
            targetIp: target.ip,
            targetName: target.displayName,
            selectedPaths: selectedPaths,
          );
    } catch (error) {
      _errorMessage = 'Failed to send transfer request: $error';
      _log(_errorMessage!);
    } finally {
      notifyListeners();
    }
  }

  Future<void> _refresh({
    required bool isManual,
    bool refreshNetworkScope = true,
  }) async {
    if (_isRefreshInProgress) {
      _log('Refresh skipped. Another refresh is already running.');
      return;
    }

    _isRefreshInProgress = true;
    if (isManual) {
      _isManualRefreshInProgress = true;
      _state = DiscoveryFlowState.discovering;
      notifyListeners();
    }

    try {
      if (refreshNetworkScope) {
        await _discoveryNetworkScopeStore.refresh();
      }
      await _ensureDiscoveryScopeApplied();
      _log('${isManual ? "Manual" : "Auto"} refresh scan started');
      final now = DateTime.now();
      final refreshResult = await _refreshRunner.run(
        currentDevicesByIp: _devicesByIp,
        localSourceIps: _discoveryNetworkScopeStore.activeLocalIps,
        configuredTargetIps: _configuredDiscoveryTargetsStore.targetSet,
        observedAt: now,
        selectedDeviceIp: _selectedDeviceIp,
        isDisposed: () => _isDisposed,
      );
      if (_isDisposed) {
        return;
      }
      _log(
        '${isManual ? "Manual" : "Auto"} refresh scan finished. hosts=${refreshResult.hostCount}',
      );

      _devicesByIp
        ..clear()
        ..addAll(refreshResult.devicesByIp);
      if (_selectedDeviceIp != null &&
          (!refreshResult.hasSelectedDevice ||
              !_isDeviceVisibleInSelectedProjection(_selectedDeviceIp!))) {
        _selectedDeviceIp = null;
      }
      _expireStalePresence(now: now, notifyListenersWhenChanged: false);
      _log(
        'Device list updated. total=${_devicesByIp.length} '
        'appDetected=$appDetectedCount removed=${refreshResult.removedIps.length}',
      );

      _errorMessage = null;
    } catch (error) {
      if (_isDisposed) {
        return;
      }
      _errorMessage = 'Host scan failed: $error';
      _log(_errorMessage!);
    } finally {
      if (!_isDisposed) {
        _isRefreshInProgress = false;
        if (isManual) {
          _isManualRefreshInProgress = false;
          _state = DiscoveryFlowState.idle;
        }
        notifyListeners();
        if (_pendingScopeReconfigureAfterRefresh) {
          _pendingScopeReconfigureAfterRefresh = false;
          unawaited(_refresh(isManual: false, refreshNetworkScope: false));
        } else if (_pendingDiscoveryRestartAfterRefresh) {
          _pendingDiscoveryRestartAfterRefresh = false;
          unawaited(_restartDiscoveryAfterAndroidResume());
        }
      }
    }
  }

  void _onAppDetected(AppPresenceEvent event) {
    _log('App handshake detected from ${event.ip} (${event.deviceName})');
    final existing = _devicesByIp[event.ip];
    final result = _devicePresenceProjector.projectAppPresence(
      event: event,
      existing: existing,
      friends: _internetPeerEndpointStore.peers,
    );
    _devicesByIp[event.ip] = result.device;
    final normalizedMac = result.normalizedMacAddress;
    final normalizedPeerId = result.normalizedPeerId;
    if (normalizedMac != null && normalizedPeerId != null) {
      final persistedMac = _deviceRegistry.macForPeerId(normalizedPeerId);
      final persistedIpMac = _deviceRegistry.macForIp(event.ip);
      if (persistedMac != normalizedMac || persistedIpMac != normalizedMac) {
        unawaited(
          _deviceRegistry.recordPeerIdentity(
            macAddress: normalizedMac,
            peerId: normalizedPeerId,
            ip: event.ip,
          ),
        );
      }
    }
    notifyListeners();
  }

  void _handleNearbyTransferAvailabilityChanged() {
    if (!_started) {
      return;
    }
    unawaited(
      _lanDiscoveryService.broadcastPresenceNow(deviceName: _localName),
    );
  }

  void _handleConfiguredDiscoveryTargetsChanged() {
    if (_started) {
      if (_isRefreshInProgress) {
        _pendingScopeReconfigureAfterRefresh = true;
      } else {
        unawaited(_refresh(isManual: false, refreshNetworkScope: false));
      }
    }
    notifyListeners();
  }

  void _onTransferRequest(TransferRequestEvent event) {
    _transferSessionCoordinator.incomingTransferRequestBoundary
        .handleTransferRequestEvent(event);
  }

  void _onFriendRequest(FriendRequestEvent event) {
    final result = _friendRequestRouter.handleFriendRequest(event);
    if (result.infoMessage != null) {
      _infoMessage = result.infoMessage;
    }
    if (result.shouldNotifyListeners) {
      notifyListeners();
    }
  }

  void _onFriendResponse(FriendResponseEvent event) {
    unawaited(
      _applyFriendResponseResult(
        _friendRequestRouter.acceptFriendResponse(event),
      ),
    );
  }

  Future<void> _applyFriendResponseResult(
    Future<DiscoveryFriendRequestResult> resultFuture,
  ) async {
    final result = await resultFuture;
    if (result.errorMessage == null && result.infoMessage == null) {
      return;
    }
    _errorMessage = result.errorMessage;
    if (result.infoMessage != null) {
      _infoMessage = result.infoMessage;
    }
    notifyListeners();
  }

  Future<void> _rememberVisibleFriendPeer({
    required String ip,
    required String macAddress,
    required String deviceName,
    required DateTime observedAt,
    String? peerId,
  }) async {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    final trimmedIp = ip.trim();
    if (normalizedMac == null || trimmedIp.isEmpty) {
      return;
    }

    final existing = _devicesByIp[trimmedIp];
    final projected = _devicePresenceProjector.projectVisibleFriendPeer(
      ip: trimmedIp,
      macAddress: normalizedMac,
      deviceName: deviceName,
      observedAt: observedAt,
      existing: existing,
      peerId: peerId,
    );
    if (projected == null) {
      return;
    }
    _devicesByIp[trimmedIp] = projected;
    final normalizedPeerId =
        DiscoveryDevicePresenceProjector.normalizePeerId(peerId) ??
        DiscoveryDevicePresenceProjector.normalizePeerId(existing?.peerId);
    if (normalizedPeerId != null) {
      await _deviceRegistry.recordPeerIdentity(
        macAddress: normalizedMac,
        peerId: normalizedPeerId,
        ip: trimmedIp,
      );
    } else {
      await _deviceRegistry.recordSeenDevices(<String, String>{
        normalizedMac: trimmedIp,
      });
    }
  }

  void _onTransferDecision(TransferDecisionEvent event) {
    _transferSessionCoordinator.outgoingTransferSendBoundary
        .handleTransferDecisionEvent(event);
  }

  Future<void> openHistoryPath(String path) async {
    try {
      await _pathOpener.openContainingFolder(path);
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to open folder: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  void _onClipboardQuery(ClipboardQueryEvent event) {
    unawaited(_clipboardPacketRouteAdapter.handleClipboardQuery(event));
  }

  void _onClipboardCatalog(ClipboardCatalogEvent event) {
    final result = _clipboardPacketRouteAdapter.handleClipboardCatalog(event);
    if (result == null) {
      return;
    }

    final existing = _devicesByIp[result.ownerIp];
    final ownerMac = _devicePresenceProjector.resolveStableDeviceMac(
      ip: result.ownerIp,
      observedMac: result.ownerMacAddress,
      existingMac: existing?.macAddress,
    );
    final aliasName = _deviceRegistry.aliasForMac(ownerMac);
    _devicesByIp[result.ownerIp] =
        (existing ??
                DiscoveredDevice(
                  ip: result.ownerIp,
                  lastSeen: result.observedAt,
                ))
            .copyWith(
              deviceName: result.ownerName,
              isReachable: true,
              isAppDetected: true,
              appPresenceObservedAt: result.observedAt,
              macAddress: ownerMac ?? existing?.macAddress,
              lastSeen: result.observedAt,
            );

    _infoMessage =
        'Clipboard history received from ${aliasName ?? result.ownerName}.';
    _errorMessage = null;
    notifyListeners();
  }

  void _startClipboardPolling() {
    _lifecycleTimers.startClipboardPolling(
      interval: const Duration(seconds: 2),
      onTick: () => unawaited(_clipboardPacketRouteAdapter.captureSnapshot()),
    );
  }

  Future<void> _trimClipboardHistoryToSettingsLimit() async {
    await _clipboardPacketRouteAdapter.trimHistoryToSettingsLimit();
  }

  void _onShareQuery(ShareQueryEvent event) {
    unawaited(
      _remoteSharePacketRouteAdapter.handleShareQuery(event).catchError((
        Object error,
        StackTrace stack,
      ) {
        _log('Unhandled share query error from ${event.requesterIp}: $error');
        _log(stack.toString());
      }),
    );
  }

  void _onShareAccessRequest(ShareAccessRequestEvent event) {
    _transferSessionCoordinator.remoteShareAccessSessionBoundary
        .handleRequestEvent(event);
  }

  void _onShareAccessResponse(ShareAccessResponseEvent event) {
    _transferSessionCoordinator.remoteShareAccessSessionBoundary
        .handleResponseEvent(event);
  }

  void _onShareCatalog(ShareCatalogEvent event) {
    unawaited(
      _handleShareCatalog(event).catchError((Object error, StackTrace stack) {
        _log('Unhandled share catalog error from ${event.ownerIp}: $error');
        _log(stack.toString());
      }),
    );
  }

  Future<void> _handleShareCatalog(ShareCatalogEvent event) async {
    try {
      final existing = _devicesByIp[event.ownerIp];
      final ownerMac = _devicePresenceProjector.resolveStableDeviceMac(
        ip: event.ownerIp,
        observedMac: event.ownerMacAddress,
        existingMac: existing?.macAddress,
      );
      final aliasName = _deviceRegistry.aliasForMac(ownerMac);
      _devicesByIp[event.ownerIp] =
          (existing ??
                  DiscoveredDevice(
                    ip: event.ownerIp,
                    lastSeen: event.observedAt,
                  ))
              .copyWith(
                macAddress: ownerMac ?? existing?.macAddress,
                deviceName: event.ownerName,
                isAppDetected: true,
                isReachable: true,
                appPresenceObservedAt: event.observedAt,
                lastSeen: event.observedAt,
              );

      final result = await _remoteSharePacketRouteAdapter.handleShareCatalog(
        event: event,
        ownerDisplayName: aliasName ?? event.ownerName,
        ownerMacAddress: ownerMac,
      );
      if (result.removedLocalCacheCount > 0) {
        _infoMessage =
            'Remote shares updated: removed ${result.removedLocalCacheCount} stale cache(s).';
      }
      notifyListeners();
    } catch (error, stackTrace) {
      _errorMessage = 'Failed to process remote share list: $error';
      _log('Share catalog handling failed: $error');
      _log(stackTrace.toString());
      notifyListeners();
    }
  }

  void _onThumbnailSyncRequest(ThumbnailSyncRequestEvent event) {
    unawaited(
      _remoteShareMediaProjectionBoundary
          .handleThumbnailSyncRequest(
            event: event,
            ownerMacAddress: _localDeviceMac,
          )
          .catchError((Object error, StackTrace stack) {
            _log(
              'Unhandled thumbnail sync request error '
              'from ${event.requesterIp}: $error',
            );
            _log(stack.toString());
          }),
    );
  }

  void _onThumbnailPacket(ThumbnailPacketEvent event) {
    unawaited(
      _remoteShareMediaProjectionBoundary
          .handleThumbnailPacket(event: event)
          .catchError((Object error, StackTrace stack) {
            _log(
              'Unhandled thumbnail packet error from ${event.ownerIp}: $error',
            );
            _log(stack.toString());
          }),
    );
  }

  void _onDownloadRequest(DownloadRequestEvent event) {
    _transferSessionCoordinator.sharedDownloadBoundary
        .handleDownloadRequestEvent(event);
  }

  void _onDownloadResponse(DownloadResponseEvent event) {
    _transferSessionCoordinator.sharedDownloadBoundary
        .handleDownloadResponseEvent(event);
  }

  void _handleNetworkScopeChanged() {
    if (_consumeNetworkScopeState()) {
      notifyListeners();
    }
  }

  bool _consumeNetworkScopeState() {
    var changed = false;
    final nextLocalIp = _discoveryNetworkScopeStore.preferredLocalIp;
    if (_localIp != nextLocalIp) {
      _localIp = nextLocalIp;
      changed = true;
    }
    if (_selectedDeviceIp != null &&
        !_isDeviceVisibleInSelectedProjection(_selectedDeviceIp!)) {
      _selectedDeviceIp = null;
      changed = true;
    }
    return changed;
  }

  bool _isDeviceVisibleInSelectedProjection(String ip) {
    return _discoveryNetworkScopeStore.matchesSelectedScope(ip) ||
        _configuredDiscoveryTargetsStore.containsIp(ip);
  }

  Future<void> _ensureDiscoveryScopeApplied() async {
    final desiredLocalIps = _discoveryNetworkScopeStore.activeLocalIps;
    final desiredConfiguredTargets = _configuredDiscoveryTargetsStore.targetSet;
    _consumeNetworkScopeState();
    if (!_started) {
      return;
    }
    if (_isDiscoveryServiceRunning &&
        setEquals(_activeDiscoveryLocalIps, desiredLocalIps) &&
        setEquals(
          _activeDiscoveryConfiguredTargetIps,
          desiredConfiguredTargets,
        )) {
      return;
    }
    if (_isDiscoveryServiceRunning) {
      await _lanDiscoveryService.stop();
      _isDiscoveryServiceRunning = false;
    }

    await _lanDiscoveryService.start(
      deviceName: _localName,
      localPeerId: _localPeerId,
      localSourceIps: desiredLocalIps,
      configuredTargetIps: desiredConfiguredTargets,
      onAppDetected: _onAppDetected,
      onTransferRequest: _onTransferRequest,
      onTransferDecision: _onTransferDecision,
      onFriendRequest: _onFriendRequest,
      onFriendResponse: _onFriendResponse,
      onShareQuery: _onShareQuery,
      onShareAccessRequest: _onShareAccessRequest,
      onShareAccessResponse: _onShareAccessResponse,
      onShareCatalog: _onShareCatalog,
      onDownloadRequest: _onDownloadRequest,
      onDownloadResponse: _onDownloadResponse,
      onThumbnailSyncRequest: _onThumbnailSyncRequest,
      onThumbnailPacket: _onThumbnailPacket,
      onClipboardQuery: _onClipboardQuery,
      onClipboardCatalog: _onClipboardCatalog,
    );
    _activeDiscoveryLocalIps = Set<String>.from(desiredLocalIps);
    _activeDiscoveryConfiguredTargetIps = Set<String>.from(
      desiredConfiguredTargets,
    );
    _isDiscoveryServiceRunning = true;
    _log(
      'Applied discovery network scope. '
      'scope=${_discoveryNetworkScopeStore.selectedScopeId} '
      'localIps=$_activeDiscoveryLocalIps '
      'configuredTargets=$_activeDiscoveryConfiguredTargetIps',
    );
  }

  Future<void> _restartDiscoveryAfterAndroidResume() async {
    if (_isDisposed || !_started) {
      return;
    }
    if (_isRefreshInProgress) {
      _pendingDiscoveryRestartAfterRefresh = true;
      return;
    }

    _log('Android app resumed. Restarting discovery socket.');
    try {
      await _forceDiscoveryServiceRestart();
      await Future<void>.delayed(_androidResumeRestartDelay);
      if (!_isDisposed && _started) {
        await _lanDiscoveryService.broadcastPresenceNow(deviceName: _localName);
      }
    } catch (error) {
      if (_isDisposed) {
        return;
      }
      _errorMessage = 'LAN discovery resume error: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> _forceDiscoveryServiceRestart() async {
    await _discoveryNetworkScopeStore.refresh();
    _consumeNetworkScopeState();
    if (!_started) {
      return;
    }
    if (_isDiscoveryServiceRunning) {
      await _lanDiscoveryService.stop();
      _isDiscoveryServiceRunning = false;
    }
    _activeDiscoveryLocalIps = <String>{};
    _activeDiscoveryConfiguredTargetIps = <String>{};
    await _ensureDiscoveryScopeApplied();
  }

  void _resolveLocalDeviceMac() {
    final peerId = _localPeerId.trim();
    final stableIdentitySeed = peerId.isNotEmpty
        ? 'peer:$peerId'
        : '${_localIp ?? "0.0.0.0"}|$_localName';
    final digest = sha256.convert(utf8.encode(stableIdentitySeed)).bytes;
    final bytes = digest.take(6).toList(growable: false);
    bytes[0] = (bytes[0] & 0xfe) | 0x02;
    _localDeviceMac = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  Future<void> _loadOwnerCaches() async {
    try {
      if (!_ownerCacheMacRebindChecked) {
        _ownerCacheMacRebindChecked = true;
        final result = await _sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: _localDeviceMac,
          rebindOwnerCachesToMac: true,
        );
        final reboundCount = result.reboundCount;
        if (reboundCount > 0) {
          _log(
            'Rebound $reboundCount owner shared cache(s) to local MAC $_localDeviceMac',
          );
        }
      } else {
        await _sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: _localDeviceMac,
        );
      }
    } catch (error) {
      _log('Failed to load owner cache list: $error');
    }
  }

  void _applySharedFolderIndexingState(SharedFolderIndexingState state) {
    _isAddingShare = state.isAddingShare;
    _sharedFolderIndexingProgress = state.progress;
    _sharedFolderIndexingVisualProgress = state.visualProgress;
    notifyListeners();
  }

  Future<void> _setFriendStatus({
    required String macAddress,
    required bool isFriend,
  }) async {
    final normalizedMac = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalizedMac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }

    if (isFriend) {
      await _trustedLanPeerStore.trustDevice(macAddress: normalizedMac);
    } else {
      await _trustedLanPeerStore.revokeTrust(macAddress: normalizedMac);
    }
  }

  void _restartAutoRefreshTimer() {
    _lifecycleTimers.restartAutoRefresh(
      interval: _activeAutoRefreshInterval,
      onTick: () => unawaited(_refresh(isManual: false)),
    );
    _log(
      'Auto-refresh timer restarted. '
      'foreground=$_isAppInForeground '
      'interval=${_activeAutoRefreshInterval.inSeconds}s',
    );
  }

  void _restartPresenceExpiryTimer() {
    _lifecycleTimers.restartPresenceExpiry(
      interval: _presenceExpiryCheckInterval,
      onTick: _expireStalePresence,
    );
  }

  void _expireStalePresence({
    DateTime? now,
    bool notifyListenersWhenChanged = true,
  }) {
    final observedNow = now ?? _now();
    final staleIps = <String>[];
    var changed = false;

    _devicesByIp.forEach((ip, device) {
      final expiry = _presenceExpiryPolicy.expire(
        now: observedNow,
        device: device,
      );
      final nextDevice = expiry.device;

      if (expiry.shouldRemove) {
        staleIps.add(ip);
        if (expiry.changed) {
          changed = true;
        }
        return;
      }

      if (expiry.changed) {
        _devicesByIp[ip] = nextDevice;
        changed = true;
      }
    });

    if (staleIps.isNotEmpty) {
      for (final ip in staleIps) {
        _devicesByIp.remove(ip);
      }
      if (_selectedDeviceIp != null && staleIps.contains(_selectedDeviceIp)) {
        _selectedDeviceIp = null;
      }
      changed = true;
    }

    if (changed && notifyListenersWhenChanged) {
      notifyListeners();
    }
  }

  Duration get _activeAutoRefreshInterval {
    return _currentSettings.backgroundScanInterval.duration;
  }

  Future<void> _cleanupPreviewCacheBySettings() async {
    try {
      final result = await _previewCacheOwner.cleanupPreviewArtifacts(
        maxSizeGb: _currentSettings.previewCacheMaxSizeGb,
        maxAgeDays: _currentSettings.previewCacheMaxAgeDays,
      );
      if (result.filesDeleted > 0) {
        _log(
          'Preview cache cleanup complete. '
          'deleted=${result.filesDeleted} freedBytes=${result.bytesFreed} '
          'remaining=${result.filesRemaining} remainingBytes=${result.remainingBytes}',
        );
      }
    } catch (error) {
      _log('Failed to cleanup preview cache: $error');
    }
  }

  int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < 4; i += 1) {
      final cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) {
        return cmp;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _started = false;
    _lifecycleTimers.cancelAll();
    _discoveryNetworkScopeStore.removeListener(_handleNetworkScopeChanged);
    _configuredDiscoveryTargetsStore.removeListener(
      _handleConfiguredDiscoveryTargetsChanged,
    );
    _nearbyTransferAvailabilityStore.removeListener(
      _handleNearbyTransferAvailabilityChanged,
    );
    _downloadHistoryBoundary.dispose();
    _clipboardHistoryStore.dispose();
    _remoteClipboardProjectionStore.dispose();
    _transferSessionCoordinator.removeListener(
      _handleTransferSessionCoordinatorChanged,
    );
    _transferSessionCoordinator.dispose();
    _isDiscoveryServiceRunning = false;
    _activeDiscoveryLocalIps = <String>{};
    _activeDiscoveryConfiguredTargetIps = <String>{};
    _lanDiscoveryService.stop();
    super.dispose();
  }

  void _applyFriendCommandResult(DiscoveryFriendCommandResult result) {
    _errorMessage = result.errorMessage;
    if (result.infoMessage != null && result.infoMessage!.isNotEmpty) {
      _infoMessage = result.infoMessage;
    }
    _isFriendMutationInProgress = false;
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'DiscoveryController');
  }

  String? _resolveRemoteOwnerMac({
    required String ownerIp,
    required String cacheId,
  }) {
    return _remoteShareBrowser.ownerMacForCache(
      ownerIp: ownerIp,
      cacheId: cacheId,
    );
  }

  DiscoveredDevice _projectDeviceFromOwners(DiscoveredDevice device) {
    final normalizedMac = DeviceAliasRepository.normalizeMac(device.macAddress);
    return device.copyWith(
      macAddress: normalizedMac ?? device.macAddress,
      aliasName: _deviceRegistry.aliasForMac(normalizedMac) ?? device.aliasName,
      isTrusted: _trustedLanPeerStore.isTrustedMac(normalizedMac),
    );
  }
}

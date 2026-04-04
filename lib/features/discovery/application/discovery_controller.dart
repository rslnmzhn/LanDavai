import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
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
import '../../clipboard/domain/clipboard_entry.dart';
import '../../files/application/preview_cache_owner.dart';
import 'remote_share_media_projection_boundary.dart';
import 'remote_share_browser.dart';
import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/application/shared_cache_owner_contracts.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import 'device_registry.dart';
import 'internet_peer_endpoint_store.dart';
import 'local_peer_identity_store.dart';
import 'trusted_lan_peer_store.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_packet_codec.dart';
import '../data/lan_protocol_events.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';
import 'discovery_network_scope_store.dart';

enum DiscoveryFlowState { idle, discovering }

class IncomingFriendRequest {
  const IncomingFriendRequest({
    required this.requestId,
    required this.senderIp,
    required this.senderName,
    required this.senderMacAddress,
    required this.createdAt,
  });

  final String requestId;
  final String senderIp;
  final String senderName;
  final String senderMacAddress;
  final DateTime createdAt;
}

class _PendingOutgoingFriendRequest {
  const _PendingOutgoingFriendRequest({
    required this.requestId,
    required this.targetIp,
    required this.targetName,
    required this.targetMacAddress,
    required this.createdAt,
  });

  final String requestId;
  final String targetIp;
  final String targetName;
  final String targetMacAddress;
  final DateTime createdAt;
}

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

class SharedFolderIndexingProgress {
  const SharedFolderIndexingProgress({
    required this.processedFiles,
    required this.totalFiles,
    required this.currentRelativePath,
    required this.stage,
    required this.eta,
  });

  final int processedFiles;
  final int totalFiles;
  final String currentRelativePath;
  final OwnerCacheProgressStage stage;
  final Duration? eta;
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
    DateTime Function()? nowProvider,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _networkHostScanner = networkHostScanner,
       _deviceRegistry = deviceRegistry,
       _internetPeerEndpointStore = internetPeerEndpointStore,
       _trustedLanPeerStore = trustedLanPeerStore,
       _localPeerIdentityStore = localPeerIdentityStore,
       _discoveryNetworkScopeStore = discoveryNetworkScopeStore,
       _settingsStore = settingsStore,
       _appNotificationService = appNotificationService,
       _remoteShareBrowser = remoteShareBrowser,
       _remoteShareMediaProjectionBoundary = remoteShareMediaProjectionBoundary,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _previewCacheOwner = previewCacheOwner,
       _pathOpener = pathOpener,
       _appPresenceTtl = appPresenceTtl,
       _nearbyAvailabilityTtl = nearbyAvailabilityTtl,
       _presenceExpiryCheckInterval = presenceExpiryCheckInterval,
       _now = nowProvider ?? DateTime.now,
       _nearbyTransferAvailabilityStore =
           nearbyTransferAvailabilityStore ??
           NearbyTransferAvailabilityStore() {
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
          previewCacheOwner: previewCacheOwner,
          appNotificationService: appNotificationService,
          settingsProvider: () => _settingsStore.settings,
          localNameProvider: () => _localName,
          localDeviceMacProvider: () => _localDeviceMac,
          isTrustedSender: (normalizedMac) =>
              _trustedLanPeerStore.isTrustedMac(normalizedMac),
          resolveRemoteOwnerMac:
              ({required String ownerIp, required String cacheId}) =>
                  _resolveRemoteOwnerMac(ownerIp: ownerIp, cacheId: cacheId),
        );
    _discoveryNetworkScopeStore.addListener(_handleNetworkScopeChanged);
    _nearbyTransferAvailabilityStore.addListener(
      _handleNearbyTransferAvailabilityChanged,
    );
    _transferSessionCoordinator.addListener(
      _handleTransferSessionCoordinatorChanged,
    );
  }

  static const Duration _pendingFriendRequestTtl = Duration(minutes: 2);
  static const Duration _sharedFolderIndexingUiTickInterval = Duration(
    milliseconds: 120,
  );
  static const double _sharedFolderScanProgressWeight = 0.35;
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;
  final DeviceRegistry _deviceRegistry;
  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final TrustedLanPeerStore _trustedLanPeerStore;
  final LocalPeerIdentityStore _localPeerIdentityStore;
  final DiscoveryNetworkScopeStore _discoveryNetworkScopeStore;
  final SettingsStore _settingsStore;
  final AppNotificationService _appNotificationService;
  final RemoteShareBrowser _remoteShareBrowser;
  final RemoteShareMediaProjectionBoundary _remoteShareMediaProjectionBoundary;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final PreviewCacheOwner _previewCacheOwner;
  final PathOpener _pathOpener;
  final Duration _appPresenceTtl;
  final Duration _nearbyAvailabilityTtl;
  final Duration _presenceExpiryCheckInterval;
  final DateTime Function() _now;
  final NearbyTransferAvailabilityStore _nearbyTransferAvailabilityStore;
  late final DownloadHistoryBoundary _downloadHistoryBoundary;
  late final ClipboardHistoryStore _clipboardHistoryStore;
  late final RemoteClipboardProjectionStore _remoteClipboardProjectionStore;
  late final TransferSessionCoordinator _transferSessionCoordinator;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  final List<IncomingFriendRequest> _incomingFriendRequests =
      <IncomingFriendRequest>[];
  final Map<String, _PendingOutgoingFriendRequest>
  _pendingOutgoingFriendRequestsByRequestId =
      <String, _PendingOutgoingFriendRequest>{};
  Timer? _scanTimer;
  Timer? _clipboardPollTimer;
  Timer? _presenceExpiryTimer;
  bool _started = false;
  bool _isDiscoveryServiceRunning = false;
  bool _isAppInForeground = true;
  bool _isRefreshInProgress = false;
  bool _isManualRefreshInProgress = false;
  bool _isAddingShare = false;
  SharedFolderIndexingProgress? _sharedFolderIndexingProgress;
  double? _sharedFolderIndexingVisualProgress;

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
      List<IncomingFriendRequest>.unmodifiable(_incomingFriendRequests);
  String get selectedNetworkScopeId =>
      _discoveryNetworkScopeStore.selectedScopeId;

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
    _purgeExpiredPendingFriendRequests();
    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      return false;
    }
    return _pendingOutgoingFriendRequestsByRequestId.values.any(
      (pending) => pending.targetMacAddress == mac,
    );
  }

  Future<void> start() async {
    if (_started) {
      _log('start() ignored: controller already started');
      return;
    }

    _started = true;

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
      await _settingsStore.load();
      final settings = _currentSettings;
      _log(
        'Loaded settings. background=${settings.backgroundScanInterval.label}, '
        'notifyDownloadAttempts=${settings.downloadAttemptNotificationsEnabled}, '
        'trayOnClose=${settings.minimizeToTrayOnClose}, '
        'previewMaxSizeGb=${settings.previewCacheMaxSizeGb}, '
        'previewMaxAgeDays=${settings.previewCacheMaxAgeDays}, '
        'clipboardMaxEntries=${settings.clipboardHistoryMaxEntries}, '
        'recacheWorkers=${settings.recacheParallelWorkers}',
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
      _log('Starting discovery. localName=$_localName localIp=$_localIp');
      _syncInternetPeers();
      await _ensureDiscoveryScopeApplied();
      await _refresh(isManual: false, refreshNetworkScope: false);
      _restartAutoRefreshTimer();
      _restartPresenceExpiryTimer();
      _startClipboardPolling();
    } catch (error) {
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
    final normalizedId = friendId.trim();
    if (normalizedId.isEmpty) {
      _errorMessage = 'Friend ID is required.';
      notifyListeners();
      return;
    }

    final parsedEndpoint = _parseEndpoint(endpoint);
    if (parsedEndpoint == null) {
      _errorMessage =
          'Endpoint must be in IPv4:port format, for example 203.0.113.7:40404.';
      notifyListeners();
      return;
    }

    _isFriendMutationInProgress = true;
    notifyListeners();
    try {
      await _internetPeerEndpointStore.saveEndpoint(
        friendId: normalizedId,
        displayName: displayName.trim(),
        endpointHost: parsedEndpoint.$1,
        endpointPort: parsedEndpoint.$2,
        isEnabled: isEnabled,
      );
      _syncInternetPeers();
      _errorMessage = null;
      _infoMessage = 'Friend saved: $normalizedId';
    } catch (error) {
      _errorMessage = 'Failed to save friend: $error';
      _log(_errorMessage!);
    } finally {
      _isFriendMutationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> removeFriend(String friendId) async {
    _isFriendMutationInProgress = true;
    notifyListeners();
    try {
      await _internetPeerEndpointStore.removeEndpoint(friendId);
      _syncInternetPeers();
      _errorMessage = null;
      _infoMessage = 'Friend removed: ${friendId.trim()}';
    } catch (error) {
      _errorMessage = 'Failed to remove friend: $error';
      _log(_errorMessage!);
    } finally {
      _isFriendMutationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> setFriendEnabled({
    required String friendId,
    required bool enabled,
  }) async {
    try {
      await _internetPeerEndpointStore.setEndpointEnabled(
        friendId: friendId,
        isEnabled: enabled,
      );
      _syncInternetPeers();
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to update friend: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> updateBackgroundScanInterval(
    BackgroundScanIntervalOption interval,
  ) async {
    if (_currentSettings.backgroundScanInterval == interval) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(backgroundScanInterval: interval),
    );
  }

  Future<void> setDownloadAttemptNotificationsEnabled(bool enabled) async {
    if (_currentSettings.downloadAttemptNotificationsEnabled == enabled) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(downloadAttemptNotificationsEnabled: enabled),
    );
  }

  Future<void> setUseStandardAppDownloadFolder(bool enabled) async {
    if (_currentSettings.useStandardAppDownloadFolder == enabled) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(useStandardAppDownloadFolder: enabled),
    );
  }

  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    if (_currentSettings.minimizeToTrayOnClose == enabled) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(minimizeToTrayOnClose: enabled),
    );
  }

  Future<void> setLeftHandedMode(bool enabled) async {
    if (_currentSettings.isLeftHandedMode == enabled) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(isLeftHandedMode: enabled),
    );
  }

  Future<void> setVideoLinkPassword(String value) async {
    final normalized = value.trim();
    if (_currentSettings.videoLinkPassword == normalized) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(videoLinkPassword: normalized),
    );
  }

  Future<void> setPreviewCacheMaxSizeGb(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_currentSettings.previewCacheMaxSizeGb == normalized) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(previewCacheMaxSizeGb: normalized),
    );
  }

  Future<void> setPreviewCacheMaxAgeDays(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_currentSettings.previewCacheMaxAgeDays == normalized) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(previewCacheMaxAgeDays: normalized),
    );
  }

  Future<void> setClipboardHistoryMaxEntries(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_currentSettings.clipboardHistoryMaxEntries == normalized) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(clipboardHistoryMaxEntries: normalized),
    );
    await _trimClipboardHistoryToSettingsLimit();
  }

  Future<void> setRecacheParallelWorkers(int value) async {
    final normalized = value < 0 ? 0 : value;
    if (_currentSettings.recacheParallelWorkers == normalized) {
      return;
    }
    await _persistSettingsViaStore(
      _currentSettings.copyWith(recacheParallelWorkers: normalized),
    );
  }

  void setAppForegroundState(bool isForeground) {
    if (_isAppInForeground == isForeground) {
      return;
    }
    _isAppInForeground = isForeground;
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
    if (!device.isAppDetected) {
      _errorMessage = 'Friend request is available only for Landa devices.';
      notifyListeners();
      return;
    }

    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      _errorMessage = 'Cannot send friend request until MAC address is known.';
      notifyListeners();
      return;
    }

    if (_trustedLanPeerStore.isTrustedMac(mac)) {
      _infoMessage = '${device.displayName} is already in your friends list.';
      notifyListeners();
      return;
    }

    _purgeExpiredPendingFriendRequests();
    final alreadyPending = _pendingOutgoingFriendRequestsByRequestId.values.any(
      (pending) => pending.targetMacAddress == mac,
    );
    if (alreadyPending) {
      _infoMessage = 'Friend request already sent to ${device.displayName}.';
      notifyListeners();
      return;
    }

    final requestId = _fileHashService.buildStableId(
      'friend-request|${DateTime.now().microsecondsSinceEpoch}|$mac|$_localDeviceMac',
    );

    _isFriendMutationInProgress = true;
    notifyListeners();
    try {
      await _lanDiscoveryService.sendFriendRequest(
        targetIp: device.ip,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
      );
      _pendingOutgoingFriendRequestsByRequestId[requestId] =
          _PendingOutgoingFriendRequest(
            requestId: requestId,
            targetIp: device.ip,
            targetName: device.displayName,
            targetMacAddress: mac,
            createdAt: DateTime.now(),
          );
      _errorMessage = null;
      _infoMessage = 'Friend request sent to ${device.displayName}.';
    } catch (error) {
      _errorMessage = 'Failed to send friend request: $error';
      _log(_errorMessage!);
    } finally {
      _isFriendMutationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> respondToFriendRequest({
    required String requestId,
    required bool accept,
  }) async {
    final index = _incomingFriendRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index < 0) {
      return;
    }

    final request = _incomingFriendRequests[index];
    _incomingFriendRequests.removeAt(index);

    _isFriendMutationInProgress = true;
    notifyListeners();

    try {
      if (accept) {
        await _rememberVisibleFriendPeer(
          ip: request.senderIp,
          macAddress: request.senderMacAddress,
          deviceName: request.senderName,
          observedAt: request.createdAt,
        );
        await _setFriendStatus(
          macAddress: request.senderMacAddress,
          isFriend: true,
        );
        _infoMessage = '${request.senderName} added to friends.';
      } else {
        _infoMessage = 'Friend request from ${request.senderName} declined.';
      }

      await _lanDiscoveryService.sendFriendResponse(
        targetIp: request.senderIp,
        requestId: request.requestId,
        responderName: _localName,
        responderMacAddress: _localDeviceMac,
        accepted: accept,
      );
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to process friend request: $error';
      _log(_errorMessage!);
    } finally {
      _isFriendMutationInProgress = false;
      notifyListeners();
    }
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
    if (!device.isAppDetected) {
      _errorMessage = 'Remote clipboard is available only for Landa devices.';
      notifyListeners();
      return;
    }

    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (!_trustedLanPeerStore.isTrustedMac(mac)) {
      _errorMessage =
          'Remote clipboard is available only for confirmed friends.';
      notifyListeners();
      return;
    }

    final requestId = _remoteClipboardProjectionStore.beginRequest(
      ownerIp: device.ip,
      localDeviceMac: _localDeviceMac,
    );
    try {
      await _lanDiscoveryService.sendClipboardQuery(
        targetIp: device.ip,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        maxEntries: _currentSettings.clipboardHistoryMaxEntries,
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      _errorMessage = null;
      if (!_remoteClipboardProjectionStore.hasEntriesFor(device.ip)) {
        _infoMessage = 'Clipboard history from ${device.displayName} is empty.';
      }
    } catch (error) {
      _errorMessage = 'Failed to request remote clipboard: $error';
      _log(_errorMessage!);
    } finally {
      _remoteClipboardProjectionStore.finishRequest(requestId: requestId);
    }
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
    final mac = _resolveStableDeviceMac(
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
    _isAddingShare = true;
    _sharedFolderIndexingProgress = null;
    _sharedFolderIndexingVisualProgress = null;
    notifyListeners();
    try {
      if (!await _ensureAndroidSharedStorageAccessForFolderCache()) {
        return;
      }

      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null || folderPath.trim().isEmpty) {
        return;
      }

      final indexingStopwatch = Stopwatch()..start();
      DateTime? lastUiTickAt;
      _sharedFolderIndexingProgress = const SharedFolderIndexingProgress(
        processedFiles: 0,
        totalFiles: 0,
        currentRelativePath: '',
        stage: OwnerCacheProgressStage.scanning,
        eta: null,
      );
      _sharedFolderIndexingVisualProgress = 0;
      notifyListeners();

      final result = await _sharedCacheCatalog.upsertOwnerFolderCache(
        ownerMacAddress: _localDeviceMac,
        folderPath: folderPath,
        parallelWorkers: _resolveRecacheParallelWorkersOverride(),
        onProgress:
            ({
              required int processedFiles,
              required int totalFiles,
              required String relativePath,
              required OwnerCacheProgressStage stage,
            }) {
              final safeProcessedFiles = math.max(0, processedFiles);
              final safeTotalFiles = math.max(0, totalFiles);
              Duration? eta;
              double nextVisualProgress;
              if (stage == OwnerCacheProgressStage.scanning ||
                  safeTotalFiles <= 0) {
                nextVisualProgress = _estimateSharedFolderScanProgress(
                  safeProcessedFiles,
                );
              } else {
                final fileProgress = (safeProcessedFiles / safeTotalFiles)
                    .clamp(0, 1)
                    .toDouble();
                nextVisualProgress =
                    _sharedFolderScanProgressWeight +
                    fileProgress * (1 - _sharedFolderScanProgressWeight);
                eta = _estimateRecacheEta(
                  elapsed: indexingStopwatch.elapsed,
                  processedFiles: safeProcessedFiles,
                  totalFiles: safeTotalFiles,
                );
              }
              final currentVisualProgress =
                  _sharedFolderIndexingVisualProgress ?? 0;
              _sharedFolderIndexingVisualProgress = math
                  .max(currentVisualProgress, nextVisualProgress)
                  .clamp(0, 1)
                  .toDouble();
              final progress = SharedFolderIndexingProgress(
                processedFiles: safeProcessedFiles,
                totalFiles: safeTotalFiles,
                currentRelativePath: relativePath,
                stage: stage,
                eta: eta,
              );
              _sharedFolderIndexingProgress = progress;
              final now = DateTime.now();
              final shouldNotify =
                  lastUiTickAt == null ||
                  now.difference(lastUiTickAt!) >=
                      _sharedFolderIndexingUiTickInterval ||
                  (safeTotalFiles > 0 && safeProcessedFiles >= safeTotalFiles);
              if (shouldNotify) {
                lastUiTickAt = now;
                notifyListeners();
              }
            },
      );
      indexingStopwatch.stop();
      final completedCount = math.max(0, result.record.itemCount);
      _sharedFolderIndexingProgress = SharedFolderIndexingProgress(
        processedFiles: completedCount,
        totalFiles: completedCount,
        currentRelativePath: '',
        stage: OwnerCacheProgressStage.indexing,
        eta: Duration.zero,
      );
      _sharedFolderIndexingVisualProgress = 1;
      notifyListeners();
      await _loadOwnerCaches();
      final delta = result.record.itemCount - result.previousItemCount;
      if (result.created) {
        _infoMessage =
            'Shared folder added. Indexed ${result.record.itemCount} file(s).';
      } else if (delta > 0) {
        _infoMessage =
            'Shared folder updated. Found $delta new file(s), '
            'total ${result.record.itemCount}.';
      } else {
        _infoMessage =
            'Shared folder re-cached. No new files, '
            'total ${result.record.itemCount}.';
      }
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to add shared folder: $error';
      _log(_errorMessage!);
    } finally {
      _sharedFolderIndexingProgress = null;
      _sharedFolderIndexingVisualProgress = null;
      _isAddingShare = false;
      notifyListeners();
    }
  }

  double _estimateSharedFolderScanProgress(int discoveredFiles) {
    if (discoveredFiles <= 0) {
      return 0;
    }
    final normalized = 1 - math.exp(-(discoveredFiles / 3000));
    final weighted = normalized * _sharedFolderScanProgressWeight;
    return weighted.clamp(0, _sharedFolderScanProgressWeight).toDouble();
  }

  Duration? _estimateRecacheEta({
    required Duration elapsed,
    required int processedFiles,
    required int totalFiles,
  }) {
    if (processedFiles <= 0 || totalFiles <= processedFiles) {
      return null;
    }
    final elapsedMs = elapsed.inMilliseconds;
    if (elapsedMs <= 0) {
      return null;
    }
    final remainingFiles = totalFiles - processedFiles;
    final etaMs = ((elapsedMs * remainingFiles) / processedFiles).round();
    if (etaMs <= 0) {
      return Duration.zero;
    }
    return Duration(milliseconds: etaMs);
  }

  int? _resolveRecacheParallelWorkersOverride() {
    final configured = _currentSettings.recacheParallelWorkers;
    if (configured <= 0) {
      return null;
    }
    return configured;
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
      await _transferSessionCoordinator.sendFilesToDevice(
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
      final hosts = await _networkHostScanner.scanActiveHosts(
        localSourceIps: _discoveryNetworkScopeStore.activeLocalIps,
      );
      final now = DateTime.now();
      _log(
        '${isManual ? "Manual" : "Auto"} refresh scan finished. hosts=${hosts.length}',
      );

      final seenMacToIp = <String, String>{};
      for (final host in hosts.entries) {
        final normalizedMac = DeviceAliasRepository.normalizeMac(host.value);
        if (normalizedMac != null) {
          seenMacToIp[normalizedMac] = host.key;
        }
      }
      if (seenMacToIp.isNotEmpty) {
        await _deviceRegistry.recordSeenDevices(seenMacToIp);
      }

      for (final host in hosts.entries) {
        final ip = host.key;
        final existing =
            _devicesByIp[ip] ?? DiscoveredDevice(ip: ip, lastSeen: now);
        final normalizedMac = _resolveStableDeviceMac(
          ip: ip,
          observedMac: host.value,
          existingMac: existing.macAddress,
        );
        _devicesByIp[ip] = existing.copyWith(
          macAddress: normalizedMac ?? existing.macAddress,
          isReachable: true,
          lastSeen: now,
        );
      }

      final staleIps = <String>[];
      _devicesByIp.forEach((ip, device) {
        if (hosts.containsKey(ip)) {
          return;
        }

        if (!device.isAppDetected) {
          staleIps.add(ip);
          return;
        }

        _devicesByIp[ip] = device.copyWith(isReachable: false);
      });
      for (final staleIp in staleIps) {
        _devicesByIp.remove(staleIp);
      }
      if (_selectedDeviceIp != null &&
          (!_devicesByIp.containsKey(_selectedDeviceIp) ||
              !_discoveryNetworkScopeStore.matchesSelectedScope(
                _selectedDeviceIp!,
              ))) {
        _selectedDeviceIp = null;
      }
      _expireStalePresence(now: now, notifyListenersWhenChanged: false);
      _log(
        'Device list updated. total=${_devicesByIp.length} '
        'appDetected=$appDetectedCount removed=${staleIps.length}',
      );

      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Host scan failed: $error';
      _log(_errorMessage!);
    } finally {
      _isRefreshInProgress = false;
      if (isManual) {
        _isManualRefreshInProgress = false;
        _state = DiscoveryFlowState.idle;
      }
      notifyListeners();
      if (_pendingScopeReconfigureAfterRefresh) {
        _pendingScopeReconfigureAfterRefresh = false;
        unawaited(_refresh(isManual: false, refreshNetworkScope: false));
      }
    }
  }

  void _onAppDetected(AppPresenceEvent event) {
    _log('App handshake detected from ${event.ip} (${event.deviceName})');
    final existing = _devicesByIp[event.ip];
    final normalizedPeerId = _normalizePeerId(event.peerId);
    final normalizedMac = _resolveStableDeviceMac(
      ip: event.ip,
      peerId: normalizedPeerId,
      observedMac: null,
      existingMac: existing?.macAddress,
    );
    final detectedOs = _normalizeOperatingSystemName(event.operatingSystem);
    final friendName = normalizedPeerId == null
        ? null
        : _displayNameForPeerId(normalizedPeerId);
    final detectedCategory = _resolveDeviceCategory(
      deviceType: event.deviceType,
      operatingSystem: detectedOs,
    );
    _devicesByIp[event.ip] =
        (existing ?? DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
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
            );
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

  String? _normalizeOperatingSystemName(String? raw) {
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

  DeviceCategory? _resolveDeviceCategory({
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

  void _onTransferRequest(TransferRequestEvent event) {
    _transferSessionCoordinator.handleTransferRequestEvent(event);
  }

  void _onFriendRequest(FriendRequestEvent event) {
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    if (normalizedSenderMac == null) {
      _log(
        'Ignoring friend request with invalid MAC from ${event.requesterIp}',
      );
      return;
    }

    if (normalizedSenderMac == _localDeviceMac) {
      return;
    }

    final senderDevice = _devicesByIp[event.requesterIp];
    final senderName = senderDevice?.displayName ?? event.requesterName;

    if (_trustedLanPeerStore.isTrustedMac(normalizedSenderMac)) {
      unawaited(
        _rememberVisibleFriendPeer(
          ip: event.requesterIp,
          macAddress: normalizedSenderMac,
          deviceName: senderName,
          observedAt: event.observedAt,
        ),
      );
      _log('Friend request from known friend $senderName. Auto-accepting.');
      notifyListeners();
      unawaited(
        _lanDiscoveryService.sendFriendResponse(
          targetIp: event.requesterIp,
          requestId: event.requestId,
          responderName: _localName,
          responderMacAddress: _localDeviceMac,
          accepted: true,
        ),
      );
      return;
    }

    unawaited(
      _rememberVisibleFriendPeer(
        ip: event.requesterIp,
        macAddress: normalizedSenderMac,
        deviceName: senderName,
        observedAt: event.observedAt,
      ),
    );
    _incomingFriendRequests.removeWhere(
      (request) =>
          request.requestId == event.requestId ||
          request.senderMacAddress == normalizedSenderMac,
    );
    _incomingFriendRequests.insert(
      0,
      IncomingFriendRequest(
        requestId: event.requestId,
        senderIp: event.requesterIp,
        senderName: senderName,
        senderMacAddress: normalizedSenderMac,
        createdAt: event.observedAt,
      ),
    );

    _infoMessage = 'New friend request from $senderName.';
    notifyListeners();
    unawaited(
      _appNotificationService.showFriendRequestNotification(
        requesterName: senderName,
      ),
    );
  }

  void _onFriendResponse(FriendResponseEvent event) {
    _purgeExpiredPendingFriendRequests();
    final pending = _pendingOutgoingFriendRequestsByRequestId.remove(
      event.requestId,
    );
    if (pending == null) {
      return;
    }

    final responderMac = DeviceAliasRepository.normalizeMac(
      event.responderMacAddress,
    );
    final responderName = event.responderName.trim().isEmpty
        ? pending.targetName
        : event.responderName;

    if (!event.accepted) {
      _infoMessage = '$responderName declined your friend request.';
      notifyListeners();
      return;
    }

    if (responderMac == null) {
      _errorMessage = 'Friend request accepted, but responder MAC is invalid.';
      notifyListeners();
      return;
    }

    unawaited(
      _setFriendAfterAcceptance(
        responderMac,
        responderName,
        responderIp: event.responderIp,
        observedAt: event.observedAt,
      ),
    );
  }

  Future<void> _setFriendAfterAcceptance(
    String responderMac,
    String responderName, {
    String? responderIp,
    DateTime? observedAt,
  }) async {
    try {
      if (responderIp != null) {
        await _rememberVisibleFriendPeer(
          ip: responderIp,
          macAddress: responderMac,
          deviceName: responderName,
          observedAt: observedAt ?? DateTime.now(),
        );
      }
      await _setFriendStatus(macAddress: responderMac, isFriend: true);
      _errorMessage = null;
      _infoMessage = '$responderName accepted your friend request.';
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to save accepted friend: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
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
    final normalizedPeerId =
        _normalizePeerId(peerId) ?? _normalizePeerId(existing?.peerId);
    final trimmedName = deviceName.trim();
    _devicesByIp[trimmedIp] =
        (existing ?? DiscoveredDevice(ip: trimmedIp, lastSeen: observedAt))
            .copyWith(
              peerId: normalizedPeerId ?? existing?.peerId,
              macAddress: normalizedMac,
              deviceName: trimmedName.isEmpty
                  ? existing?.deviceName
                  : trimmedName,
              appPresenceObservedAt: observedAt,
              isAppDetected: true,
              isReachable: true,
              lastSeen: observedAt,
            );
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
    _transferSessionCoordinator.handleTransferDecisionEvent(event);
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
    unawaited(_handleClipboardQuery(event));
  }

  Future<void> _handleClipboardQuery(ClipboardQueryEvent event) async {
    final requesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    if (!_trustedLanPeerStore.isTrustedMac(requesterMac)) {
      _log('Clipboard query from ${event.requesterIp} ignored: not a friend.');
      return;
    }

    final safeLimit = event.maxEntries <= 0
        ? (_currentSettings.clipboardHistoryMaxEntries <= 0
              ? 120
              : _currentSettings.clipboardHistoryMaxEntries)
        : event.maxEntries;

    final sourceEntries = _clipboardHistoryStore.listRecent(limit: safeLimit);
    final entries = <ClipboardCatalogItem>[];
    for (final item in sourceEntries) {
      if (item.type == ClipboardEntryType.text) {
        final text = item.textValue ?? '';
        final clipped = text.length > 6000 ? text.substring(0, 6000) : text;
        entries.add(
          ClipboardCatalogItem(
            id: item.id,
            entryType: item.type.value,
            createdAtMs: item.createdAt.millisecondsSinceEpoch,
            textValue: clipped,
          ),
        );
        continue;
      }

      final imagePath = item.imagePath;
      if (imagePath == null || imagePath.trim().isEmpty) {
        continue;
      }
      final previewBase64 = await _encodeClipboardImagePreviewBase64(imagePath);
      if (previewBase64 == null) {
        continue;
      }
      entries.add(
        ClipboardCatalogItem(
          id: item.id,
          entryType: item.type.value,
          createdAtMs: item.createdAt.millisecondsSinceEpoch,
          imagePreviewBase64: previewBase64,
        ),
      );
    }

    try {
      await _lanDiscoveryService.sendClipboardCatalog(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerName: _localName,
        ownerMacAddress: _localDeviceMac,
        entries: entries,
      );
    } catch (error) {
      _log('Failed to send clipboard catalog: $error');
    }
  }

  void _onClipboardCatalog(ClipboardCatalogEvent event) {
    final applied = _remoteClipboardProjectionStore.applyCatalog(event);
    if (!applied) {
      return;
    }

    final existing = _devicesByIp[event.ownerIp];
    final ownerMac = _resolveStableDeviceMac(
      ip: event.ownerIp,
      observedMac: event.ownerMacAddress,
      existingMac: existing?.macAddress,
    );
    final aliasName = _deviceRegistry.aliasForMac(ownerMac);
    _devicesByIp[event.ownerIp] =
        (existing ??
                DiscoveredDevice(ip: event.ownerIp, lastSeen: event.observedAt))
            .copyWith(
              deviceName: event.ownerName,
              isReachable: true,
              isAppDetected: true,
              appPresenceObservedAt: event.observedAt,
              macAddress: ownerMac ?? existing?.macAddress,
              lastSeen: event.observedAt,
            );

    _infoMessage =
        'Clipboard history received from ${aliasName ?? event.ownerName}.';
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> _encodeClipboardImagePreviewBase64(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) {
        return null;
      }
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        return null;
      }

      final longest = math.max(decoded.width, decoded.height);
      var resized = longest > 512
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 512 : null,
              height: decoded.height > decoded.width ? 512 : null,
            )
          : decoded;
      var encoded = img.encodeJpg(resized, quality: 55);
      if (encoded.length > 48 * 1024) {
        resized = img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 360 : null,
          height: decoded.height > decoded.width ? 360 : null,
        );
        encoded = img.encodeJpg(resized, quality: 45);
      }
      return base64Encode(encoded);
    } catch (_) {
      return null;
    }
  }

  void _startClipboardPolling() {
    _clipboardPollTimer?.cancel();
    _clipboardPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_captureClipboardSnapshot()),
    );
    unawaited(_captureClipboardSnapshot());
  }

  Future<void> _captureClipboardSnapshot() async {
    try {
      await _clipboardHistoryStore.captureSnapshot(
        maxEntries: _currentSettings.clipboardHistoryMaxEntries,
      );
    } catch (error) {
      _log('Clipboard capture failed: $error');
    }
  }

  Future<void> _trimClipboardHistoryToSettingsLimit() async {
    await _clipboardHistoryStore.trimHistory(
      _currentSettings.clipboardHistoryMaxEntries,
    );
  }

  void _onShareQuery(ShareQueryEvent event) {
    unawaited(
      _handleShareQuery(event).catchError((Object error, StackTrace stack) {
        _log('Unhandled share query error from ${event.requesterIp}: $error');
        _log(stack.toString());
      }),
    );
  }

  Future<void> _handleShareQuery(ShareQueryEvent event) async {
    try {
      final requesterAddress = InternetAddress.tryParse(event.requesterIp);
      if (requesterAddress == null ||
          requesterAddress.type != InternetAddressType.IPv4 ||
          requesterAddress.address == '0.0.0.0') {
        _log(
          'Ignoring share query with invalid requester IP: ${event.requesterIp}',
        );
        return;
      }

      final removedCacheIds = <String>[];
      final canPruneUnavailableCaches =
          !Platform.isAndroid || await _hasAndroidSharedStorageAccess();
      if (canPruneUnavailableCaches) {
        removedCacheIds.addAll(
          await _sharedCacheCatalog.pruneUnavailableOwnerCaches(
            ownerMacAddress: _localDeviceMac,
          ),
        );
      } else {
        _log(
          'Skipping owner cache pruning: Android shared storage access is not granted.',
        );
      }
      await _loadOwnerCaches();

      final catalog = <SharedCatalogEntryItem>[];
      for (final cache in _ownerCachesSnapshot) {
        final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
        final files = entries
            .map(
              (entry) => SharedCatalogFileItem(
                relativePath: entry.relativePath,
                sizeBytes: entry.sizeBytes,
                thumbnailId: entry.thumbnailId,
              ),
            )
            .toList(growable: false);
        final totalBytes = entries.fold<int>(
          0,
          (sum, entry) => sum + entry.sizeBytes,
        );
        catalog.add(
          SharedCatalogEntryItem(
            cacheId: cache.cacheId,
            displayName: cache.displayName,
            itemCount: entries.length,
            totalBytes: totalBytes,
            files: files,
          ),
        );
      }

      await _lanDiscoveryService.sendShareCatalog(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerName: _localName,
        ownerMacAddress: _localDeviceMac,
        entries: catalog,
        removedCacheIds: removedCacheIds,
      );
      _log(
        'Share catalog sent to ${event.requesterIp}. '
        'entries=${catalog.length} removed=${removedCacheIds.length}',
      );
    } catch (error) {
      _log('Failed to answer share query from ${event.requesterIp}: $error');
    }
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
      final ownerMac = _resolveStableDeviceMac(
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

      if (ownerMac != null) {
        final activeCacheIds = event.entries
            .map((entry) => entry.cacheId)
            .where((id) => id.trim().isNotEmpty)
            .toSet();
        final removedLocal = await _sharedCacheCatalog
            .pruneReceiverCachesForOwner(
              ownerMacAddress: ownerMac,
              receiverMacAddress: _localDeviceMac,
              activeCacheIds: activeCacheIds,
            );
        if (removedLocal.isNotEmpty) {
          _log(
            'Pruned ${removedLocal.length} stale receiver cache(s) '
            'for owner ${event.ownerIp}',
          );
          _infoMessage =
              'Remote shares updated: removed ${removedLocal.length} stale cache(s).';
        } else if (event.removedCacheIds.isNotEmpty) {
          _log(
            'Owner ${event.ownerIp} reported '
            '${event.removedCacheIds.length} removed cache(s).',
          );
        }
      }

      await _remoteShareBrowser.applyRemoteCatalog(
        event: event,
        ownerDisplayName: aliasName ?? event.ownerName,
        ownerMacAddress: ownerMac ?? event.ownerMacAddress,
      );
      unawaited(
        _remoteShareMediaProjectionBoundary
            .syncRemoteThumbnails(event: event, requesterName: _localName)
            .catchError((Object error, StackTrace stack) {
              _log(
                'Unhandled remote share media projection error '
                'from ${event.ownerIp}: $error',
              );
              _log(stack.toString());
            }),
      );
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
    _transferSessionCoordinator.handleDownloadRequestEvent(event);
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
        !_discoveryNetworkScopeStore.matchesSelectedScope(_selectedDeviceIp!)) {
      _selectedDeviceIp = null;
      changed = true;
    }
    return changed;
  }

  Future<void> _ensureDiscoveryScopeApplied() async {
    final desiredLocalIps = _discoveryNetworkScopeStore.activeLocalIps;
    _consumeNetworkScopeState();
    if (!_started) {
      return;
    }
    if (_isDiscoveryServiceRunning &&
        setEquals(_activeDiscoveryLocalIps, desiredLocalIps)) {
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
      onAppDetected: _onAppDetected,
      onTransferRequest: _onTransferRequest,
      onTransferDecision: _onTransferDecision,
      onFriendRequest: _onFriendRequest,
      onFriendResponse: _onFriendResponse,
      onShareQuery: _onShareQuery,
      onShareCatalog: _onShareCatalog,
      onDownloadRequest: _onDownloadRequest,
      onThumbnailSyncRequest: _onThumbnailSyncRequest,
      onThumbnailPacket: _onThumbnailPacket,
      onClipboardQuery: _onClipboardQuery,
      onClipboardCatalog: _onClipboardCatalog,
    );
    _activeDiscoveryLocalIps = Set<String>.from(desiredLocalIps);
    _isDiscoveryServiceRunning = true;
    _log(
      'Applied discovery network scope. '
      'scope=${_discoveryNetworkScopeStore.selectedScopeId} '
      'localIps=$_activeDiscoveryLocalIps',
    );
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

  Future<void> _persistSettingsViaStore(AppSettings settings) async {
    try {
      await _settingsStore.save(settings);
      _errorMessage = null;
      _restartAutoRefreshTimer();
      unawaited(_cleanupPreviewCacheBySettings());
      unawaited(_trimClipboardHistoryToSettingsLimit());
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to save app settings: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  void _restartAutoRefreshTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
      _activeAutoRefreshInterval,
      (_) => unawaited(_refresh(isManual: false)),
    );
    _log(
      'Auto-refresh timer restarted. '
      'foreground=$_isAppInForeground '
      'interval=${_activeAutoRefreshInterval.inSeconds}s',
    );
  }

  void _restartPresenceExpiryTimer() {
    _presenceExpiryTimer?.cancel();
    _presenceExpiryTimer = Timer.periodic(
      _presenceExpiryCheckInterval,
      (_) => _expireStalePresence(),
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
      var nextDevice = device;
      final appPresenceObservedAt = nextDevice.appPresenceObservedAt;
      final nearbyAvailabilityObservedAt =
          nextDevice.nearbyAvailabilityObservedAt;

      if (nextDevice.isNearbyTransferAvailable &&
          (nearbyAvailabilityObservedAt == null ||
              observedNow.difference(nearbyAvailabilityObservedAt) >
                  _nearbyAvailabilityTtl)) {
        nextDevice = nextDevice.copyWith(
          isNearbyTransferAvailable: false,
          nearbyTransferPort: null,
          nearbyAvailabilityObservedAt: null,
        );
      }

      if (nextDevice.isAppDetected &&
          (appPresenceObservedAt == null ||
              observedNow.difference(appPresenceObservedAt) >
                  _appPresenceTtl)) {
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

      if (!nextDevice.isAppDetected && !nextDevice.isReachable) {
        staleIps.add(ip);
        if (!identical(nextDevice, device)) {
          changed = true;
        }
        return;
      }

      if (!identical(nextDevice, device)) {
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
    _scanTimer?.cancel();
    _clipboardPollTimer?.cancel();
    _presenceExpiryTimer?.cancel();
    _discoveryNetworkScopeStore.removeListener(_handleNetworkScopeChanged);
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
    _lanDiscoveryService.stop();
    super.dispose();
  }

  void _syncInternetPeers() {
    final peers = _internetPeerEndpointStore.peers
        .where((friend) => friend.isEnabled)
        .map(
          (friend) => InternetPeerEndpoint(
            friendId: friend.friendId,
            host: friend.endpointHost,
            port: friend.endpointPort,
          ),
        )
        .toList(growable: false);
    _lanDiscoveryService.updateInternetPeers(peers);
  }

  (String, int)? _parseEndpoint(String endpoint) {
    final raw = endpoint.trim();
    if (raw.isEmpty) {
      return null;
    }

    final match = RegExp(
      r'^([0-9]{1,3}(?:\.[0-9]{1,3}){3})(?::([0-9]{1,5}))?$',
    ).firstMatch(raw);
    if (match == null) {
      return null;
    }

    final host = match.group(1)!;
    final parts = host.split('.');
    if (parts.any((part) {
      final value = int.tryParse(part);
      return value == null || value < 0 || value > 255;
    })) {
      return null;
    }

    final parsedPort =
        int.tryParse(match.group(2) ?? '') ?? LanDiscoveryService.discoveryPort;
    if (parsedPort <= 0 || parsedPort > 65535) {
      return null;
    }
    return (host, parsedPort);
  }

  void _log(String message) {
    developer.log(message, name: 'DiscoveryController');
  }

  String? _resolveStableDeviceMac({
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

    final normalizedPeerId = _normalizePeerId(peerId);
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

  String? _normalizePeerId(String? peerId) {
    final normalized = peerId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
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

  void _purgeExpiredPendingFriendRequests() {
    final now = DateTime.now();
    _pendingOutgoingFriendRequestsByRequestId.removeWhere(
      (_, pending) =>
          now.difference(pending.createdAt) > _pendingFriendRequestTtl,
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

  String? _displayNameForPeerId(String peerId) {
    for (final peer in _internetPeerEndpointStore.peers) {
      if (peer.friendId == peerId) {
        return peer.displayName;
      }
    }
    return null;
  }
}

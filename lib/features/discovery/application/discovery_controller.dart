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
import '../../history/data/transfer_history_repository.dart';
import '../../history/domain/transfer_history_record.dart';
import '../../clipboard/data/clipboard_capture_service.dart';
import '../../clipboard/data/clipboard_history_repository.dart';
import '../../clipboard/domain/clipboard_entry.dart';
import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/shared_folder_cache_repository.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../../transfer/data/video_link_share_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../../transfer/domain/transfer_request.dart';
import 'device_registry.dart';
import 'internet_peer_endpoint_store.dart';
import 'trusted_lan_peer_store.dart';
import '../data/device_alias_repository.dart';
import '../data/friend_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';
import '../domain/friend_peer.dart';

class RemoteShareOption {
  RemoteShareOption({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entry,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String ownerMacAddress;
  final SharedCatalogEntryItem entry;
}

enum DiscoveryFlowState { idle, discovering }

class _OutgoingTransferSession {
  _OutgoingTransferSession({required this.receiverName, required this.files});

  final String receiverName;
  final List<TransferSourceFile> files;
}

class _PreparedTransferFile {
  _PreparedTransferFile({
    required this.sourcePath,
    required this.announcement,
    this.deleteAfterTransfer = false,
  });

  final String sourcePath;
  final TransferAnnouncementItem announcement;
  final bool deleteAfterTransfer;
}

class _PendingRemoteDownloadIntent {
  _PendingRemoteDownloadIntent({
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.createdAt,
  });

  final String ownerIp;
  final String? ownerMacAddress;
  final String cacheId;
  final DateTime createdAt;
}

class _PendingRemotePreviewIntent {
  _PendingRemotePreviewIntent({
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.normalizedRelativePath,
    required this.createdAt,
    required this.completer,
  });

  final String ownerIp;
  final String? ownerMacAddress;
  final String cacheId;
  final String normalizedRelativePath;
  final DateTime createdAt;
  final Completer<String?> completer;
}

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

class ShareableLocalFile {
  const ShareableLocalFile({
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.virtualPath,
    required this.absolutePath,
    required this.sizeBytes,
    required this.modifiedAtMs,
    required this.isSelectionCache,
  });

  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final String virtualPath;
  final String absolutePath;
  final int sizeBytes;
  final int modifiedAtMs;
  final bool isSelectionCache;
}

class ShareableLocalFolder {
  const ShareableLocalFolder({
    required this.name,
    required this.virtualPath,
    this.removableSharedCacheId,
  });

  final String name;
  final String virtualPath;
  final String? removableSharedCacheId;
}

class ShareableLocalDirectoryListing {
  const ShareableLocalDirectoryListing({
    required this.folders,
    required this.files,
  });

  final List<ShareableLocalFolder> folders;
  final List<ShareableLocalFile> files;
}

class SharedCacheSummary {
  const SharedCacheSummary({
    required this.totalCaches,
    required this.folderCaches,
    required this.selectionCaches,
    required this.totalFiles,
  });

  final int totalCaches;
  final int folderCaches;
  final int selectionCaches;
  final int totalFiles;
}

class SharedRecacheProgress {
  const SharedRecacheProgress({
    required this.processedCaches,
    required this.totalCaches,
    required this.processedFiles,
    required this.totalFiles,
    required this.currentCacheLabel,
    required this.currentRelativePath,
    required this.eta,
  });

  final int processedCaches;
  final int totalCaches;
  final int processedFiles;
  final int totalFiles;
  final String currentCacheLabel;
  final String currentRelativePath;
  final Duration? eta;
}

class SharedRecacheReport {
  const SharedRecacheReport({
    required this.before,
    required this.after,
    required this.updatedCaches,
    required this.failedCaches,
  });

  final SharedCacheSummary before;
  final SharedCacheSummary after;
  final int updatedCaches;
  final int failedCaches;
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

class _ScopedOwnerRecacheTarget {
  const _ScopedOwnerRecacheTarget({
    required this.cache,
    required this.relativeFolderPath,
    required this.estimatedFileCount,
  });

  final SharedFolderCacheRecord cache;
  final String relativeFolderPath;
  final int estimatedFileCount;

  String get label {
    if (relativeFolderPath.isEmpty) {
      return cache.displayName;
    }
    return '${cache.displayName}/$relativeFolderPath';
  }
}

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required LanDiscoveryService lanDiscoveryService,
    required NetworkHostScanner networkHostScanner,
    required DeviceRegistry deviceRegistry,
    required InternetPeerEndpointStore internetPeerEndpointStore,
    required TrustedLanPeerStore trustedLanPeerStore,
    required FriendRepository friendRepository,
    required SettingsStore settingsStore,
    required AppNotificationService appNotificationService,
    required TransferHistoryRepository transferHistoryRepository,
    required ClipboardHistoryRepository clipboardHistoryRepository,
    required ClipboardCaptureService clipboardCaptureService,
    required SharedFolderCacheRepository sharedFolderCacheRepository,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required VideoLinkShareService videoLinkShareService,
    required PathOpener pathOpener,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _networkHostScanner = networkHostScanner,
       _deviceRegistry = deviceRegistry,
       _internetPeerEndpointStore = internetPeerEndpointStore,
       _trustedLanPeerStore = trustedLanPeerStore,
       _friendRepository = friendRepository,
       _settingsStore = settingsStore,
       _appNotificationService = appNotificationService,
       _transferHistoryRepository = transferHistoryRepository,
       _clipboardHistoryRepository = clipboardHistoryRepository,
       _clipboardCaptureService = clipboardCaptureService,
       _sharedFolderCacheRepository = sharedFolderCacheRepository,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _videoLinkShareService = videoLinkShareService,
       _pathOpener = pathOpener;

  static const Duration _pendingRemoteDownloadTtl = Duration(minutes: 3);
  static const Duration _pendingRemotePreviewTtl = Duration(minutes: 1);
  static const Duration _pendingFriendRequestTtl = Duration(minutes: 2);
  static const Duration _sharedRecacheCooldown = Duration(minutes: 5);
  static const Duration _sharedRecacheUiTickInterval = Duration(
    milliseconds: 120,
  );
  static const Duration _sharedFolderIndexingUiTickInterval = Duration(
    milliseconds: 120,
  );
  static const Duration _sharedRecacheNotificationTickInterval = Duration(
    milliseconds: 900,
  );
  static const double _sharedFolderScanProgressWeight = 0.35;
  static const int _maxRemoteFilesPerCacheForUi = 4000;
  static const int _maxThumbnailSyncItemsPerCatalog = 240;
  static const MethodChannel _androidNetworkChannel = MethodChannel(
    'landa/network',
  );

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;
  final DeviceRegistry _deviceRegistry;
  final InternetPeerEndpointStore _internetPeerEndpointStore;
  final TrustedLanPeerStore _trustedLanPeerStore;
  final FriendRepository _friendRepository;
  final SettingsStore _settingsStore;
  final AppNotificationService _appNotificationService;
  final TransferHistoryRepository _transferHistoryRepository;
  final ClipboardHistoryRepository _clipboardHistoryRepository;
  final ClipboardCaptureService _clipboardCaptureService;
  final SharedFolderCacheRepository _sharedFolderCacheRepository;
  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final VideoLinkShareService _videoLinkShareService;
  final PathOpener _pathOpener;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  final List<IncomingTransferRequest> _incomingRequests =
      <IncomingTransferRequest>[];
  final List<IncomingFriendRequest> _incomingFriendRequests =
      <IncomingFriendRequest>[];
  final List<SharedFolderCacheRecord> _ownerSharedCaches =
      <SharedFolderCacheRecord>[];
  final List<RemoteShareOption> _remoteShareOptions = <RemoteShareOption>[];
  final Map<String, String> _remoteThumbnailPathsByFileKey = <String, String>{};
  final Map<String, _OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, _OutgoingTransferSession>{};
  final Map<String, _PendingOutgoingFriendRequest>
  _pendingOutgoingFriendRequestsByRequestId =
      <String, _PendingOutgoingFriendRequest>{};
  final Map<String, _PendingRemoteDownloadIntent> _pendingRemoteDownloads =
      <String, _PendingRemoteDownloadIntent>{};
  final Map<String, _PendingRemotePreviewIntent> _pendingRemotePreviewsByKey =
      <String, _PendingRemotePreviewIntent>{};
  final Map<String, Completer<String?>> _previewResultCompletersByRequestId =
      <String, Completer<String?>>{};
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};
  final List<TransferHistoryRecord> _downloadHistory =
      <TransferHistoryRecord>[];
  final List<ClipboardHistoryEntry> _clipboardHistory =
      <ClipboardHistoryEntry>[];
  final Map<String, List<SharedFolderIndexEntry>> _ownerIndexEntriesByCacheId =
      <String, List<SharedFolderIndexEntry>>{};
  final Map<String, List<RemoteClipboardEntry>> _remoteClipboardByOwnerIp =
      <String, List<RemoteClipboardEntry>>{};
  Timer? _scanTimer;
  Timer? _clipboardPollTimer;
  bool _started = false;
  bool _isAppInForeground = true;
  bool _isRefreshInProgress = false;
  bool _isManualRefreshInProgress = false;
  bool _isAddingShare = false;
  bool _isSharedRecacheInProgress = false;
  double? _sharedRecacheProgress;
  SharedRecacheProgress? _sharedRecacheDetails;
  SharedFolderIndexingProgress? _sharedFolderIndexingProgress;
  double? _sharedFolderIndexingVisualProgress;
  DateTime? _sharedRecacheCooldownUntil;
  bool _isSendingTransfer = false;
  bool _isLoadingRemoteShares = false;
  bool _isLoadingRemoteClipboard = false;
  String? _activeShareQueryRequestId;
  String? _activeClipboardQueryRequestId;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  int _downloadReceivedBytes = 0;
  int _downloadTotalBytes = 0;
  double _uploadSpeedBytesPerSecond = 0;
  double _downloadSpeedBytesPerSecond = 0;
  DateTime? _uploadSpeedSampleAt;
  DateTime? _downloadSpeedSampleAt;
  int _uploadSpeedSampleBytes = 0;
  int _downloadSpeedSampleBytes = 0;

  DiscoveryFlowState _state = DiscoveryFlowState.idle;
  String? _localIp;
  final String _localName = Platform.localHostname;
  String _localDeviceMac = '02:00:00:00:00:01';
  String _localPeerId = '';
  bool _ownerCacheMacRebindChecked = false;
  VideoLinkShareSession? _videoLinkShareSession;
  bool _isFriendMutationInProgress = false;
  String? _selectedDeviceIp;
  String? _lastCapturedClipboardHash;
  String? _errorMessage;
  String? _infoMessage;

  DiscoveryFlowState get state => _state;
  bool get isManualRefreshInProgress => _isManualRefreshInProgress;
  bool get isAddingShare => _isAddingShare;
  bool get isSharedRecacheInProgress => _isSharedRecacheInProgress;
  double? get sharedRecacheProgress => _sharedRecacheProgress;
  SharedRecacheProgress? get sharedRecacheDetails => _sharedRecacheDetails;
  SharedFolderIndexingProgress? get sharedFolderIndexingProgress =>
      _sharedFolderIndexingProgress;
  double? get sharedFolderIndexingProgressValue =>
      _sharedFolderIndexingVisualProgress;

  bool get isSharedRecacheCooldownActive {
    final until = _sharedRecacheCooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  Duration? get sharedRecacheCooldownRemaining {
    final until = _sharedRecacheCooldownUntil;
    if (until == null) {
      return null;
    }
    final remaining = until.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      return null;
    }
    return remaining;
  }

  bool get isSendingTransfer => _isSendingTransfer;
  bool get isLoadingRemoteShares => _isLoadingRemoteShares;
  bool get isUploading =>
      _uploadTotalBytes > 0 && _uploadSentBytes < _uploadTotalBytes;
  bool get isDownloading =>
      _downloadTotalBytes > 0 && _downloadReceivedBytes < _downloadTotalBytes;
  double get uploadProgress =>
      _uploadTotalBytes == 0 ? 0 : _uploadSentBytes / _uploadTotalBytes;
  double get downloadProgress => _downloadTotalBytes == 0
      ? 0
      : _downloadReceivedBytes / _downloadTotalBytes;
  int get uploadSentBytes => _uploadSentBytes;
  int get uploadTotalBytes => _uploadTotalBytes;
  int get downloadReceivedBytes => _downloadReceivedBytes;
  int get downloadTotalBytes => _downloadTotalBytes;
  double get uploadSpeedBytesPerSecond => _uploadSpeedBytesPerSecond;
  double get downloadSpeedBytesPerSecond => _downloadSpeedBytesPerSecond;
  Duration? get uploadEta => _estimateEta(
    totalBytes: _uploadTotalBytes,
    transferredBytes: _uploadSentBytes,
    speedBytesPerSecond: _uploadSpeedBytesPerSecond,
    isActive: isUploading,
  );
  Duration? get downloadEta => _estimateEta(
    totalBytes: _downloadTotalBytes,
    transferredBytes: _downloadReceivedBytes,
    speedBytesPerSecond: _downloadSpeedBytesPerSecond,
    isActive: isDownloading,
  );
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
  List<IncomingTransferRequest> get incomingRequests =>
      List<IncomingTransferRequest>.unmodifiable(_incomingRequests);
  List<IncomingFriendRequest> get incomingFriendRequests =>
      List<IncomingFriendRequest>.unmodifiable(_incomingFriendRequests);
  List<SharedFolderCacheRecord> get ownerSharedCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerSharedCaches);
  List<RemoteShareOption> get remoteShareOptions =>
      List<RemoteShareOption>.unmodifiable(_remoteShareOptions);
  List<TransferHistoryRecord> get downloadHistory =>
      List<TransferHistoryRecord>.unmodifiable(_downloadHistory);
  VideoLinkShareSession? get videoLinkShareSession => _videoLinkShareSession;
  String? get videoLinkWatchUrl {
    final session = _videoLinkShareSession;
    if (session == null) {
      return null;
    }
    final host = _localIp?.trim();
    final safeHost = host == null || host.isEmpty
        ? InternetAddress.loopbackIPv4.address
        : host;
    return session.buildWatchUrl(hostAddress: safeHost);
  }

  List<ClipboardHistoryEntry> get clipboardHistory =>
      List<ClipboardHistoryEntry>.unmodifiable(_clipboardHistory);
  bool get isLoadingRemoteClipboard => _isLoadingRemoteClipboard;

  List<RemoteClipboardEntry> remoteClipboardEntriesFor(String ownerIp) {
    final entries = _remoteClipboardByOwnerIp[ownerIp];
    if (entries == null) {
      return const <RemoteClipboardEntry>[];
    }
    return List<RemoteClipboardEntry>.unmodifiable(entries);
  }

  String? remoteThumbnailPath({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    final key = _remoteThumbnailKey(
      ownerIp: ownerIp,
      cacheId: cacheId,
      relativePath: relativePath,
    );
    return _remoteThumbnailPathsByFileKey[key];
  }

  AppSettings get _currentSettings => _settingsStore.settings;

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

    await _resolveLocalAddress();
    _localPeerId = await _friendRepository.loadOrCreateLocalPeerId();
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
    await _loadClipboardHistory();
    await _loadOwnerCaches();
    await _loadDownloadHistory();
    try {
      await _internetPeerEndpointStore.load();
    } catch (error) {
      _log('Failed to load friends: $error');
    }

    try {
      _log('Starting discovery. localName=$_localName localIp=$_localIp');
      _syncInternetPeers();
      final discoveryPreferredSourceIp = Platform.isAndroid ? null : _localIp;
      await _lanDiscoveryService.start(
        deviceName: _localName,
        localPeerId: _localPeerId,
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
        preferredSourceIp: discoveryPreferredSourceIp,
      );

      await _refresh(isManual: false);
      _restartAutoRefreshTimer();
      _startClipboardPolling();
    } catch (error) {
      _errorMessage = 'LAN discovery error: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> refresh() => _refresh(isManual: true);

  Future<void> reloadOwnerSharedCaches() async {
    await _loadOwnerCaches();
    notifyListeners();
  }

  Future<void> removeSharedCache(SharedFolderCacheRecord cache) async {
    _isAddingShare = true;
    notifyListeners();
    try {
      await _sharedFolderCacheRepository.deleteCache(cache.cacheId);
      await _loadOwnerCaches();
      _errorMessage = null;
      _infoMessage = 'Removed from sharing: ${cache.displayName}';
    } catch (error) {
      _errorMessage = 'Failed to remove shared folder: $error';
      _log(_errorMessage!);
    } finally {
      _isAddingShare = false;
      notifyListeners();
    }
  }

  Future<bool> removeSharedCacheById(String cacheId) async {
    await _loadOwnerCaches();
    SharedFolderCacheRecord? target;
    for (final cache in _ownerSharedCaches) {
      if (cache.cacheId == cacheId) {
        target = cache;
        break;
      }
    }
    if (target == null) {
      _errorMessage = 'Shared folder is no longer available.';
      notifyListeners();
      return false;
    }

    await removeSharedCache(target);
    return _errorMessage == null;
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

    _isLoadingRemoteClipboard = true;
    _remoteClipboardByOwnerIp.remove(device.ip);
    notifyListeners();

    final requestId = _fileHashService.buildStableId(
      'clipboard-query|${DateTime.now().microsecondsSinceEpoch}|${device.ip}|$_localDeviceMac',
    );
    _activeClipboardQueryRequestId = requestId;
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
      if ((_remoteClipboardByOwnerIp[device.ip] ?? const []).isEmpty) {
        _infoMessage = 'Clipboard history from ${device.displayName} is empty.';
      }
    } catch (error) {
      _errorMessage = 'Failed to request remote clipboard: $error';
      _log(_errorMessage!);
    } finally {
      _isLoadingRemoteClipboard = false;
      notifyListeners();
    }
  }

  Future<void> removeClipboardHistoryEntry(String entryId) async {
    final normalizedId = entryId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    try {
      final removed = await _clipboardHistoryRepository.deleteById(
        normalizedId,
      );
      if (removed == null) {
        return;
      }
      await _deleteClipboardImageFileIfExists(removed.imagePath);
      await _loadClipboardHistory(notify: false, updateLastCapturedHash: false);
      _errorMessage = null;
      _infoMessage = 'Clipboard entry removed.';
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to remove clipboard entry: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> loadRemoteShareOptions() async {
    final targets = devices.where((device) => device.isAppDetected).toList();
    if (targets.isEmpty) {
      _remoteShareOptions.clear();
      _remoteThumbnailPathsByFileKey.clear();
      _infoMessage = 'No Landa devices available for shared content.';
      notifyListeners();
      return;
    }

    _isLoadingRemoteShares = true;
    _remoteShareOptions.clear();
    _remoteThumbnailPathsByFileKey.clear();
    notifyListeners();

    final requestId = _fileHashService.buildStableId(
      'share-query|${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
    );
    _activeShareQueryRequestId = requestId;
    try {
      for (final target in targets) {
        await _lanDiscoveryService.sendShareQuery(
          targetIp: target.ip,
          requestId: requestId,
          requesterName: _localName,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (_remoteShareOptions.isEmpty) {
        _infoMessage = 'No shared folders/files found on LAN devices.';
      }
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to request remote shares: $error';
      _log(_errorMessage!);
    } finally {
      _isLoadingRemoteShares = false;
      notifyListeners();
    }
  }

  Future<void> requestDownloadFromRemoteShare(RemoteShareOption option) async {
    await requestDownloadFromRemoteFiles(
      ownerIp: option.ownerIp,
      ownerName: option.ownerName,
      selectedRelativePathsByCache: <String, Set<String>>{
        option.entry.cacheId: <String>{},
      },
    );
  }

  Future<void> requestDownloadFromRemoteFiles({
    required String ownerIp,
    required String ownerName,
    required Map<String, Set<String>> selectedRelativePathsByCache,
  }) async {
    if (selectedRelativePathsByCache.isEmpty) {
      _errorMessage = 'Select at least one file before requesting download.';
      notifyListeners();
      return;
    }

    final normalizedSelection = <String, List<String>>{};
    var selectedFilesCount = 0;
    for (final entry in selectedRelativePathsByCache.entries) {
      final cacheId = entry.key.trim();
      if (cacheId.isEmpty) {
        continue;
      }
      final paths =
          entry.value
              .map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
      normalizedSelection[cacheId] = paths;
      selectedFilesCount += paths.length;
    }

    if (normalizedSelection.isEmpty) {
      _errorMessage = 'Selected file list is empty.';
      notifyListeners();
      return;
    }

    try {
      _purgeExpiredPendingRemoteDownloads();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      for (final entry in normalizedSelection.entries) {
        final requestId = _fileHashService.buildStableId(
          'download|$ownerIp|${entry.key}|$stamp|'
          '${entry.value.join(",")}|$_localDeviceMac',
        );
        await _lanDiscoveryService.sendDownloadRequest(
          targetIp: ownerIp,
          requestId: requestId,
          requesterName: _localName,
          requesterMacAddress: _localDeviceMac,
          cacheId: entry.key,
          selectedRelativePaths: entry.value,
        );

        final normalizedOwnerMac = _resolveRemoteOwnerMac(
          ownerIp: ownerIp,
          cacheId: entry.key,
        );
        final pendingKey = _pendingRemoteDownloadKey(
          ownerIp: ownerIp,
          cacheId: entry.key,
        );
        _pendingRemoteDownloads[pendingKey] = _PendingRemoteDownloadIntent(
          ownerIp: ownerIp,
          ownerMacAddress: normalizedOwnerMac,
          cacheId: entry.key,
          createdAt: DateTime.now(),
        );
      }
      _infoMessage = selectedFilesCount > 0
          ? 'Requested $selectedFilesCount file(s) from $ownerName.'
          : 'Download request sent to $ownerName.';
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to request remote download: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<String?> requestRemoteFilePreview({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String relativePath,
  }) async {
    final normalizedRelativePath = _normalizeTransferPathForMatch(relativePath);
    if (normalizedRelativePath.isEmpty) {
      _errorMessage = 'Preview path is empty.';
      notifyListeners();
      return null;
    }

    await _cleanupPreviewCacheBySettings();
    _purgeExpiredPendingRemotePreviews();
    final pendingKey = _pendingRemotePreviewKey(
      ownerIp: ownerIp,
      cacheId: cacheId,
      normalizedRelativePath: normalizedRelativePath,
    );

    final existing = _pendingRemotePreviewsByKey[pendingKey];
    if (existing != null) {
      return existing.completer.future;
    }

    final previewCompleter = Completer<String?>();
    final normalizedOwnerMac = _resolveRemoteOwnerMac(
      ownerIp: ownerIp,
      cacheId: cacheId,
    );
    _pendingRemotePreviewsByKey[pendingKey] = _PendingRemotePreviewIntent(
      ownerIp: ownerIp,
      ownerMacAddress: normalizedOwnerMac,
      cacheId: cacheId,
      normalizedRelativePath: normalizedRelativePath,
      createdAt: DateTime.now(),
      completer: previewCompleter,
    );

    try {
      final requestId = _fileHashService.buildStableId(
        'preview|$ownerIp|$cacheId|$normalizedRelativePath|'
        '${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
      );
      await _lanDiscoveryService.sendDownloadRequest(
        targetIp: ownerIp,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        cacheId: cacheId,
        selectedRelativePaths: <String>[relativePath],
        previewMode: true,
      );

      final previewPath = await previewCompleter.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => null,
      );
      if (previewPath == null) {
        _errorMessage = 'Preview timed out for $ownerName.';
        notifyListeners();
      }
      return previewPath;
    } catch (error) {
      _errorMessage = 'Failed to request preview: $error';
      _log(_errorMessage!);
      notifyListeners();
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      return null;
    } finally {
      _pendingRemotePreviewsByKey.remove(pendingKey);
    }
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

      final result = await _sharedFolderCacheRepository.upsertOwnerFolderCache(
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

  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    await _loadOwnerCaches();
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    if (normalizedFolder.isEmpty) {
      return _buildSharedCacheSummary(_ownerSharedCaches);
    }
    final targets = await _resolveScopedOwnerRecacheTargets(
      virtualFolderPath: normalizedFolder,
    );
    return _buildScopedSharedCacheSummary(targets);
  }

  Future<SharedRecacheReport?> recacheSharedContent({
    void Function(SharedRecacheProgress progress)? onProgress,
    String virtualFolderPath = '',
  }) async {
    if (_isSharedRecacheInProgress || isSharedRecacheCooldownActive) {
      return null;
    }

    _isAddingShare = true;
    _isSharedRecacheInProgress = true;
    _sharedRecacheProgress = null;
    _sharedRecacheDetails = null;
    notifyListeners();

    var shouldStartCooldown = false;
    SharedRecacheReport? report;
    final recacheStopwatch = Stopwatch()..start();
    DateTime? lastUiTickAt;
    DateTime? lastNotificationTickAt;
    try {
      await _loadOwnerCaches();
      final normalizedScopeFolder = _normalizeVirtualFolderPath(
        virtualFolderPath,
      );
      final targets = await _resolveScopedOwnerRecacheTargets(
        virtualFolderPath: normalizedScopeFolder,
      );
      if (targets.isEmpty) {
        _infoMessage = normalizedScopeFolder.isEmpty
            ? 'No shared folders/files to re-cache.'
            : 'No shared files found in selected folder.';
        _errorMessage = null;
        return null;
      }

      final before = _buildScopedSharedCacheSummary(targets);
      var updatedCount = 0;
      var failedCount = 0;
      final totalCaches = targets.length;
      var estimatedTotalFiles = targets.fold<int>(
        0,
        (sum, target) => sum + math.max(target.estimatedFileCount, 0),
      );
      var processedFilesAcrossCaches = 0;

      void publishProgress({
        required int processedCaches,
        required int processedFiles,
        required int totalFiles,
        required String currentCacheLabel,
        required String currentRelativePath,
        bool force = false,
      }) {
        final safeProcessedFiles = math.max(0, processedFiles);
        final safeTotalFiles = math.max(totalFiles, safeProcessedFiles);
        final progress = SharedRecacheProgress(
          processedCaches: processedCaches.clamp(0, totalCaches),
          totalCaches: totalCaches,
          processedFiles: safeProcessedFiles,
          totalFiles: safeTotalFiles,
          currentCacheLabel: currentCacheLabel,
          currentRelativePath: currentRelativePath,
          eta: _estimateRecacheEta(
            elapsed: recacheStopwatch.elapsed,
            processedFiles: safeProcessedFiles,
            totalFiles: safeTotalFiles,
          ),
        );
        _sharedRecacheDetails = progress;
        _sharedRecacheProgress = _resolveSharedRecacheProgressValue(progress);
        onProgress?.call(progress);

        final now = DateTime.now();
        final shouldNotifyUi =
            force ||
            lastUiTickAt == null ||
            now.difference(lastUiTickAt!) >= _sharedRecacheUiTickInterval;
        if (shouldNotifyUi) {
          lastUiTickAt = now;
          notifyListeners();
        }

        final shouldNotifyPlatform =
            force ||
            lastNotificationTickAt == null ||
            now.difference(lastNotificationTickAt!) >=
                _sharedRecacheNotificationTickInterval;
        if (shouldNotifyPlatform) {
          lastNotificationTickAt = now;
          unawaited(
            _appNotificationService.showSharedRecacheProgressNotification(
              processedCaches: progress.processedCaches,
              totalCaches: progress.totalCaches,
              currentCacheLabel: progress.currentCacheLabel,
              processedFiles: progress.processedFiles,
              totalFiles: progress.totalFiles > 0 ? progress.totalFiles : null,
              etaSeconds: progress.eta?.inSeconds,
              currentFileLabel: progress.currentRelativePath.isEmpty
                  ? null
                  : progress.currentRelativePath,
            ),
          );
        }
      }

      publishProgress(
        processedCaches: 0,
        processedFiles: 0,
        totalFiles: estimatedTotalFiles,
        currentCacheLabel: '',
        currentRelativePath: '',
        force: true,
      );

      for (var index = 0; index < targets.length; index++) {
        final target = targets[index];
        final cache = target.cache;
        var cacheTotalFiles = math.max(target.estimatedFileCount, 0);
        var cacheProcessedFiles = 0;

        void handleCacheFileProgress({
          required int processedFiles,
          required int totalFiles,
          required String relativePath,
          required OwnerCacheProgressStage stage,
        }) {
          if (stage == OwnerCacheProgressStage.scanning) {
            return;
          }
          cacheProcessedFiles = math.max(0, processedFiles);
          final normalizedTotal = math.max(totalFiles, cacheProcessedFiles);
          if (normalizedTotal != cacheTotalFiles) {
            estimatedTotalFiles += normalizedTotal - cacheTotalFiles;
            cacheTotalFiles = normalizedTotal;
          }
          final globalProcessed =
              processedFilesAcrossCaches + cacheProcessedFiles;
          if (estimatedTotalFiles < globalProcessed) {
            estimatedTotalFiles = globalProcessed;
          }
          publishProgress(
            processedCaches: index,
            processedFiles: globalProcessed,
            totalFiles: estimatedTotalFiles,
            currentCacheLabel: target.label,
            currentRelativePath: relativePath,
          );
        }

        try {
          if (cache.rootPath.startsWith('selection://')) {
            await _sharedFolderCacheRepository
                .refreshOwnerSelectionCacheEntries(
                  cache,
                  onProgress: handleCacheFileProgress,
                );
          } else if (target.relativeFolderPath.isEmpty) {
            await _sharedFolderCacheRepository.upsertOwnerFolderCache(
              ownerMacAddress: _localDeviceMac,
              folderPath: cache.rootPath,
              displayName: cache.displayName,
              parallelWorkers: _resolveRecacheParallelWorkersOverride(),
              onProgress: handleCacheFileProgress,
            );
          } else {
            await _sharedFolderCacheRepository
                .refreshOwnerFolderSubdirectoryEntries(
                  cache,
                  relativeFolderPath: target.relativeFolderPath,
                  parallelWorkers: _resolveRecacheParallelWorkersOverride(),
                  onProgress: handleCacheFileProgress,
                );
          }
          updatedCount += 1;
        } catch (error) {
          failedCount += 1;
          _log('Failed to re-cache folder ${target.label}: $error');
        }

        final finalizedCacheFiles = math.max(
          cacheProcessedFiles,
          cacheTotalFiles,
        );
        processedFilesAcrossCaches += finalizedCacheFiles;
        if (estimatedTotalFiles < processedFilesAcrossCaches) {
          estimatedTotalFiles = processedFilesAcrossCaches;
        }
        publishProgress(
          processedCaches: index + 1,
          processedFiles: processedFilesAcrossCaches,
          totalFiles: estimatedTotalFiles,
          currentCacheLabel: target.label,
          currentRelativePath: '',
          force: true,
        );
      }

      await _loadOwnerCaches();
      final afterTargets = await _resolveScopedOwnerRecacheTargets(
        virtualFolderPath: normalizedScopeFolder,
      );
      final after = _buildScopedSharedCacheSummary(afterTargets);
      report = SharedRecacheReport(
        before: before,
        after: after,
        updatedCaches: updatedCount,
        failedCaches: failedCount,
      );
      shouldStartCooldown = true;
      _sharedRecacheCooldownUntil = DateTime.now().add(_sharedRecacheCooldown);

      final summaryText =
          'Before cache: ${before.totalFiles} files, '
          'after re-cache: ${after.totalFiles} files.';
      if (updatedCount == 0) {
        _errorMessage = 'Failed to re-cache shared folders/files.';
        _infoMessage = null;
      } else {
        _errorMessage = null;
        final suffix = failedCount > 0 ? ' ($failedCount failed)' : '';
        _infoMessage =
            'Re-cached $updatedCount shared cache(s)$suffix. $summaryText';
      }
      await _appNotificationService.showSharedRecacheCompletedNotification(
        beforeFiles: before.totalFiles,
        afterFiles: after.totalFiles,
      );
      return report;
    } catch (error) {
      _errorMessage = 'Failed to re-cache shared folders/files: $error';
      _log(_errorMessage!);
      return report;
    } finally {
      recacheStopwatch.stop();
      _isAddingShare = false;
      _isSharedRecacheInProgress = false;
      _sharedRecacheProgress = null;
      _sharedRecacheDetails = null;
      if (!shouldStartCooldown) {
        _sharedRecacheCooldownUntil = null;
      }
      notifyListeners();
    }
  }

  SharedCacheSummary _buildSharedCacheSummary(
    List<SharedFolderCacheRecord> caches,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final cache in caches) {
      totalFiles += cache.itemCount;
      if (cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: caches.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  SharedCacheSummary _buildScopedSharedCacheSummary(
    List<_ScopedOwnerRecacheTarget> targets,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final target in targets) {
      totalFiles += math.max(target.estimatedFileCount, 0);
      if (target.cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: targets.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  Future<List<_ScopedOwnerRecacheTarget>> _resolveScopedOwnerRecacheTargets({
    required String virtualFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    final targets = <_ScopedOwnerRecacheTarget>[];
    for (final cache in _ownerSharedCaches) {
      final isSelection = cache.rootPath.startsWith('selection://');
      if (isSelection) {
        if (normalizedFolder.isNotEmpty) {
          continue;
        }
        targets.add(
          _ScopedOwnerRecacheTarget(
            cache: cache,
            relativeFolderPath: '',
            estimatedFileCount: math.max(cache.itemCount, 0),
          ),
        );
        continue;
      }

      final cacheVirtualRoot = _normalizeVirtualFolderPath(cache.displayName);
      if (normalizedFolder.isNotEmpty &&
          normalizedFolder != cacheVirtualRoot &&
          !normalizedFolder.startsWith('$cacheVirtualRoot/')) {
        continue;
      }

      final relativeFolderPath =
          normalizedFolder.isEmpty || normalizedFolder == cacheVirtualRoot
          ? ''
          : normalizedFolder.substring(cacheVirtualRoot.length + 1);

      var estimatedFiles = math.max(cache.itemCount, 0);
      if (relativeFolderPath.isNotEmpty) {
        estimatedFiles = await _countFilesInCacheFolder(
          cacheId: cache.cacheId,
          relativeFolderPath: relativeFolderPath,
        );
      }

      targets.add(
        _ScopedOwnerRecacheTarget(
          cache: cache,
          relativeFolderPath: relativeFolderPath,
          estimatedFileCount: estimatedFiles,
        ),
      );
    }
    return targets;
  }

  Future<int> _countFilesInCacheFolder({
    required String cacheId,
    required String relativeFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(relativeFolderPath);
    final entries = await _readOwnerIndexEntriesCached(cacheId);
    if (normalizedFolder.isEmpty) {
      return entries.length;
    }
    var count = 0;
    for (final entry in entries) {
      if (_isCacheEntryWithinFolder(entry.relativePath, normalizedFolder)) {
        count += 1;
      }
    }
    return count;
  }

  bool _isCacheEntryWithinFolder(String relativePath, String folderPath) {
    final normalizedRelative = _normalizeVirtualFolderPath(relativePath);
    final normalizedFolder = _normalizeVirtualFolderPath(folderPath);
    if (normalizedFolder.isEmpty) {
      return true;
    }
    return normalizedRelative == normalizedFolder ||
        normalizedRelative.startsWith('$normalizedFolder/');
  }

  double _resolveSharedRecacheProgressValue(SharedRecacheProgress progress) {
    if (progress.totalFiles > 0) {
      final value = progress.processedFiles / progress.totalFiles;
      return value.clamp(0, 1).toDouble();
    }
    if (progress.totalCaches <= 0) {
      return 0;
    }
    final value = progress.processedCaches / progress.totalCaches;
    return value.clamp(0, 1).toDouble();
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

  double _estimateSharedFolderScanProgress(int discoveredFiles) {
    if (discoveredFiles <= 0) {
      return 0;
    }
    final normalized = 1 - math.exp(-(discoveredFiles / 3000));
    final weighted = normalized * _sharedFolderScanProgressWeight;
    return weighted.clamp(0, _sharedFolderScanProgressWeight).toDouble();
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

      await _sharedFolderCacheRepository.buildOwnerSelectionCache(
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

  Future<List<ShareableVideoFile>> listShareableVideoFiles({
    String? cacheId,
  }) async {
    await _loadOwnerCaches();
    final files = <ShareableVideoFile>[];
    for (final cache in _ownerSharedCaches) {
      if (cacheId != null && cache.cacheId != cacheId) {
        continue;
      }
      final entries = await _sharedFolderCacheRepository.readIndexEntries(
        cache.cacheId,
      );
      for (final entry in entries) {
        if (!_sharedFolderCacheRepository.isVideoPath(entry.relativePath)) {
          continue;
        }
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }
        final file = File(absolutePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        files.add(
          ShareableVideoFile(
            id: '${cache.cacheId}|${entry.relativePath}',
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            absolutePath: absolutePath,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    files.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  Future<List<ShareableLocalFile>> listShareableLocalFiles() async {
    await _loadOwnerCaches();
    final files = <ShareableLocalFile>[];
    final seenPaths = <String>{};
    var processed = 0;

    for (final cache in _ownerSharedCaches) {
      final entries = await _sharedFolderCacheRepository.readIndexEntries(
        cache.cacheId,
      );
      for (final entry in entries) {
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }
        final normalizedPath = p.normalize(absolutePath).replaceAll('\\', '/');
        final dedupeKey = Platform.isWindows
            ? normalizedPath.toLowerCase()
            : normalizedPath;
        if (!seenPaths.add(dedupeKey)) {
          continue;
        }

        files.add(
          ShareableLocalFile(
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            virtualPath: _buildShareVirtualPath(cache: cache, entry: entry),
            absolutePath: absolutePath,
            sizeBytes: entry.sizeBytes,
            modifiedAtMs: entry.modifiedAtMs,
            isSelectionCache: cache.rootPath.startsWith('selection://'),
          ),
        );
        processed += 1;
        if (processed % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    files.sort((a, b) {
      final nameCmp = p
          .basename(a.relativePath)
          .toLowerCase()
          .compareTo(p.basename(b.relativePath).toLowerCase());
      if (nameCmp != 0) {
        return nameCmp;
      }
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  Future<ShareableLocalDirectoryListing> listShareableLocalDirectory({
    required String virtualFolderPath,
  }) async {
    if (_ownerSharedCaches.isEmpty) {
      await _loadOwnerCaches();
    }

    final folder = _normalizeVirtualFolderPath(virtualFolderPath);
    final foldersByPath = <String, ShareableLocalFolder>{};
    final files = <ShareableLocalFile>[];
    final seenFilePaths = <String>{};
    var processed = 0;

    for (final cache in _ownerSharedCaches) {
      final isSelection = cache.rootPath.startsWith('selection://');
      final cacheVirtualRoot = _normalizeVirtualFolderPath(cache.displayName);

      if (folder.isEmpty && !isSelection) {
        if (cacheVirtualRoot.isNotEmpty) {
          final key = Platform.isWindows
              ? cacheVirtualRoot.toLowerCase()
              : cacheVirtualRoot;
          foldersByPath.putIfAbsent(
            key,
            () => ShareableLocalFolder(
              name: cache.displayName,
              virtualPath: cacheVirtualRoot,
              removableSharedCacheId: cache.cacheId,
            ),
          );
        }
        continue;
      }

      if (!isSelection &&
          folder != cacheVirtualRoot &&
          !folder.startsWith('$cacheVirtualRoot/')) {
        continue;
      }
      if (isSelection && folder.isNotEmpty) {
        continue;
      }

      final subFolder = !isSelection && folder != cacheVirtualRoot
          ? folder.substring(cacheVirtualRoot.length + 1)
          : '';
      final entries = await _readOwnerIndexEntriesCached(cache.cacheId);
      for (final entry in entries) {
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }

        final virtualPath = _buildShareVirtualPath(cache: cache, entry: entry);
        final relativeInsideCache = isSelection
            ? _normalizeVirtualFolderPath(virtualPath)
            : _normalizeVirtualFolderPath(entry.relativePath);
        final rest = _relativeRestForFolder(
          folder: subFolder,
          targetPath: relativeInsideCache,
        );
        if (rest == null || rest.isEmpty) {
          continue;
        }

        final slashIndex = rest.indexOf('/');
        if (!isSelection && slashIndex != -1) {
          final folderName = rest.substring(0, slashIndex);
          final folderPath = folder.isEmpty
              ? folderName
              : '$folder/$folderName';
          final normalizedFolderPath = _normalizeVirtualFolderPath(folderPath);
          final dedupeKey = Platform.isWindows
              ? normalizedFolderPath.toLowerCase()
              : normalizedFolderPath;
          foldersByPath.putIfAbsent(
            dedupeKey,
            () => ShareableLocalFolder(
              name: folderName,
              virtualPath: normalizedFolderPath,
            ),
          );
          continue;
        }

        final normalizedPath = p.normalize(absolutePath).replaceAll('\\', '/');
        final fileKey = Platform.isWindows
            ? normalizedPath.toLowerCase()
            : normalizedPath;
        if (!seenFilePaths.add(fileKey)) {
          continue;
        }

        files.add(
          ShareableLocalFile(
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            virtualPath: virtualPath,
            absolutePath: absolutePath,
            sizeBytes: entry.sizeBytes,
            modifiedAtMs: entry.modifiedAtMs,
            isSelectionCache: isSelection,
          ),
        );
        processed += 1;
        if (processed % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    final folders = foldersByPath.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort((a, b) {
      final nameCmp = p
          .basename(a.virtualPath)
          .toLowerCase()
          .compareTo(p.basename(b.virtualPath).toLowerCase());
      if (nameCmp != 0) {
        return nameCmp;
      }
      return a.virtualPath.toLowerCase().compareTo(b.virtualPath.toLowerCase());
    });

    return ShareableLocalDirectoryListing(folders: folders, files: files);
  }

  Future<List<SharedFolderIndexEntry>> _readOwnerIndexEntriesCached(
    String cacheId,
  ) async {
    final cached = _ownerIndexEntriesByCacheId[cacheId];
    if (cached != null) {
      return cached;
    }
    final entries = await _sharedFolderCacheRepository.readIndexEntries(
      cacheId,
    );
    _ownerIndexEntriesByCacheId[cacheId] = entries;
    return entries;
  }

  String _buildShareVirtualPath({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
  }) {
    final normalizedRelative = _normalizeVirtualFolderPath(entry.relativePath);
    if (cache.rootPath.startsWith('selection://')) {
      return p.basename(normalizedRelative);
    }
    final cacheRoot = _normalizeVirtualFolderPath(cache.displayName);
    if (cacheRoot.isEmpty) {
      return normalizedRelative;
    }
    if (normalizedRelative.isEmpty) {
      return cacheRoot;
    }
    return '$cacheRoot/$normalizedRelative';
  }

  String _normalizeVirtualFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  String? _relativeRestForFolder({
    required String folder,
    required String targetPath,
  }) {
    if (folder.isEmpty) {
      return targetPath;
    }
    if (targetPath == folder) {
      return '';
    }
    if (!targetPath.startsWith('$folder/')) {
      return null;
    }
    return targetPath.substring(folder.length + 1);
  }

  Future<void> publishVideoLinkShare({
    required ShareableVideoFile file,
    required String password,
  }) async {
    final normalizedPassword = password.trim();
    if (normalizedPassword.isEmpty) {
      _errorMessage = 'Password is required for video link sharing.';
      notifyListeners();
      return;
    }

    try {
      _videoLinkShareSession = await _videoLinkShareService.publish(
        filePath: file.absolutePath,
        displayName: file.fileName,
        password: normalizedPassword,
      );
      final link = videoLinkWatchUrl;
      _errorMessage = null;
      _infoMessage = link == null
          ? 'Video link updated for ${file.fileName}.'
          : 'Video link updated: $link';
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to publish video link: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> stopVideoLinkShare() async {
    try {
      await _videoLinkShareService.stop();
      _videoLinkShareSession = null;
      _errorMessage = null;
      _infoMessage = 'Video link sharing stopped.';
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to stop video link sharing: $error';
      _log(_errorMessage!);
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

    _isSendingTransfer = true;
    String? pendingRequestId;
    notifyListeners();
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

      final cache = await _sharedFolderCacheRepository.buildOwnerSelectionCache(
        ownerMacAddress: _localDeviceMac,
        filePaths: selectedPaths,
        displayName: 'Transfer to ${target.displayName}',
      );
      await _loadOwnerCaches();

      final items = <TransferAnnouncementItem>[];
      final transferFiles = <TransferSourceFile>[];
      for (final filePath in selectedPaths) {
        final file = File(filePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }

        final sha = await _fileHashService.computeSha256ForPath(filePath);
        final announcement = TransferAnnouncementItem(
          fileName: p.basename(filePath),
          sizeBytes: stat.size,
          sha256: sha,
        );
        items.add(announcement);
        transferFiles.add(
          TransferSourceFile(
            sourcePath: filePath,
            fileName: announcement.fileName,
            sizeBytes: announcement.sizeBytes,
            sha256: announcement.sha256,
          ),
        );
      }

      if (items.isEmpty) {
        _errorMessage = 'No readable files selected.';
        notifyListeners();
        return;
      }

      final requestId = _fileHashService.buildStableId(
        '${DateTime.now().microsecondsSinceEpoch}|${target.ip}|${cache.cacheId}',
      );
      pendingRequestId = requestId;
      _pendingOutgoingTransfers[requestId] = _OutgoingTransferSession(
        receiverName: target.displayName,
        files: transferFiles,
      );
      await _lanDiscoveryService.sendTransferRequest(
        targetIp: target.ip,
        requestId: requestId,
        senderName: _localName,
        senderMacAddress: _localDeviceMac,
        sharedCacheId: cache.cacheId,
        sharedLabel: cache.displayName,
        items: items,
      );

      _infoMessage =
          'Transfer request sent to ${target.displayName}. Waiting for accept.';
      _errorMessage = null;
    } catch (error) {
      if (pendingRequestId != null) {
        _pendingOutgoingTransfers.remove(pendingRequestId);
      }
      _errorMessage = 'Failed to send transfer request: $error';
      _log(_errorMessage!);
    } finally {
      _isSendingTransfer = false;
      notifyListeners();
    }
  }

  Future<void> respondToTransferRequest({
    required String requestId,
    required bool approved,
    bool forPreview = false,
    String? previewRelativePath,
  }) async {
    final index = _incomingRequests.indexWhere((r) => r.requestId == requestId);
    if (index < 0) {
      return;
    }

    final request = _incomingRequests[index];
    final isPreview = forPreview;
    TransferReceiveSession? receiveSession;
    var skippedExistingCount = 0;
    var itemsToReceive = request.items;
    var expectedBytes = request.totalBytes;
    var decisionApproved = approved;
    final previewCompleter = isPreview
        ? _previewResultCompletersByRequestId.remove(request.requestId)
        : null;

    try {
      if (decisionApproved) {
        final destinationDirectory = isPreview
            ? await _transferStorageService.resolvePreviewDirectory(
                appFolderName: 'Landa',
              )
            : await _transferStorageService.resolveReceiveDirectory(
                appFolderName: 'Landa',
              );

        if (isPreview) {
          final normalizedPreviewPath = previewRelativePath == null
              ? null
              : _normalizeTransferPathForMatch(previewRelativePath);
          if (normalizedPreviewPath != null &&
              normalizedPreviewPath.isNotEmpty) {
            itemsToReceive = request.items
                .where(
                  (item) =>
                      _normalizeTransferPathForMatch(item.fileName) ==
                      normalizedPreviewPath,
                )
                .toList(growable: false);
          }
          if (itemsToReceive.isEmpty && request.items.isNotEmpty) {
            itemsToReceive = <TransferFileManifestItem>[request.items.first];
          }
        } else {
          itemsToReceive = await _filterMissingIncomingItems(
            items: request.items,
            destinationDirectory: destinationDirectory,
          );
          skippedExistingCount = request.items.length - itemsToReceive.length;
        }

        expectedBytes = itemsToReceive.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );

        if (itemsToReceive.isNotEmpty) {
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = expectedBytes;
          _resetDownloadSpeedTracking(currentBytes: 0);
          notifyListeners();

          if (!isPreview) {
            unawaited(
              _transferStorageService.showAndroidDownloadProgressNotification(
                requestId: request.requestId,
                senderName: request.senderName,
                receivedBytes: 0,
                totalBytes: expectedBytes,
              ),
            );
          }

          var lastNotifiedAtMs = 0;
          var lastNotifiedPercent = -1;
          receiveSession = await _fileTransferService.startReceiver(
            requestId: request.requestId,
            expectedItems: request.items,
            destinationDirectory: destinationDirectory,
            onProgress: (received, total) {
              _downloadReceivedBytes = received;
              _downloadTotalBytes = total;
              _updateDownloadSpeedTracking(currentBytes: received);
              notifyListeners();

              if (isPreview) {
                return;
              }

              final nowMs = DateTime.now().millisecondsSinceEpoch;
              final percent = total <= 0
                  ? -1
                  : (received * 100 ~/ total).clamp(0, 100);
              final isFinalChunk = total > 0 && received >= total;
              final hasMeaningfulPercentStep =
                  percent >= 0 &&
                  (lastNotifiedPercent < 0 ||
                      percent >= lastNotifiedPercent + 2);
              final shouldNotify =
                  isFinalChunk ||
                  nowMs - lastNotifiedAtMs >= 600 ||
                  hasMeaningfulPercentStep;
              if (!shouldNotify) {
                return;
              }
              lastNotifiedAtMs = nowMs;
              if (percent >= 0) {
                lastNotifiedPercent = percent;
              }
              unawaited(
                _transferStorageService.showAndroidDownloadProgressNotification(
                  requestId: request.requestId,
                  senderName: request.senderName,
                  receivedBytes: received,
                  totalBytes: total,
                ),
              );
            },
          );
          _activeReceiveSessions[request.requestId] = receiveSession;
          unawaited(
            _waitForIncomingTransferResult(
              request: request,
              session: receiveSession,
              acceptedItems: itemsToReceive,
              persistToUserDownloads: !isPreview,
              recordHistory: !isPreview,
              sendCompletionNotification: !isPreview,
              previewCompleter: previewCompleter,
            ),
          );
        } else {
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = 0;
          _clearDownloadSpeedTracking();
          if (isPreview) {
            decisionApproved = false;
            if (previewCompleter != null && !previewCompleter.isCompleted) {
              previewCompleter.complete(null);
            }
          }
        }
      }

      await _lanDiscoveryService.sendTransferDecision(
        targetIp: request.senderIp,
        requestId: request.requestId,
        approved: decisionApproved,
        receiverName: _localName,
        transferPort: decisionApproved ? receiveSession?.port : null,
        acceptedFileNames: decisionApproved
            ? itemsToReceive
                  .map((item) => item.fileName)
                  .toList(growable: false)
            : null,
      );

      if (decisionApproved && !isPreview) {
        final entries = request.items
            .map(
              (item) => SharedFolderIndexEntry(
                relativePath: item.fileName,
                sizeBytes: item.sizeBytes,
                modifiedAtMs: request.createdAt.millisecondsSinceEpoch,
              ),
            )
            .toList(growable: false);

        await _sharedFolderCacheRepository.saveReceiverCache(
          ownerMacAddress: request.senderMacAddress,
          receiverMacAddress: _localDeviceMac,
          remoteFolderIdentity: request.sharedCacheId,
          remoteDisplayName: request.sharedLabel,
          entries: entries,
        );
      }

      _incomingRequests.removeAt(index);
      if (!decisionApproved) {
        _infoMessage = isPreview
            ? 'Preview request was declined.'
            : 'Transfer declined.';
      } else if (isPreview) {
        _infoMessage = 'Preview accepted. Waiting for file stream...';
      } else if (itemsToReceive.isEmpty) {
        _infoMessage =
            'All requested files already exist locally. Transfer skipped.';
      } else if (skippedExistingCount > 0) {
        _infoMessage =
            'Transfer accepted. Skipping $skippedExistingCount existing file(s), waiting for missing files...';
      } else {
        _infoMessage = 'Transfer accepted. Waiting for file stream...';
      }
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      if (receiveSession != null) {
        await receiveSession.close();
        _activeReceiveSessions.remove(request.requestId);
      }
      if (previewCompleter != null && !previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      _previewResultCompletersByRequestId.remove(request.requestId);
      _errorMessage = 'Failed to respond to transfer request: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> _refresh({required bool isManual}) async {
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
      _log('${isManual ? "Manual" : "Auto"} refresh scan started');
      final scanPreferredSourceIp = Platform.isAndroid ? null : _localIp;
      final hosts = await _networkHostScanner.scanActiveHosts(
        preferredSourceIp: scanPreferredSourceIp,
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
          !_devicesByIp.containsKey(_selectedDeviceIp)) {
        _selectedDeviceIp = null;
      }
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
    }
  }

  void _onAppDetected(AppPresenceEvent event) {
    _log('App handshake detected from ${event.ip} (${event.deviceName})');
    final existing = _devicesByIp[event.ip];
    final normalizedMac = _resolveStableDeviceMac(
      ip: event.ip,
      observedMac: null,
      existingMac: existing?.macAddress,
    );
    final detectedOs = _normalizeOperatingSystemName(event.operatingSystem);
    final friendName = event.peerId == null
        ? null
        : _displayNameForPeerId(event.peerId!);
    final detectedCategory = _resolveDeviceCategory(
      deviceType: event.deviceType,
      operatingSystem: detectedOs,
    );
    _devicesByIp[event.ip] =
        (existing ?? DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
            .copyWith(
              deviceName: friendName ?? event.deviceName,
              operatingSystem: detectedOs ?? existing?.operatingSystem,
              deviceCategory: detectedCategory,
              macAddress: normalizedMac ?? existing?.macAddress,
              isAppDetected: true,
              isReachable: true,
              lastSeen: event.observedAt,
            );
    notifyListeners();
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
    final mappedItems = event.items
        .map(
          (item) => TransferFileManifestItem(
            fileName: item.fileName,
            sizeBytes: item.sizeBytes,
            sha256: item.sha256,
          ),
        )
        .toList(growable: false);

    _incomingRequests.removeWhere((req) => req.requestId == event.requestId);
    _incomingRequests.insert(
      0,
      IncomingTransferRequest(
        requestId: event.requestId,
        senderIp: event.senderIp,
        senderName: event.senderName,
        senderMacAddress: event.senderMacAddress,
        sharedCacheId: event.sharedCacheId,
        sharedLabel: event.sharedLabel,
        items: mappedItems,
        createdAt: event.observedAt,
      ),
    );
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.senderMacAddress,
    );
    final requestedByCurrentDevice = _consumePendingRemoteDownload(event);
    if (requestedByCurrentDevice) {
      _infoMessage =
          'Auto-accepting download transfer from ${event.senderName}.';
      notifyListeners();
      unawaited(
        respondToTransferRequest(requestId: event.requestId, approved: true),
      );
      return;
    }

    final previewIntent = _consumePendingRemotePreview(event);
    if (previewIntent != null) {
      _previewResultCompletersByRequestId[event.requestId] =
          previewIntent.completer;
      _infoMessage = 'Preparing remote preview from ${event.senderName}...';
      notifyListeners();
      unawaited(
        respondToTransferRequest(
          requestId: event.requestId,
          approved: true,
          forPreview: true,
          previewRelativePath: previewIntent.normalizedRelativePath,
        ),
      );
      return;
    }

    final isFriendSender = _trustedLanPeerStore.isTrustedMac(
      normalizedSenderMac,
    );

    if (isFriendSender) {
      _infoMessage = 'Auto-accepting transfer from friend ${event.senderName}.';
      notifyListeners();
      unawaited(
        respondToTransferRequest(requestId: event.requestId, approved: true),
      );
      return;
    }

    _infoMessage = 'Incoming transfer request from ${event.senderName}.';
    notifyListeners();
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
      _log('Friend request from known friend $senderName. Auto-accepting.');
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

    unawaited(_setFriendAfterAcceptance(responderMac, responderName));
  }

  Future<void> _setFriendAfterAcceptance(
    String responderMac,
    String responderName,
  ) async {
    try {
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

  void _onTransferDecision(TransferDecisionEvent event) {
    if (!event.approved) {
      _pendingOutgoingTransfers.remove(event.requestId);
      _infoMessage = '${event.receiverName} declined your transfer request.';
      notifyListeners();
      return;
    }

    final session = _pendingOutgoingTransfers[event.requestId];
    if (session == null) {
      _infoMessage = '${event.receiverName} accepted your transfer request.';
      notifyListeners();
      return;
    }

    final filteredFiles = _filterOutgoingFilesForDecision(
      files: session.files,
      acceptedFileNames: event.acceptedFileNames,
    );
    if (filteredFiles.isEmpty) {
      _pendingOutgoingTransfers.remove(event.requestId);
      unawaited(_cleanupTemporaryOutgoingFiles(session.files));
      _infoMessage =
          '${event.receiverName} already has these files. Transfer skipped.';
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (event.transferPort == null) {
      _errorMessage =
          '${event.receiverName} accepted request but did not provide transfer port.';
      notifyListeners();
      return;
    }

    _infoMessage =
        '${event.receiverName} accepted request. Starting transfer...';
    notifyListeners();
    unawaited(
      _sendApprovedTransfer(
        event: event,
        session: _OutgoingTransferSession(
          receiverName: session.receiverName,
          files: filteredFiles,
        ),
      ),
    );
  }

  Future<void> _sendApprovedTransfer({
    required TransferDecisionEvent event,
    required _OutgoingTransferSession session,
  }) async {
    _uploadSentBytes = 0;
    _uploadTotalBytes = session.files.fold<int>(
      0,
      (sum, file) => sum + file.sizeBytes,
    );
    _resetUploadSpeedTracking(currentBytes: 0);
    notifyListeners();

    try {
      await _fileTransferService.sendFiles(
        host: event.receiverIp,
        port: event.transferPort!,
        requestId: event.requestId,
        files: session.files,
        onProgress: (sent, total) {
          _uploadSentBytes = sent;
          _uploadTotalBytes = total;
          _updateUploadSpeedTracking(currentBytes: sent);
          notifyListeners();
        },
      );
      _infoMessage =
          'Transferred ${session.files.length} file(s) to ${session.receiverName}.';
      _errorMessage = null;
      _uploadSentBytes = _uploadTotalBytes;
      _updateUploadSpeedTracking(currentBytes: _uploadSentBytes);
    } catch (error) {
      _errorMessage = 'File transfer failed: $error';
      _log(_errorMessage!);
    } finally {
      _pendingOutgoingTransfers.remove(event.requestId);
      await _cleanupTemporaryOutgoingFiles(session.files);
      Future<void>.delayed(const Duration(seconds: 1), () {
        _uploadSentBytes = 0;
        _uploadTotalBytes = 0;
        _clearUploadSpeedTracking();
        notifyListeners();
      });
      notifyListeners();
    }
  }

  Future<void> _cleanupTemporaryOutgoingFiles(
    List<TransferSourceFile> files,
  ) async {
    for (final file in files) {
      if (!file.deleteAfterTransfer) {
        continue;
      }
      try {
        final source = File(file.sourcePath);
        if (await source.exists()) {
          await source.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _waitForIncomingTransferResult({
    required IncomingTransferRequest request,
    required TransferReceiveSession session,
    required List<TransferFileManifestItem> acceptedItems,
    required bool persistToUserDownloads,
    required bool recordHistory,
    required bool sendCompletionNotification,
    Completer<String?>? previewCompleter,
  }) async {
    try {
      final result = await session.result;
      if (result.success) {
        var savedPaths = result.savedPaths;
        if (persistToUserDownloads) {
          try {
            savedPaths = await _transferStorageService.publishToUserDownloads(
              sourcePaths: result.savedPaths,
              relativePaths: acceptedItems
                  .map((item) => item.fileName)
                  .toList(growable: false),
              appFolderName: 'Landa',
            );
          } catch (error) {
            _log('Failed to publish files into user downloads: $error');
          }
        }

        final rootPath = savedPaths.isEmpty
            ? result.destinationDirectory
            : File(savedPaths.first).parent.path;

        if (recordHistory) {
          try {
            await _transferHistoryRepository.addRecord(
              id: _fileHashService.buildStableId(
                'download-history|${request.requestId}|'
                '${DateTime.now().microsecondsSinceEpoch}',
              ),
              requestId: request.requestId,
              direction: TransferHistoryDirection.download,
              peerName: request.senderName,
              peerIp: request.senderIp,
              rootPath: rootPath,
              savedPaths: savedPaths,
              fileCount: savedPaths.length,
              totalBytes: result.totalBytes,
              status: TransferHistoryStatus.completed,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            );
            await _loadDownloadHistory();
          } catch (error) {
            _log('Failed to persist transfer history: $error');
          }
        }

        if (sendCompletionNotification) {
          unawaited(
            _transferStorageService.showAndroidDownloadCompletedNotification(
              requestId: request.requestId,
              savedPaths: savedPaths,
              directoryPath: rootPath,
            ),
          );
        }

        final hashStatus = result.hashVerified ? ' Hash verified.' : '';
        if (previewCompleter != null) {
          final previewPath = savedPaths.isEmpty ? null : savedPaths.first;
          if (!previewCompleter.isCompleted) {
            previewCompleter.complete(previewPath);
          }
          _infoMessage = previewPath == null
              ? 'Preview received but file is unavailable.'
              : 'Preview ready: ${p.basename(previewPath)}.$hashStatus';
        } else {
          _infoMessage =
              'Received ${savedPaths.length} file(s) from ${request.senderName}. '
              'Saved to $rootPath.$hashStatus';
        }

        _errorMessage = null;
        _downloadReceivedBytes = _downloadTotalBytes;
        _updateDownloadSpeedTracking(currentBytes: _downloadReceivedBytes);
      } else {
        if (previewCompleter != null && !previewCompleter.isCompleted) {
          previewCompleter.complete(null);
        }
        _errorMessage = previewCompleter != null
            ? 'Preview from ${request.senderName} failed: ${result.message}'
            : 'Transfer from ${request.senderName} failed: ${result.message}';
        _log(_errorMessage!);
        if (sendCompletionNotification) {
          unawaited(
            _transferStorageService.showAndroidDownloadFailedNotification(
              requestId: request.requestId,
              message: result.message,
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      if (previewCompleter != null && !previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      final message = previewCompleter != null
          ? 'Preview from ${request.senderName} failed: $error'
          : 'Transfer from ${request.senderName} failed: $error';
      _errorMessage = message;
      _log('$message\n$stackTrace');
      if (sendCompletionNotification) {
        unawaited(
          _transferStorageService.showAndroidDownloadFailedNotification(
            requestId: request.requestId,
            message: error.toString(),
          ),
        );
      }
    } finally {
      _activeReceiveSessions.remove(request.requestId);
      Future<void>.delayed(const Duration(seconds: 1), () {
        _downloadReceivedBytes = 0;
        _downloadTotalBytes = 0;
        _clearDownloadSpeedTracking();
        notifyListeners();
      });
      notifyListeners();
    }
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

    final sourceEntries = _clipboardHistory.take(safeLimit);
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
    if (_activeClipboardQueryRequestId != null &&
        event.requestId != _activeClipboardQueryRequestId) {
      return;
    }

    final mapped = <RemoteClipboardEntry>[];
    for (final item in event.entries) {
      final type = ClipboardEntryTypeX.fromValue(item.entryType);
      List<int>? imageBytes;
      if (type == ClipboardEntryType.image) {
        final encoded = item.imagePreviewBase64;
        if (encoded == null || encoded.trim().isEmpty) {
          continue;
        }
        try {
          imageBytes = base64Decode(encoded);
        } catch (_) {
          continue;
        }
      }
      mapped.add(
        RemoteClipboardEntry(
          id: item.id,
          type: type,
          createdAt: DateTime.fromMillisecondsSinceEpoch(item.createdAtMs),
          textValue: item.textValue,
          imageBytes: imageBytes,
        ),
      );
    }

    mapped.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _remoteClipboardByOwnerIp[event.ownerIp] = mapped;

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
      final captured = await _clipboardCaptureService.readCurrentClipboard();
      if (captured == null) {
        return;
      }
      if (_lastCapturedClipboardHash == captured.contentHash) {
        return;
      }
      if (await _clipboardHistoryRepository.hasHash(captured.contentHash)) {
        _lastCapturedClipboardHash = captured.contentHash;
        return;
      }

      final entryId = _fileHashService.buildStableId(
        'clipboard|${captured.contentHash}|${DateTime.now().microsecondsSinceEpoch}',
      );
      String? imagePath;
      if (captured.type == ClipboardEntryType.image &&
          captured.imageBytes != null &&
          captured.imageBytes!.isNotEmpty) {
        final directory = await _transferStorageService
            .resolveClipboardDirectory(appFolderName: 'Landa');
        imagePath = p.join(directory.path, '$entryId.png');
        await File(imagePath).writeAsBytes(captured.imageBytes!, flush: true);
      }

      await _clipboardHistoryRepository.insert(
        ClipboardHistoryEntry(
          id: entryId,
          type: captured.type,
          contentHash: captured.contentHash,
          textValue: captured.textValue,
          imagePath: imagePath,
          createdAt: DateTime.now(),
        ),
      );
      _lastCapturedClipboardHash = captured.contentHash;
      await _trimClipboardHistoryToSettingsLimit();
      await _loadClipboardHistory(notify: true);
    } catch (error) {
      _log('Clipboard capture failed: $error');
    }
  }

  Future<void> _trimClipboardHistoryToSettingsLimit() async {
    final removed = await _clipboardHistoryRepository.trimToMaxEntries(
      _currentSettings.clipboardHistoryMaxEntries,
    );
    for (final entry in removed) {
      await _deleteClipboardImageFileIfExists(entry.imagePath);
    }
  }

  Future<void> _loadClipboardHistory({
    bool notify = false,
    bool updateLastCapturedHash = true,
  }) async {
    try {
      final rows = await _clipboardHistoryRepository.listRecent(limit: 300);
      _clipboardHistory
        ..clear()
        ..addAll(rows);
      if (updateLastCapturedHash) {
        final latest = rows.isEmpty ? null : rows.first;
        _lastCapturedClipboardHash = latest?.contentHash;
      }
      if (notify) {
        notifyListeners();
      }
    } catch (error) {
      _log('Failed to load clipboard history: $error');
    }
  }

  Future<void> _deleteClipboardImageFileIfExists(String? imagePath) async {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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
          await _sharedFolderCacheRepository.pruneUnavailableOwnerCaches(
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
      for (final cache in _ownerSharedCaches) {
        final entries = await _sharedFolderCacheRepository.readIndexEntries(
          cache.cacheId,
        );
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
    if (_activeShareQueryRequestId != null &&
        event.requestId != _activeShareQueryRequestId) {
      return;
    }

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
                lastSeen: event.observedAt,
              );

      if (ownerMac != null) {
        final activeCacheIds = event.entries
            .map((entry) => entry.cacheId)
            .where((id) => id.trim().isNotEmpty)
            .toSet();
        final removedLocal = await _sharedFolderCacheRepository
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

      _remoteShareOptions.removeWhere(
        (option) => option.ownerIp == event.ownerIp,
      );
      _remoteThumbnailPathsByFileKey.removeWhere(
        (key, _) => key.startsWith('${event.ownerIp}|'),
      );

      var trimmedEntries = 0;
      var trimmedFilesTotal = 0;
      for (final entry in event.entries) {
        final uiEntry = _trimRemoteShareEntryForUi(entry);
        if (!identical(uiEntry, entry)) {
          trimmedEntries += 1;
          trimmedFilesTotal += entry.files.length - uiEntry.files.length;
        }
        _remoteShareOptions.add(
          RemoteShareOption(
            requestId: event.requestId,
            ownerIp: event.ownerIp,
            ownerName: aliasName ?? event.ownerName,
            ownerMacAddress: ownerMac ?? event.ownerMacAddress,
            entry: uiEntry,
          ),
        );
      }
      if (trimmedEntries > 0) {
        _log(
          'Remote catalog trimmed for UI: owner=${event.ownerIp}, '
          'entries=$trimmedEntries filesHidden=$trimmedFilesTotal',
        );
      }

      _remoteShareOptions.sort((a, b) {
        final ownerCmp = a.ownerName.toLowerCase().compareTo(
          b.ownerName.toLowerCase(),
        );
        if (ownerCmp != 0) {
          return ownerCmp;
        }
        return a.entry.displayName.toLowerCase().compareTo(
          b.entry.displayName.toLowerCase(),
        );
      });
      unawaited(_syncRemoteThumbnails(event));
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
      _handleThumbnailSyncRequest(event).catchError((
        Object error,
        StackTrace stack,
      ) {
        _log(
          'Unhandled thumbnail sync request error from ${event.requesterIp}: $error',
        );
        _log(stack.toString());
      }),
    );
  }

  Future<void> _handleThumbnailSyncRequest(
    ThumbnailSyncRequestEvent event,
  ) async {
    await _loadOwnerCaches();
    final entriesByCache = <String, Map<String, SharedFolderIndexEntry>>{};
    for (final item in event.items) {
      final cache = _findOwnerCacheById(item.cacheId);
      if (cache == null) {
        continue;
      }
      final byRelative = entriesByCache.putIfAbsent(
        item.cacheId,
        () => <String, SharedFolderIndexEntry>{},
      );
      if (!byRelative.containsKey(item.relativePath)) {
        final entries = await _sharedFolderCacheRepository.readIndexEntries(
          item.cacheId,
        );
        for (final entry in entries) {
          byRelative[entry.relativePath] = entry;
        }
      }

      final entry = byRelative[item.relativePath];
      if (entry == null ||
          entry.thumbnailId == null ||
          entry.thumbnailId != item.thumbnailId) {
        continue;
      }

      final bytes = await _sharedFolderCacheRepository.readOwnerThumbnailBytes(
        cacheId: item.cacheId,
        thumbnailId: item.thumbnailId,
      );
      if (bytes == null || bytes.isEmpty) {
        continue;
      }

      await _lanDiscoveryService.sendThumbnailPacket(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerMacAddress: _localDeviceMac,
        cacheId: item.cacheId,
        relativePath: item.relativePath,
        thumbnailId: item.thumbnailId,
        bytes: bytes,
      );
    }
  }

  void _onThumbnailPacket(ThumbnailPacketEvent event) {
    unawaited(
      _handleThumbnailPacket(event).catchError((
        Object error,
        StackTrace stack,
      ) {
        _log('Unhandled thumbnail packet error from ${event.ownerIp}: $error');
        _log(stack.toString());
      }),
    );
  }

  Future<void> _handleThumbnailPacket(ThumbnailPacketEvent event) async {
    if (event.bytes.isEmpty) {
      return;
    }
    final ownerMac = DeviceAliasRepository.normalizeMac(event.ownerMacAddress);
    if (ownerMac == null) {
      return;
    }
    final savedPath = await _sharedFolderCacheRepository
        .saveReceiverThumbnailBytes(
          ownerMacAddress: ownerMac,
          cacheId: event.cacheId,
          thumbnailId: event.thumbnailId,
          bytes: event.bytes,
        );
    final key = _remoteThumbnailKey(
      ownerIp: event.ownerIp,
      cacheId: event.cacheId,
      relativePath: event.relativePath,
    );
    _remoteThumbnailPathsByFileKey[key] = savedPath;
    notifyListeners();
  }

  Future<void> _syncRemoteThumbnails(ShareCatalogEvent event) async {
    final ownerMac = DeviceAliasRepository.normalizeMac(event.ownerMacAddress);
    if (ownerMac == null) {
      return;
    }

    final requested = <ThumbnailSyncItem>[];
    var syncLimitReached = false;
    for (final entry in event.entries) {
      for (final file in entry.files) {
        final thumbId = file.thumbnailId;
        if (thumbId == null || thumbId.isEmpty) {
          continue;
        }

        final key = _remoteThumbnailKey(
          ownerIp: event.ownerIp,
          cacheId: entry.cacheId,
          relativePath: file.relativePath,
        );
        final existing = _remoteThumbnailPathsByFileKey[key];
        if (existing != null && await File(existing).exists()) {
          continue;
        }

        final localPath = await _sharedFolderCacheRepository
            .resolveReceiverThumbnailPath(
              ownerMacAddress: ownerMac,
              cacheId: entry.cacheId,
              thumbnailId: thumbId,
            );
        if (localPath != null) {
          _remoteThumbnailPathsByFileKey[key] = localPath;
          continue;
        }

        requested.add(
          ThumbnailSyncItem(
            cacheId: entry.cacheId,
            relativePath: file.relativePath,
            thumbnailId: thumbId,
          ),
        );
        if (requested.length >= _maxThumbnailSyncItemsPerCatalog) {
          syncLimitReached = true;
          break;
        }
      }
      if (syncLimitReached) {
        break;
      }
    }

    if (requested.isEmpty) {
      return;
    }

    final requestId = _fileHashService.buildStableId(
      'thumb-sync|${event.ownerIp}|${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await _lanDiscoveryService.sendThumbnailSyncRequest(
        targetIp: event.ownerIp,
        requestId: requestId,
        requesterName: _localName,
        items: requested,
      );
      if (syncLimitReached) {
        _log(
          'Thumbnail sync request capped at '
          '$_maxThumbnailSyncItemsPerCatalog items for ${event.ownerIp}.',
        );
      }
    } catch (error) {
      _log('Failed to request remote thumbnails: $error');
    }
  }

  SharedCatalogEntryItem _trimRemoteShareEntryForUi(
    SharedCatalogEntryItem entry,
  ) {
    if (entry.files.length <= _maxRemoteFilesPerCacheForUi) {
      return entry;
    }
    final cappedFiles = entry.files
        .take(_maxRemoteFilesPerCacheForUi)
        .toList(growable: false);
    return SharedCatalogEntryItem(
      cacheId: entry.cacheId,
      displayName: entry.displayName,
      itemCount: entry.itemCount,
      totalBytes: entry.totalBytes,
      files: cappedFiles,
    );
  }

  String _remoteThumbnailKey({
    required String ownerIp,
    required String cacheId,
    required String relativePath,
  }) {
    return '$ownerIp|$cacheId|${relativePath.replaceAll('\\', '/').toLowerCase()}';
  }

  void _onDownloadRequest(DownloadRequestEvent event) {
    unawaited(_handleDownloadRequest(event));
  }

  Future<void> _handleDownloadRequest(DownloadRequestEvent event) async {
    await _loadOwnerCaches();
    final cache = _findOwnerCacheById(event.cacheId);
    if (cache == null) {
      _log(
        'Download request from ${event.requesterIp} ignored. '
        'Unknown cacheId=${event.cacheId}',
      );
      return;
    }

    final isPreviewRequest = event.previewMode;
    if (!isPreviewRequest &&
        _currentSettings.downloadAttemptNotificationsEnabled) {
      unawaited(
        _appNotificationService.showDownloadAttemptNotification(
          requesterName: event.requesterName,
          shareLabel: cache.displayName,
          requestedFilesCount: event.selectedRelativePaths.length,
        ),
      );
    }

    _infoMessage = isPreviewRequest
        ? 'Preview request from ${event.requesterName}.'
        : 'Download request from ${event.requesterName} for "${cache.displayName}".';
    notifyListeners();

    final relativePathFilter = event.selectedRelativePaths.isEmpty
        ? null
        : event.selectedRelativePaths.toSet();
    final preparedFiles = isPreviewRequest
        ? await _buildCompressedPreviewFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
          )
        : await _buildTransferFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
          );

    if (preparedFiles.isEmpty) {
      _log(
        '${isPreviewRequest ? 'Preview' : 'Download'} request from ${event.requesterIp} ignored. '
        'No readable files in cacheId=${event.cacheId}',
      );
      return;
    }

    final items = preparedFiles
        .map((prepared) => prepared.announcement)
        .toList(growable: false);

    final requestId = isPreviewRequest
        ? event.requestId
        : _fileHashService.buildStableId(
            'download-share|${event.requestId}|${event.requesterIp}|${cache.cacheId}',
          );

    try {
      _pendingOutgoingTransfers[requestId] = _OutgoingTransferSession(
        receiverName: event.requesterName,
        files: preparedFiles
            .map(
              (prepared) => TransferSourceFile(
                sourcePath: prepared.sourcePath,
                fileName: prepared.announcement.fileName,
                sizeBytes: prepared.announcement.sizeBytes,
                sha256: prepared.announcement.sha256,
                deleteAfterTransfer: prepared.deleteAfterTransfer,
              ),
            )
            .toList(growable: false),
      );

      await _lanDiscoveryService.sendTransferRequest(
        targetIp: event.requesterIp,
        requestId: requestId,
        senderName: _localName,
        senderMacAddress: _localDeviceMac,
        sharedCacheId: cache.cacheId,
        sharedLabel: isPreviewRequest
            ? 'Preview: ${cache.displayName}'
            : cache.displayName,
        items: items,
      );
    } catch (error) {
      final pending = _pendingOutgoingTransfers.remove(requestId);
      if (pending != null) {
        unawaited(_cleanupTemporaryOutgoingFiles(pending.files));
      }
      _log(
        'Failed to prepare ${isPreviewRequest ? 'preview' : 'download-share'} transfer: $error',
      );
      return;
    }

    _log(
      'Transfer request sent for cache ${cache.cacheId} to ${event.requesterIp}. '
      'items=${items.length} preview=$isPreviewRequest',
    );
  }

  Future<void> _resolveLocalAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    InternetAddress? bestAddress;
    String? bestInterfaceName;
    var bestScore = -100000;

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final score = _scoreAddress(interface.name, address.address);
        _log(
          'Interface candidate: ${interface.name} -> ${address.address} '
          '(score=$score)',
        );
        if (score > bestScore) {
          bestScore = score;
          bestAddress = address;
          bestInterfaceName = interface.name;
        }
      }
    }

    if (bestAddress != null) {
      _localIp = bestAddress.address;
      _log(
        'Selected local interface: $bestInterfaceName '
        '(${bestAddress.address})',
      );
      notifyListeners();
      return;
    }

    _log('No suitable IPv4 local interface found');
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
        final reboundCount = await _sharedFolderCacheRepository
            .rebindOwnerCachesToMac(ownerMacAddress: _localDeviceMac);
        if (reboundCount > 0) {
          _log(
            'Rebound $reboundCount owner shared cache(s) to local MAC $_localDeviceMac',
          );
        }
      }
      final caches = await _sharedFolderCacheRepository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: _localDeviceMac,
      );
      _ownerIndexEntriesByCacheId.clear();
      _ownerSharedCaches
        ..clear()
        ..addAll(caches);
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

  Duration get _activeAutoRefreshInterval {
    return _currentSettings.backgroundScanInterval.duration;
  }

  Future<void> _cleanupPreviewCacheBySettings() async {
    try {
      final result = await _transferStorageService.cleanupPreviewCache(
        maxSizeGb: _currentSettings.previewCacheMaxSizeGb,
        maxAgeDays: _currentSettings.previewCacheMaxAgeDays,
        appFolderName: 'Landa',
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

  static const Set<String> _previewImageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };
  static const Set<String> _previewVideoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.m4v',
    '.3gp',
    '.mpeg',
    '.mpg',
  };
  static const Set<String> _previewTextExtensions = <String>{
    '.txt',
    '.md',
    '.log',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
  };

  Future<List<_PreparedTransferFile>> _buildCompressedPreviewFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  }) async {
    final entries = await _sharedFolderCacheRepository.readIndexEntries(
      cache.cacheId,
    );
    final normalizedFilter = relativePathFilter
        ?.map(_normalizeTransferPathForMatch)
        .toSet();

    final result = <_PreparedTransferFile>[];
    for (final entry in entries) {
      if (normalizedFilter != null &&
          !normalizedFilter.contains(
            _normalizeTransferPathForMatch(entry.relativePath),
          )) {
        continue;
      }
      final sourcePath = _resolveCacheFilePath(cache: cache, entry: entry);
      if (sourcePath == null) {
        continue;
      }
      final preview = await _buildCompressedPreviewForEntry(
        cache: cache,
        entry: entry,
        sourcePath: sourcePath,
      );
      if (preview != null) {
        result.add(preview);
      }
    }
    return result;
  }

  Future<_PreparedTransferFile?> _buildCompressedPreviewForEntry({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
    required String sourcePath,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      return null;
    }

    final ext = p.extension(entry.relativePath).toLowerCase();
    if (_previewImageExtensions.contains(ext)) {
      try {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final longest = math.max(decoded.width, decoded.height);
          final resized = longest > 960
              ? img.copyResize(
                  decoded,
                  width: decoded.width >= decoded.height ? 960 : null,
                  height: decoded.height > decoded.width ? 960 : null,
                )
              : decoded;
          final compressed = Uint8List.fromList(
            img.encodeJpg(resized, quality: 52),
          );
          return _writeCompressedPreviewArtifact(
            originalRelativePath: entry.relativePath,
            outputExtension: '.jpg',
            contentBytes: compressed,
          );
        }
      } catch (_) {}
    }

    if (_previewVideoExtensions.contains(ext)) {
      try {
        Uint8List? bytes;
        final thumbnailId = entry.thumbnailId;
        if (thumbnailId != null && thumbnailId.trim().isNotEmpty) {
          bytes = await _sharedFolderCacheRepository.readOwnerThumbnailBytes(
            cacheId: cache.cacheId,
            thumbnailId: thumbnailId,
          );
        }
        if (bytes != null && bytes.isNotEmpty) {
          final decoded = img.decodeImage(bytes);
          final compressed = decoded == null
              ? bytes
              : Uint8List.fromList(img.encodeJpg(decoded, quality: 50));
          return _writeCompressedPreviewArtifact(
            originalRelativePath: entry.relativePath,
            outputExtension: '.jpg',
            contentBytes: compressed,
            suffix: 'video-preview',
          );
        }
      } catch (_) {}
      return _writeCompressedPreviewArtifact(
        originalRelativePath: entry.relativePath,
        outputExtension: '.txt',
        contentBytes: utf8.encode(
          'Video preview is unavailable on sender side for this file.',
        ),
        suffix: 'video-preview',
      );
    }

    if (_previewTextExtensions.contains(ext)) {
      try {
        final bytes = await file.readAsBytes();
        final maxBytes = math.min(bytes.length, 64 * 1024);
        final snippet = utf8.decode(
          bytes.sublist(0, maxBytes),
          allowMalformed: true,
        );
        final previewText = bytes.length > maxBytes
            ? '$snippet\n\n--- Preview truncated ---'
            : snippet;
        return _writeCompressedPreviewArtifact(
          originalRelativePath: entry.relativePath,
          outputExtension: '.txt',
          contentBytes: utf8.encode(previewText),
          suffix: 'text-preview',
        );
      } catch (_) {}
    }

    if (ext == '.pdf') {
      final previewText =
          'PDF preview is available after download. Compressed text preview is not generated for this file yet.';
      return _writeCompressedPreviewArtifact(
        originalRelativePath: entry.relativePath,
        outputExtension: '.txt',
        contentBytes: utf8.encode(previewText),
        suffix: 'pdf-preview',
      );
    }

    return _writeCompressedPreviewArtifact(
      originalRelativePath: entry.relativePath,
      outputExtension: '.txt',
      contentBytes: utf8.encode(
        'Preview is not available for this file type yet.',
      ),
      suffix: 'preview-note',
    );
  }

  Future<_PreparedTransferFile?> _writeCompressedPreviewArtifact({
    required String originalRelativePath,
    required String outputExtension,
    required List<int> contentBytes,
    String suffix = 'preview',
  }) async {
    if (contentBytes.isEmpty) {
      return null;
    }

    final directory = await _transferStorageService.resolvePreviewDirectory(
      appFolderName: 'Landa',
    );
    final relativeName = _buildPreviewRelativeName(
      originalRelativePath,
      outputExtension: outputExtension,
      suffix: suffix,
    );
    final token = _fileHashService.buildStableId(
      'preview-artifact|$relativeName|$suffix|${DateTime.now().microsecondsSinceEpoch}',
    );
    final outputPath = p.join(directory.path, '$token$outputExtension');
    final outputFile = File(outputPath);
    await outputFile.create(recursive: true);
    await outputFile.writeAsBytes(contentBytes, flush: true);

    final stat = await outputFile.stat();
    final sha = await _fileHashService.computeSha256ForPath(outputPath);
    return _PreparedTransferFile(
      sourcePath: outputPath,
      announcement: TransferAnnouncementItem(
        fileName: relativeName,
        sizeBytes: stat.size,
        sha256: sha,
      ),
      deleteAfterTransfer: true,
    );
  }

  String _buildPreviewRelativeName(
    String originalRelativePath, {
    required String outputExtension,
    required String suffix,
  }) {
    final normalized = originalRelativePath.replaceAll('\\', '/');
    final dir = p.dirname(normalized);
    final base = p.basenameWithoutExtension(normalized);
    final safeBase = _safePreviewSegment(base);
    final fileName = '$safeBase.$suffix$outputExtension';
    if (dir == '.' || dir.isEmpty) {
      return fileName;
    }
    final safeDir = dir
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .map(_safePreviewSegment)
        .toList(growable: false);
    if (safeDir.isEmpty) {
      return fileName;
    }
    return [...safeDir, fileName].join('/');
  }

  String _safePreviewSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'file';
    }
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  Future<List<_PreparedTransferFile>> _buildTransferFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  }) async {
    final indexEntries = await _sharedFolderCacheRepository.readIndexEntries(
      cache.cacheId,
    );
    final items = <_PreparedTransferFile>[];
    for (final entry in indexEntries) {
      if (relativePathFilter != null &&
          !relativePathFilter.contains(entry.relativePath)) {
        continue;
      }
      final filePath = _resolveCacheFilePath(cache: cache, entry: entry);
      if (filePath == null) {
        continue;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      final sha256Hash = await _fileHashService.computeSha256ForPath(filePath);

      items.add(
        _PreparedTransferFile(
          sourcePath: filePath,
          announcement: TransferAnnouncementItem(
            fileName: entry.relativePath,
            sizeBytes: entry.sizeBytes,
            sha256: sha256Hash,
          ),
        ),
      );
    }
    return items;
  }

  SharedFolderCacheRecord? _findOwnerCacheById(String cacheId) {
    for (final cache in _ownerSharedCaches) {
      if (cache.cacheId == cacheId) {
        return cache;
      }
    }
    return null;
  }

  String? _resolveCacheFilePath({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
  }) {
    if (cache.rootPath.startsWith('selection://')) {
      return entry.absolutePath;
    }
    final localRelative = entry.relativePath.replaceAll('/', p.separator);
    return p.join(cache.rootPath, localRelative);
  }

  List<TransferSourceFile> _filterOutgoingFilesForDecision({
    required List<TransferSourceFile> files,
    required List<String>? acceptedFileNames,
  }) {
    if (acceptedFileNames == null) {
      return files;
    }

    final accepted = acceptedFileNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (accepted.isEmpty) {
      return const <TransferSourceFile>[];
    }

    return files
        .where((file) => accepted.contains(file.fileName))
        .toList(growable: false);
  }

  Future<List<TransferFileManifestItem>> _filterMissingIncomingItems({
    required List<TransferFileManifestItem> items,
    required Directory destinationDirectory,
  }) async {
    final missing = <TransferFileManifestItem>[];
    for (final item in items) {
      final relativePath = _sanitizeTransferRelativePath(item.fileName);
      final targetPath = p.join(destinationDirectory.path, relativePath);
      final targetFile = File(targetPath);
      if (!await targetFile.exists()) {
        missing.add(item);
        continue;
      }

      try {
        final stat = await targetFile.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size != item.sizeBytes) {
          missing.add(item);
          continue;
        }

        final existingHash = await _fileHashService.computeSha256ForPath(
          targetPath,
        );
        if (existingHash.toLowerCase() != item.sha256.toLowerCase()) {
          missing.add(item);
        }
      } catch (_) {
        missing.add(item);
      }
    }
    return missing;
  }

  String _sanitizeTransferRelativePath(String input) {
    final raw = input.replaceAll('\\', '/');
    final parts = raw
        .split('/')
        .map((part) => _sanitizeTransferRelativePathPart(part.trim()))
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
  }

  String _sanitizeTransferRelativePathPart(String input) {
    if (input.isEmpty) {
      return '';
    }

    var value = input
        .replaceAll(RegExp(r'[\x00-\x1F]'), '')
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    if (Platform.isWindows) {
      value = value.trimRight();
      value = value.replaceFirst(RegExp(r'[. ]+$'), '');
      if (value.isEmpty) {
        return '_';
      }

      final reserved = <String>{
        'con',
        'prn',
        'aux',
        'nul',
        'com1',
        'com2',
        'com3',
        'com4',
        'com5',
        'com6',
        'com7',
        'com8',
        'com9',
        'lpt1',
        'lpt2',
        'lpt3',
        'lpt4',
        'lpt5',
        'lpt6',
        'lpt7',
        'lpt8',
        'lpt9',
      };
      final base = value.split('.').first.toLowerCase();
      if (reserved.contains(base)) {
        value = '_$value';
      }
    }

    if (value.length > 120) {
      value = value.substring(0, 120);
    }

    return value.isEmpty ? '_' : value;
  }

  Duration? _estimateEta({
    required int totalBytes,
    required int transferredBytes,
    required double speedBytesPerSecond,
    required bool isActive,
  }) {
    if (!isActive) {
      return null;
    }
    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) {
      return Duration.zero;
    }
    if (speedBytesPerSecond <= 1) {
      return null;
    }
    final seconds = (remaining / speedBytesPerSecond).ceil();
    return Duration(seconds: seconds);
  }

  void _resetUploadSpeedTracking({required int currentBytes}) {
    _uploadSpeedBytesPerSecond = 0;
    _uploadSpeedSampleBytes = currentBytes;
    _uploadSpeedSampleAt = DateTime.now();
  }

  void _updateUploadSpeedTracking({required int currentBytes}) {
    final now = DateTime.now();
    final sampleAt = _uploadSpeedSampleAt;
    if (sampleAt == null) {
      _uploadSpeedSampleAt = now;
      _uploadSpeedSampleBytes = currentBytes;
      return;
    }

    final elapsedMs = now.difference(sampleAt).inMilliseconds;
    final deltaBytes = currentBytes - _uploadSpeedSampleBytes;
    if (deltaBytes < 0) {
      _uploadSpeedSampleAt = now;
      _uploadSpeedSampleBytes = currentBytes;
      _uploadSpeedBytesPerSecond = 0;
      return;
    }
    if (elapsedMs < 250 || deltaBytes == 0) {
      return;
    }

    final instantSpeed = (deltaBytes * 1000) / elapsedMs;
    if (_uploadSpeedBytesPerSecond <= 0) {
      _uploadSpeedBytesPerSecond = instantSpeed;
    } else {
      _uploadSpeedBytesPerSecond =
          (_uploadSpeedBytesPerSecond * 0.7) + (instantSpeed * 0.3);
    }
    _uploadSpeedSampleAt = now;
    _uploadSpeedSampleBytes = currentBytes;
  }

  void _clearUploadSpeedTracking() {
    _uploadSpeedBytesPerSecond = 0;
    _uploadSpeedSampleBytes = 0;
    _uploadSpeedSampleAt = null;
  }

  void _resetDownloadSpeedTracking({required int currentBytes}) {
    _downloadSpeedBytesPerSecond = 0;
    _downloadSpeedSampleBytes = currentBytes;
    _downloadSpeedSampleAt = DateTime.now();
  }

  void _updateDownloadSpeedTracking({required int currentBytes}) {
    final now = DateTime.now();
    final sampleAt = _downloadSpeedSampleAt;
    if (sampleAt == null) {
      _downloadSpeedSampleAt = now;
      _downloadSpeedSampleBytes = currentBytes;
      return;
    }

    final elapsedMs = now.difference(sampleAt).inMilliseconds;
    final deltaBytes = currentBytes - _downloadSpeedSampleBytes;
    if (deltaBytes < 0) {
      _downloadSpeedSampleAt = now;
      _downloadSpeedSampleBytes = currentBytes;
      _downloadSpeedBytesPerSecond = 0;
      return;
    }
    if (elapsedMs < 250 || deltaBytes == 0) {
      return;
    }

    final instantSpeed = (deltaBytes * 1000) / elapsedMs;
    if (_downloadSpeedBytesPerSecond <= 0) {
      _downloadSpeedBytesPerSecond = instantSpeed;
    } else {
      _downloadSpeedBytesPerSecond =
          (_downloadSpeedBytesPerSecond * 0.7) + (instantSpeed * 0.3);
    }
    _downloadSpeedSampleAt = now;
    _downloadSpeedSampleBytes = currentBytes;
  }

  void _clearDownloadSpeedTracking() {
    _downloadSpeedBytesPerSecond = 0;
    _downloadSpeedSampleBytes = 0;
    _downloadSpeedSampleAt = null;
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
    for (final session in _activeReceiveSessions.values) {
      unawaited(session.close());
    }
    _activeReceiveSessions.clear();
    for (final pending in _pendingRemotePreviewsByKey.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(null);
      }
    }
    _pendingRemotePreviewsByKey.clear();
    for (final completer in _previewResultCompletersByRequestId.values) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _previewResultCompletersByRequestId.clear();
    _lanDiscoveryService.stop();
    unawaited(_videoLinkShareService.stop());
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
    required String? observedMac,
    required String? existingMac,
  }) {
    final normalizedObservedMac = DeviceAliasRepository.normalizeMac(
      observedMac,
    );
    if (normalizedObservedMac != null) {
      return normalizedObservedMac;
    }

    final knownMac = _deviceRegistry.macForIp(ip);
    if (knownMac != null) {
      return knownMac;
    }

    return DeviceAliasRepository.normalizeMac(existingMac);
  }

  Future<void> _loadDownloadHistory() async {
    try {
      final rows = await _transferHistoryRepository.listRecords(
        direction: TransferHistoryDirection.download,
        limit: 120,
      );
      _downloadHistory
        ..clear()
        ..addAll(rows);
    } catch (error) {
      _log('Failed to load transfer history: $error');
    }
  }

  String _pendingRemoteDownloadKey({
    required String ownerIp,
    required String cacheId,
  }) {
    return '$ownerIp|$cacheId';
  }

  String _pendingRemotePreviewKey({
    required String ownerIp,
    required String cacheId,
    required String normalizedRelativePath,
  }) {
    return '$ownerIp|$cacheId|$normalizedRelativePath';
  }

  String _normalizeTransferPathForMatch(String value) {
    return value.replaceAll('\\', '/').trim().toLowerCase();
  }

  String? _resolveRemoteOwnerMac({
    required String ownerIp,
    required String cacheId,
  }) {
    for (final option in _remoteShareOptions) {
      if (option.ownerIp != ownerIp || option.entry.cacheId != cacheId) {
        continue;
      }
      return DeviceAliasRepository.normalizeMac(option.ownerMacAddress);
    }
    return null;
  }

  bool _consumePendingRemoteDownload(TransferRequestEvent event) {
    _purgeExpiredPendingRemoteDownloads();
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.senderMacAddress,
    );

    String? matchedKey;
    for (final entry in _pendingRemoteDownloads.entries) {
      final pending = entry.value;
      if (pending.cacheId != event.sharedCacheId) {
        continue;
      }

      final ipMatches = pending.ownerIp == event.senderIp;
      final macMatches =
          pending.ownerMacAddress != null &&
          normalizedSenderMac != null &&
          pending.ownerMacAddress == normalizedSenderMac;
      if (!ipMatches && !macMatches) {
        continue;
      }

      matchedKey = entry.key;
      break;
    }

    if (matchedKey == null) {
      return false;
    }
    _pendingRemoteDownloads.remove(matchedKey);
    return true;
  }

  _PendingRemotePreviewIntent? _consumePendingRemotePreview(
    TransferRequestEvent event,
  ) {
    _purgeExpiredPendingRemotePreviews();
    final normalizedSenderMac = DeviceAliasRepository.normalizeMac(
      event.senderMacAddress,
    );

    String? matchedKey;
    for (final entry in _pendingRemotePreviewsByKey.entries) {
      final pending = entry.value;
      if (pending.cacheId != event.sharedCacheId) {
        continue;
      }

      final ipMatches = pending.ownerIp == event.senderIp;
      final macMatches =
          pending.ownerMacAddress != null &&
          normalizedSenderMac != null &&
          pending.ownerMacAddress == normalizedSenderMac;
      if (!ipMatches && !macMatches) {
        continue;
      }

      matchedKey = entry.key;
      break;
    }

    if (matchedKey == null) {
      return null;
    }
    return _pendingRemotePreviewsByKey.remove(matchedKey);
  }

  void _purgeExpiredPendingRemotePreviews() {
    final now = DateTime.now();
    _pendingRemotePreviewsByKey.removeWhere((_, pending) {
      final expired =
          now.difference(pending.createdAt) > _pendingRemotePreviewTtl;
      if (expired && !pending.completer.isCompleted) {
        pending.completer.complete(null);
      }
      return expired;
    });
  }

  void _purgeExpiredPendingRemoteDownloads() {
    final now = DateTime.now();
    _pendingRemoteDownloads.removeWhere(
      (_, pending) =>
          now.difference(pending.createdAt) > _pendingRemoteDownloadTtl,
    );
  }

  void _purgeExpiredPendingFriendRequests() {
    final now = DateTime.now();
    _pendingOutgoingFriendRequestsByRequestId.removeWhere(
      (_, pending) =>
          now.difference(pending.createdAt) > _pendingFriendRequestTtl,
    );
  }

  int _scoreAddress(String interfaceName, String ip) {
    final lower = interfaceName.toLowerCase();
    var score = 0;

    if (_isLikelyVirtualInterface(lower)) {
      score -= 400;
    } else {
      score += 100;
    }

    if (_isInSubnet(ip, 192, 168)) {
      score += 220;
    } else if (_isInSubnet(ip, 10, null)) {
      score += 170;
    } else if (_isInRange172Private(ip)) {
      score += 120;
    } else if (_isInSubnet(ip, 100, null)) {
      score += 60;
    } else {
      score += 20;
    }

    if (lower.contains('wi-fi') ||
        lower.contains('wifi') ||
        lower.contains('wlan') ||
        lower.contains('ethernet') ||
        lower.contains('eth')) {
      score += 50;
    }

    return score;
  }

  bool _isLikelyVirtualInterface(String lowerName) {
    const hints = <String>[
      'loopback',
      'docker',
      'vmware',
      'virtual',
      'vethernet',
      'hyper-v',
      'vbox',
      'wsl',
      'tailscale',
      'zerotier',
      'hamachi',
      'tun',
      'tap',
      'bridge',
    ];
    return hints.any(lowerName.contains);
  }

  bool _isInSubnet(String ip, int first, int? second) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final firstOctet = int.tryParse(parts[0]);
    final secondOctet = int.tryParse(parts[1]);
    if (firstOctet == null || secondOctet == null) {
      return false;
    }
    if (firstOctet != first) {
      return false;
    }
    if (second != null && secondOctet != second) {
      return false;
    }
    return true;
  }

  bool _isInRange172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) {
      return false;
    }
    return first == 172 && second >= 16 && second <= 31;
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

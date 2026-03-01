import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/app_notification_service.dart';
import '../../../core/utils/path_opener.dart';
import '../../history/data/transfer_history_repository.dart';
import '../../history/domain/transfer_history_record.dart';
import '../../settings/data/app_settings_repository.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/shared_folder_cache_repository.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../../transfer/domain/transfer_request.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';

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
  _PreparedTransferFile({required this.sourcePath, required this.announcement});

  final String sourcePath;
  final TransferAnnouncementItem announcement;
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

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required LanDiscoveryService lanDiscoveryService,
    required NetworkHostScanner networkHostScanner,
    required DeviceAliasRepository deviceAliasRepository,
    required AppSettingsRepository appSettingsRepository,
    required AppNotificationService appNotificationService,
    required TransferHistoryRepository transferHistoryRepository,
    required SharedFolderCacheRepository sharedFolderCacheRepository,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required PathOpener pathOpener,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _networkHostScanner = networkHostScanner,
       _deviceAliasRepository = deviceAliasRepository,
       _appSettingsRepository = appSettingsRepository,
       _appNotificationService = appNotificationService,
       _transferHistoryRepository = transferHistoryRepository,
       _sharedFolderCacheRepository = sharedFolderCacheRepository,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _pathOpener = pathOpener;

  static const Duration _pendingRemoteDownloadTtl = Duration(minutes: 3);

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;
  final DeviceAliasRepository _deviceAliasRepository;
  final AppSettingsRepository _appSettingsRepository;
  final AppNotificationService _appNotificationService;
  final TransferHistoryRepository _transferHistoryRepository;
  final SharedFolderCacheRepository _sharedFolderCacheRepository;
  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final PathOpener _pathOpener;

  final Map<String, DiscoveredDevice> _devicesByIp =
      <String, DiscoveredDevice>{};
  final Map<String, String> _aliasByMac = <String, String>{};
  final List<IncomingTransferRequest> _incomingRequests =
      <IncomingTransferRequest>[];
  final List<SharedFolderCacheRecord> _ownerSharedCaches =
      <SharedFolderCacheRecord>[];
  final List<RemoteShareOption> _remoteShareOptions = <RemoteShareOption>[];
  final Map<String, String> _remoteThumbnailPathsByFileKey = <String, String>{};
  final Set<String> _trustedDeviceMacs = <String>{};
  final Map<String, _OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, _OutgoingTransferSession>{};
  final Map<String, _PendingRemoteDownloadIntent> _pendingRemoteDownloads =
      <String, _PendingRemoteDownloadIntent>{};
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};
  final List<TransferHistoryRecord> _downloadHistory =
      <TransferHistoryRecord>[];
  Timer? _scanTimer;
  AppSettings _settings = AppSettings.defaults;
  bool _started = false;
  bool _isAppInForeground = true;
  bool _isRefreshInProgress = false;
  bool _isManualRefreshInProgress = false;
  bool _isAddingShare = false;
  bool _isSendingTransfer = false;
  bool _isLoadingRemoteShares = false;
  String? _activeShareQueryRequestId;
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
  String? _selectedDeviceIp;
  String? _errorMessage;
  String? _infoMessage;

  DiscoveryFlowState get state => _state;
  bool get isManualRefreshInProgress => _isManualRefreshInProgress;
  bool get isAddingShare => _isAddingShare;
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
  AppSettings get settings => _settings;
  bool get isAppInForeground => _isAppInForeground;
  Duration get activeAutoRefreshInterval => _activeAutoRefreshInterval;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  List<IncomingTransferRequest> get incomingRequests =>
      List<IncomingTransferRequest>.unmodifiable(_incomingRequests);
  List<SharedFolderCacheRecord> get ownerSharedCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerSharedCaches);
  List<RemoteShareOption> get remoteShareOptions =>
      List<RemoteShareOption>.unmodifiable(_remoteShareOptions);
  List<TransferHistoryRecord> get downloadHistory =>
      List<TransferHistoryRecord>.unmodifiable(_downloadHistory);

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

  List<DiscoveredDevice> get devices {
    final values = _devicesByIp.values.toList(growable: false);
    values.sort((a, b) {
      if (a.isAppDetected != b.isAppDetected) {
        return a.isAppDetected ? -1 : 1;
      }
      return _compareIp(a.ip, b.ip);
    });
    return values;
  }

  DiscoveredDevice? get selectedDevice {
    final ip = _selectedDeviceIp;
    if (ip == null) {
      return null;
    }
    return _devicesByIp[ip];
  }

  int get appDetectedCount =>
      _devicesByIp.values.where((d) => d.isAppDetected).length;

  Future<void> start() async {
    if (_started) {
      _log('start() ignored: controller already started');
      return;
    }

    _started = true;

    await _resolveLocalAddress();
    _resolveLocalDeviceMac();
    await _loadAliases();
    await _loadTrustedDevices();
    await _loadSettings();
    await _loadOwnerCaches();
    await _loadDownloadHistory();

    try {
      _log('Starting discovery. localName=$_localName localIp=$_localIp');
      await _lanDiscoveryService.start(
        deviceName: _localName,
        onAppDetected: _onAppDetected,
        onTransferRequest: _onTransferRequest,
        onTransferDecision: _onTransferDecision,
        onShareQuery: _onShareQuery,
        onShareCatalog: _onShareCatalog,
        onDownloadRequest: _onDownloadRequest,
        onThumbnailSyncRequest: _onThumbnailSyncRequest,
        onThumbnailPacket: _onThumbnailPacket,
        preferredSourceIp: _localIp,
      );

      await _refresh(isManual: false);
      _restartAutoRefreshTimer();
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

  void clearInfoMessage() {
    _infoMessage = null;
    notifyListeners();
  }

  Future<void> updateBackgroundScanInterval(
    BackgroundScanIntervalOption interval,
  ) async {
    if (_settings.backgroundScanInterval == interval) {
      return;
    }
    await _saveSettings(_settings.copyWith(backgroundScanInterval: interval));
  }

  Future<void> setDownloadAttemptNotificationsEnabled(bool enabled) async {
    if (_settings.downloadAttemptNotificationsEnabled == enabled) {
      return;
    }
    await _saveSettings(
      _settings.copyWith(downloadAttemptNotificationsEnabled: enabled),
    );
  }

  Future<void> setMinimizeToTrayOnClose(bool enabled) async {
    if (_settings.minimizeToTrayOnClose == enabled) {
      return;
    }
    await _saveSettings(_settings.copyWith(minimizeToTrayOnClose: enabled));
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

  Future<void> toggleTrustedDevice(DiscoveredDevice device) async {
    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      _errorMessage = 'Cannot mark favorite until MAC address is known.';
      notifyListeners();
      return;
    }

    final currentlyTrusted = _trustedDeviceMacs.contains(mac);
    try {
      await _deviceAliasRepository.setTrusted(
        macAddress: mac,
        isTrusted: !currentlyTrusted,
      );
      if (currentlyTrusted) {
        _trustedDeviceMacs.remove(mac);
      } else {
        _trustedDeviceMacs.add(mac);
      }

      _devicesByIp.updateAll((_, value) {
        final candidateMac = DeviceAliasRepository.normalizeMac(
          value.macAddress,
        );
        if (candidateMac != mac) {
          return value;
        }
        return value.copyWith(isTrusted: !currentlyTrusted);
      });
      _errorMessage = null;
      notifyListeners();
    } catch (error) {
      _errorMessage = 'Failed to update favorite device: $error';
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

  Future<void> renameDeviceAlias({
    required DiscoveredDevice device,
    required String alias,
  }) async {
    final mac = DeviceAliasRepository.normalizeMac(device.macAddress);
    if (mac == null) {
      _errorMessage = 'Cannot rename device until MAC address is known.';
      notifyListeners();
      return;
    }

    final normalizedAlias = alias.trim();
    try {
      await _deviceAliasRepository.setAlias(
        macAddress: mac,
        alias: normalizedAlias,
      );
      final aliasOrNull = normalizedAlias.isEmpty ? null : normalizedAlias;
      if (normalizedAlias.isEmpty) {
        _aliasByMac.remove(mac);
      } else {
        _aliasByMac[mac] = normalizedAlias;
      }

      _devicesByIp.updateAll((_, value) {
        if (DeviceAliasRepository.normalizeMac(value.macAddress) != mac) {
          return value;
        }
        return value.copyWith(aliasName: aliasOrNull);
      });
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
    notifyListeners();
    try {
      final folderPath = await FilePicker.platform.getDirectoryPath();
      if (folderPath == null || folderPath.trim().isEmpty) {
        return;
      }

      final result = await _sharedFolderCacheRepository.upsertOwnerFolderCache(
        ownerMacAddress: _localDeviceMac,
        folderPath: folderPath,
      );
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
      _isAddingShare = false;
      notifyListeners();
    }
  }

  Future<void> recacheSharedFolders() async {
    _isAddingShare = true;
    notifyListeners();
    try {
      await _loadOwnerCaches();
      final folderCaches = _ownerSharedCaches
          .where((cache) => !cache.rootPath.startsWith('selection://'))
          .toList(growable: false);
      if (folderCaches.isEmpty) {
        _infoMessage = 'No shared folders to re-cache.';
        _errorMessage = null;
        return;
      }

      var updatedCount = 0;
      var failedCount = 0;
      var indexedTotal = 0;
      var discoveredNewFiles = 0;

      for (final cache in folderCaches) {
        try {
          final result = await _sharedFolderCacheRepository
              .upsertOwnerFolderCache(
                ownerMacAddress: _localDeviceMac,
                folderPath: cache.rootPath,
                displayName: cache.displayName,
              );
          updatedCount += 1;
          indexedTotal += result.record.itemCount;
          final delta = result.record.itemCount - result.previousItemCount;
          if (delta > 0) {
            discoveredNewFiles += delta;
          }
        } catch (error) {
          failedCount += 1;
          _log('Failed to re-cache folder ${cache.rootPath}: $error');
        }
      }

      await _loadOwnerCaches();
      if (updatedCount == 0) {
        _errorMessage = 'Failed to re-cache shared folders.';
        _infoMessage = null;
      } else {
        _errorMessage = null;
        final suffix = failedCount > 0 ? ' ($failedCount failed)' : '';
        _infoMessage =
            'Re-cached $updatedCount shared folder(s). '
            'Indexed $indexedTotal file(s), '
            'new: $discoveredNewFiles$suffix.';
      }
    } catch (error) {
      _errorMessage = 'Failed to re-cache shared folders: $error';
      _log(_errorMessage!);
    } finally {
      _isAddingShare = false;
      notifyListeners();
    }
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
  }) async {
    final index = _incomingRequests.indexWhere((r) => r.requestId == requestId);
    if (index < 0) {
      return;
    }

    final request = _incomingRequests[index];
    TransferReceiveSession? receiveSession;
    var skippedExistingCount = 0;
    var itemsToReceive = request.items;
    var expectedBytes = request.totalBytes;
    try {
      if (approved) {
        final destinationDirectory = await _transferStorageService
            .resolveReceiveDirectory(appFolderName: 'Landa');
        itemsToReceive = await _filterMissingIncomingItems(
          items: request.items,
          destinationDirectory: destinationDirectory,
        );
        skippedExistingCount = request.items.length - itemsToReceive.length;
        expectedBytes = itemsToReceive.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );

        if (itemsToReceive.isNotEmpty) {
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = expectedBytes;
          _resetDownloadSpeedTracking(currentBytes: 0);
          notifyListeners();

          unawaited(
            _transferStorageService.showAndroidDownloadProgressNotification(
              requestId: request.requestId,
              senderName: request.senderName,
              receivedBytes: 0,
              totalBytes: expectedBytes,
            ),
          );

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
            ),
          );
        } else {
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = 0;
          _clearDownloadSpeedTracking();
        }
      }

      await _lanDiscoveryService.sendTransferDecision(
        targetIp: request.senderIp,
        requestId: request.requestId,
        approved: approved,
        receiverName: _localName,
        transferPort: receiveSession?.port,
        acceptedFileNames: approved
            ? itemsToReceive
                  .map((item) => item.fileName)
                  .toList(growable: false)
            : null,
      );

      if (approved) {
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
      if (!approved) {
        _infoMessage = 'Transfer declined.';
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
      final hosts = await _networkHostScanner.scanActiveHosts(
        preferredSourceIp: _localIp,
      );
      final now = DateTime.now();
      _log(
        '${isManual ? "Manual" : "Auto"} refresh scan finished. hosts=${hosts.length}',
      );

      final seenMacToIp = <String, String>{};
      for (final host in hosts.entries) {
        final ip = host.key;
        final normalizedMac = DeviceAliasRepository.normalizeMac(host.value);
        final existing =
            _devicesByIp[ip] ?? DiscoveredDevice(ip: ip, lastSeen: now);
        final aliasName = normalizedMac == null
            ? existing.aliasName
            : _aliasByMac[normalizedMac];
        final isTrusted =
            normalizedMac != null && _trustedDeviceMacs.contains(normalizedMac);

        _devicesByIp[ip] = existing.copyWith(
          macAddress: normalizedMac ?? existing.macAddress,
          aliasName: aliasName ?? existing.aliasName,
          isTrusted: isTrusted,
          isReachable: true,
          lastSeen: now,
        );
        if (normalizedMac != null) {
          seenMacToIp[normalizedMac] = ip;
        }
      }

      if (seenMacToIp.isNotEmpty) {
        await _deviceAliasRepository.recordSeenDevices(seenMacToIp);
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
    final normalizedMac = DeviceAliasRepository.normalizeMac(
      existing?.macAddress,
    );
    final aliasName = normalizedMac == null ? null : _aliasByMac[normalizedMac];
    final isTrusted =
        normalizedMac != null && _trustedDeviceMacs.contains(normalizedMac);
    final detectedOs = _normalizeOperatingSystemName(event.operatingSystem);
    final detectedCategory = _resolveDeviceCategory(
      deviceType: event.deviceType,
      operatingSystem: detectedOs,
    );
    _devicesByIp[event.ip] =
        (existing ?? DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
            .copyWith(
              aliasName: aliasName ?? existing?.aliasName,
              deviceName: event.deviceName,
              operatingSystem: detectedOs ?? existing?.operatingSystem,
              deviceCategory: detectedCategory,
              isTrusted: isTrusted,
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

    final isTrustedSender =
        normalizedSenderMac != null &&
        _trustedDeviceMacs.contains(normalizedSenderMac);

    if (isTrustedSender) {
      _infoMessage =
          'Auto-accepting transfer from trusted device ${event.senderName}.';
      notifyListeners();
      unawaited(
        respondToTransferRequest(requestId: event.requestId, approved: true),
      );
      return;
    }

    _infoMessage = 'Incoming transfer request from ${event.senderName}.';
    notifyListeners();
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
      Future<void>.delayed(const Duration(seconds: 1), () {
        _uploadSentBytes = 0;
        _uploadTotalBytes = 0;
        _clearUploadSpeedTracking();
        notifyListeners();
      });
      notifyListeners();
    }
  }

  Future<void> _waitForIncomingTransferResult({
    required IncomingTransferRequest request,
    required TransferReceiveSession session,
  }) async {
    final result = await session.result;
    _activeReceiveSessions.remove(request.requestId);

    if (result.success) {
      var savedPaths = result.savedPaths;
      try {
        savedPaths = await _transferStorageService.publishToUserDownloads(
          sourcePaths: result.savedPaths,
          relativePaths: request.items
              .map((item) => item.fileName)
              .toList(growable: false),
          appFolderName: 'Landa',
        );
      } catch (error) {
        _log('Failed to publish files into user downloads: $error');
      }

      final rootPath = savedPaths.isEmpty
          ? result.destinationDirectory
          : File(savedPaths.first).parent.path;

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

      unawaited(
        _transferStorageService.showAndroidDownloadCompletedNotification(
          requestId: request.requestId,
          savedPaths: savedPaths,
          directoryPath: rootPath,
        ),
      );

      final hashStatus = result.hashVerified ? ' Hash verified.' : '';
      _infoMessage =
          'Received ${savedPaths.length} file(s) from ${request.senderName}. '
          'Saved to $rootPath.$hashStatus';
      _errorMessage = null;
      _downloadReceivedBytes = _downloadTotalBytes;
      _updateDownloadSpeedTracking(currentBytes: _downloadReceivedBytes);
    } else {
      _errorMessage =
          'Transfer from ${request.senderName} failed: ${result.message}';
      _log(_errorMessage!);
      unawaited(
        _transferStorageService.showAndroidDownloadFailedNotification(
          requestId: request.requestId,
          message: result.message,
        ),
      );
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      _downloadReceivedBytes = 0;
      _downloadTotalBytes = 0;
      _clearDownloadSpeedTracking();
      notifyListeners();
    });
    notifyListeners();
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

  void _onShareQuery(ShareQueryEvent event) {
    unawaited(_handleShareQuery(event));
  }

  Future<void> _handleShareQuery(ShareQueryEvent event) async {
    try {
      final removedCacheIds = await _sharedFolderCacheRepository
          .pruneUnavailableOwnerCaches(ownerMacAddress: _localDeviceMac);
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

    unawaited(_handleShareCatalog(event));
  }

  Future<void> _handleShareCatalog(ShareCatalogEvent event) async {
    final ownerMac = DeviceAliasRepository.normalizeMac(event.ownerMacAddress);
    final aliasName = ownerMac == null ? null : _aliasByMac[ownerMac];
    final trusted = ownerMac != null && _trustedDeviceMacs.contains(ownerMac);
    final existing = _devicesByIp[event.ownerIp];
    _devicesByIp[event.ownerIp] =
        (existing ??
                DiscoveredDevice(ip: event.ownerIp, lastSeen: event.observedAt))
            .copyWith(
              macAddress: ownerMac ?? existing?.macAddress,
              aliasName: aliasName ?? existing?.aliasName,
              deviceName: event.ownerName,
              isTrusted: trusted,
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
    for (final entry in event.entries) {
      _remoteShareOptions.add(
        RemoteShareOption(
          requestId: event.requestId,
          ownerIp: event.ownerIp,
          ownerName: aliasName ?? event.ownerName,
          ownerMacAddress: ownerMac ?? event.ownerMacAddress,
          entry: entry,
        ),
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
  }

  void _onThumbnailSyncRequest(ThumbnailSyncRequestEvent event) {
    unawaited(_handleThumbnailSyncRequest(event));
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
    unawaited(_handleThumbnailPacket(event));
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
    } catch (error) {
      _log('Failed to request remote thumbnails: $error');
    }
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

    if (_settings.downloadAttemptNotificationsEnabled) {
      unawaited(
        _appNotificationService.showDownloadAttemptNotification(
          requesterName: event.requesterName,
          shareLabel: cache.displayName,
          requestedFilesCount: event.selectedRelativePaths.length,
        ),
      );
    }
    _infoMessage =
        'Download request from ${event.requesterName} for "${cache.displayName}".';
    notifyListeners();

    final relativePathFilter = event.selectedRelativePaths.isEmpty
        ? null
        : event.selectedRelativePaths.toSet();
    final preparedFiles = await _buildTransferFilesForCache(
      cache,
      relativePathFilter: relativePathFilter,
    );
    if (preparedFiles.isEmpty) {
      _log(
        'Download request from ${event.requesterIp} ignored. '
        'No readable files in cacheId=${event.cacheId}',
      );
      return;
    }
    final items = preparedFiles
        .map((prepared) => prepared.announcement)
        .toList(growable: false);

    final requestId = _fileHashService.buildStableId(
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
        sharedLabel: cache.displayName,
        items: items,
      );
    } catch (error) {
      _pendingOutgoingTransfers.remove(requestId);
      _log('Failed to prepare download-share transfer: $error');
      return;
    }
    _log(
      'Transfer request sent for cache ${cache.cacheId} to ${event.requesterIp}. '
      'items=${items.length}',
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
    final seed = '${_localIp ?? "0.0.0.0"}|$_localName';
    final digest = sha256.convert(utf8.encode(seed)).bytes;
    final bytes = digest.take(6).toList(growable: false);
    bytes[0] = (bytes[0] & 0xfe) | 0x02;
    _localDeviceMac = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }

  Future<void> _loadOwnerCaches() async {
    try {
      final caches = await _sharedFolderCacheRepository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: _localDeviceMac,
      );
      _ownerSharedCaches
        ..clear()
        ..addAll(caches);
    } catch (error) {
      _log('Failed to load owner cache list: $error');
    }
  }

  Future<void> _loadTrustedDevices() async {
    try {
      final trustedMacs = await _deviceAliasRepository.loadTrustedMacs();
      _trustedDeviceMacs
        ..clear()
        ..addAll(trustedMacs);
      _devicesByIp.updateAll((_, value) {
        final normalizedMac = DeviceAliasRepository.normalizeMac(
          value.macAddress,
        );
        final isTrusted =
            normalizedMac != null && _trustedDeviceMacs.contains(normalizedMac);
        return value.copyWith(isTrusted: isTrusted);
      });
      _log('Loaded trusted devices from DB. count=${trustedMacs.length}');
    } catch (error) {
      _log('Failed to load trusted devices from DB: $error');
    }
  }

  Future<void> _loadSettings() async {
    try {
      _settings = await _appSettingsRepository.load();
      _log(
        'Loaded settings. background=${_settings.backgroundScanInterval.label}, '
        'notifyDownloadAttempts=${_settings.downloadAttemptNotificationsEnabled}, '
        'trayOnClose=${_settings.minimizeToTrayOnClose}',
      );
    } catch (error) {
      _log('Failed to load app settings: $error');
      _settings = AppSettings.defaults;
    }
  }

  Future<void> _saveSettings(AppSettings settings) async {
    try {
      await _appSettingsRepository.save(settings);
      _settings = settings;
      _errorMessage = null;
      _restartAutoRefreshTimer();
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
    return _settings.backgroundScanInterval.duration;
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
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != '.' && part != '..')
        .toList(growable: false);
    if (parts.isEmpty) {
      return 'file.bin';
    }
    return p.joinAll(parts);
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
    for (final session in _activeReceiveSessions.values) {
      unawaited(session.close());
    }
    _activeReceiveSessions.clear();
    _lanDiscoveryService.stop();
    super.dispose();
  }

  void _log(String message) {
    developer.log(message, name: 'DiscoveryController');
  }

  Future<void> _loadAliases() async {
    try {
      final aliases = await _deviceAliasRepository.loadAliasMap();
      _aliasByMac
        ..clear()
        ..addAll(aliases);
      _log('Loaded aliases from DB. count=${aliases.length}');
    } catch (error) {
      _log('Failed to load aliases from DB: $error');
    }
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

  void _purgeExpiredPendingRemoteDownloads() {
    final now = DateTime.now();
    _pendingRemoteDownloads.removeWhere(
      (_, pending) =>
          now.difference(pending.createdAt) > _pendingRemoteDownloadTtl,
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
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/path_opener.dart';
import '../../history/data/transfer_history_repository.dart';
import '../../history/domain/transfer_history_record.dart';
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

class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required LanDiscoveryService lanDiscoveryService,
    required NetworkHostScanner networkHostScanner,
    required DeviceAliasRepository deviceAliasRepository,
    required TransferHistoryRepository transferHistoryRepository,
    required SharedFolderCacheRepository sharedFolderCacheRepository,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required PathOpener pathOpener,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _networkHostScanner = networkHostScanner,
       _deviceAliasRepository = deviceAliasRepository,
       _transferHistoryRepository = transferHistoryRepository,
       _sharedFolderCacheRepository = sharedFolderCacheRepository,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _pathOpener = pathOpener;

  static const Duration _autoRefreshInterval = Duration(seconds: 30);

  final LanDiscoveryService _lanDiscoveryService;
  final NetworkHostScanner _networkHostScanner;
  final DeviceAliasRepository _deviceAliasRepository;
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
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};
  final List<TransferHistoryRecord> _downloadHistory =
      <TransferHistoryRecord>[];
  Timer? _scanTimer;
  bool _started = false;
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
  String? get localIp => _localIp;
  String get localName => _localName;
  String get localDeviceMac => _localDeviceMac;
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
      _scanTimer = Timer.periodic(
        _autoRefreshInterval,
        (_) => unawaited(_refresh(isManual: false)),
      );
    } catch (error) {
      _errorMessage = 'LAN discovery error: $error';
      _log(_errorMessage!);
      notifyListeners();
    }
  }

  Future<void> refresh() => _refresh(isManual: true);

  void clearInfoMessage() {
    _infoMessage = null;
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

      await _sharedFolderCacheRepository.buildOwnerCache(
        ownerMacAddress: _localDeviceMac,
        folderPath: folderPath,
      );
      await _loadOwnerCaches();
      _infoMessage = 'Shared folder added.';
      _errorMessage = null;
    } catch (error) {
      _errorMessage = 'Failed to add shared folder: $error';
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
    try {
      if (approved) {
        _downloadReceivedBytes = 0;
        _downloadTotalBytes = request.totalBytes;
        notifyListeners();

        final destinationDirectory = await _transferStorageService
            .resolveReceiveDirectory(appFolderName: 'Landa');
        receiveSession = await _fileTransferService.startReceiver(
          requestId: request.requestId,
          expectedItems: request.items,
          destinationDirectory: destinationDirectory,
          onProgress: (received, total) {
            _downloadReceivedBytes = received;
            _downloadTotalBytes = total;
            notifyListeners();
          },
        );
        _activeReceiveSessions[request.requestId] = receiveSession;
        unawaited(
          _waitForIncomingTransferResult(
            request: request,
            session: receiveSession,
          ),
        );
      }

      await _lanDiscoveryService.sendTransferDecision(
        targetIp: request.senderIp,
        requestId: request.requestId,
        approved: approved,
        receiverName: _localName,
        transferPort: receiveSession?.port,
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
      _infoMessage = approved
          ? 'Transfer accepted. Waiting for file stream...'
          : 'Transfer declined.';
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
    _devicesByIp[event.ip] =
        (existing ?? DiscoveredDevice(ip: event.ip, lastSeen: event.observedAt))
            .copyWith(
              aliasName: aliasName ?? existing?.aliasName,
              deviceName: event.deviceName,
              isTrusted: isTrusted,
              isAppDetected: true,
              isReachable: true,
              lastSeen: event.observedAt,
            );
    notifyListeners();
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
    if (event.transferPort == null) {
      _errorMessage =
          '${event.receiverName} accepted request but did not provide transfer port.';
      notifyListeners();
      return;
    }

    _infoMessage =
        '${event.receiverName} accepted request. Starting transfer...';
    notifyListeners();
    unawaited(_sendApprovedTransfer(event: event, session: session));
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
          notifyListeners();
        },
      );
      _infoMessage =
          'Transferred ${session.files.length} file(s) to ${session.receiverName}.';
      _errorMessage = null;
      _uploadSentBytes = _uploadTotalBytes;
    } catch (error) {
      _errorMessage = 'File transfer failed: $error';
      _log(_errorMessage!);
    } finally {
      _pendingOutgoingTransfers.remove(event.requestId);
      Future<void>.delayed(const Duration(seconds: 1), () {
        _uploadSentBytes = 0;
        _uploadTotalBytes = 0;
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
          rootPath: savedPaths.isEmpty
              ? result.destinationDirectory
              : File(savedPaths.first).parent.path,
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

      _infoMessage =
          'Received ${savedPaths.length} file(s) from ${request.senderName}. '
          'Saved to ${savedPaths.isEmpty ? result.destinationDirectory : File(savedPaths.first).parent.path}.';
      _errorMessage = null;
      _downloadReceivedBytes = _downloadTotalBytes;
    } else {
      _errorMessage =
          'Transfer from ${request.senderName} failed: ${result.message}';
      _log(_errorMessage!);
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      _downloadReceivedBytes = 0;
      _downloadTotalBytes = 0;
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
    await _loadOwnerCaches();
    if (_ownerSharedCaches.isEmpty) {
      _log('Share query from ${event.requesterIp} returned 0 owner caches');
      return;
    }

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
      catalog.add(
        SharedCatalogEntryItem(
          cacheId: cache.cacheId,
          displayName: cache.displayName,
          itemCount: cache.itemCount,
          totalBytes: cache.totalBytes,
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
    );
    _log(
      'Share catalog sent to ${event.requesterIp}. entries=${catalog.length}',
    );
  }

  void _onShareCatalog(ShareCatalogEvent event) {
    if (_activeShareQueryRequestId != null &&
        event.requestId != _activeShareQueryRequestId) {
      return;
    }

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

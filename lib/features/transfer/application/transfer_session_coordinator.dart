import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/app_notification_service.dart';
import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_packet_codec.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../history/application/download_history_boundary.dart';
import '../../history/domain/transfer_history_record.dart';
import '../../settings/domain/app_settings.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../data/transfer_storage_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'shared_cache_catalog.dart';
import 'shared_cache_index_store.dart';

class TransferSessionNotice {
  const TransferSessionNotice({
    this.infoMessage,
    this.errorMessage,
    this.clearInfo = false,
    this.clearError = false,
  });

  final String? infoMessage;
  final String? errorMessage;
  final bool clearInfo;
  final bool clearError;
}

class TransferSessionCoordinator extends ChangeNotifier {
  TransferSessionCoordinator({
    required LanDiscoveryService lanDiscoveryService,
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
    required DownloadHistoryBoundary downloadHistoryBoundary,
    required PreviewCacheOwner previewCacheOwner,
    required AppNotificationService appNotificationService,
    required AppSettings Function() settingsProvider,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required bool Function(String? normalizedMac) isTrustedSender,
    required String? Function({
      required String ownerIp,
      required String cacheId,
    })
    resolveRemoteOwnerMac,
    this.pendingRemoteDownloadTtl = const Duration(minutes: 3),
    this.pendingRemotePreviewTtl = const Duration(minutes: 1),
    this.previewRequestTimeout = const Duration(seconds: 45),
    this.progressResetDelay = const Duration(seconds: 1),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _downloadHistoryBoundary = downloadHistoryBoundary,
       _previewCacheOwner = previewCacheOwner,
       _appNotificationService = appNotificationService,
       _settingsProvider = settingsProvider,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _isTrustedSender = isTrustedSender,
       _resolveRemoteOwnerMac = resolveRemoteOwnerMac;

  final LanDiscoveryService _lanDiscoveryService;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final DownloadHistoryBoundary _downloadHistoryBoundary;
  final PreviewCacheOwner _previewCacheOwner;
  final AppNotificationService _appNotificationService;
  final AppSettings Function() _settingsProvider;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final bool Function(String? normalizedMac) _isTrustedSender;
  final String? Function({required String ownerIp, required String cacheId})
  _resolveRemoteOwnerMac;

  final List<IncomingTransferRequest> _incomingRequests =
      <IncomingTransferRequest>[];
  final Map<String, _OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, _OutgoingTransferSession>{};
  final Map<String, _PendingRemoteDownloadIntent> _pendingRemoteDownloads =
      <String, _PendingRemoteDownloadIntent>{};
  final Map<String, _PendingRemotePreviewIntent> _pendingRemotePreviewsByKey =
      <String, _PendingRemotePreviewIntent>{};
  final Map<String, Completer<String?>> _previewResultCompletersByRequestId =
      <String, Completer<String?>>{};
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};

  final Duration pendingRemoteDownloadTtl;
  final Duration pendingRemotePreviewTtl;
  final Duration previewRequestTimeout;
  final Duration progressResetDelay;

  bool _isSendingTransfer = false;
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
  TransferSessionNotice? _pendingNotice;
  bool _disposed = false;

  bool get isSendingTransfer => _isSendingTransfer;
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
  List<IncomingTransferRequest> get incomingRequests =>
      List<IncomingTransferRequest>.unmodifiable(_incomingRequests);

  TransferSessionNotice? takePendingNotice() {
    final notice = _pendingNotice;
    _pendingNotice = null;
    return notice;
  }

  Future<void> sendFilesToDevice({
    required String targetIp,
    required String targetName,
    required List<String> selectedPaths,
  }) async {
    if (selectedPaths.isEmpty) {
      return;
    }

    _isSendingTransfer = true;
    String? pendingRequestId;
    _notify();
    try {
      final cache = await _sharedCacheCatalog.buildOwnerSelectionCache(
        ownerMacAddress: _localDeviceMac,
        filePaths: selectedPaths,
        displayName: 'Transfer to $targetName',
      );
      await _sharedCacheCatalog.loadOwnerCaches(
        ownerMacAddress: _localDeviceMac,
      );

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
        _publishNotice(
          const TransferSessionNotice(
            errorMessage: 'No readable files selected.',
          ),
        );
        return;
      }

      final requestId = _fileHashService.buildStableId(
        '${DateTime.now().microsecondsSinceEpoch}|$targetIp|${cache.cacheId}',
      );
      pendingRequestId = requestId;
      _pendingOutgoingTransfers[requestId] = _OutgoingTransferSession(
        receiverName: targetName,
        files: transferFiles,
      );
      await _lanDiscoveryService.sendTransferRequest(
        targetIp: targetIp,
        requestId: requestId,
        senderName: _localName,
        senderMacAddress: _localDeviceMac,
        sharedCacheId: cache.cacheId,
        sharedLabel: cache.displayName,
        items: items,
      );

      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Transfer request sent to $targetName. Waiting for accept.',
          clearError: true,
        ),
      );
    } catch (error) {
      if (pendingRequestId != null) {
        _pendingOutgoingTransfers.remove(pendingRequestId);
      }
      _log('Failed to send transfer request: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to send transfer request: $error',
        ),
      );
    } finally {
      _isSendingTransfer = false;
      _notify();
    }
  }

  Future<void> requestDownloadFromRemoteFiles({
    required String ownerIp,
    required String ownerName,
    required Map<String, Set<String>> selectedRelativePathsByCache,
    Map<String, Set<String>> selectedFolderPrefixesByCache =
        const <String, Set<String>>{},
    required bool useStandardAppDownloadFolder,
  }) async {
    if (selectedRelativePathsByCache.isEmpty &&
        selectedFolderPrefixesByCache.isEmpty) {
      _publishNotice(
        const TransferSessionNotice(
          errorMessage: 'Select at least one file before requesting download.',
        ),
      );
      return;
    }

    final normalizedSelection = <String, List<String>>{};
    final normalizedFolderPrefixes = <String, List<String>>{};
    var selectedFilesCount = 0;
    var selectedFolderCount = 0;
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
    for (final entry in selectedFolderPrefixesByCache.entries) {
      final cacheId = entry.key.trim();
      if (cacheId.isEmpty) {
        continue;
      }
      final prefixes =
          entry.value
              .map((path) => path.trim())
              .where((path) => path.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
      if (prefixes.isEmpty) {
        continue;
      }
      normalizedFolderPrefixes[cacheId] = prefixes;
      selectedFolderCount += prefixes.length;
    }

    if (normalizedSelection.isEmpty && normalizedFolderPrefixes.isEmpty) {
      _publishNotice(
        const TransferSessionNotice(
          errorMessage: 'Selected file list is empty.',
        ),
      );
      return;
    }

    Directory? destinationDirectory;
    try {
      destinationDirectory = await _resolveRemoteDownloadDestinationDirectory(
        useStandardAppDownloadFolder: useStandardAppDownloadFolder,
      );
    } catch (error) {
      _log('Failed to resolve remote download destination: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to choose download destination: $error',
        ),
      );
      return;
    }

    if (destinationDirectory == null) {
      return;
    }

    try {
      _purgeExpiredPendingRemoteDownloads();
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final cacheIds = <String>{
        ...normalizedSelection.keys,
        ...normalizedFolderPrefixes.keys,
      };
      for (final cacheId in cacheIds) {
        final selectedPaths = normalizedSelection[cacheId] ?? const <String>[];
        final folderPrefixes =
            normalizedFolderPrefixes[cacheId] ?? const <String>[];
        final requestId = _fileHashService.buildStableId(
          'download|$ownerIp|$cacheId|$stamp|'
          '${selectedPaths.join(",")}|${folderPrefixes.join(",")}|$_localDeviceMac',
        );
        await _lanDiscoveryService.sendDownloadRequest(
          targetIp: ownerIp,
          requestId: requestId,
          requesterName: _localName,
          requesterMacAddress: _localDeviceMac,
          cacheId: cacheId,
          selectedRelativePaths: selectedPaths,
          selectedFolderPrefixes: folderPrefixes,
        );

        final pendingKey = _pendingRemoteDownloadKey(
          ownerIp: ownerIp,
          cacheId: cacheId,
        );
        _pendingRemoteDownloads[pendingKey] = _PendingRemoteDownloadIntent(
          ownerIp: ownerIp,
          ownerMacAddress: _resolveRemoteOwnerMac(
            ownerIp: ownerIp,
            cacheId: cacheId,
          ),
          cacheId: cacheId,
          destinationDirectoryPath: destinationDirectory.path,
          preserveSharedRootOnReceive:
              selectedPaths.isEmpty && folderPrefixes.isEmpty,
          createdAt: DateTime.now(),
        );
      }
      _publishNotice(
        TransferSessionNotice(
          infoMessage: selectedFilesCount > 0
              ? 'Requested $selectedFilesCount file(s) from $ownerName.'
              : selectedFolderCount > 0
              ? 'Requested $selectedFolderCount folder(s) from $ownerName.'
              : 'Download request sent to $ownerName.',
          clearError: true,
        ),
      );
    } catch (error) {
      _log('Failed to request remote download: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to request remote download: $error',
        ),
      );
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
      _publishNotice(
        const TransferSessionNotice(errorMessage: 'Preview path is empty.'),
      );
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
    _pendingRemotePreviewsByKey[pendingKey] = _PendingRemotePreviewIntent(
      ownerIp: ownerIp,
      ownerMacAddress: _resolveRemoteOwnerMac(
        ownerIp: ownerIp,
        cacheId: cacheId,
      ),
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
        selectedFolderPrefixes: const <String>[],
        previewMode: true,
      );

      final previewPath = await previewCompleter.future.timeout(
        previewRequestTimeout,
        onTimeout: () => null,
      );
      if (previewPath == null) {
        _publishNotice(
          TransferSessionNotice(
            errorMessage: 'Preview timed out for $ownerName.',
          ),
        );
      }
      return previewPath;
    } catch (error) {
      _log('Failed to request preview: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to request preview: $error',
        ),
      );
      if (!previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      return null;
    } finally {
      _pendingRemotePreviewsByKey.remove(pendingKey);
    }
  }

  Future<void> respondToTransferRequest({
    required String requestId,
    required bool approved,
    bool forPreview = false,
    String? previewRelativePath,
    String? destinationDirectoryOverridePath,
    bool preserveSharedRootOnReceive = false,
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
    var decisionApproved = approved;
    final previewCompleter = isPreview
        ? _previewResultCompletersByRequestId.remove(request.requestId)
        : null;

    try {
      if (decisionApproved) {
        final destinationDirectory = isPreview
            ? await _previewCacheOwner.resolvePreviewArtifactDirectory()
            : destinationDirectoryOverridePath != null
            ? Directory(destinationDirectoryOverridePath)
            : await _transferStorageService.resolveReceiveDirectory(
                appFolderName: 'Landa',
              );
        final destinationRelativeRootPrefix =
            !isPreview && preserveSharedRootOnReceive
            ? _resolveReceiveRootPrefix(request.sharedLabel)
            : null;

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
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
          );
          skippedExistingCount = request.items.length - itemsToReceive.length;
        }

        final expectedBytes = itemsToReceive.fold<int>(
          0,
          (sum, item) => sum + item.sizeBytes,
        );

        if (itemsToReceive.isNotEmpty) {
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = expectedBytes;
          _resetDownloadSpeedTracking(currentBytes: 0);
          _notify();

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
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
            onProgress: (received, total) {
              _downloadReceivedBytes = received;
              _downloadTotalBytes = total;
              _updateDownloadSpeedTracking(currentBytes: received);
              _notify();

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
              destinationRelativeRootPrefix: destinationRelativeRootPrefix,
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

        await _sharedCacheCatalog.saveReceiverCache(
          ownerMacAddress: request.senderMacAddress,
          receiverMacAddress: _localDeviceMac,
          remoteFolderIdentity: request.sharedCacheId,
          remoteDisplayName: request.sharedLabel,
          entries: entries,
        );
      }

      _incomingRequests.removeAt(index);
      if (!decisionApproved) {
        _publishNotice(
          TransferSessionNotice(
            infoMessage: isPreview
                ? 'Preview request was declined.'
                : 'Transfer declined.',
            clearError: true,
          ),
        );
      } else if (isPreview) {
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Preview accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      } else if (itemsToReceive.isEmpty) {
        _publishNotice(
          const TransferSessionNotice(
            infoMessage:
                'All requested files already exist locally. Transfer skipped.',
            clearError: true,
          ),
        );
      } else if (skippedExistingCount > 0) {
        _publishNotice(
          TransferSessionNotice(
            infoMessage:
                'Transfer accepted. Skipping $skippedExistingCount existing file(s), waiting for missing files...',
            clearError: true,
          ),
        );
      } else {
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Transfer accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      }
    } catch (error) {
      if (receiveSession != null) {
        await receiveSession.close();
        _activeReceiveSessions.remove(request.requestId);
      }
      if (previewCompleter != null && !previewCompleter.isCompleted) {
        previewCompleter.complete(null);
      }
      _previewResultCompletersByRequestId.remove(request.requestId);
      _log('Failed to respond to transfer request: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to respond to transfer request: $error',
        ),
      );
    }
  }

  void handleTransferRequestEvent(TransferRequestEvent event) {
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
    final pendingRemoteDownload = _consumePendingRemoteDownload(event);
    if (pendingRemoteDownload != null) {
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Auto-accepting download transfer from ${event.senderName}.',
          clearError: true,
        ),
      );
      unawaited(
        respondToTransferRequest(
          requestId: event.requestId,
          approved: true,
          destinationDirectoryOverridePath:
              pendingRemoteDownload.destinationDirectoryPath,
          preserveSharedRootOnReceive:
              pendingRemoteDownload.preserveSharedRootOnReceive,
        ),
      );
      return;
    }

    final previewIntent = _consumePendingRemotePreview(event);
    if (previewIntent != null) {
      _previewResultCompletersByRequestId[event.requestId] =
          previewIntent.completer;
      _publishNotice(
        TransferSessionNotice(
          infoMessage: 'Preparing remote preview from ${event.senderName}...',
          clearError: true,
        ),
      );
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

    if (_isTrustedSender(normalizedSenderMac)) {
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Auto-accepting transfer from friend ${event.senderName}.',
          clearError: true,
        ),
      );
      unawaited(
        respondToTransferRequest(requestId: event.requestId, approved: true),
      );
      return;
    }

    _publishNotice(
      TransferSessionNotice(
        infoMessage: 'Incoming transfer request from ${event.senderName}.',
        clearError: true,
      ),
    );
  }

  void handleTransferDecisionEvent(TransferDecisionEvent event) {
    unawaited(_handleTransferDecisionEventAsync(event));
  }

  Future<void> _handleTransferDecisionEventAsync(
    TransferDecisionEvent event,
  ) async {
    if (!event.approved) {
      _pendingOutgoingTransfers.remove(event.requestId);
      _publishNotice(
        TransferSessionNotice(
          infoMessage: '${event.receiverName} declined your transfer request.',
        ),
      );
      return;
    }

    final session = _pendingOutgoingTransfers[event.requestId];
    if (session == null) {
      _publishNotice(
        TransferSessionNotice(
          infoMessage: '${event.receiverName} accepted your transfer request.',
        ),
      );
      return;
    }

    final resolvedFiles = await _resolveOutgoingSessionFiles(session);
    final filteredFiles = _filterOutgoingFilesForDecision(
      files: resolvedFiles,
      acceptedFileNames: event.acceptedFileNames,
    );
    if (filteredFiles.isEmpty) {
      _pendingOutgoingTransfers.remove(event.requestId);
      unawaited(_cleanupTemporaryOutgoingFiles(resolvedFiles));
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              '${event.receiverName} already has these files. Transfer skipped.',
          clearError: true,
        ),
      );
      return;
    }

    if (event.transferPort == null) {
      _publishNotice(
        TransferSessionNotice(
          errorMessage:
              '${event.receiverName} accepted request but did not provide transfer port.',
        ),
      );
      return;
    }

    _publishNotice(
      TransferSessionNotice(
        infoMessage:
            '${event.receiverName} accepted request. Starting transfer...',
        clearError: true,
      ),
    );
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

  void handleDownloadRequestEvent(DownloadRequestEvent event) {
    unawaited(_handleDownloadRequest(event));
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
    _notify();

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
          _notify();
        },
      );
      _uploadSentBytes = _uploadTotalBytes;
      _updateUploadSpeedTracking(currentBytes: _uploadSentBytes);
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Transferred ${session.files.length} file(s) to ${session.receiverName}.',
          clearError: true,
        ),
      );
    } catch (error) {
      _log('File transfer failed: $error');
      _publishNotice(
        TransferSessionNotice(errorMessage: 'File transfer failed: $error'),
      );
    } finally {
      _pendingOutgoingTransfers.remove(event.requestId);
      await _cleanupTemporaryOutgoingFiles(session.files);
      Future<void>.delayed(progressResetDelay, () {
        if (_disposed) {
          return;
        }
        _uploadSentBytes = 0;
        _uploadTotalBytes = 0;
        _clearUploadSpeedTracking();
        _notify();
      });
      _notify();
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
    String? destinationRelativeRootPrefix,
    Completer<String?>? previewCompleter,
  }) async {
    try {
      final result = await session.result;
      if (result.success) {
        var savedPaths = result.savedPaths;
        final recordedRelativePaths = acceptedItems
            .map(
              (item) => _buildReceiveRelativePath(
                item.fileName,
                destinationRelativeRootPrefix: destinationRelativeRootPrefix,
              ),
            )
            .toList(growable: false);
        if (persistToUserDownloads &&
            _transferStorageService.publishesReceivedDownloadsToUserDownloads) {
          try {
            savedPaths = await _transferStorageService.publishToUserDownloads(
              sourcePaths: result.savedPaths,
              relativePaths: recordedRelativePaths,
              appFolderName: 'Landa',
            );
          } catch (error) {
            _log('Failed to publish files into user downloads: $error');
          }
        }

        final hasReceiveRootPrefix =
            destinationRelativeRootPrefix != null &&
            destinationRelativeRootPrefix.isNotEmpty;
        final rootPath =
            persistToUserDownloads &&
                _transferStorageService
                    .publishesReceivedDownloadsToUserDownloads
            ? hasReceiveRootPrefix
                  ? _sharedParentPath(savedPaths)
                  : savedPaths.isEmpty
                  ? result.destinationDirectory
                  : File(savedPaths.first).parent.path
            : hasReceiveRootPrefix
            ? p.join(result.destinationDirectory, destinationRelativeRootPrefix)
            : result.destinationDirectory;

        if (recordHistory) {
          try {
            await _downloadHistoryBoundary.recordDownload(
              id: _fileHashService.buildStableId(
                'download-history|${request.requestId}|'
                '${DateTime.now().microsecondsSinceEpoch}',
              ),
              requestId: request.requestId,
              peerName: request.senderName,
              peerIp: request.senderIp,
              rootPath: rootPath,
              savedPaths: savedPaths,
              fileCount: savedPaths.length,
              totalBytes: result.totalBytes,
              status: TransferHistoryStatus.completed,
              createdAtMs: DateTime.now().millisecondsSinceEpoch,
            );
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
          _publishNotice(
            TransferSessionNotice(
              infoMessage: previewPath == null
                  ? 'Preview received but file is unavailable.'
                  : 'Preview ready: ${p.basename(previewPath)}.$hashStatus',
              clearError: true,
            ),
          );
        } else {
          _publishNotice(
            TransferSessionNotice(
              infoMessage:
                  'Received ${savedPaths.length} file(s) from ${request.senderName}. '
                  'Saved to $rootPath.$hashStatus',
              clearError: true,
            ),
          );
        }

        _downloadReceivedBytes = _downloadTotalBytes;
        _updateDownloadSpeedTracking(currentBytes: _downloadReceivedBytes);
      } else {
        if (previewCompleter != null && !previewCompleter.isCompleted) {
          previewCompleter.complete(null);
        }
        _log('Transfer from ${request.senderName} failed: ${result.message}');
        _publishNotice(
          TransferSessionNotice(
            errorMessage: previewCompleter != null
                ? 'Preview from ${request.senderName} failed: ${result.message}'
                : 'Transfer from ${request.senderName} failed: ${result.message}',
          ),
        );
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
      _log('$message\n$stackTrace');
      _publishNotice(TransferSessionNotice(errorMessage: message));
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
      Future<void>.delayed(progressResetDelay, () {
        if (_disposed) {
          return;
        }
        _downloadReceivedBytes = 0;
        _downloadTotalBytes = 0;
        _clearDownloadSpeedTracking();
        _notify();
      });
      _notify();
    }
  }

  Future<void> _handleDownloadRequest(DownloadRequestEvent event) async {
    await _sharedCacheCatalog.loadOwnerCaches(ownerMacAddress: _localDeviceMac);
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
        _settingsProvider().downloadAttemptNotificationsEnabled) {
      unawaited(
        _appNotificationService.showDownloadAttemptNotification(
          requesterName: event.requesterName,
          shareLabel: cache.displayName,
          requestedFilesCount: event.selectedRelativePaths.length,
        ),
      );
    }

    _publishNotice(
      TransferSessionNotice(
        infoMessage: isPreviewRequest
            ? 'Preview request from ${event.requesterName}.'
            : 'Download request from ${event.requesterName} for "${cache.displayName}".',
        clearError: true,
      ),
    );

    final relativePathFilter = event.selectedRelativePaths.isEmpty
        ? null
        : event.selectedRelativePaths.toSet();
    final folderPrefixFilter = event.selectedFolderPrefixes.isEmpty
        ? null
        : event.selectedFolderPrefixes.toSet();
    final deferHashesUntilAccept =
        !isPreviewRequest &&
        folderPrefixFilter == null &&
        event.selectedRelativePaths.length == 1;
    final preparedFiles = isPreviewRequest
        ? await _buildCompressedPreviewFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
          )
        : await _buildTransferFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
            folderPrefixFilter: folderPrefixFilter,
            includeHashes: !deferHashesUntilAccept,
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
        finalizedFilesFuture: deferHashesUntilAccept
            ? _hydrateTransferSourceFilesWithHashes(
                preparedFiles
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
              )
            : null,
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

  Future<void> _cleanupPreviewCacheBySettings() async {
    try {
      final settings = _settingsProvider();
      await _previewCacheOwner.cleanupPreviewArtifacts(
        maxSizeGb: settings.previewCacheMaxSizeGb,
        maxAgeDays: settings.previewCacheMaxAgeDays,
      );
    } catch (error) {
      _log('Failed to cleanup preview cache: $error');
    }
  }

  Future<List<_PreparedTransferFile>> _buildCompressedPreviewFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  }) async {
    final prepared = await _previewCacheOwner
        .buildCompressedPreviewFilesForCache(
          cache,
          relativePathFilter: relativePathFilter,
        );
    return prepared
        .map(
          (file) => _PreparedTransferFile(
            sourcePath: file.sourcePath,
            announcement: TransferAnnouncementItem(
              fileName: file.fileName,
              sizeBytes: file.sizeBytes,
              sha256: file.sha256,
            ),
            deleteAfterTransfer: file.deleteAfterTransfer,
          ),
        )
        .toList(growable: false);
  }

  Future<List<_PreparedTransferFile>> _buildTransferFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
    Set<String>? folderPrefixFilter,
    bool includeHashes = true,
  }) async {
    final indexEntries = await _sharedCacheIndexStore.readIndexEntries(cache);
    final items = <_PreparedTransferFile>[];
    final normalizedFolderPrefixes = folderPrefixFilter
        ?.map(_normalizeTransferPathForMatch)
        .where((prefix) => prefix.isNotEmpty)
        .toSet();
    for (final entry in indexEntries) {
      final normalizedRelativePath = _normalizeTransferPathForMatch(
        entry.relativePath,
      );
      if (relativePathFilter != null) {
        if (!relativePathFilter.contains(entry.relativePath)) {
          continue;
        }
      } else if (normalizedFolderPrefixes != null &&
          normalizedFolderPrefixes.isNotEmpty) {
        final matchesFolderPrefix = normalizedFolderPrefixes.any(
          (prefix) =>
              normalizedRelativePath == prefix ||
              normalizedRelativePath.startsWith('$prefix/'),
        );
        if (!matchesFolderPrefix) {
          continue;
        }
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
      final sha256Hash = includeHashes
          ? await _fileHashService.computeSha256ForPath(filePath)
          : '';

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
    for (final cache in _sharedCacheCatalog.ownerCaches) {
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
    String? destinationRelativeRootPrefix,
  }) async {
    final missing = <TransferFileManifestItem>[];
    for (final item in items) {
      final relativePath = _buildReceiveRelativePath(
        item.fileName,
        destinationRelativeRootPrefix: destinationRelativeRootPrefix,
      );
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

        final expectedHash = item.sha256.trim();
        if (expectedHash.isEmpty) {
          missing.add(item);
          continue;
        }

        final existingHash = await _fileHashService.computeSha256ForPath(
          targetPath,
        );
        if (existingHash.toLowerCase() != expectedHash.toLowerCase()) {
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

  String _buildReceiveRelativePath(
    String relativePath, {
    String? destinationRelativeRootPrefix,
  }) {
    final sanitizedRelativePath = _sanitizeTransferRelativePath(relativePath);
    final sanitizedPrefix = destinationRelativeRootPrefix?.trim();
    if (sanitizedPrefix == null || sanitizedPrefix.isEmpty) {
      return sanitizedRelativePath;
    }
    return p.join(sanitizedPrefix, sanitizedRelativePath);
  }

  String? _resolveReceiveRootPrefix(String sharedLabel) {
    final sanitized = _sanitizeTransferRelativePathPart(sharedLabel.trim());
    if (sanitized.isEmpty || sanitized == '_') {
      return null;
    }
    return sanitized;
  }

  String _sharedParentPath(List<String> paths) {
    if (paths.isEmpty) {
      return '';
    }

    final directories = paths
        .map((path) => p.normalize(p.dirname(path)))
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (directories.isEmpty) {
      return '';
    }

    List<String> common = p.split(directories.first);
    for (final directory in directories.skip(1)) {
      final next = p.split(directory);
      var sharedLength = 0;
      while (sharedLength < common.length &&
          sharedLength < next.length &&
          common[sharedLength] == next[sharedLength]) {
        sharedLength += 1;
      }
      common = common.take(sharedLength).toList(growable: false);
      if (common.isEmpty) {
        break;
      }
    }
    if (common.isEmpty) {
      final rootPrefix = p.rootPrefix(paths.first);
      return rootPrefix.isEmpty ? p.dirname(paths.first) : rootPrefix;
    }
    return p.joinAll(common);
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

  _PendingRemoteDownloadIntent? _consumePendingRemoteDownload(
    TransferRequestEvent event,
  ) {
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
      return null;
    }
    return _pendingRemoteDownloads.remove(matchedKey);
  }

  Future<Directory?> _resolveRemoteDownloadDestinationDirectory({
    required bool useStandardAppDownloadFolder,
  }) async {
    if (_transferStorageService.supportsDesktopDownloadPicker) {
      if (useStandardAppDownloadFolder) {
        return _transferStorageService.resolveReceiveDirectory(
          appFolderName: 'Landa',
        );
      }
      return _transferStorageService.pickDesktopDownloadDirectory();
    }

    return _transferStorageService.resolveReceiveDirectory(
      appFolderName: 'Landa',
    );
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

  Future<List<TransferSourceFile>> _resolveOutgoingSessionFiles(
    _OutgoingTransferSession session,
  ) async {
    final finalizedFilesFuture = session.finalizedFilesFuture;
    if (finalizedFilesFuture == null) {
      return session.files;
    }
    final resolved = await finalizedFilesFuture;
    session.files = resolved;
    session.finalizedFilesFuture = null;
    return resolved;
  }

  Future<List<TransferSourceFile>> _hydrateTransferSourceFilesWithHashes(
    List<TransferSourceFile> files,
  ) async {
    final hydrated = <TransferSourceFile>[];
    for (final file in files) {
      final normalizedHash = file.sha256.trim();
      if (normalizedHash.isNotEmpty) {
        hydrated.add(file);
        continue;
      }
      final computedHash = await _fileHashService.computeSha256ForPath(
        file.sourcePath,
      );
      hydrated.add(
        TransferSourceFile(
          sourcePath: file.sourcePath,
          fileName: file.fileName,
          sizeBytes: file.sizeBytes,
          sha256: computedHash,
          deleteAfterTransfer: file.deleteAfterTransfer,
        ),
      );
    }
    return hydrated;
  }

  void _purgeExpiredPendingRemotePreviews() {
    final now = DateTime.now();
    _pendingRemotePreviewsByKey.removeWhere((_, pending) {
      final expired =
          now.difference(pending.createdAt) > pendingRemotePreviewTtl;
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
          now.difference(pending.createdAt) > pendingRemoteDownloadTtl,
    );
  }

  void _publishNotice(TransferSessionNotice notice) {
    _pendingNotice = notice;
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'TransferSessionCoordinator');
  }

  @override
  void dispose() {
    _disposed = true;
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
    super.dispose();
  }

  String get _localName => _localNameProvider();

  String get _localDeviceMac => _localDeviceMacProvider();
}

class _OutgoingTransferSession {
  _OutgoingTransferSession({
    required this.receiverName,
    required this.files,
    this.finalizedFilesFuture,
  });

  final String receiverName;
  List<TransferSourceFile> files;
  Future<List<TransferSourceFile>>? finalizedFilesFuture;
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
    required this.destinationDirectoryPath,
    required this.preserveSharedRootOnReceive,
    required this.createdAt,
  });

  final String ownerIp;
  final String? ownerMacAddress;
  final String cacheId;
  final String destinationDirectoryPath;
  final bool preserveSharedRootOnReceive;
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

import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

export 'transfer_cache_preparation_models.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/app_notification_service.dart';
import '../../discovery/data/device_alias_repository.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../../settings/domain/app_settings.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../data/shared_download_diagnostic_log_store.dart';
import '../data/transfer_storage_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'shared_cache_catalog.dart';
import 'transfer_cache_preparation_boundary.dart';
import 'transfer_cache_preparation_models.dart';
import 'transfer_session_coordinator.dart';

enum SharedDownloadReceiveLayout {
  preserveRelativeStructure,
  preserveSharedRoot,
}

class TransferStreamedFileHash {
  const TransferStreamedFileHash({
    required this.file,
    required this.computedSha256,
  });

  final TransferSourceFile file;
  final String computedSha256;
}

class SharedDownloadBoundary extends ChangeNotifier {
  SharedDownloadBoundary({
    required LanDiscoveryService lanDiscoveryService,
    required SharedCacheCatalog sharedCacheCatalog,
    required FileHashService fileHashService,
    required FileTransferService fileTransferService,
    required TransferStorageService transferStorageService,
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
    required void Function(TransferSessionNotice notice) publishNotice,
    required void Function({
      required String requestId,
      required int receivedBytes,
      required int totalBytes,
    })
    updateDownloadProgress,
    required void Function({int? totalBytes}) resetDownloadProgress,
    required TransferRuntimeDiagnosticCallback Function({
      required String requestId,
      required Map<String, Object?> baseDetails,
    })
    fileTransferDiagnosticLogger,
    required Future<void> Function({
      required IncomingTransferRequest request,
      required TransferReceiveSession session,
      required List<TransferFileManifestItem> acceptedItems,
      required bool persistToUserDownloads,
      required bool recordHistory,
      required bool sendCompletionNotification,
      String? destinationRelativeRootPrefix,
      Completer<String?>? previewCompleter,
    })
    waitForIncomingTransferResult,
    required void Function(String requestId, TransferReceiveSession session)
    registerActiveReceiveSession,
    required TransferReceiveSession? Function(String requestId)
    removeActiveReceiveSession,
    required TransferReceiveSession? Function(String requestId)
    activeReceiveSessionForRequest,
    required void Function({
      required String requestId,
      required String receiverName,
      required List<TransferSourceFile> files,
      Future<List<TransferSourceFile>>? finalizedFilesFuture,
    })
    registerOutgoingTransfer,
    required void Function(String requestId) removeOutgoingTransfer,
    required Future<void> Function(List<TransferSourceFile> files)
    cleanupTemporaryOutgoingFiles,
    required Future<List<TransferSourceFile>> Function(
      List<TransferSourceFile> files,
    )
    hydrateTransferSourceFilesWithHashes,
    required Future<void> Function({
      required String requestId,
      required String targetIp,
      required String receiverName,
      required int transferPort,
      required List<TransferSourceFile> files,
      List<TransferFileManifestItem>? manifestItems,
      Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
      Future<void> Function(List<TransferStreamedFileHash> hashes)?
      onSuccessfulStreamedHashes,
      Map<String, Object?> diagnosticDetails,
      bool logWholeShareConnectAttempt,
      Map<String, Object?> wholeShareConnectAttemptDetails,
    })
    sendDirectSharedDownload,
    required Future<void> Function({
      required String requestId,
      required SharedFolderCacheRecord cache,
      required List<TransferStreamedFileHash> streamedHashes,
    })
    persistWholeShareTransferHashBackfill,
    required TransferCachePreparationBoundary cachePreparationBoundary,
    required Future<List<SharedDownloadPreparedFile>> Function(
      SharedFolderCacheRecord cache, {
      Set<String>? relativePathFilter,
    })
    buildCompressedPreviewFilesForCache,
    required Future<List<SharedDownloadPreparedFile>> Function(
      SharedFolderCacheRecord cache, {
      Set<String>? relativePathFilter,
      Set<String>? folderPrefixFilter,
      SharedDownloadHashPreparationMode hashPreparationMode,
      TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
    })
    buildTransferFilesForCache,
    required Future<SharedDownloadWholeShareSendPlan> Function(
      SharedFolderCacheRecord cache, {
      TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
    })
    buildWholeShareDirectStartSendPlan,
    SharedDownloadDiagnosticLogStore? diagnosticLogStore,
    this.pendingRemoteDownloadTtl = const Duration(minutes: 3),
    this.progressResetDelay = const Duration(seconds: 1),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _sharedCacheCatalog = sharedCacheCatalog,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _appNotificationService = appNotificationService,
       _settingsProvider = settingsProvider,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _isTrustedSender = isTrustedSender,
       _resolveRemoteOwnerMac = resolveRemoteOwnerMac,
       _publishNotice = publishNotice,
       _updateDownloadProgress = updateDownloadProgress,
       _resetDownloadProgress = resetDownloadProgress,
       _fileTransferDiagnosticLogger = fileTransferDiagnosticLogger,
       _waitForIncomingTransferResult = waitForIncomingTransferResult,
       _registerActiveReceiveSession = registerActiveReceiveSession,
       _removeActiveReceiveSession = removeActiveReceiveSession,
       _activeReceiveSessionForRequest = activeReceiveSessionForRequest,
       _registerOutgoingTransfer = registerOutgoingTransfer,
       _removeOutgoingTransfer = removeOutgoingTransfer,
       _cleanupTemporaryOutgoingFiles = cleanupTemporaryOutgoingFiles,
       _hydrateTransferSourceFilesWithHashes =
           hydrateTransferSourceFilesWithHashes,
       _sendDirectSharedDownload = sendDirectSharedDownload,
       _persistWholeShareTransferHashBackfill =
           persistWholeShareTransferHashBackfill,
       _cachePreparationBoundary = cachePreparationBoundary,
       _buildCompressedPreviewFilesForCache =
           buildCompressedPreviewFilesForCache,
       _buildTransferFilesForCache = buildTransferFilesForCache,
       _buildWholeShareDirectStartSendPlan = buildWholeShareDirectStartSendPlan,
       _diagnosticLogStore =
           diagnosticLogStore ?? SharedDownloadDiagnosticLogStore.disabled();

  final LanDiscoveryService _lanDiscoveryService;
  final SharedCacheCatalog _sharedCacheCatalog;
  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final AppNotificationService _appNotificationService;
  final AppSettings Function() _settingsProvider;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final bool Function(String? normalizedMac) _isTrustedSender;
  final String? Function({required String ownerIp, required String cacheId})
  _resolveRemoteOwnerMac;
  final void Function(TransferSessionNotice notice) _publishNotice;
  final void Function({
    required String requestId,
    required int receivedBytes,
    required int totalBytes,
  })
  _updateDownloadProgress;
  final void Function({int? totalBytes}) _resetDownloadProgress;
  final TransferRuntimeDiagnosticCallback Function({
    required String requestId,
    required Map<String, Object?> baseDetails,
  })
  _fileTransferDiagnosticLogger;
  final Future<void> Function({
    required IncomingTransferRequest request,
    required TransferReceiveSession session,
    required List<TransferFileManifestItem> acceptedItems,
    required bool persistToUserDownloads,
    required bool recordHistory,
    required bool sendCompletionNotification,
    String? destinationRelativeRootPrefix,
    Completer<String?>? previewCompleter,
  })
  _waitForIncomingTransferResult;
  final void Function(String requestId, TransferReceiveSession session)
  _registerActiveReceiveSession;
  final TransferReceiveSession? Function(String requestId)
  _removeActiveReceiveSession;
  final TransferReceiveSession? Function(String requestId)
  _activeReceiveSessionForRequest;
  final void Function({
    required String requestId,
    required String receiverName,
    required List<TransferSourceFile> files,
    Future<List<TransferSourceFile>>? finalizedFilesFuture,
  })
  _registerOutgoingTransfer;
  final void Function(String requestId) _removeOutgoingTransfer;
  final Future<void> Function(List<TransferSourceFile> files)
  _cleanupTemporaryOutgoingFiles;
  final Future<List<TransferSourceFile>> Function(
    List<TransferSourceFile> files,
  )
  _hydrateTransferSourceFilesWithHashes;
  final Future<void> Function({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    List<TransferFileManifestItem>? manifestItems,
    Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
    Future<void> Function(List<TransferStreamedFileHash> hashes)?
    onSuccessfulStreamedHashes,
    Map<String, Object?> diagnosticDetails,
    bool logWholeShareConnectAttempt,
    Map<String, Object?> wholeShareConnectAttemptDetails,
  })
  _sendDirectSharedDownload;
  final Future<void> Function({
    required String requestId,
    required SharedFolderCacheRecord cache,
    required List<TransferStreamedFileHash> streamedHashes,
  })
  _persistWholeShareTransferHashBackfill;
  final TransferCachePreparationBoundary _cachePreparationBoundary;
  final Future<List<SharedDownloadPreparedFile>> Function(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  })
  _buildCompressedPreviewFilesForCache;
  final Future<List<SharedDownloadPreparedFile>> Function(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
    Set<String>? folderPrefixFilter,
    SharedDownloadHashPreparationMode hashPreparationMode,
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
  })
  _buildTransferFilesForCache;
  final Future<SharedDownloadWholeShareSendPlan> Function(
    SharedFolderCacheRecord cache, {
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
  })
  _buildWholeShareDirectStartSendPlan;
  final SharedDownloadDiagnosticLogStore _diagnosticLogStore;

  final List<IncomingSharedDownloadRequest> _incomingRequests =
      <IncomingSharedDownloadRequest>[];
  final Map<String, PendingRemoteDownloadIntent> _pendingRemoteDownloads =
      <String, PendingRemoteDownloadIntent>{};
  final Map<String, PendingRemoteDownloadIntent>
  _pendingRemoteDownloadsByRequestId = <String, PendingRemoteDownloadIntent>{};

  final Duration pendingRemoteDownloadTtl;
  final Duration progressResetDelay;

  bool _disposed = false;

  String get _localName => _localNameProvider();

  String get _localDeviceMac => _localDeviceMacProvider();

  List<IncomingSharedDownloadRequest> get incomingSharedDownloadRequests =>
      List<IncomingSharedDownloadRequest>.unmodifiable(_incomingRequests);

  SharedDownloadPreparationState? get sharedDownloadPreparationState =>
      _cachePreparationBoundary.sharedDownloadPreparationState;

  bool get isPreparingSharedDownload =>
      _cachePreparationBoundary.isPreparingSharedDownload;

  SharedUploadPreparationState? get sharedUploadPreparationState =>
      _cachePreparationBoundary.sharedUploadPreparationState;

  bool get isPreparingSharedUpload =>
      _cachePreparationBoundary.isPreparingSharedUpload;

  @visibleForTesting
  void debugReplaceIncomingSharedDownloadRequests(
    List<IncomingSharedDownloadRequest> requests,
  ) {
    _incomingRequests
      ..clear()
      ..addAll(requests);
    _notify();
  }

  Future<void> requestDownloadFromRemoteFiles({
    required String ownerIp,
    required String ownerName,
    required Map<String, Set<String>> selectedRelativePathsByCache,
    Map<String, Set<String>> selectedFolderPrefixesByCache =
        const <String, Set<String>>{},
    Map<String, String> sharedLabelsByCache = const <String, String>{},
    bool preferDirectStart = false,
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
        final sharedLabel = sharedLabelsByCache[cacheId]?.trim() ?? '';
        final requestsWholeShare =
            selectedPaths.isEmpty && folderPrefixes.isEmpty;
        final requestId = _fileHashService.buildStableId(
          'download|$ownerIp|$cacheId|$stamp|'
          '${selectedPaths.join(",")}|${folderPrefixes.join(",")}|$_localDeviceMac',
        );
        _setPreparation(
          requestId: requestId,
          ownerName: ownerName,
          stage: SharedDownloadPreparationStage.preparingRequest,
        );
        final canUseDirectStart =
            preferDirectStart &&
            (selectedPaths.isNotEmpty ||
                folderPrefixes.isNotEmpty ||
                (requestsWholeShare && sharedLabel.isNotEmpty));
        final receiveLayout = _resolveSharedDownloadReceiveLayout(
          selectedRelativePaths: selectedPaths,
          selectedFolderPrefixes: folderPrefixes,
        );
        final destinationRelativeRootPrefix =
            receiveLayout == SharedDownloadReceiveLayout.preserveSharedRoot
            ? _resolveReceiveRootPrefix(sharedLabel)
            : null;
        _writeDiagnostic(
          stage: 'download_request_preparing',
          requestId: requestId,
          details: <String, Object?>{
            'ownerIp': ownerIp,
            'ownerName': ownerName,
            'cacheId': cacheId,
            'sharedLabel': sharedLabel,
            'selectedFileCount': selectedPaths.length,
            'selectedFolderPrefixCount': folderPrefixes.length,
            'requestsWholeShare': requestsWholeShare,
            'pathKind': canUseDirectStart ? 'direct_start' : 'legacy',
          },
        );
        if (canUseDirectStart) {
          await _startDirectDownloadRequest(
            ownerIp: ownerIp,
            ownerName: ownerName,
            cacheId: cacheId,
            sharedLabel: sharedLabel,
            selectedPaths: selectedPaths,
            folderPrefixes: folderPrefixes,
            requestId: requestId,
            destinationDirectory: destinationDirectory,
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
            requestsWholeShare: requestsWholeShare,
          );
        } else {
          await _sendLegacyDownloadRequest(
            ownerIp: ownerIp,
            ownerName: ownerName,
            cacheId: cacheId,
            sharedLabel: sharedLabel,
            selectedPaths: selectedPaths,
            folderPrefixes: folderPrefixes,
            requestId: requestId,
            destinationDirectory: destinationDirectory,
            receiveLayout: receiveLayout,
            requestsWholeShare: requestsWholeShare,
            preferDirectStart: preferDirectStart,
          );
        }
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
    } catch (error, stackTrace) {
      _clearPreparation();
      _log('Failed to request remote download: $error');
      _writeDiagnostic(
        stage: 'download_request_failed',
        requestId: 'request-batch',
        details: <String, Object?>{'ownerIp': ownerIp, 'ownerName': ownerName},
        error: error,
        stackTrace: stackTrace,
      );
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Failed to request remote download: $error',
        ),
      );
    }
  }

  Future<void> respondToIncomingSharedDownloadRequest({
    required String requestId,
    required bool approved,
  }) async {
    final request = _removeIncomingRequest(requestId);
    if (request == null) {
      return;
    }

    if (!approved) {
      _writeDiagnostic(
        stage: 'sender_download_request_rejected',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
          'sharedCacheId': request.sharedCacheId,
          'sharedLabel': request.sharedLabel,
        },
      );
      await _lanDiscoveryService.sendDownloadResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: false,
        message: 'Отправитель отклонил запрос на скачивание.',
      );
      _publishNotice(
        TransferSessionNotice(
          infoMessage: 'Запрос ${request.requesterName} отклонён.',
          clearError: true,
        ),
      );
      return;
    }

    _writeDiagnostic(
      stage: 'sender_download_request_approved',
      requestId: request.requestId,
      details: <String, Object?>{
        'requesterIp': request.requesterIp,
        'requesterName': request.requesterName,
        'sharedCacheId': request.sharedCacheId,
        'sharedLabel': request.sharedLabel,
      },
    );
    await _approveIncomingSharedDownloadRequest(request);
  }

  void handleDownloadRequestEvent(DownloadRequestEvent event) {
    unawaited(_handleDownloadRequest(event));
  }

  void handleDownloadResponseEvent(DownloadResponseEvent event) {
    final pendingDownload = _pendingRemoteDownloadsByRequestId.remove(
      event.requestId,
    );
    if (pendingDownload != null) {
      final pendingKey = _pendingRemoteDownloadKey(
        ownerIp: pendingDownload.ownerIp,
        cacheId: pendingDownload.cacheId,
      );
      _pendingRemoteDownloads.remove(pendingKey);
    }

    if (!event.approved) {
      final activeReceiveSession = _removeActiveReceiveSession(event.requestId);
      if (activeReceiveSession != null) {
        unawaited(activeReceiveSession.close());
      }
      _clearPreparation(requestId: event.requestId);
      _publishNotice(
        TransferSessionNotice(
          infoMessage: '${event.responderName} отклонил запрос на скачивание.',
          clearError: true,
        ),
      );
    }
    _writeDiagnostic(
      stage: 'download_response_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'responderIp': event.responderIp,
        'responderName': event.responderName,
        'approved': event.approved,
        'phase': event.phase,
        'message': event.message,
      },
    );
    if (event.approved && event.phase == 'ready_to_connect') {
      final activeReceiveSession = _activeReceiveSessionForRequest(
        event.requestId,
      );
      activeReceiveSession?.armTimeout();
      _writeDiagnostic(
        stage: 'requester_receiver_timeout_armed_from_sender_ready',
        requestId: event.requestId,
        details: <String, Object?>{
          'responderIp': event.responderIp,
          'responderName': event.responderName,
        },
      );
    }
  }

  void logSharedDownloadDebug({
    required String stage,
    String? requestId,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _writeDiagnostic(
      stage: stage,
      requestId: requestId,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  PendingRemoteDownloadIntent? consumePendingRemoteDownload(
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
    final pending = _pendingRemoteDownloads.remove(matchedKey);
    if (pending != null) {
      _pendingRemoteDownloadsByRequestId.remove(pending.requestId);
    }
    return pending;
  }

  void setPreparation({
    required String requestId,
    required String ownerName,
    required SharedDownloadPreparationStage stage,
  }) {
    _setPreparation(requestId: requestId, ownerName: ownerName, stage: stage);
  }

  void clearPreparation({String? requestId}) {
    _clearPreparation(requestId: requestId);
  }

  Future<void> _startDirectDownloadRequest({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String sharedLabel,
    required List<String> selectedPaths,
    required List<String> folderPrefixes,
    required String requestId,
    required Directory destinationDirectory,
    required String? destinationRelativeRootPrefix,
    required bool requestsWholeShare,
  }) async {
    final deferReceiverTimeoutUntilSenderReady = requestsWholeShare;
    _setPreparation(
      requestId: requestId,
      ownerName: ownerName,
      stage: SharedDownloadPreparationStage.startingReceiver,
    );
    _resetDownloadProgress(totalBytes: 0);
    final receiveSession = await _fileTransferService.startReceiver(
      requestId: requestId,
      expectedItems: null,
      destinationDirectory: destinationDirectory,
      armTimeoutImmediately: !deferReceiverTimeoutUntilSenderReady,
      destinationRelativeRootPrefix: destinationRelativeRootPrefix,
      onProgress: (received, total) {
        if (received > 0) {
          _clearPreparation(requestId: requestId);
        }
        _updateDownloadProgress(
          requestId: requestId,
          receivedBytes: received,
          totalBytes: total,
        );
        unawaited(
          _transferStorageService.showAndroidDownloadProgressNotification(
            requestId: requestId,
            senderName: ownerName,
            receivedBytes: received,
            totalBytes: total,
          ),
        );
      },
      onDiagnosticEvent: _fileTransferDiagnosticLogger(
        requestId: requestId,
        baseDetails: <String, Object?>{
          'pathKind': 'direct_start',
          'ownerIp': ownerIp,
          'ownerName': ownerName,
          'cacheId': cacheId,
          'sharedLabel': sharedLabel,
        },
      ),
    );
    _registerActiveReceiveSession(requestId, receiveSession);
    _writeDiagnostic(
      stage: deferReceiverTimeoutUntilSenderReady
          ? 'requester_receiver_wait_deferred_until_sender_ready'
          : 'requester_receiver_wait_started_immediately',
      requestId: requestId,
      details: <String, Object?>{
        'pathKind': 'direct_start',
        'ownerIp': ownerIp,
        'cacheId': cacheId,
        'requestsWholeShare': requestsWholeShare,
        'transferPort': receiveSession.port,
      },
    );
    unawaited(
      _waitForIncomingTransferResult(
        request: IncomingTransferRequest(
          requestId: requestId,
          senderIp: ownerIp,
          senderName: ownerName,
          senderMacAddress:
              _resolveRemoteOwnerMac(ownerIp: ownerIp, cacheId: cacheId) ?? '',
          sharedCacheId: cacheId,
          sharedLabel: sharedLabel.isEmpty ? 'Shared files' : sharedLabel,
          items: const <TransferFileManifestItem>[],
          createdAt: DateTime.now(),
        ),
        session: receiveSession,
        acceptedItems: const <TransferFileManifestItem>[],
        persistToUserDownloads: true,
        recordHistory: true,
        sendCompletionNotification: true,
        destinationRelativeRootPrefix: destinationRelativeRootPrefix,
      ),
    );
    try {
      await _lanDiscoveryService.sendDownloadRequest(
        targetIp: ownerIp,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        cacheId: cacheId,
        selectedRelativePaths: selectedPaths,
        selectedFolderPrefixes: folderPrefixes,
        transferPort: receiveSession.port,
      );
      _writeDiagnostic(
        stage: 'download_request_sent',
        requestId: requestId,
        details: <String, Object?>{
          'pathKind': 'direct_start',
          'ownerIp': ownerIp,
          'cacheId': cacheId,
          'transferPort': receiveSession.port,
          'requestsWholeShare': requestsWholeShare,
        },
      );
      _setPreparation(
        requestId: requestId,
        ownerName: ownerName,
        stage: SharedDownloadPreparationStage.waitingForRemote,
      );
    } catch (error, stackTrace) {
      _removeActiveReceiveSession(requestId);
      await receiveSession.close();
      _clearPreparation(requestId: requestId);
      _writeDiagnostic(
        stage: 'download_request_send_failure',
        requestId: requestId,
        details: <String, Object?>{
          'pathKind': 'direct_start',
          'ownerIp': ownerIp,
          'cacheId': cacheId,
        },
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> _sendLegacyDownloadRequest({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String sharedLabel,
    required List<String> selectedPaths,
    required List<String> folderPrefixes,
    required String requestId,
    required Directory destinationDirectory,
    required SharedDownloadReceiveLayout receiveLayout,
    required bool requestsWholeShare,
    required bool preferDirectStart,
  }) async {
    if (requestsWholeShare && sharedLabel.isEmpty && preferDirectStart) {
      _writeDiagnostic(
        stage: 'download_request_direct_start_skipped',
        requestId: requestId,
        details: <String, Object?>{
          'reason': 'missing_shared_label_for_root_preservation',
          'cacheId': cacheId,
          'ownerIp': ownerIp,
        },
      );
    }
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
    final pendingIntent = PendingRemoteDownloadIntent(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerMacAddress: _resolveRemoteOwnerMac(
        ownerIp: ownerIp,
        cacheId: cacheId,
      ),
      cacheId: cacheId,
      destinationDirectoryPath: destinationDirectory.path,
      receiveLayout: receiveLayout,
      createdAt: DateTime.now(),
    );
    _pendingRemoteDownloads[pendingKey] = pendingIntent;
    _pendingRemoteDownloadsByRequestId[requestId] = pendingIntent;
    _writeDiagnostic(
      stage: 'download_request_sent',
      requestId: requestId,
      details: <String, Object?>{
        'pathKind': 'legacy',
        'ownerIp': ownerIp,
        'cacheId': cacheId,
        'requestsWholeShare': requestsWholeShare,
      },
    );
    _setPreparation(
      requestId: requestId,
      ownerName: ownerName,
      stage: SharedDownloadPreparationStage.waitingForRemote,
    );
  }

  Future<void> _handleDownloadRequest(DownloadRequestEvent event) async {
    final normalizedRequesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    _writeDiagnostic(
      stage: 'sender_download_request_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'requesterIp': event.requesterIp,
        'requesterName': event.requesterName,
        'requesterMacAddress':
            normalizedRequesterMac ?? event.requesterMacAddress,
        'cacheId': event.cacheId,
        'selectedFileCount': event.selectedRelativePaths.length,
        'selectedFolderPrefixCount': event.selectedFolderPrefixes.length,
        'previewMode': event.previewMode,
        'transferPort': event.transferPort,
        'requestsWholeShare':
            event.selectedRelativePaths.isEmpty &&
            event.selectedFolderPrefixes.isEmpty,
      },
    );
    var cache = _findOwnerCacheById(event.cacheId);
    if (cache == null) {
      await _sharedCacheCatalog.loadOwnerCaches(
        ownerMacAddress: _localDeviceMac,
      );
      cache = _findOwnerCacheById(event.cacheId);
    }
    if (cache == null) {
      _log(
        'Download request from ${event.requesterIp} ignored. '
        'Unknown cacheId=${event.cacheId}',
      );
      return;
    }

    final isPreviewRequest = event.previewMode;
    final isTrustedFriendRequester =
        !isPreviewRequest && _isTrustedSender(normalizedRequesterMac);
    if (!isPreviewRequest &&
        !isTrustedFriendRequester &&
        _settingsProvider().downloadAttemptNotificationsEnabled) {
      unawaited(
        _appNotificationService.showDownloadAttemptNotification(
          requesterName: event.requesterName,
          shareLabel: cache.displayName,
          requestedFilesCount: event.selectedRelativePaths.length,
        ),
      );
    }
    if (!isPreviewRequest && !isTrustedFriendRequester) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }

    _publishNotice(
      TransferSessionNotice(
        infoMessage: isPreviewRequest
            ? 'Preview request from ${event.requesterName}.'
            : isTrustedFriendRequester
            ? 'Trusted friend ${event.requesterName} requested "${cache.displayName}". Auto-approving.'
            : 'Download request from ${event.requesterName} for "${cache.displayName}".',
        clearError: true,
      ),
    );

    if (!isPreviewRequest) {
      final request = IncomingSharedDownloadRequest(
        requestId: event.requestId,
        requesterIp: event.requesterIp,
        requesterName: event.requesterName,
        requesterMacAddress: event.requesterMacAddress,
        sharedCacheId: cache.cacheId,
        sharedLabel: cache.displayName,
        selectedRelativePaths: List<String>.from(event.selectedRelativePaths),
        selectedFolderPrefixes: List<String>.from(event.selectedFolderPrefixes),
        transferPort: event.transferPort,
        createdAt: event.observedAt,
      );
      if (isTrustedFriendRequester) {
        _writeDiagnostic(
          stage: 'sender_download_request_auto_approved_for_friend',
          requestId: event.requestId,
          details: <String, Object?>{
            'requesterIp': event.requesterIp,
            'requesterName': event.requesterName,
            'requesterMacAddress':
                normalizedRequesterMac ?? event.requesterMacAddress,
            'cacheId': cache.cacheId,
            'selectedFileCount': event.selectedRelativePaths.length,
            'selectedFolderPrefixCount': event.selectedFolderPrefixes.length,
            'requestsWholeShare':
                event.selectedRelativePaths.isEmpty &&
                event.selectedFolderPrefixes.isEmpty,
          },
        );
        await _approveIncomingSharedDownloadRequest(request);
        return;
      }
      _upsertIncomingRequest(request);
      return;
    }

    await _preparePreviewOrLegacyDownloadTransfer(event: event, cache: cache);
  }

  Future<void> _preparePreviewOrLegacyDownloadTransfer({
    required DownloadRequestEvent event,
    required SharedFolderCacheRecord cache,
  }) async {
    final isPreviewRequest = event.previewMode;
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
    final hashPreparationMode = deferHashesUntilAccept
        ? SharedDownloadHashPreparationMode.none
        : SharedDownloadHashPreparationMode.full;
    final preparedFiles = isPreviewRequest
        ? await _buildCompressedPreviewFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
          )
        : await _buildTransferFilesForCache(
            cache,
            relativePathFilter: relativePathFilter,
            folderPrefixFilter: folderPrefixFilter,
            hashPreparationMode: hashPreparationMode,
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

    final directTransferPort = isPreviewRequest ? null : event.transferPort;
    final canUseDirectStart = directTransferPort != null && !isPreviewRequest;
    if (canUseDirectStart) {
      _writeDiagnostic(
        stage: 'sender_direct_start_selected',
        requestId: event.requestId,
        details: <String, Object?>{
          'requesterIp': event.requesterIp,
          'cacheId': cache.cacheId,
          'transferPort': directTransferPort,
          'preparedItemCount': items.length,
        },
      );
      unawaited(
        _sendDirectSharedDownload(
          requestId: event.requestId,
          targetIp: event.requesterIp,
          receiverName: event.requesterName,
          transferPort: directTransferPort,
          files: _toTransferSourceFiles(preparedFiles),
          diagnosticDetails: <String, Object?>{
            'cacheId': cache.cacheId,
            'sharedLabel': cache.displayName,
          },
          logWholeShareConnectAttempt: false,
          wholeShareConnectAttemptDetails: const <String, Object?>{},
        ),
      );
      _log(
        'Direct download transfer started for cache ${cache.cacheId} to ${event.requesterIp}. '
        'items=${items.length}',
      );
      return;
    }

    final requestId = isPreviewRequest
        ? event.requestId
        : _fileHashService.buildStableId(
            'download-share|${event.requestId}|${event.requesterIp}|${cache.cacheId}',
          );

    final transferFiles = _toTransferSourceFiles(preparedFiles);
    try {
      _registerOutgoingTransfer(
        requestId: requestId,
        receiverName: event.requesterName,
        files: transferFiles,
        finalizedFilesFuture: deferHashesUntilAccept
            ? _hydrateTransferSourceFilesWithHashes(transferFiles)
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
      _writeDiagnostic(
        stage: 'sender_legacy_transfer_request_sent',
        requestId: requestId,
        details: <String, Object?>{
          'sourceDownloadRequestId': event.requestId,
          'requesterIp': event.requesterIp,
          'cacheId': cache.cacheId,
          'preparedItemCount': items.length,
        },
      );
    } catch (error) {
      _removeOutgoingTransfer(requestId);
      unawaited(_cleanupTemporaryOutgoingFiles(transferFiles));
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

  Future<void> _approveIncomingSharedDownloadRequest(
    IncomingSharedDownloadRequest request,
  ) async {
    final emitWholeShareDirectStartDiagnostics =
        request.requestsWholeShare && request.transferPort != null;
    final wholeShareDiagnosticDetails = <String, Object?>{
      'requesterIp': request.requesterIp,
      'requesterName': request.requesterName,
      'sharedCacheId': request.sharedCacheId,
      'sharedLabel': request.sharedLabel,
      'pathKind': 'direct_start',
      'requestsWholeShare': true,
    };
    final TransferRuntimeDiagnosticCallback? wholeShareDiagnosticLogger =
        emitWholeShareDirectStartDiagnostics
        ? ({
            required String stage,
            Map<String, Object?> details = const <String, Object?>{},
            Object? error,
            StackTrace? stackTrace,
          }) {
            _writeDiagnostic(
              stage: stage,
              requestId: request.requestId,
              details: <String, Object?>{
                ...wholeShareDiagnosticDetails,
                ...details,
              },
              error: error,
              stackTrace: stackTrace,
            );
          }
        : null;
    _writeDiagnostic(
      stage: 'sender_prepare_start',
      requestId: request.requestId,
      details: <String, Object?>{
        'requesterIp': request.requesterIp,
        'requesterName': request.requesterName,
        'sharedCacheId': request.sharedCacheId,
        'sharedLabel': request.sharedLabel,
        'selectedFileCount': request.selectedRelativePaths.length,
        'selectedFolderPrefixCount': request.selectedFolderPrefixes.length,
        'requestsWholeShare': request.requestsWholeShare,
      },
    );
    wholeShareDiagnosticLogger?.call(
      stage: 'sender_whole_share_prepare_start',
      details: <String, Object?>{
        'selectedFileCount': request.selectedRelativePaths.length,
        'selectedFolderPrefixCount': request.selectedFolderPrefixes.length,
      },
    );
    final cache = _findOwnerCacheById(request.sharedCacheId);
    if (cache == null) {
      _writeDiagnostic(
        stage: 'sender_prepare_failure',
        requestId: request.requestId,
        details: <String, Object?>{
          'sharedCacheId': request.sharedCacheId,
          'reason': 'cache_not_found',
        },
      );
      wholeShareDiagnosticLogger?.call(
        stage: 'sender_whole_share_prepare_failure',
        details: const <String, Object?>{'reason': 'cache_not_found'},
      );
      _publishNotice(
        const TransferSessionNotice(
          errorMessage: 'Не удалось найти запрошенную общую папку.',
        ),
      );
      return;
    }

    final relativePathFilter = request.selectedRelativePaths.isEmpty
        ? null
        : request.selectedRelativePaths.toSet();
    final folderPrefixFilter = request.selectedFolderPrefixes.isEmpty
        ? null
        : request.selectedFolderPrefixes.toSet();
    final deferHashesUntilAccept =
        folderPrefixFilter == null && request.selectedRelativePaths.length == 1;
    final hashPreparationMode = emitWholeShareDirectStartDiagnostics
        ? SharedDownloadHashPreparationMode.cachedOnly
        : deferHashesUntilAccept
        ? SharedDownloadHashPreparationMode.none
        : SharedDownloadHashPreparationMode.full;

    setUploadPreparation(
      requestId: request.requestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.resolvingSelection,
    );

    try {
      final directTransferPort = request.transferPort;
      final useWholeShareFirstBatchDirectStart =
          request.requestsWholeShare && directTransferPort != null;
      if (useWholeShareFirstBatchDirectStart) {
        await _approveWholeShareFirstBatchDirectStart(
          request: request,
          cache: cache,
          directTransferPort: directTransferPort,
          wholeShareDiagnosticLogger: wholeShareDiagnosticLogger,
          wholeShareDiagnosticDetails: wholeShareDiagnosticDetails,
          hashPreparationMode: hashPreparationMode,
        );
        return;
      }

      final preparedFiles = await _buildTransferFilesForCache(
        cache,
        relativePathFilter: relativePathFilter,
        folderPrefixFilter: folderPrefixFilter,
        hashPreparationMode: hashPreparationMode,
        onDiagnosticEvent: wholeShareDiagnosticLogger,
      );
      if (preparedFiles.isEmpty) {
        await _rejectPreparedRequestWithNoFiles(
          request: request,
          wholeShareDiagnosticLogger: wholeShareDiagnosticLogger,
        );
        return;
      }

      final transferFiles = _toTransferSourceFiles(preparedFiles);
      setUploadPreparation(
        requestId: request.requestId,
        requesterName: request.requesterName,
        stage: SharedUploadPreparationStage.preparingTransfer,
      );
      _writeDiagnostic(
        stage: 'sender_prepare_complete',
        requestId: request.requestId,
        details: <String, Object?>{
          'sharedCacheId': request.sharedCacheId,
          'preparedFileCount': transferFiles.length,
          'preparedTotalBytes': transferFiles.fold<int>(
            0,
            (sum, file) => sum + file.sizeBytes,
          ),
          'preparedKnownHashCount': transferFiles
              .where((file) => file.sha256.trim().isNotEmpty)
              .length,
          'preparedMissingHashCount': transferFiles
              .where((file) => file.sha256.trim().isEmpty)
              .length,
          'hashPreparationMode': hashPreparationMode.name,
        },
      );
      wholeShareDiagnosticLogger?.call(
        stage: 'sender_whole_share_prepare_complete',
        details: <String, Object?>{
          'preparedFileCount': transferFiles.length,
          'preparedTotalBytes': transferFiles.fold<int>(
            0,
            (sum, file) => sum + file.sizeBytes,
          ),
          'preparedKnownHashCount': transferFiles
              .where((file) => file.sha256.trim().isNotEmpty)
              .length,
          'preparedMissingHashCount': transferFiles
              .where((file) => file.sha256.trim().isEmpty)
              .length,
          'hashPreparationMode': hashPreparationMode.name,
        },
      );

      final canUseDirectStart = directTransferPort != null;
      if (canUseDirectStart) {
        clearUploadPreparation(requestId: request.requestId);
        await _startApprovedDirectSend(
          request: request,
          directTransferPort: directTransferPort,
          transferFiles: transferFiles,
          emitWholeShareDirectStartDiagnostics:
              emitWholeShareDirectStartDiagnostics,
          wholeShareDiagnosticDetails: wholeShareDiagnosticDetails,
          hashPreparationMode: hashPreparationMode,
        );
        return;
      }

      await _sendApprovedLegacyTransferRequest(
        request: request,
        cache: cache,
        preparedFiles: preparedFiles,
        transferFiles: transferFiles,
        deferHashesUntilAccept: deferHashesUntilAccept,
      );
    } catch (error, stackTrace) {
      _writeDiagnostic(
        stage: 'sender_prepare_failure',
        requestId: request.requestId,
        details: <String, Object?>{
          'sharedCacheId': request.sharedCacheId,
          'requesterIp': request.requesterIp,
        },
        error: error,
        stackTrace: stackTrace,
      );
      wholeShareDiagnosticLogger?.call(
        stage: 'sender_whole_share_prepare_failure',
        details: const <String, Object?>{},
        error: error,
        stackTrace: stackTrace,
      );
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Не удалось подготовить отправку: $error',
        ),
      );
    }
  }

  Future<void> _approveWholeShareFirstBatchDirectStart({
    required IncomingSharedDownloadRequest request,
    required SharedFolderCacheRecord cache,
    required int directTransferPort,
    required TransferRuntimeDiagnosticCallback? wholeShareDiagnosticLogger,
    required Map<String, Object?> wholeShareDiagnosticDetails,
    required SharedDownloadHashPreparationMode hashPreparationMode,
  }) async {
    final sendPlan = await _buildWholeShareDirectStartSendPlan(
      cache,
      onDiagnosticEvent: wholeShareDiagnosticLogger,
    );
    if (sendPlan.manifestItems.isEmpty || sendPlan.firstBatchFiles.isEmpty) {
      await _rejectPreparedRequestWithNoFiles(
        request: request,
        wholeShareDiagnosticLogger: wholeShareDiagnosticLogger,
      );
      return;
    }

    final firstBatchKnownHashCount = sendPlan.firstBatchFiles
        .where((file) => file.sha256.trim().isNotEmpty)
        .length;
    final firstBatchMissingHashCount =
        sendPlan.firstBatchFiles.length - firstBatchKnownHashCount;
    setUploadPreparation(
      requestId: request.requestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.preparingTransfer,
    );
    _writeDiagnostic(
      stage: 'sender_prepare_complete',
      requestId: request.requestId,
      details: <String, Object?>{
        'sharedCacheId': request.sharedCacheId,
        'preparedFileCount': sendPlan.firstBatchFiles.length,
        'preparedTotalBytes': sendPlan.firstBatchFiles.fold<int>(
          0,
          (sum, file) => sum + file.sizeBytes,
        ),
        'preparedKnownHashCount': firstBatchKnownHashCount,
        'preparedMissingHashCount': firstBatchMissingHashCount,
        'manifestFileCount': sendPlan.manifestItems.length,
        'preparationMode': 'whole_share_first_batch',
        'hashPreparationMode': hashPreparationMode.name,
      },
    );
    wholeShareDiagnosticLogger?.call(
      stage: 'sender_whole_share_prepare_complete',
      details: <String, Object?>{
        'preparedFileCount': sendPlan.firstBatchFiles.length,
        'preparedTotalBytes': sendPlan.firstBatchFiles.fold<int>(
          0,
          (sum, file) => sum + file.sizeBytes,
        ),
        'preparedKnownHashCount': firstBatchKnownHashCount,
        'preparedMissingHashCount': firstBatchMissingHashCount,
        'manifestFileCount': sendPlan.manifestItems.length,
        'preparationMode': 'whole_share_first_batch',
        'hashPreparationMode': hashPreparationMode.name,
      },
    );

    clearUploadPreparation(requestId: request.requestId);
    await _lanDiscoveryService.sendDownloadResponse(
      targetIp: request.requesterIp,
      requestId: request.requestId,
      responderName: _localName,
      approved: true,
      phase: 'ready_to_connect',
      message: 'Отправитель подготовил первую партию отправки.',
    );
    _writeDiagnostic(
      stage: 'sender_ready_to_connect_sent',
      requestId: request.requestId,
      details: <String, Object?>{
        'sharedCacheId': request.sharedCacheId,
        'transferPort': directTransferPort,
        'preparedFileCount': sendPlan.firstBatchFiles.length,
        'manifestFileCount': sendPlan.manifestItems.length,
      },
    );
    _writeDiagnostic(
      stage: 'sender_direct_start_selected',
      requestId: request.requestId,
      details: <String, Object?>{
        'sharedCacheId': request.sharedCacheId,
        'transferPort': directTransferPort,
        'preparedFileCount': sendPlan.firstBatchFiles.length,
        'manifestFileCount': sendPlan.manifestItems.length,
        'preparedTotalBytes': sendPlan.firstBatchFiles.fold<int>(
          0,
          (sum, file) => sum + file.sizeBytes,
        ),
        'preparedKnownHashCount': firstBatchKnownHashCount,
        'preparedMissingHashCount': firstBatchMissingHashCount,
        'hashPreparationMode': hashPreparationMode.name,
        'preparationMode': 'whole_share_first_batch',
      },
    );
    unawaited(
      _sendDirectSharedDownload(
        requestId: request.requestId,
        targetIp: request.requesterIp,
        receiverName: request.requesterName,
        transferPort: directTransferPort,
        files: sendPlan.firstBatchFiles,
        manifestItems: sendPlan.manifestItems,
        resolveBatch: sendPlan.resolveBatch,
        onSuccessfulStreamedHashes: (hashes) =>
            _persistWholeShareTransferHashBackfill(
              requestId: request.requestId,
              cache: cache,
              streamedHashes: hashes,
            ),
        diagnosticDetails: <String, Object?>{
          'cacheId': request.sharedCacheId,
          'sharedLabel': request.sharedLabel,
          'requestsWholeShare': request.requestsWholeShare,
          'preparationMode': 'whole_share_first_batch',
        },
        logWholeShareConnectAttempt: true,
        wholeShareConnectAttemptDetails: wholeShareDiagnosticDetails,
      ),
    );
  }

  Future<void> _rejectPreparedRequestWithNoFiles({
    required IncomingSharedDownloadRequest request,
    required TransferRuntimeDiagnosticCallback? wholeShareDiagnosticLogger,
  }) async {
    _writeDiagnostic(
      stage: 'sender_prepare_failure',
      requestId: request.requestId,
      details: <String, Object?>{
        'sharedCacheId': request.sharedCacheId,
        'reason': 'no_prepared_files',
      },
    );
    wholeShareDiagnosticLogger?.call(
      stage: 'sender_whole_share_prepare_failure',
      details: const <String, Object?>{'reason': 'no_prepared_files'},
    );
    await _lanDiscoveryService.sendDownloadResponse(
      targetIp: request.requesterIp,
      requestId: request.requestId,
      responderName: _localName,
      approved: false,
      message: 'Не найдено доступных файлов для отправки.',
    );
    _publishNotice(
      const TransferSessionNotice(
        errorMessage: 'Не удалось подготовить файлы к отправке.',
      ),
    );
  }

  Future<void> _startApprovedDirectSend({
    required IncomingSharedDownloadRequest request,
    required int directTransferPort,
    required List<TransferSourceFile> transferFiles,
    required bool emitWholeShareDirectStartDiagnostics,
    required Map<String, Object?> wholeShareDiagnosticDetails,
    required SharedDownloadHashPreparationMode hashPreparationMode,
  }) async {
    if (request.requestsWholeShare) {
      await _lanDiscoveryService.sendDownloadResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: true,
        phase: 'ready_to_connect',
        message: 'Отправитель подготовил отправку. Начинаем соединение.',
      );
      _writeDiagnostic(
        stage: 'sender_ready_to_connect_sent',
        requestId: request.requestId,
        details: <String, Object?>{
          'sharedCacheId': request.sharedCacheId,
          'transferPort': directTransferPort,
          'preparedFileCount': transferFiles.length,
        },
      );
    }
    _writeDiagnostic(
      stage: 'sender_direct_start_selected',
      requestId: request.requestId,
      details: <String, Object?>{
        'sharedCacheId': request.sharedCacheId,
        'transferPort': directTransferPort,
        'preparedFileCount': transferFiles.length,
        'preparedTotalBytes': transferFiles.fold<int>(
          0,
          (sum, file) => sum + file.sizeBytes,
        ),
        'preparedKnownHashCount': transferFiles
            .where((file) => file.sha256.trim().isNotEmpty)
            .length,
        'preparedMissingHashCount': transferFiles
            .where((file) => file.sha256.trim().isEmpty)
            .length,
        'hashPreparationMode': hashPreparationMode.name,
      },
    );
    unawaited(
      _sendDirectSharedDownload(
        requestId: request.requestId,
        targetIp: request.requesterIp,
        receiverName: request.requesterName,
        transferPort: directTransferPort,
        files: transferFiles,
        diagnosticDetails: <String, Object?>{
          'cacheId': request.sharedCacheId,
          'sharedLabel': request.sharedLabel,
          'requestsWholeShare': request.requestsWholeShare,
        },
        logWholeShareConnectAttempt: emitWholeShareDirectStartDiagnostics,
        wholeShareConnectAttemptDetails: wholeShareDiagnosticDetails,
      ),
    );
  }

  Future<void> _sendApprovedLegacyTransferRequest({
    required IncomingSharedDownloadRequest request,
    required SharedFolderCacheRecord cache,
    required List<SharedDownloadPreparedFile> preparedFiles,
    required List<TransferSourceFile> transferFiles,
    required bool deferHashesUntilAccept,
  }) async {
    final items = preparedFiles
        .map((prepared) => prepared.announcement)
        .toList(growable: false);
    final transferRequestId = _fileHashService.buildStableId(
      'download-share|${request.requestId}|${request.requesterIp}|${cache.cacheId}',
    );

    _registerOutgoingTransfer(
      requestId: transferRequestId,
      receiverName: request.requesterName,
      files: transferFiles,
      finalizedFilesFuture: deferHashesUntilAccept
          ? _hydrateTransferSourceFilesWithHashes(transferFiles)
          : null,
    );
    setUploadPreparation(
      requestId: transferRequestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.waitingForRequester,
    );
    await _lanDiscoveryService.sendTransferRequest(
      targetIp: request.requesterIp,
      requestId: transferRequestId,
      senderName: _localName,
      senderMacAddress: _localDeviceMac,
      sharedCacheId: cache.cacheId,
      sharedLabel: cache.displayName,
      items: items,
    );
    _writeDiagnostic(
      stage: 'sender_legacy_transfer_request_sent',
      requestId: transferRequestId,
      details: <String, Object?>{
        'sourceDownloadRequestId': request.requestId,
        'sharedCacheId': request.sharedCacheId,
        'preparedFileCount': transferFiles.length,
      },
    );
  }

  SharedFolderCacheRecord? _findOwnerCacheById(String cacheId) {
    for (final cache in _sharedCacheCatalog.ownerCaches) {
      if (cache.cacheId == cacheId) {
        return cache;
      }
    }
    return null;
  }

  List<TransferSourceFile> _toTransferSourceFiles(
    List<SharedDownloadPreparedFile> preparedFiles,
  ) {
    return preparedFiles
        .map(
          (prepared) => TransferSourceFile(
            sourcePath: prepared.sourcePath,
            fileName: prepared.announcement.fileName,
            sizeBytes: prepared.announcement.sizeBytes,
            sha256: prepared.announcement.sha256,
            deleteAfterTransfer: prepared.deleteAfterTransfer,
          ),
        )
        .toList(growable: false);
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

  SharedDownloadReceiveLayout _resolveSharedDownloadReceiveLayout({
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
  }) {
    if (selectedRelativePaths.isEmpty && selectedFolderPrefixes.isEmpty) {
      return SharedDownloadReceiveLayout.preserveSharedRoot;
    }
    return SharedDownloadReceiveLayout.preserveRelativeStructure;
  }

  String? _resolveReceiveRootPrefix(String sharedLabel) {
    final sanitized = _sanitizeTransferRelativePathPart(sharedLabel.trim());
    if (sanitized.isEmpty || sanitized == '_') {
      return null;
    }
    return sanitized;
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

      const reserved = <String>{
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

  String _pendingRemoteDownloadKey({
    required String ownerIp,
    required String cacheId,
  }) {
    return '$ownerIp|$cacheId';
  }

  void _purgeExpiredPendingRemoteDownloads() {
    final now = DateTime.now();
    final expired = <String>[];
    _pendingRemoteDownloads.removeWhere((_, pending) {
      final isExpired =
          now.difference(pending.createdAt) > pendingRemoteDownloadTtl;
      if (isExpired) {
        expired.add(pending.requestId);
      }
      return isExpired;
    });
    for (final requestId in expired) {
      _pendingRemoteDownloadsByRequestId.remove(requestId);
    }
  }

  void _writeDiagnostic({
    required String stage,
    String? requestId,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    unawaited(
      _diagnosticLogStore.appendEvent(
        stage: stage,
        requestId: requestId,
        details: details,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _setPreparation({
    required String requestId,
    required String ownerName,
    required SharedDownloadPreparationStage stage,
  }) {
    final current = _cachePreparationBoundary.sharedDownloadPreparationState;
    if (current?.requestId == requestId &&
        current?.stage == stage &&
        current?.ownerName == ownerName) {
      return;
    }
    _cachePreparationBoundary.setDownloadPreparation(
      requestId: requestId,
      ownerName: ownerName,
      stage: stage,
    );
    _notify();
  }

  void setUploadPreparation({
    required String requestId,
    required String requesterName,
    required SharedUploadPreparationStage stage,
  }) {
    final current = _cachePreparationBoundary.sharedUploadPreparationState;
    if (current?.requestId == requestId &&
        current?.stage == stage &&
        current?.requesterName == requesterName) {
      return;
    }
    _cachePreparationBoundary.setUploadPreparation(
      requestId: requestId,
      requesterName: requesterName,
      stage: stage,
    );
    _notify();
  }

  void clearUploadPreparation({String? requestId}) {
    final current = _cachePreparationBoundary.sharedUploadPreparationState;
    if (current == null ||
        (requestId != null && current.requestId != requestId)) {
      return;
    }
    _cachePreparationBoundary.clearUploadPreparation(requestId: requestId);
    _notify();
  }

  void _clearPreparation({String? requestId}) {
    final current = _cachePreparationBoundary.sharedDownloadPreparationState;
    if (current == null ||
        (requestId != null && current.requestId != requestId)) {
      return;
    }
    _cachePreparationBoundary.clearDownloadPreparation(requestId: requestId);
    _notify();
  }

  void _upsertIncomingRequest(IncomingSharedDownloadRequest request) {
    _incomingRequests.removeWhere(
      (existing) => existing.requestId == request.requestId,
    );
    _incomingRequests.insert(0, request);
    _notify();
  }

  IncomingSharedDownloadRequest? _removeIncomingRequest(String requestId) {
    final index = _incomingRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index == -1) {
      return null;
    }
    final request = _incomingRequests.removeAt(index);
    _notify();
    return request;
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'SharedDownloadBoundary');
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class PendingRemoteDownloadIntent {
  PendingRemoteDownloadIntent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.destinationDirectoryPath,
    required this.receiveLayout,
    required this.createdAt,
  });

  final String requestId;
  final String ownerIp;
  final String? ownerMacAddress;
  final String cacheId;
  final String destinationDirectoryPath;
  final SharedDownloadReceiveLayout receiveLayout;
  final DateTime createdAt;
}

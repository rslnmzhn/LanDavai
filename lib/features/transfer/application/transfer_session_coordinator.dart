import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/app_notification_service.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_packet_codec.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../history/application/download_history_boundary.dart';
import '../../history/domain/transfer_history_record.dart';
import '../../settings/domain/app_settings.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../data/shared_download_diagnostic_log_store.dart';
import '../data/transfer_storage_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'incoming_transfer_request_boundary.dart';
import 'incoming_transfer_request_helpers.dart';
import 'remote_share_access_session_boundary.dart';
import 'remote_share_access_session_models.dart';
import 'shared_cache_catalog.dart';
import 'shared_cache_index_store.dart';
import 'shared_download_boundary.dart';
import 'transfer_cache_preparation_boundary.dart';
import 'transfer_cache_snapshot_builder.dart';
import 'remote_file_preview_boundary.dart';
import 'transfer_path_policy.dart';
import 'transfer_speed_tracker.dart';

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
  static const Duration _wholeShareUploadProgressMinEmitInterval = Duration(
    milliseconds: 250,
  );
  static const int _wholeShareUploadProgressMinEmitBytes = 512 * 1024;

  static Future<RemoteShareAccessProjectionLoadResult>
  _noopApplyRemoteShareAccessSnapshot({
    required String ownerIp,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
  }) async {
    return RemoteShareAccessProjectionLoadResult(
      ownerIp: ownerIp,
      cacheCount: entries.length,
      fileCount: entries.fold<int>(0, (sum, entry) => sum + entry.files.length),
    );
  }

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
    Future<RemoteShareAccessProjectionLoadResult> Function({
      required String ownerIp,
      required String ownerName,
      required String ownerMacAddress,
      required List<SharedCatalogEntryItem> entries,
    })?
    applyRemoteShareAccessSnapshot,
    SharedDownloadDiagnosticLogStore? sharedDownloadDiagnosticLogStore,
    Duration pendingRemotePreviewTtl = const Duration(minutes: 1),
    Duration previewRequestTimeout = const Duration(seconds: 45),
    this.progressResetDelay = const Duration(seconds: 1),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _fileTransferService = fileTransferService,
       _transferStorageService = transferStorageService,
       _downloadHistoryBoundary = downloadHistoryBoundary,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _applyRemoteShareAccessSnapshot =
           applyRemoteShareAccessSnapshot ??
           _noopApplyRemoteShareAccessSnapshot,
       _sharedDownloadDiagnosticLogStore =
           sharedDownloadDiagnosticLogStore ??
           SharedDownloadDiagnosticLogStore.disabled() {
    _remoteFilePreviewBoundary = RemoteFilePreviewBoundary(
      lanDiscoveryService: lanDiscoveryService,
      fileHashService: fileHashService,
      previewCacheOwner: previewCacheOwner,
      settingsProvider: settingsProvider,
      localNameProvider: localNameProvider,
      localDeviceMacProvider: localDeviceMacProvider,
      resolveRemoteOwnerMac: resolveRemoteOwnerMac,
      publishNotice: _publishNotice,
      pendingRemotePreviewTtl: pendingRemotePreviewTtl,
      previewRequestTimeout: previewRequestTimeout,
      pathPolicy: _pathPolicy,
    );
    _transferCacheSnapshotBuilder = TransferCacheSnapshotBuilder(
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
    );
    _transferCachePreparationBoundary = TransferCachePreparationBoundary();
    _transferCachePreparationBoundary.addListener(_notify);
    _sharedDownloadBoundary = SharedDownloadBoundary(
      lanDiscoveryService: lanDiscoveryService,
      sharedCacheCatalog: sharedCacheCatalog,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: transferStorageService,
      appNotificationService: appNotificationService,
      settingsProvider: settingsProvider,
      localNameProvider: localNameProvider,
      localDeviceMacProvider: localDeviceMacProvider,
      isTrustedSender: isTrustedSender,
      resolveRemoteOwnerMac: resolveRemoteOwnerMac,
      publishNotice: _publishNotice,
      updateDownloadProgress: _updateDownloadProgress,
      resetDownloadProgress: _resetDownloadProgress,
      fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
      waitForIncomingTransferResult: _waitForIncomingTransferResult,
      registerActiveReceiveSession: _registerActiveReceiveSession,
      removeActiveReceiveSession: _removeActiveReceiveSession,
      activeReceiveSessionForRequest: _activeReceiveSessionForRequest,
      registerOutgoingTransfer: _registerOutgoingTransfer,
      removeOutgoingTransfer: _removeOutgoingTransfer,
      cleanupTemporaryOutgoingFiles: _cleanupTemporaryOutgoingFiles,
      hydrateTransferSourceFilesWithHashes:
          _hydrateTransferSourceFilesWithHashes,
      sendDirectSharedDownload: _sendDirectSharedDownloadForBoundary,
      persistWholeShareTransferHashBackfill:
          _persistWholeShareTransferHashBackfillForBoundary,
      cachePreparationBoundary: _transferCachePreparationBoundary,
      buildCompressedPreviewFilesForCache:
          _remoteFilePreviewBoundary.buildCompressedPreviewFilesForCache,
      buildTransferFilesForCache:
          _transferCacheSnapshotBuilder.buildTransferFilesForCache,
      buildWholeShareDirectStartSendPlan:
          _transferCacheSnapshotBuilder.buildWholeShareDirectStartSendPlan,
      diagnosticLogStore: _sharedDownloadDiagnosticLogStore,
      progressResetDelay: progressResetDelay,
    );
    _sharedDownloadBoundary.addListener(_notify);
    _incomingTransferRequestBoundary = IncomingTransferRequestBoundary(
      lanDiscoveryService: lanDiscoveryService,
      missingFileFilter: IncomingTransferMissingFileFilter(
        fileHashService: fileHashService,
        pathPolicy: _pathPolicy,
      ),
      fileTransferService: fileTransferService,
      transferStorageService: transferStorageService,
      sharedDownloadBoundary: _sharedDownloadBoundary,
      remoteFilePreviewBoundary: _remoteFilePreviewBoundary,
      pathPolicy: _pathPolicy,
      localNameProvider: localNameProvider,
      isTrustedSender: isTrustedSender,
      publishNotice: _publishNotice,
      updateDownloadProgress: _updateDownloadProgress,
      resetDownloadProgress: _resetDownloadProgress,
      resetDownloadSpeed: (currentBytes) =>
          _speedTracker.resetDownload(currentBytes: currentBytes),
      updateDownloadSpeed: (currentBytes) =>
          _speedTracker.updateDownload(currentBytes: currentBytes),
      clearDownloadSpeed: _speedTracker.clearDownload,
      notifyOwner: _notify,
      fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
      waitForIncomingTransferResult: _waitForIncomingTransferResult,
      registerActiveReceiveSession: _registerActiveReceiveSession,
      removeActiveReceiveSession: _removeActiveReceiveSession,
    );
    _incomingTransferRequestBoundary.addListener(_notify);
    _remoteShareAccessSessionBoundary = RemoteShareAccessSessionBoundary(
      config: RemoteShareAccessSessionConfig(
        lanDiscoveryService: lanDiscoveryService,
        fileTransferService: fileTransferService,
        transferStorageService: transferStorageService,
        localNameProvider: localNameProvider,
        localDeviceMacProvider: localDeviceMacProvider,
        isTrustedSender: isTrustedSender,
        buildStableId: _fileHashService.buildStableId,
      ),
      deps: RemoteShareAccessDeps(
        publishNotice: _publishNotice,
        writeDiagnostic: _writeSharedDownloadDiagnostic,
        fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
        applyRemoteShareAccessSnapshot: _applyRemoteShareAccessSnapshot,
        buildSnapshotFile: _buildRemoteShareAccessSnapshotFile,
        readPreparedFileMetrics: _readPreparedFileMetrics,
        sendSnapshotTransfer: _sendRemoteShareAccessSnapshotTransfer,
        setSharedUploadPreparation: _setSharedUploadPreparation,
        clearSharedUploadPreparation: _clearSharedUploadPreparation,
      ),
    );
    _remoteShareAccessSessionBoundary.addListener(_notify);
  }

  final LanDiscoveryService _lanDiscoveryService;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final FileTransferService _fileTransferService;
  final TransferStorageService _transferStorageService;
  final DownloadHistoryBoundary _downloadHistoryBoundary;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  late final RemoteFilePreviewBoundary _remoteFilePreviewBoundary;
  late final TransferCacheSnapshotBuilder _transferCacheSnapshotBuilder;
  late final TransferCachePreparationBoundary _transferCachePreparationBoundary;
  late final SharedDownloadBoundary _sharedDownloadBoundary;
  late final IncomingTransferRequestBoundary _incomingTransferRequestBoundary;
  late final RemoteShareAccessSessionBoundary _remoteShareAccessSessionBoundary;
  final Future<RemoteShareAccessProjectionLoadResult> Function({
    required String ownerIp,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
  })
  _applyRemoteShareAccessSnapshot;
  final SharedDownloadDiagnosticLogStore _sharedDownloadDiagnosticLogStore;
  final TransferPathPolicy _pathPolicy = const TransferPathPolicy();

  final Map<String, _OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, _OutgoingTransferSession>{};
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};

  final Duration progressResetDelay;

  bool _isSendingTransfer = false;
  final TransferSpeedTracker _speedTracker = TransferSpeedTracker();
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  int _downloadReceivedBytes = 0;
  int _downloadTotalBytes = 0;
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
  double get uploadSpeedBytesPerSecond =>
      _speedTracker.uploadSpeedBytesPerSecond;
  double get downloadSpeedBytesPerSecond =>
      _speedTracker.downloadSpeedBytesPerSecond;
  Duration? get uploadEta => _estimateEta(
    totalBytes: _uploadTotalBytes,
    transferredBytes: _uploadSentBytes,
    speedBytesPerSecond: uploadSpeedBytesPerSecond,
    isActive: isUploading,
  );
  Duration? get downloadEta => _estimateEta(
    totalBytes: _downloadTotalBytes,
    transferredBytes: _downloadReceivedBytes,
    speedBytesPerSecond: downloadSpeedBytesPerSecond,
    isActive: isDownloading,
  );
  IncomingTransferRequestBoundary get incomingTransferRequestBoundary =>
      _incomingTransferRequestBoundary;
  SharedDownloadBoundary get sharedDownloadBoundary => _sharedDownloadBoundary;
  TransferCachePreparationBoundary get transferCachePreparationBoundary =>
      _transferCachePreparationBoundary;
  RemoteShareAccessSessionBoundary get remoteShareAccessSessionBoundary =>
      _remoteShareAccessSessionBoundary;
  TransferSessionNotice? takePendingNotice() {
    final notice = _pendingNotice;
    _pendingNotice = null;
    return notice;
  }

  void _writeSharedDownloadDiagnostic({
    required String stage,
    String? requestId,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    unawaited(
      _sharedDownloadDiagnosticLogStore.appendEvent(
        stage: stage,
        requestId: requestId,
        details: details,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  TransferRuntimeDiagnosticCallback _fileTransferDiagnosticLogger({
    required String requestId,
    required Map<String, Object?> baseDetails,
  }) {
    return ({
      required String stage,
      Map<String, Object?> details = const <String, Object?>{},
      Object? error,
      StackTrace? stackTrace,
    }) {
      _writeSharedDownloadDiagnostic(
        stage: stage,
        requestId: requestId,
        details: <String, Object?>{...baseDetails, ...details},
        error: error,
        stackTrace: stackTrace,
      );
    };
  }

  void _updateDownloadProgress({
    required String requestId,
    required int receivedBytes,
    required int totalBytes,
  }) {
    _downloadReceivedBytes = receivedBytes;
    _downloadTotalBytes = totalBytes;
    _speedTracker.updateDownload(currentBytes: receivedBytes);
    _notify();
  }

  void _resetDownloadProgress({int? totalBytes}) {
    _downloadReceivedBytes = 0;
    _downloadTotalBytes = totalBytes ?? 0;
    _speedTracker.resetDownload(currentBytes: 0);
    _notify();
  }

  void _registerActiveReceiveSession(
    String requestId,
    TransferReceiveSession session,
  ) {
    _activeReceiveSessions[requestId] = session;
  }

  TransferReceiveSession? _removeActiveReceiveSession(String requestId) {
    return _activeReceiveSessions.remove(requestId);
  }

  TransferReceiveSession? _activeReceiveSessionForRequest(String requestId) {
    return _activeReceiveSessions[requestId];
  }

  void _registerOutgoingTransfer({
    required String requestId,
    required String receiverName,
    required List<TransferSourceFile> files,
    Future<List<TransferSourceFile>>? finalizedFilesFuture,
  }) {
    _pendingOutgoingTransfers[requestId] = _OutgoingTransferSession(
      receiverName: receiverName,
      files: files,
      finalizedFilesFuture: finalizedFilesFuture,
    );
  }

  void _removeOutgoingTransfer(String requestId) {
    _pendingOutgoingTransfers.remove(requestId);
  }

  void _setSharedUploadPreparation({
    required String requestId,
    required String requesterName,
    required SharedUploadPreparationStage stage,
  }) {
    _sharedDownloadBoundary.setUploadPreparation(
      requestId: requestId,
      requesterName: requesterName,
      stage: stage,
    );
  }

  void _clearSharedUploadPreparation({String? requestId}) {
    _sharedDownloadBoundary.clearUploadPreparation(requestId: requestId);
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

  Future<String?> requestRemoteFilePreview({
    required String ownerIp,
    required String ownerName,
    required String cacheId,
    required String relativePath,
  }) {
    return _remoteFilePreviewBoundary.requestRemoteFilePreview(
      ownerIp: ownerIp,
      ownerName: ownerName,
      cacheId: cacheId,
      relativePath: relativePath,
    );
  }

  Future<void> respondToTransferRequest({
    required String requestId,
    required bool approved,
    bool forPreview = false,
    String? previewRelativePath,
    String? destinationDirectoryOverridePath,
    SharedDownloadReceiveLayout receiveLayout =
        SharedDownloadReceiveLayout.preserveRelativeStructure,
  }) {
    return _incomingTransferRequestBoundary.respondToTransferRequest(
      requestId: requestId,
      approved: approved,
      forPreview: forPreview,
      previewRelativePath: previewRelativePath,
      destinationDirectoryOverridePath: destinationDirectoryOverridePath,
      receiveLayout: receiveLayout,
    );
  }

  void handleTransferRequestEvent(TransferRequestEvent event) {
    _incomingTransferRequestBoundary.handleTransferRequestEvent(event);
  }

  void handleTransferDecisionEvent(TransferDecisionEvent event) {
    unawaited(_handleTransferDecisionEventAsync(event));
  }

  Future<void> _handleTransferDecisionEventAsync(
    TransferDecisionEvent event,
  ) async {
    if (!event.approved) {
      _pendingOutgoingTransfers.remove(event.requestId);
      _clearSharedUploadPreparation(requestId: event.requestId);
      _publishNotice(
        TransferSessionNotice(
          infoMessage: '${event.receiverName} declined your transfer request.',
        ),
      );
      return;
    }

    final session = _pendingOutgoingTransfers[event.requestId];
    if (session == null) {
      _clearSharedUploadPreparation(requestId: event.requestId);
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
      _clearSharedUploadPreparation(requestId: event.requestId);
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
      _clearSharedUploadPreparation(requestId: event.requestId);
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

  Future<void> _sendApprovedTransfer({
    required TransferDecisionEvent event,
    required _OutgoingTransferSession session,
  }) async {
    _clearSharedUploadPreparation(requestId: event.requestId);
    _uploadSentBytes = 0;
    _uploadTotalBytes = session.files.fold<int>(
      0,
      (sum, file) => sum + file.sizeBytes,
    );
    _speedTracker.resetUpload(currentBytes: 0);
    _notify();

    try {
      await _fileTransferService.sendFiles(
        host: event.receiverIp,
        port: event.transferPort!,
        requestId: event.requestId,
        files: session.files,
        onDiagnosticEvent: _fileTransferDiagnosticLogger(
          requestId: event.requestId,
          baseDetails: <String, Object?>{
            'pathKind': 'legacy',
            'receiverIp': event.receiverIp,
            'transferPort': event.transferPort!,
          },
        ),
        onProgress: (sent, total) {
          _uploadSentBytes = sent;
          _uploadTotalBytes = total;
          _speedTracker.updateUpload(currentBytes: sent);
          _notify();
        },
      );
      _uploadSentBytes = _uploadTotalBytes;
      _speedTracker.updateUpload(currentBytes: _uploadSentBytes);
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
        _speedTracker.clearUpload();
        _notify();
      });
      _notify();
    }
  }

  Future<void> _sendDirectSharedDownload({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    List<TransferFileManifestItem>? manifestItems,
    Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
    Future<TransferSourceFile> Function(int index)? resolveFileAt,
    Future<void> Function(List<_StreamedTransferFileHash> hashes)?
    onSuccessfulStreamedHashes,
    Map<String, Object?> diagnosticDetails = const <String, Object?>{},
    bool logWholeShareConnectAttempt = false,
    Map<String, Object?> wholeShareConnectAttemptDetails =
        const <String, Object?>{},
  }) async {
    _clearSharedUploadPreparation(requestId: requestId);
    _uploadSentBytes = 0;
    _uploadTotalBytes =
        manifestItems?.fold<int>(0, (sum, file) => sum + file.sizeBytes) ??
        files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    _speedTracker.resetUpload(currentBytes: 0);
    _notify();

    try {
      final throttledWholeShareProgress =
          resolveBatch != null && manifestItems != null;
      final streamedHashes = <_StreamedTransferFileHash>[];
      final progressEmitter = _buildUploadProgressEmitter(
        requestId: requestId,
        diagnosticDetails: diagnosticDetails,
        throttleForWholeShare: throttledWholeShareProgress,
      );
      if (logWholeShareConnectAttempt) {
        _writeSharedDownloadDiagnostic(
          stage: 'sender_whole_share_direct_send_connect_attempt_start',
          requestId: requestId,
          details: <String, Object?>{
            ...wholeShareConnectAttemptDetails,
            'targetIp': targetIp,
            'receiverName': receiverName,
            'transferPort': transferPort,
            'preparedFileCount': files.length,
            'manifestFileCount': manifestItems?.length ?? files.length,
            'preparedTotalBytes': files.fold<int>(
              0,
              (sum, file) => sum + file.sizeBytes,
            ),
          },
        );
      }
      await _fileTransferService.sendFiles(
        host: targetIp,
        port: transferPort,
        requestId: requestId,
        files: files,
        manifestItems: manifestItems,
        resolveBatch: resolveBatch,
        resolveFileAt: resolveFileAt,
        onDiagnosticEvent: _fileTransferDiagnosticLogger(
          requestId: requestId,
          baseDetails: <String, Object?>{
            'pathKind': 'direct_start',
            'targetIp': targetIp,
            'receiverName': receiverName,
            'transferPort': transferPort,
            ...diagnosticDetails,
          },
        ),
        onProgress: progressEmitter,
        onFileHashed: ({required file, required computedSha256}) {
          streamedHashes.add(
            _StreamedTransferFileHash(
              file: file,
              computedSha256: computedSha256,
            ),
          );
        },
      );
      if (onSuccessfulStreamedHashes != null && streamedHashes.isNotEmpty) {
        try {
          await onSuccessfulStreamedHashes(
            List<_StreamedTransferFileHash>.unmodifiable(streamedHashes),
          );
        } catch (error, stackTrace) {
          _writeSharedDownloadDiagnostic(
            stage: 'sender_whole_share_hash_backfill_failure',
            requestId: requestId,
            details: <String, Object?>{...diagnosticDetails},
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _uploadSentBytes = _uploadTotalBytes;
      _speedTracker.updateUpload(currentBytes: _uploadSentBytes);
      _notify();
      if (logWholeShareConnectAttempt) {
        _writeSharedDownloadDiagnostic(
          stage: 'sender_whole_share_session_complete',
          requestId: requestId,
          details: <String, Object?>{
            ...wholeShareConnectAttemptDetails,
            'manifestFileCount': manifestItems?.length ?? files.length,
            'preparedFirstBatchCount': files.length,
            'sentTotalBytes': _uploadTotalBytes,
          },
        );
      }
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Transferred ${manifestItems?.length ?? files.length} file(s) to $receiverName.',
          clearError: true,
        ),
      );
    } catch (error) {
      _log('Direct shared download failed: $error');
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Direct shared download failed: $error',
        ),
      );
    } finally {
      await _cleanupTemporaryOutgoingFiles(files);
      Future<void>.delayed(progressResetDelay, () {
        if (_disposed) {
          return;
        }
        _uploadSentBytes = 0;
        _uploadTotalBytes = 0;
        _speedTracker.clearUpload();
        _notify();
      });
    }
  }

  Future<void> _sendDirectSharedDownloadForBoundary({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    List<TransferFileManifestItem>? manifestItems,
    Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
    Future<void> Function(List<TransferStreamedFileHash> hashes)?
    onSuccessfulStreamedHashes,
    Map<String, Object?> diagnosticDetails = const <String, Object?>{},
    bool logWholeShareConnectAttempt = false,
    Map<String, Object?> wholeShareConnectAttemptDetails =
        const <String, Object?>{},
  }) {
    return _sendDirectSharedDownload(
      requestId: requestId,
      targetIp: targetIp,
      receiverName: receiverName,
      transferPort: transferPort,
      files: files,
      manifestItems: manifestItems,
      resolveBatch: resolveBatch,
      onSuccessfulStreamedHashes: onSuccessfulStreamedHashes == null
          ? null
          : (hashes) => onSuccessfulStreamedHashes(
              hashes
                  .map(
                    (hash) => TransferStreamedFileHash(
                      file: hash.file,
                      computedSha256: hash.computedSha256,
                    ),
                  )
                  .toList(growable: false),
            ),
      diagnosticDetails: diagnosticDetails,
      logWholeShareConnectAttempt: logWholeShareConnectAttempt,
      wholeShareConnectAttemptDetails: wholeShareConnectAttemptDetails,
    );
  }

  Future<void> _sendRemoteShareAccessSnapshotTransfer({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    Map<String, Object?> diagnosticDetails = const <String, Object?>{},
  }) {
    return _sendDirectSharedDownload(
      requestId: requestId,
      targetIp: targetIp,
      receiverName: receiverName,
      transferPort: transferPort,
      files: files,
      diagnosticDetails: diagnosticDetails,
    );
  }

  void Function(int sentBytes, int totalBytes) _buildUploadProgressEmitter({
    required String requestId,
    required Map<String, Object?> diagnosticDetails,
    required bool throttleForWholeShare,
  }) {
    if (!throttleForWholeShare) {
      return (sent, total) {
        _uploadSentBytes = sent;
        _uploadTotalBytes = total;
        _speedTracker.updateUpload(currentBytes: sent);
        _notify();
      };
    }

    var lastEmittedAt = DateTime.fromMillisecondsSinceEpoch(0);
    var lastEmittedBytes = 0;
    var lastLoggedBucket = -1;

    return (sent, total) {
      final now = DateTime.now();
      final elapsed = now.difference(lastEmittedAt);
      final deltaBytes = sent - lastEmittedBytes;
      final bucket = total <= 0 ? 100 : ((sent * 20) ~/ total) * 5;
      final isTerminal = total > 0 && sent >= total;
      final shouldEmit =
          lastEmittedAt.millisecondsSinceEpoch == 0 ||
          isTerminal ||
          deltaBytes >= _wholeShareUploadProgressMinEmitBytes ||
          elapsed >= _wholeShareUploadProgressMinEmitInterval;
      if (!shouldEmit) {
        return;
      }

      _uploadSentBytes = sent;
      _uploadTotalBytes = total;
      _speedTracker.updateUpload(currentBytes: sent);
      _notify();
      lastEmittedAt = now;
      lastEmittedBytes = sent;

      if (bucket > lastLoggedBucket || isTerminal) {
        lastLoggedBucket = bucket;
        _writeSharedDownloadDiagnostic(
          stage: 'sender_whole_share_progress_checkpoint',
          requestId: requestId,
          details: <String, Object?>{
            ...diagnosticDetails,
            'sentBytes': sent,
            'totalBytes': total,
            'progressPercent': total <= 0 ? 100 : ((sent * 100) / total),
          },
        );
      }
    };
  }

  Future<RemoteShareAccessPreparedSnapshot>
  _buildRemoteShareAccessSnapshotFile({required String requestId}) async {
    await _sharedCacheCatalog.loadOwnerCaches(ownerMacAddress: _localDeviceMac);
    final catalog = <SharedCatalogEntryItem>[];
    for (final cache in _sharedCacheCatalog.ownerCaches) {
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

    final payload = jsonEncode(<String, Object?>{
      'ownerName': _localName,
      'ownerMacAddress': _localDeviceMac,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
      'entries': catalog.map((entry) => entry.toJson()).toList(growable: false),
    });
    final encodedBytes = gzip.encode(utf8.encode(payload));
    final directory = await _transferStorageService
        .resolveRemoteShareAccessDirectory();
    final finalPath = p.join(directory.path, 'share-access-$requestId.json.gz');
    final tempFile = File(
      p.join(
        directory.path,
        'share-access-$requestId.${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    File? finalizedFile;
    final existingFinalFile = File(finalPath);
    final replacedExistingFinalPath = await existingFinalFile.exists();
    try {
      await tempFile.writeAsBytes(encodedBytes, flush: true);
      if (replacedExistingFinalPath) {
        await existingFinalFile.delete();
      }
      finalizedFile = await tempFile.rename(finalPath);
      final finalizedStat = await finalizedFile.stat();
      final finalizedSha256 = await _fileHashService.computeSha256ForPath(
        finalizedFile.path,
      );
      return RemoteShareAccessPreparedSnapshot(
        sourcePath: finalizedFile.path,
        announcement: TransferAnnouncementItem(
          fileName: p.basename(finalizedFile.path),
          sizeBytes: finalizedStat.size,
          sha256: finalizedSha256,
        ),
        deleteAfterTransfer: true,
        diagnosticDetails: <String, Object?>{
          'tempPath': tempFile.path,
          'finalPath': finalizedFile.path,
          'finalizedBytes': finalizedStat.size,
          'finalizedSha256': finalizedSha256,
          'finalizedModifiedAtMs':
              finalizedStat.modified.millisecondsSinceEpoch,
          'replacedExistingFinalPath': replacedExistingFinalPath,
        },
      );
    } finally {
      if (finalizedFile == null && await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  Future<({int sizeBytes, String sha256, int modifiedAtMs})>
  _readPreparedFileMetrics(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError('Prepared transfer file does not exist: $filePath');
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw StateError('Prepared transfer path is not a file: $filePath');
    }
    final sha256 = await _fileHashService.computeSha256ForPath(filePath);
    return (
      sizeBytes: stat.size,
      sha256: sha256,
      modifiedAtMs: stat.modified.millisecondsSinceEpoch,
    );
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
      _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
      _writeSharedDownloadDiagnostic(
        stage: 'receiver_result',
        requestId: request.requestId,
        details: <String, Object?>{
          'success': result.success,
          'savedPathCount': result.savedPaths.length,
          'receivedItemCount': result.receivedItems.length,
          'message': result.message,
        },
      );
      if (result.success) {
        var savedPaths = result.savedPaths;
        savedPaths = await _verifyReceivedSavedPaths(savedPaths);
        final effectiveItems = acceptedItems.isEmpty
            ? result.receivedItems
            : acceptedItems;
        final recordedRelativePaths = effectiveItems
            .map(
              (item) => _pathPolicy.buildReceiveRelativePath(
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
            savedPaths = await _verifyReceivedSavedPaths(savedPaths);
          } catch (error) {
            throw StateError(
              'Failed to publish files into user downloads: $error',
            );
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
                  ? _pathPolicy.sharedParentPath(savedPaths)
                  : savedPaths.isEmpty
                  ? result.destinationDirectory
                  : File(savedPaths.first).parent.path
            : hasReceiveRootPrefix
            ? p.join(result.destinationDirectory, destinationRelativeRootPrefix)
            : result.destinationDirectory;

        if (previewCompleter == null &&
            request.sharedCacheId.trim().isNotEmpty &&
            request.senderMacAddress.trim().isNotEmpty &&
            result.receivedItems.isNotEmpty) {
          try {
            await _sharedCacheCatalog.saveReceiverCache(
              ownerMacAddress: request.senderMacAddress,
              receiverMacAddress: _localDeviceMac,
              remoteFolderIdentity: request.sharedCacheId,
              remoteDisplayName: request.sharedLabel,
              entries: result.receivedItems
                  .map(
                    (item) => SharedFolderIndexEntry(
                      relativePath: item.fileName,
                      sizeBytes: item.sizeBytes,
                      modifiedAtMs: request.createdAt.millisecondsSinceEpoch,
                      sha256: item.sha256,
                    ),
                  )
                  .toList(growable: false),
            );
          } catch (error) {
            _log('Failed to persist receiver cache: $error');
          }
        }

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
        _speedTracker.updateDownload(currentBytes: _downloadReceivedBytes);
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
      _writeSharedDownloadDiagnostic(
        stage: 'receiver_result_failure',
        requestId: request.requestId,
        details: <String, Object?>{
          'senderIp': request.senderIp,
          'senderName': request.senderName,
          'sharedCacheId': request.sharedCacheId,
        },
        error: error,
        stackTrace: stackTrace,
      );
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
      _sharedDownloadBoundary.clearPreparation(requestId: request.requestId);
      _activeReceiveSessions.remove(request.requestId);
      Future<void>.delayed(progressResetDelay, () {
        if (_disposed) {
          return;
        }
        _downloadReceivedBytes = 0;
        _downloadTotalBytes = 0;
        _speedTracker.clearDownload();
        _notify();
      });
      _notify();
    }
  }

  Future<List<String>> _verifyReceivedSavedPaths(List<String> paths) async {
    if (paths.isEmpty) {
      throw StateError('Transfer completed without saved files.');
    }
    final verified = <String>[];
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty) {
        throw StateError('Transfer completed with an empty saved file path.');
      }
      final file = File(trimmed);
      if (!await file.exists()) {
        throw StateError('Received file is missing on disk: $trimmed');
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw StateError('Received path is not a file: $trimmed');
      }
      verified.add(trimmed);
    }
    return List<String>.unmodifiable(verified);
  }

  Future<void> _persistWholeShareTransferHashBackfill({
    required String requestId,
    required SharedFolderCacheRecord cache,
    required List<_StreamedTransferFileHash> streamedHashes,
  }) async {
    if (streamedHashes.isEmpty) {
      return;
    }
    final updatesByRelativePath = <String, SharedFolderIndexEntry>{};
    for (final streamedHash in streamedHashes) {
      final file = streamedHash.file;
      final modifiedAtMs =
          file.modifiedAtMs ??
          (await File(file.sourcePath).stat()).modified.millisecondsSinceEpoch;
      updatesByRelativePath[file.fileName] = SharedFolderIndexEntry(
        relativePath: file.fileName,
        sizeBytes: file.sizeBytes,
        modifiedAtMs: modifiedAtMs,
        absolutePath: cache.rootPath.startsWith('selection://')
            ? file.sourcePath
            : null,
        sha256: streamedHash.computedSha256,
      );
    }
    _writeSharedDownloadDiagnostic(
      stage: 'sender_whole_share_hash_backfill_start',
      requestId: requestId,
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'backfillCandidateCount': updatesByRelativePath.length,
      },
    );
    final changed = await _sharedCacheIndexStore.persistCachedManifestEntries(
      record: cache,
      entries: updatesByRelativePath.values.toList(growable: false),
    );
    _writeSharedDownloadDiagnostic(
      stage: 'sender_whole_share_hash_backfill_complete',
      requestId: requestId,
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'backfillCandidateCount': updatesByRelativePath.length,
        'indexChanged': changed,
      },
    );
  }

  Future<void> _persistWholeShareTransferHashBackfillForBoundary({
    required String requestId,
    required SharedFolderCacheRecord cache,
    required List<TransferStreamedFileHash> streamedHashes,
  }) {
    return _persistWholeShareTransferHashBackfill(
      requestId: requestId,
      cache: cache,
      streamedHashes: streamedHashes
          .map(
            (hash) => _StreamedTransferFileHash(
              file: hash.file,
              computedSha256: hash.computedSha256,
            ),
          )
          .toList(growable: false),
    );
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
    _remoteFilePreviewBoundary.dispose();
    _incomingTransferRequestBoundary.removeListener(_notify);
    _incomingTransferRequestBoundary.dispose();
    _remoteShareAccessSessionBoundary.removeListener(_notify);
    _remoteShareAccessSessionBoundary.dispose();
    _transferCachePreparationBoundary.removeListener(_notify);
    _transferCachePreparationBoundary.dispose();
    _sharedDownloadBoundary.removeListener(_notify);
    _sharedDownloadBoundary.dispose();
    for (final session in _activeReceiveSessions.values) {
      unawaited(session.close());
    }
    _activeReceiveSessions.clear();
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

class _StreamedTransferFileHash {
  const _StreamedTransferFileHash({
    required this.file,
    required this.computedSha256,
  });

  final TransferSourceFile file;
  final String computedSha256;
}

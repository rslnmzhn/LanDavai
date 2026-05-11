import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../core/utils/app_notification_service.dart';
import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_packet_codec.dart';
import '../../history/application/download_history_boundary.dart';
import '../../settings/domain/app_settings.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../data/shared_download_diagnostic_log_store.dart';
import '../data/transfer_storage_service.dart';
import 'incoming_transfer_completion_boundary.dart';
import 'incoming_transfer_request_boundary.dart';
import 'incoming_transfer_request_helpers.dart';
import 'outgoing_direct_shared_download_sender.dart';
import 'outgoing_transfer_send_file_ops.dart';
import 'outgoing_transfer_send_boundary.dart';
import 'remote_share_access_session_boundary.dart';
import 'remote_share_access_session_models.dart';
import 'remote_share_access_snapshot_file_builder.dart';
import 'shared_cache_catalog.dart';
import 'shared_cache_index_store.dart';
import 'shared_download_boundary.dart';
import 'transfer_cache_preparation_boundary.dart';
import 'transfer_cache_snapshot_builder.dart';
import 'remote_file_preview_transfer_boundary.dart';
import 'transfer_path_policy.dart';
import 'transfer_speed_tracker.dart';

export 'outgoing_transfer_send_boundary.dart' show OutgoingTransferSendBoundary;

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
    required RemoteFilePreviewTransferBoundary
    remoteFilePreviewTransferBoundary,
    SharedDownloadDiagnosticLogStore? sharedDownloadDiagnosticLogStore,
    this.progressResetDelay = const Duration(seconds: 1),
  }) : _fileHashService = fileHashService,
       _remoteFilePreviewTransferBoundary = remoteFilePreviewTransferBoundary,
       _applyRemoteShareAccessSnapshot =
           applyRemoteShareAccessSnapshot ??
           _noopApplyRemoteShareAccessSnapshot,
       _sharedDownloadDiagnosticLogStore =
           sharedDownloadDiagnosticLogStore ??
           SharedDownloadDiagnosticLogStore.disabled() {
    _transferCacheSnapshotBuilder = TransferCacheSnapshotBuilder(
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
    );
    _transferCachePreparationBoundary = TransferCachePreparationBoundary();
    _transferCachePreparationBoundary.addListener(_notify);
    _incomingTransferCompletionBoundary = IncomingTransferCompletionBoundary(
      sharedCacheCatalog: sharedCacheCatalog,
      fileHashService: fileHashService,
      transferStorageService: transferStorageService,
      downloadHistoryBoundary: downloadHistoryBoundary,
      cachePreparationBoundary: _transferCachePreparationBoundary,
      remoteFilePreviewTransferBoundary: _remoteFilePreviewTransferBoundary,
      localDeviceMacProvider: localDeviceMacProvider,
      publishNotice: _publishNotice,
      writeDiagnostic: _writeSharedDownloadDiagnostic,
      progressResetDelay: progressResetDelay,
    );
    _incomingTransferCompletionBoundary.addListener(_notify);
    final outgoingSpeedTracker = TransferSpeedTracker();
    final outgoingFileOps = OutgoingTransferSendFileOps(
      sharedCacheCatalog: sharedCacheCatalog,
      fileHashService: fileHashService,
      sharedCacheIndexStore: sharedCacheIndexStore,
      writeDiagnostic: _writeSharedDownloadDiagnostic,
    );
    final outgoingDirectSharedDownloadSender =
        OutgoingDirectSharedDownloadSender(
          fileTransferService: fileTransferService,
          fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
          writeDiagnostic: _writeSharedDownloadDiagnostic,
        );
    final remoteShareAccessSnapshotFileBuilder =
        RemoteShareAccessSnapshotFileBuilder(
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          fileHashService: fileHashService,
          transferStorageService: transferStorageService,
          localNameProvider: localNameProvider,
          localDeviceMacProvider: localDeviceMacProvider,
        );
    _outgoingTransferSendBoundary = OutgoingTransferSendBoundary(
      lanDiscoveryService: lanDiscoveryService,
      fileTransferService: fileTransferService,
      cachePreparationBoundary: _transferCachePreparationBoundary,
      fileOps: outgoingFileOps,
      directSharedDownloadSender: outgoingDirectSharedDownloadSender,
      speedTracker: outgoingSpeedTracker,
      localNameProvider: localNameProvider,
      localDeviceMacProvider: localDeviceMacProvider,
      publishNotice: _publishNotice,
      clearSharedUploadPreparation: _clearSharedUploadPreparation,
      fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
      writeDiagnostic: _writeSharedDownloadDiagnostic,
      progressResetDelay: progressResetDelay,
    );
    _outgoingTransferSendBoundary.addListener(_notify);
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
      updateDownloadProgress:
          _incomingTransferCompletionBoundary.updateDownloadProgress,
      resetDownloadProgress:
          _incomingTransferCompletionBoundary.resetDownloadProgress,
      fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
      waitForIncomingTransferResult:
          _incomingTransferCompletionBoundary.waitForIncomingTransferResult,
      registerActiveReceiveSession:
          _incomingTransferCompletionBoundary.registerActiveReceiveSession,
      removeActiveReceiveSession:
          _incomingTransferCompletionBoundary.removeActiveReceiveSession,
      activeReceiveSessionForRequest:
          _incomingTransferCompletionBoundary.activeReceiveSessionForRequest,
      registerOutgoingTransfer:
          _outgoingTransferSendBoundary.registerOutgoingTransfer,
      removeOutgoingTransfer:
          _outgoingTransferSendBoundary.removeOutgoingTransfer,
      cleanupTemporaryOutgoingFiles:
          _outgoingTransferSendBoundary.cleanupTemporaryOutgoingFiles,
      hydrateTransferSourceFilesWithHashes:
          _outgoingTransferSendBoundary.hydrateTransferSourceFilesWithHashes,
      sendDirectSharedDownload:
          _outgoingTransferSendBoundary.sendDirectSharedDownload,
      persistWholeShareTransferHashBackfill:
          _outgoingTransferSendBoundary.persistWholeShareTransferHashBackfill,
      cachePreparationBoundary: _transferCachePreparationBoundary,
      buildCompressedPreviewFilesForCache: _remoteFilePreviewTransferBoundary
          .buildCompressedPreviewFilesForCache,
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
      remoteFilePreviewTransferBoundary: _remoteFilePreviewTransferBoundary,
      pathPolicy: _pathPolicy,
      localNameProvider: localNameProvider,
      isTrustedSender: isTrustedSender,
      publishNotice: _publishNotice,
      updateDownloadProgress:
          _incomingTransferCompletionBoundary.updateDownloadProgress,
      resetDownloadProgress:
          _incomingTransferCompletionBoundary.resetDownloadProgress,
      resetDownloadSpeed:
          _incomingTransferCompletionBoundary.resetDownloadSpeed,
      updateDownloadSpeed:
          _incomingTransferCompletionBoundary.updateDownloadSpeed,
      clearDownloadSpeed:
          _incomingTransferCompletionBoundary.clearDownloadSpeed,
      notifyOwner: _notify,
      fileTransferDiagnosticLogger: _fileTransferDiagnosticLogger,
      waitForIncomingTransferResult:
          _incomingTransferCompletionBoundary.waitForIncomingTransferResult,
      registerActiveReceiveSession:
          _incomingTransferCompletionBoundary.registerActiveReceiveSession,
      removeActiveReceiveSession:
          _incomingTransferCompletionBoundary.removeActiveReceiveSession,
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
        buildSnapshotFile:
            remoteShareAccessSnapshotFileBuilder.buildSnapshotFile,
        readPreparedFileMetrics:
            remoteShareAccessSnapshotFileBuilder.readMetrics,
        sendSnapshotTransfer:
            _outgoingTransferSendBoundary.sendDirectSharedDownload,
        setSharedUploadPreparation: _setSharedUploadPreparation,
        clearSharedUploadPreparation: _clearSharedUploadPreparation,
      ),
    );
    _remoteShareAccessSessionBoundary.addListener(_notify);
  }

  final FileHashService _fileHashService;
  final RemoteFilePreviewTransferBoundary _remoteFilePreviewTransferBoundary;
  late final TransferCacheSnapshotBuilder _transferCacheSnapshotBuilder;
  late final TransferCachePreparationBoundary _transferCachePreparationBoundary;
  late final IncomingTransferCompletionBoundary
  _incomingTransferCompletionBoundary;
  late final SharedDownloadBoundary _sharedDownloadBoundary;
  late final IncomingTransferRequestBoundary _incomingTransferRequestBoundary;
  late final RemoteShareAccessSessionBoundary _remoteShareAccessSessionBoundary;
  late final OutgoingTransferSendBoundary _outgoingTransferSendBoundary;
  final Future<RemoteShareAccessProjectionLoadResult> Function({
    required String ownerIp,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
  })
  _applyRemoteShareAccessSnapshot;
  final SharedDownloadDiagnosticLogStore _sharedDownloadDiagnosticLogStore;
  final TransferPathPolicy _pathPolicy = const TransferPathPolicy();

  final Duration progressResetDelay;

  TransferSessionNotice? _pendingNotice;
  bool _disposed = false;

  IncomingTransferRequestBoundary get incomingTransferRequestBoundary =>
      _incomingTransferRequestBoundary;
  SharedDownloadBoundary get sharedDownloadBoundary => _sharedDownloadBoundary;
  TransferCachePreparationBoundary get transferCachePreparationBoundary =>
      _transferCachePreparationBoundary;
  IncomingTransferCompletionBoundary get incomingTransferCompletionBoundary =>
      _incomingTransferCompletionBoundary;
  RemoteShareAccessSessionBoundary get remoteShareAccessSessionBoundary =>
      _remoteShareAccessSessionBoundary;
  OutgoingTransferSendBoundary get outgoingTransferSendBoundary =>
      _outgoingTransferSendBoundary;

  void publishBoundaryNotice(TransferSessionNotice notice) {
    _publishNotice(notice);
  }

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

  @override
  void dispose() {
    _disposed = true;
    _incomingTransferRequestBoundary.removeListener(_notify);
    _incomingTransferRequestBoundary.dispose();
    _remoteShareAccessSessionBoundary.removeListener(_notify);
    _remoteShareAccessSessionBoundary.dispose();
    _transferCachePreparationBoundary.removeListener(_notify);
    _transferCachePreparationBoundary.dispose();
    _incomingTransferCompletionBoundary.removeListener(_notify);
    _incomingTransferCompletionBoundary.dispose();
    _outgoingTransferSendBoundary.removeListener(_notify);
    _outgoingTransferSendBoundary.dispose();
    _sharedDownloadBoundary.removeListener(_notify);
    _sharedDownloadBoundary.dispose();
    super.dispose();
  }
}

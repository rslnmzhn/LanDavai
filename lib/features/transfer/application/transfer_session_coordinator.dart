import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
import '../data/shared_download_diagnostic_log_store.dart';
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

enum SharedDownloadPreparationStage {
  preparingRequest,
  checkingExistingLocalFiles,
  startingReceiver,
  waitingForRemote,
}

enum SharedUploadPreparationStage {
  resolvingSelection,
  preparingTransfer,
  waitingForRequester,
}

enum SharedDownloadReceiveLayout {
  preserveRelativeStructure,
  preserveSharedRoot,
}

enum RemoteShareAccessStage {
  sendingRequest,
  waitingForApproval,
  syncingCatalog,
  rejected,
  failed,
}

class SharedDownloadPreparationState {
  const SharedDownloadPreparationState({
    required this.requestId,
    required this.ownerName,
    required this.stage,
  });

  final String requestId;
  final String ownerName;
  final SharedDownloadPreparationStage stage;

  String get message {
    switch (stage) {
      case SharedDownloadPreparationStage.preparingRequest:
        return 'Подготавливаем запрос для $ownerName...';
      case SharedDownloadPreparationStage.checkingExistingLocalFiles:
        return 'Проверяем, какие файлы уже есть локально...';
      case SharedDownloadPreparationStage.startingReceiver:
        return 'Запускаем приём для $ownerName...';
      case SharedDownloadPreparationStage.waitingForRemote:
        return 'Ждём, пока $ownerName начнёт передачу...';
    }
  }
}

class SharedUploadPreparationState {
  const SharedUploadPreparationState({
    required this.requestId,
    required this.requesterName,
    required this.stage,
  });

  final String requestId;
  final String requesterName;
  final SharedUploadPreparationStage stage;

  String get message {
    switch (stage) {
      case SharedUploadPreparationStage.resolvingSelection:
        return 'Определяем, что нужно отправить для $requesterName...';
      case SharedUploadPreparationStage.preparingTransfer:
        return 'Подготавливаем отправку для $requesterName...';
      case SharedUploadPreparationStage.waitingForRequester:
        return 'Ждём, пока $requesterName подтвердит приём...';
    }
  }
}

class RemoteShareAccessState {
  const RemoteShareAccessState({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.stage,
    this.message,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final RemoteShareAccessStage stage;
  final String? message;

  String get statusMessage {
    switch (stage) {
      case RemoteShareAccessStage.sendingRequest:
        return message ?? 'Отправляем запрос доступа для $ownerName...';
      case RemoteShareAccessStage.waitingForApproval:
        return message ?? 'Ждём, пока $ownerName подтвердит доступ...';
      case RemoteShareAccessStage.syncingCatalog:
        return message ?? 'Синхронизируем список общих файлов с $ownerName...';
      case RemoteShareAccessStage.rejected:
        return message ?? '$ownerName отклонил запрос доступа.';
      case RemoteShareAccessStage.failed:
        return message ?? 'Не удалось получить доступ к общим файлам.';
    }
  }
}

class RemoteShareAccessProjectionLoadResult {
  const RemoteShareAccessProjectionLoadResult({
    required this.ownerIp,
    required this.cacheCount,
    required this.fileCount,
  });

  final String ownerIp;
  final int cacheCount;
  final int fileCount;
}

class TransferSessionCoordinator extends ChangeNotifier {
  static const int _wholeShareDirectStartFirstBatchFileCount = 256;
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
       _resolveRemoteOwnerMac = resolveRemoteOwnerMac,
       _applyRemoteShareAccessSnapshot =
           applyRemoteShareAccessSnapshot ??
           _noopApplyRemoteShareAccessSnapshot,
       _sharedDownloadDiagnosticLogStore =
           sharedDownloadDiagnosticLogStore ??
           SharedDownloadDiagnosticLogStore.disabled();

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
  final Future<RemoteShareAccessProjectionLoadResult> Function({
    required String ownerIp,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
  })
  _applyRemoteShareAccessSnapshot;
  final SharedDownloadDiagnosticLogStore _sharedDownloadDiagnosticLogStore;

  final List<IncomingTransferRequest> _incomingRequests =
      <IncomingTransferRequest>[];
  final List<IncomingSharedDownloadRequest> _incomingSharedDownloadRequests =
      <IncomingSharedDownloadRequest>[];
  final List<IncomingRemoteShareAccessRequest>
  _incomingRemoteShareAccessRequests = <IncomingRemoteShareAccessRequest>[];
  final Map<String, _OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, _OutgoingTransferSession>{};
  final Map<String, _PendingRemoteDownloadIntent> _pendingRemoteDownloads =
      <String, _PendingRemoteDownloadIntent>{};
  final Map<String, _PendingRemoteDownloadIntent>
  _pendingRemoteDownloadsByRequestId = <String, _PendingRemoteDownloadIntent>{};
  final Map<String, _PendingRemotePreviewIntent> _pendingRemotePreviewsByKey =
      <String, _PendingRemotePreviewIntent>{};
  final Map<String, Completer<String?>> _previewResultCompletersByRequestId =
      <String, Completer<String?>>{};
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};
  final Map<String, TransferReceiveSession> _activeRemoteShareAccessSessions =
      <String, TransferReceiveSession>{};
  final Map<String, _PendingRemoteShareAccessIntent>
  _pendingRemoteShareAccessByRequestId =
      <String, _PendingRemoteShareAccessIntent>{};
  final Map<String, List<_PreparedTransferFile>>
  _preparedTransferFilesByScopeKey = <String, List<_PreparedTransferFile>>{};

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
  SharedDownloadPreparationState? _sharedDownloadPreparationState;
  SharedUploadPreparationState? _sharedUploadPreparationState;
  RemoteShareAccessState? _remoteShareAccessState;
  bool _disposed = false;
  int _preparedTransferScopeCacheHits = 0;

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
  List<IncomingSharedDownloadRequest> get incomingSharedDownloadRequests =>
      List<IncomingSharedDownloadRequest>.unmodifiable(
        _incomingSharedDownloadRequests,
      );
  List<IncomingRemoteShareAccessRequest>
  get incomingRemoteShareAccessRequests =>
      List<IncomingRemoteShareAccessRequest>.unmodifiable(
        _incomingRemoteShareAccessRequests,
      );
  SharedDownloadPreparationState? get sharedDownloadPreparationState =>
      _sharedDownloadPreparationState;
  bool get isPreparingSharedDownload => _sharedDownloadPreparationState != null;
  SharedUploadPreparationState? get sharedUploadPreparationState =>
      _sharedUploadPreparationState;
  bool get isPreparingSharedUpload => _sharedUploadPreparationState != null;
  RemoteShareAccessState? get remoteShareAccessState => _remoteShareAccessState;
  @visibleForTesting
  int get preparedTransferScopeCacheEntryCount =>
      _preparedTransferFilesByScopeKey.length;
  @visibleForTesting
  int get preparedTransferScopeCacheHits => _preparedTransferScopeCacheHits;
  @visibleForTesting
  void debugReplaceIncomingSharedDownloadRequests(
    List<IncomingSharedDownloadRequest> requests,
  ) {
    _incomingSharedDownloadRequests
      ..clear()
      ..addAll(requests);
    _notify();
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

  void logSharedDownloadDebug({
    required String stage,
    String? requestId,
    Map<String, Object?> details = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) {
    _writeSharedDownloadDiagnostic(
      stage: stage,
      requestId: requestId,
      details: details,
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _setSharedDownloadPreparation({
    required String requestId,
    required String ownerName,
    required SharedDownloadPreparationStage stage,
  }) {
    final next = SharedDownloadPreparationState(
      requestId: requestId,
      ownerName: ownerName,
      stage: stage,
    );
    if (_sharedDownloadPreparationState?.requestId == next.requestId &&
        _sharedDownloadPreparationState?.stage == next.stage &&
        _sharedDownloadPreparationState?.ownerName == next.ownerName) {
      return;
    }
    _sharedDownloadPreparationState = next;
    _notify();
  }

  void _clearSharedDownloadPreparation({String? requestId}) {
    final current = _sharedDownloadPreparationState;
    if (current == null) {
      return;
    }
    if (requestId != null && current.requestId != requestId) {
      return;
    }
    _sharedDownloadPreparationState = null;
    _notify();
  }

  void _setSharedUploadPreparation({
    required String requestId,
    required String requesterName,
    required SharedUploadPreparationStage stage,
  }) {
    final next = SharedUploadPreparationState(
      requestId: requestId,
      requesterName: requesterName,
      stage: stage,
    );
    if (_sharedUploadPreparationState?.requestId == next.requestId &&
        _sharedUploadPreparationState?.stage == next.stage &&
        _sharedUploadPreparationState?.requesterName == next.requesterName) {
      return;
    }
    _sharedUploadPreparationState = next;
    _notify();
  }

  void _clearSharedUploadPreparation({String? requestId}) {
    final current = _sharedUploadPreparationState;
    if (current == null) {
      return;
    }
    if (requestId != null && current.requestId != requestId) {
      return;
    }
    _sharedUploadPreparationState = null;
    _notify();
  }

  void _setRemoteShareAccessState({
    required String requestId,
    required String ownerIp,
    required String ownerName,
    required RemoteShareAccessStage stage,
    String? message,
  }) {
    final next = RemoteShareAccessState(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      stage: stage,
      message: message,
    );
    final current = _remoteShareAccessState;
    if (current?.requestId == next.requestId &&
        current?.ownerIp == next.ownerIp &&
        current?.ownerName == next.ownerName &&
        current?.stage == next.stage &&
        current?.message == next.message) {
      return;
    }
    _remoteShareAccessState = next;
    _notify();
  }

  void clearRemoteShareAccessState({String? ownerIp}) {
    final current = _remoteShareAccessState;
    if (current == null) {
      return;
    }
    if (ownerIp != null && current.ownerIp != ownerIp) {
      return;
    }
    _remoteShareAccessState = null;
    _notify();
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
        _setSharedDownloadPreparation(
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
        _writeSharedDownloadDiagnostic(
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
          final deferReceiverTimeoutUntilSenderReady = requestsWholeShare;
          _setSharedDownloadPreparation(
            requestId: requestId,
            ownerName: ownerName,
            stage: SharedDownloadPreparationStage.startingReceiver,
          );
          _downloadReceivedBytes = 0;
          _downloadTotalBytes = 0;
          _resetDownloadSpeedTracking(currentBytes: 0);
          _notify();
          final receiveSession = await _fileTransferService.startReceiver(
            requestId: requestId,
            expectedItems: null,
            destinationDirectory: destinationDirectory,
            armTimeoutImmediately: !deferReceiverTimeoutUntilSenderReady,
            destinationRelativeRootPrefix: destinationRelativeRootPrefix,
            onProgress: (received, total) {
              if (received > 0) {
                _clearSharedDownloadPreparation(requestId: requestId);
              }
              _downloadReceivedBytes = received;
              _downloadTotalBytes = total;
              _updateDownloadSpeedTracking(currentBytes: received);
              _notify();
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
          _activeReceiveSessions[requestId] = receiveSession;
          _writeSharedDownloadDiagnostic(
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
                    _resolveRemoteOwnerMac(
                      ownerIp: ownerIp,
                      cacheId: cacheId,
                    ) ??
                    '',
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
            _writeSharedDownloadDiagnostic(
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
            _setSharedDownloadPreparation(
              requestId: requestId,
              ownerName: ownerName,
              stage: SharedDownloadPreparationStage.waitingForRemote,
            );
          } catch (error, stackTrace) {
            _activeReceiveSessions.remove(requestId);
            await receiveSession.close();
            _clearSharedDownloadPreparation(requestId: requestId);
            _writeSharedDownloadDiagnostic(
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
        } else {
          if (requestsWholeShare && sharedLabel.isEmpty && preferDirectStart) {
            _writeSharedDownloadDiagnostic(
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
          final pendingIntent = _PendingRemoteDownloadIntent(
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
          _writeSharedDownloadDiagnostic(
            stage: 'download_request_sent',
            requestId: requestId,
            details: <String, Object?>{
              'pathKind': 'legacy',
              'ownerIp': ownerIp,
              'cacheId': cacheId,
              'requestsWholeShare': requestsWholeShare,
            },
          );
          _setSharedDownloadPreparation(
            requestId: requestId,
            ownerName: ownerName,
            stage: SharedDownloadPreparationStage.waitingForRemote,
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
      _clearSharedDownloadPreparation();
      _log('Failed to request remote download: $error');
      _writeSharedDownloadDiagnostic(
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

  Future<void> requestRemoteShareAccess({
    required String ownerIp,
    required String ownerName,
  }) async {
    final activeState = _remoteShareAccessState;
    if (activeState != null &&
        activeState.ownerIp == ownerIp &&
        (activeState.stage == RemoteShareAccessStage.sendingRequest ||
            activeState.stage == RemoteShareAccessStage.waitingForApproval ||
            activeState.stage == RemoteShareAccessStage.syncingCatalog)) {
      return;
    }

    final requestId = _fileHashService.buildStableId(
      'share-access|$ownerIp|${DateTime.now().microsecondsSinceEpoch}|$_localDeviceMac',
    );
    _setRemoteShareAccessState(
      requestId: requestId,
      ownerIp: ownerIp,
      ownerName: ownerName,
      stage: RemoteShareAccessStage.sendingRequest,
    );
    _writeSharedDownloadDiagnostic(
      stage: 'share_access_request_preparing',
      requestId: requestId,
      details: <String, Object?>{'ownerIp': ownerIp, 'ownerName': ownerName},
    );

    TransferReceiveSession? receiveSession;
    Directory? requestDirectory;
    try {
      final baseDirectory = await _transferStorageService
          .resolveRemoteShareAccessDirectory();
      requestDirectory = Directory(p.join(baseDirectory.path, requestId));
      await requestDirectory.create(recursive: true);
      receiveSession = await _fileTransferService.startReceiver(
        requestId: requestId,
        expectedItems: null,
        destinationDirectory: requestDirectory,
        onDiagnosticEvent: _fileTransferDiagnosticLogger(
          requestId: requestId,
          baseDetails: <String, Object?>{
            'pathKind': 'share_access_snapshot',
            'ownerIp': ownerIp,
            'ownerName': ownerName,
          },
        ),
      );
      final pendingIntent = _PendingRemoteShareAccessIntent(
        requestId: requestId,
        ownerIp: ownerIp,
        ownerName: ownerName,
        destinationDirectoryPath: requestDirectory.path,
        createdAt: DateTime.now(),
      );
      _pendingRemoteShareAccessByRequestId[requestId] = pendingIntent;
      _activeRemoteShareAccessSessions[requestId] = receiveSession;
      unawaited(
        _waitForRemoteShareAccessSnapshot(pendingIntent, receiveSession),
      );

      await _lanDiscoveryService.sendShareAccessRequest(
        targetIp: ownerIp,
        requestId: requestId,
        requesterName: _localName,
        requesterMacAddress: _localDeviceMac,
        transferPort: receiveSession.port,
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_request_sent',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': ownerIp,
          'ownerName': ownerName,
          'transferPort': receiveSession.port,
        },
      );
      if (_pendingRemoteShareAccessByRequestId.containsKey(requestId)) {
        _setRemoteShareAccessState(
          requestId: requestId,
          ownerIp: ownerIp,
          ownerName: ownerName,
          stage: RemoteShareAccessStage.waitingForApproval,
        );
      }
    } catch (error, stackTrace) {
      if (receiveSession != null) {
        await receiveSession.close();
      }
      _activeRemoteShareAccessSessions.remove(requestId);
      _pendingRemoteShareAccessByRequestId.remove(requestId);
      if (requestDirectory != null) {
        await _cleanupDirectory(requestDirectory);
      }
      _setRemoteShareAccessState(
        requestId: requestId,
        ownerIp: ownerIp,
        ownerName: ownerName,
        stage: RemoteShareAccessStage.failed,
        message: 'Не удалось запросить доступ у $ownerName: $error',
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_request_failed',
        requestId: requestId,
        details: <String, Object?>{'ownerIp': ownerIp, 'ownerName': ownerName},
        error: error,
        stackTrace: stackTrace,
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
    SharedDownloadReceiveLayout receiveLayout =
        SharedDownloadReceiveLayout.preserveRelativeStructure,
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
            !isPreview &&
                receiveLayout == SharedDownloadReceiveLayout.preserveSharedRoot
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
          _setSharedDownloadPreparation(
            requestId: request.requestId,
            ownerName: request.senderName,
            stage: SharedDownloadPreparationStage.checkingExistingLocalFiles,
          );
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
          _setSharedDownloadPreparation(
            requestId: request.requestId,
            ownerName: request.senderName,
            stage: SharedDownloadPreparationStage.startingReceiver,
          );
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
            onDiagnosticEvent: isPreview
                ? null
                : _fileTransferDiagnosticLogger(
                    requestId: request.requestId,
                    baseDetails: <String, Object?>{
                      'pathKind': 'legacy',
                      'senderIp': request.senderIp,
                      'senderName': request.senderName,
                      'sharedCacheId': request.sharedCacheId,
                    },
                  ),
            onProgress: (received, total) {
              if (received > 0) {
                _clearSharedDownloadPreparation(requestId: request.requestId);
              }
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
          _clearSharedDownloadPreparation(requestId: request.requestId);
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

      _incomingRequests.removeAt(index);
      if (!decisionApproved) {
        _clearSharedDownloadPreparation(requestId: request.requestId);
        _publishNotice(
          TransferSessionNotice(
            infoMessage: isPreview
                ? 'Preview request was declined.'
                : 'Transfer declined.',
            clearError: true,
          ),
        );
      } else if (isPreview) {
        _clearSharedDownloadPreparation(requestId: request.requestId);
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Preview accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      } else if (itemsToReceive.isEmpty) {
        _clearSharedDownloadPreparation(requestId: request.requestId);
        _publishNotice(
          const TransferSessionNotice(
            infoMessage:
                'All requested files already exist locally. Transfer skipped.',
            clearError: true,
          ),
        );
      } else if (skippedExistingCount > 0) {
        _setSharedDownloadPreparation(
          requestId: request.requestId,
          ownerName: request.senderName,
          stage: SharedDownloadPreparationStage.waitingForRemote,
        );
        _publishNotice(
          TransferSessionNotice(
            infoMessage:
                'Transfer accepted. Skipping $skippedExistingCount existing file(s), waiting for missing files...',
            clearError: true,
          ),
        );
      } else {
        _setSharedDownloadPreparation(
          requestId: request.requestId,
          ownerName: request.senderName,
          stage: SharedDownloadPreparationStage.waitingForRemote,
        );
        _publishNotice(
          const TransferSessionNotice(
            infoMessage: 'Transfer accepted. Waiting for file stream...',
            clearError: true,
          ),
        );
      }
    } catch (error) {
      _clearSharedDownloadPreparation(requestId: request.requestId);
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
          receiveLayout: pendingRemoteDownload.receiveLayout,
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

  void handleDownloadRequestEvent(DownloadRequestEvent event) {
    unawaited(_handleDownloadRequest(event));
  }

  void handleShareAccessRequestEvent(ShareAccessRequestEvent event) {
    final normalizedRequesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    _writeSharedDownloadDiagnostic(
      stage: 'share_access_request_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'requesterIp': event.requesterIp,
        'requesterName': event.requesterName,
        'requesterMacAddress':
            normalizedRequesterMac ?? event.requesterMacAddress,
        'transferPort': event.transferPort,
      },
    );
    if (_isTrustedSender(normalizedRequesterMac)) {
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_request_auto_approved_for_friend',
        requestId: event.requestId,
        details: <String, Object?>{
          'requesterIp': event.requesterIp,
          'requesterName': event.requesterName,
          'requesterMacAddress':
              normalizedRequesterMac ?? event.requesterMacAddress,
          'transferPort': event.transferPort,
        },
      );
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              '${event.requesterName} is trusted. Granting shared access automatically.',
          clearError: true,
        ),
      );
      unawaited(
        _approveIncomingRemoteShareAccessRequest(
          IncomingRemoteShareAccessRequest(
            requestId: event.requestId,
            requesterIp: event.requesterIp,
            requesterName: event.requesterName,
            requesterMacAddress: event.requesterMacAddress,
            transferPort: event.transferPort,
            createdAt: event.observedAt,
          ),
        ),
      );
      return;
    }
    unawaited(SystemSound.play(SystemSoundType.alert));
    _incomingRemoteShareAccessRequests.removeWhere(
      (request) => request.requestId == event.requestId,
    );
    _incomingRemoteShareAccessRequests.insert(
      0,
      IncomingRemoteShareAccessRequest(
        requestId: event.requestId,
        requesterIp: event.requesterIp,
        requesterName: event.requesterName,
        requesterMacAddress: event.requesterMacAddress,
        transferPort: event.transferPort,
        createdAt: event.observedAt,
      ),
    );
    _publishNotice(
      TransferSessionNotice(
        infoMessage:
            '${event.requesterName} запрашивает доступ к вашим общим папкам.',
        clearError: true,
      ),
    );
    _notify();
  }

  void handleShareAccessResponseEvent(ShareAccessResponseEvent event) {
    final pending = _pendingRemoteShareAccessByRequestId[event.requestId];
    if (pending == null) {
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_response_received',
        requestId: event.requestId,
        details: <String, Object?>{
          'responderIp': event.responderIp,
          'approved': event.approved,
          'message': event.message,
          'handled': false,
        },
      );
      return;
    }

    _writeSharedDownloadDiagnostic(
      stage: 'share_access_response_received',
      requestId: event.requestId,
      details: <String, Object?>{
        'responderIp': event.responderIp,
        'responderName': event.responderName,
        'approved': event.approved,
        'message': event.message,
      },
    );
    if (!event.approved) {
      final session = _activeRemoteShareAccessSessions.remove(event.requestId);
      if (session != null) {
        unawaited(session.close());
      }
      _pendingRemoteShareAccessByRequestId.remove(event.requestId);
      unawaited(_cleanupDirectory(Directory(pending.destinationDirectoryPath)));
      _setRemoteShareAccessState(
        requestId: event.requestId,
        ownerIp: pending.ownerIp,
        ownerName: pending.ownerName,
        stage: RemoteShareAccessStage.rejected,
        message: event.message?.trim().isNotEmpty == true
            ? event.message
            : '${event.responderName} отклонил запрос доступа.',
      );
      return;
    }
    _setRemoteShareAccessState(
      requestId: event.requestId,
      ownerIp: pending.ownerIp,
      ownerName: pending.ownerName,
      stage: RemoteShareAccessStage.syncingCatalog,
      message: '${pending.ownerName} разрешил доступ. Синхронизируем список...',
    );
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
      final activeReceiveSession = _activeReceiveSessions.remove(
        event.requestId,
      );
      if (activeReceiveSession != null) {
        unawaited(activeReceiveSession.close());
      }
      _clearSharedDownloadPreparation(requestId: event.requestId);
      _publishNotice(
        TransferSessionNotice(
          infoMessage: '${event.responderName} отклонил запрос на скачивание.',
          clearError: true,
        ),
      );
    }
    _writeSharedDownloadDiagnostic(
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
      final activeReceiveSession = _activeReceiveSessions[event.requestId];
      activeReceiveSession?.armTimeout();
      _writeSharedDownloadDiagnostic(
        stage: 'requester_receiver_timeout_armed_from_sender_ready',
        requestId: event.requestId,
        details: <String, Object?>{
          'responderIp': event.responderIp,
          'responderName': event.responderName,
        },
      );
    }
  }

  Future<void> respondToIncomingRemoteShareAccessRequest({
    required String requestId,
    required bool approved,
  }) async {
    final index = _incomingRemoteShareAccessRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index == -1) {
      return;
    }
    final request = _incomingRemoteShareAccessRequests.removeAt(index);
    _notify();

    if (!approved) {
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_request_rejected',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
      );
      await _lanDiscoveryService.sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: false,
        message: 'Отправитель отклонил запрос доступа.',
      );
      _publishNotice(
        TransferSessionNotice(
          infoMessage: 'Запрос доступа от ${request.requesterName} отклонён.',
          clearError: true,
        ),
      );
      return;
    }

    await _approveIncomingRemoteShareAccessRequest(request);
  }

  Future<void> respondToIncomingSharedDownloadRequest({
    required String requestId,
    required bool approved,
  }) async {
    final index = _incomingSharedDownloadRequests.indexWhere(
      (request) => request.requestId == requestId,
    );
    if (index == -1) {
      return;
    }
    final request = _incomingSharedDownloadRequests.removeAt(index);
    _notify();

    if (!approved) {
      _writeSharedDownloadDiagnostic(
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

    _writeSharedDownloadDiagnostic(
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

  Future<void> _approveIncomingRemoteShareAccessRequest(
    IncomingRemoteShareAccessRequest request,
  ) async {
    _setSharedUploadPreparation(
      requestId: request.requestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.resolvingSelection,
    );
    _writeSharedDownloadDiagnostic(
      stage: 'share_access_request_approved',
      requestId: request.requestId,
      details: <String, Object?>{
        'requesterIp': request.requesterIp,
        'requesterName': request.requesterName,
        'transferPort': request.transferPort,
      },
    );

    try {
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_prepare_start',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
      );
      final snapshotFile = await _buildRemoteShareAccessSnapshotFile(
        requestId: request.requestId,
      );
      _setSharedUploadPreparation(
        requestId: request.requestId,
        requesterName: request.requesterName,
        stage: SharedUploadPreparationStage.preparingTransfer,
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_prepare_complete',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
          'snapshotPath': snapshotFile.sourcePath,
          'snapshotBytes': snapshotFile.announcement.sizeBytes,
          'snapshotSha256': snapshotFile.announcement.sha256,
          ...snapshotFile.diagnosticDetails,
        },
      );
      final preSendSnapshotMetrics = await _readPreparedFileMetrics(
        snapshotFile.sourcePath,
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_send_preflight',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
          'snapshotPath': snapshotFile.sourcePath,
          'preSendBytes': preSendSnapshotMetrics.sizeBytes,
          'preSendSha256': preSendSnapshotMetrics.sha256,
          'preSendModifiedAtMs': preSendSnapshotMetrics.modifiedAtMs,
          'sameFinalPathReopened':
              snapshotFile.diagnosticDetails['finalPath'] ==
              snapshotFile.sourcePath,
          ...snapshotFile.diagnosticDetails,
        },
      );
      if (preSendSnapshotMetrics.sizeBytes !=
              snapshotFile.announcement.sizeBytes ||
          preSendSnapshotMetrics.sha256.toLowerCase() !=
              snapshotFile.announcement.sha256.toLowerCase()) {
        throw StateError('Shared-access snapshot changed after preparation.');
      }
      await _lanDiscoveryService.sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: true,
        message: 'Доступ разрешён. Синхронизируем список общих файлов.',
      );
      _clearSharedUploadPreparation(requestId: request.requestId);
      unawaited(
        _sendDirectSharedDownload(
          requestId: request.requestId,
          targetIp: request.requesterIp,
          receiverName: request.requesterName,
          transferPort: request.transferPort,
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: snapshotFile.sourcePath,
              fileName: snapshotFile.announcement.fileName,
              sizeBytes: snapshotFile.announcement.sizeBytes,
              sha256: snapshotFile.announcement.sha256,
              deleteAfterTransfer: true,
            ),
          ],
          diagnosticDetails: <String, Object?>{
            'pathKind': 'share_access_snapshot',
            'snapshot': true,
            ...snapshotFile.diagnosticDetails,
          },
        ),
      );
    } catch (error, stackTrace) {
      _clearSharedUploadPreparation(requestId: request.requestId);
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_prepare_failure',
        requestId: request.requestId,
        details: <String, Object?>{
          'requesterIp': request.requesterIp,
          'requesterName': request.requesterName,
        },
        error: error,
        stackTrace: stackTrace,
      );
      await _lanDiscoveryService.sendShareAccessResponse(
        targetIp: request.requesterIp,
        requestId: request.requestId,
        responderName: _localName,
        approved: false,
        message: 'Не удалось подготовить список общих файлов.',
      );
      _publishNotice(
        TransferSessionNotice(
          errorMessage: 'Не удалось подготовить доступ к общим папкам: $error',
        ),
      );
    }
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
    _resetUploadSpeedTracking(currentBytes: 0);
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
    _resetUploadSpeedTracking(currentBytes: 0);
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
      _updateUploadSpeedTracking(currentBytes: _uploadSentBytes);
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
        _clearUploadSpeedTracking();
        _notify();
      });
    }
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
        _updateUploadSpeedTracking(currentBytes: sent);
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
      _updateUploadSpeedTracking(currentBytes: sent);
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

  Future<_PreparedTransferFile> _buildRemoteShareAccessSnapshotFile({
    required String requestId,
  }) async {
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
      return _PreparedTransferFile(
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

  Future<void> _waitForRemoteShareAccessSnapshot(
    _PendingRemoteShareAccessIntent pendingIntent,
    TransferReceiveSession session,
  ) async {
    try {
      final result = await session.result;
      final requestId = pendingIntent.requestId;
      final wasRejected =
          _remoteShareAccessState?.requestId == requestId &&
          _remoteShareAccessState?.stage == RemoteShareAccessStage.rejected;
      if (wasRejected) {
        return;
      }
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_result',
        requestId: requestId,
        details: <String, Object?>{
          'success': result.success,
          'savedPathCount': result.savedPaths.length,
          'message': result.message,
        },
      );
      if (!result.success || result.savedPaths.isEmpty) {
        _setRemoteShareAccessState(
          requestId: requestId,
          ownerIp: pendingIntent.ownerIp,
          ownerName: pendingIntent.ownerName,
          stage: RemoteShareAccessStage.failed,
          message: 'Не удалось получить список общих файлов: ${result.message}',
        );
        return;
      }

      final snapshot = await _parseRemoteShareAccessSnapshot(result.savedPaths);
      final projectionResult = await _applyRemoteShareAccessSnapshot(
        ownerIp: pendingIntent.ownerIp,
        ownerName: snapshot.ownerName,
        ownerMacAddress: snapshot.ownerMacAddress,
        entries: snapshot.entries,
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_applied',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': pendingIntent.ownerIp,
          'entryCount': snapshot.entries.length,
        },
      );
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_projection_load_result',
        requestId: requestId,
        details: <String, Object?>{
          'ownerIp': projectionResult.ownerIp,
          'cacheCount': projectionResult.cacheCount,
          'fileCount': projectionResult.fileCount,
        },
      );
      _remoteShareAccessState = null;
      _publishNotice(
        TransferSessionNotice(
          infoMessage:
              'Доступ к общим папкам ${pendingIntent.ownerName} обновлён.',
          clearError: true,
        ),
      );
    } catch (error, stackTrace) {
      final wasRejected =
          _remoteShareAccessState?.requestId == pendingIntent.requestId &&
          _remoteShareAccessState?.stage == RemoteShareAccessStage.rejected;
      if (wasRejected) {
        return;
      }
      _writeSharedDownloadDiagnostic(
        stage: 'share_access_snapshot_failure',
        requestId: pendingIntent.requestId,
        details: <String, Object?>{
          'ownerIp': pendingIntent.ownerIp,
          'ownerName': pendingIntent.ownerName,
        },
        error: error,
        stackTrace: stackTrace,
      );
      _setRemoteShareAccessState(
        requestId: pendingIntent.requestId,
        ownerIp: pendingIntent.ownerIp,
        ownerName: pendingIntent.ownerName,
        stage: RemoteShareAccessStage.failed,
        message: 'Не удалось синхронизировать общие папки: $error',
      );
    } finally {
      _pendingRemoteShareAccessByRequestId.remove(pendingIntent.requestId);
      _activeRemoteShareAccessSessions.remove(pendingIntent.requestId);
      await _cleanupDirectory(
        Directory(pendingIntent.destinationDirectoryPath),
      );
      _notify();
    }
  }

  Future<_RemoteShareAccessSnapshotPayload> _parseRemoteShareAccessSnapshot(
    List<String> savedPaths,
  ) async {
    Object? lastError;
    for (final path in savedPaths) {
      try {
        final file = File(path);
        if (!await file.exists()) {
          continue;
        }
        final rawBytes = await file.readAsBytes();
        final decodedBytes = p.extension(path).toLowerCase() == '.gz'
            ? gzip.decode(rawBytes)
            : rawBytes;
        final decoded = jsonDecode(utf8.decode(decodedBytes));
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final ownerName = (decoded['ownerName'] as String? ?? '').trim();
        final ownerMacAddress = (decoded['ownerMacAddress'] as String? ?? '')
            .trim();
        final entriesRaw = decoded['entries'];
        if (ownerName.isEmpty ||
            ownerMacAddress.isEmpty ||
            entriesRaw is! List<dynamic>) {
          continue;
        }
        final entries = <SharedCatalogEntryItem>[];
        for (final entry in entriesRaw) {
          if (entry is! Map<String, dynamic>) {
            continue;
          }
          final parsed = SharedCatalogEntryItem.fromJson(entry);
          if (parsed != null) {
            entries.add(parsed);
          }
        }
        return _RemoteShareAccessSnapshotPayload(
          ownerName: ownerName,
          ownerMacAddress: ownerMacAddress,
          entries: entries,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw StateError(
      'Не удалось прочитать snapshot общего доступа.'
      '${lastError == null ? '' : ' $lastError'}',
    );
  }

  Future<void> _cleanupDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {}
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
      _clearSharedDownloadPreparation(requestId: request.requestId);
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
        final effectiveItems = acceptedItems.isEmpty
            ? result.receivedItems
            : acceptedItems;
        final recordedRelativePaths = effectiveItems
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
      _clearSharedDownloadPreparation(requestId: request.requestId);
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
    final normalizedRequesterMac = DeviceAliasRepository.normalizeMac(
      event.requesterMacAddress,
    );
    _writeSharedDownloadDiagnostic(
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
    if (!isPreviewRequest) {
      if (!isTrustedFriendRequester) {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
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
        _writeSharedDownloadDiagnostic(
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
      _incomingSharedDownloadRequests.removeWhere(
        (existing) => existing.requestId == event.requestId,
      );
      _incomingSharedDownloadRequests.insert(0, request);
      _notify();
      return;
    }

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
        ? _TransferHashPreparationMode.none
        : _TransferHashPreparationMode.full;
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
      _writeSharedDownloadDiagnostic(
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
          diagnosticDetails: <String, Object?>{
            'cacheId': cache.cacheId,
            'sharedLabel': cache.displayName,
          },
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
      _writeSharedDownloadDiagnostic(
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
            _writeSharedDownloadDiagnostic(
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
    _writeSharedDownloadDiagnostic(
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
      _writeSharedDownloadDiagnostic(
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
        ? _TransferHashPreparationMode.cachedOnly
        : deferHashesUntilAccept
        ? _TransferHashPreparationMode.none
        : _TransferHashPreparationMode.full;

    _setSharedUploadPreparation(
      requestId: request.requestId,
      requesterName: request.requesterName,
      stage: SharedUploadPreparationStage.resolvingSelection,
    );

    try {
      final directTransferPort = request.transferPort;
      final useWholeShareFirstBatchDirectStart =
          request.requestsWholeShare && directTransferPort != null;
      if (useWholeShareFirstBatchDirectStart) {
        final sendPlan = await _buildWholeShareDirectStartSendPlan(
          cache,
          onDiagnosticEvent: wholeShareDiagnosticLogger,
        );
        if (sendPlan.manifestItems.isEmpty ||
            sendPlan.firstBatchFiles.isEmpty) {
          _clearSharedUploadPreparation(requestId: request.requestId);
          _writeSharedDownloadDiagnostic(
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
          return;
        }

        _setSharedUploadPreparation(
          requestId: request.requestId,
          requesterName: request.requesterName,
          stage: SharedUploadPreparationStage.preparingTransfer,
        );
        final firstBatchKnownHashCount = sendPlan.firstBatchFiles
            .where((file) => file.sha256.trim().isNotEmpty)
            .length;
        final firstBatchMissingHashCount =
            sendPlan.firstBatchFiles.length - firstBatchKnownHashCount;
        _writeSharedDownloadDiagnostic(
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

        _clearSharedUploadPreparation(requestId: request.requestId);
        await _lanDiscoveryService.sendDownloadResponse(
          targetIp: request.requesterIp,
          requestId: request.requestId,
          responderName: _localName,
          approved: true,
          phase: 'ready_to_connect',
          message: 'Отправитель подготовил первую партию отправки.',
        );
        _writeSharedDownloadDiagnostic(
          stage: 'sender_ready_to_connect_sent',
          requestId: request.requestId,
          details: <String, Object?>{
            'sharedCacheId': request.sharedCacheId,
            'transferPort': directTransferPort,
            'preparedFileCount': sendPlan.firstBatchFiles.length,
            'manifestFileCount': sendPlan.manifestItems.length,
          },
        );
        _writeSharedDownloadDiagnostic(
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
            logWholeShareConnectAttempt: emitWholeShareDirectStartDiagnostics,
            wholeShareConnectAttemptDetails: wholeShareDiagnosticDetails,
          ),
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
        _clearSharedUploadPreparation(requestId: request.requestId);
        _writeSharedDownloadDiagnostic(
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
        return;
      }

      final transferFiles = preparedFiles
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
      _setSharedUploadPreparation(
        requestId: request.requestId,
        requesterName: request.requesterName,
        stage: SharedUploadPreparationStage.preparingTransfer,
      );
      _writeSharedDownloadDiagnostic(
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
        _clearSharedUploadPreparation(requestId: request.requestId);
        if (request.requestsWholeShare) {
          await _lanDiscoveryService.sendDownloadResponse(
            targetIp: request.requesterIp,
            requestId: request.requestId,
            responderName: _localName,
            approved: true,
            phase: 'ready_to_connect',
            message: 'Отправитель подготовил отправку. Начинаем соединение.',
          );
          _writeSharedDownloadDiagnostic(
            stage: 'sender_ready_to_connect_sent',
            requestId: request.requestId,
            details: <String, Object?>{
              'sharedCacheId': request.sharedCacheId,
              'transferPort': directTransferPort,
              'preparedFileCount': transferFiles.length,
            },
          );
        }
        _writeSharedDownloadDiagnostic(
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
        return;
      }

      final items = preparedFiles
          .map((prepared) => prepared.announcement)
          .toList(growable: false);
      final transferRequestId = _fileHashService.buildStableId(
        'download-share|${request.requestId}|${request.requesterIp}|${cache.cacheId}',
      );

      _pendingOutgoingTransfers[transferRequestId] = _OutgoingTransferSession(
        receiverName: request.requesterName,
        files: transferFiles,
        finalizedFilesFuture: deferHashesUntilAccept
            ? _hydrateTransferSourceFilesWithHashes(transferFiles)
            : null,
      );
      _setSharedUploadPreparation(
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
      _writeSharedDownloadDiagnostic(
        stage: 'sender_legacy_transfer_request_sent',
        requestId: transferRequestId,
        details: <String, Object?>{
          'sourceDownloadRequestId': request.requestId,
          'sharedCacheId': request.sharedCacheId,
          'preparedFileCount': transferFiles.length,
        },
      );
    } catch (error, stackTrace) {
      _clearSharedUploadPreparation(requestId: request.requestId);
      _writeSharedDownloadDiagnostic(
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
    _TransferHashPreparationMode hashPreparationMode =
        _TransferHashPreparationMode.full,
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
  }) async {
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'relativePathFilterCount': relativePathFilter?.length ?? 0,
        'folderPrefixFilterCount': folderPrefixFilter?.length ?? 0,
        'hashPreparationMode': hashPreparationMode.name,
      },
    );
    var scopedSelection = await _sharedCacheIndexStore.readScopedSelection(
      cache,
      relativePathFilter: relativePathFilter,
      folderPrefixFilter: folderPrefixFilter,
    );
    final initialScopeCacheKey = _preparedTransferScopeCacheKey(
      cacheId: cache.cacheId,
      selectionFingerprint: scopedSelection.fingerprint,
      hashPreparationMode: hashPreparationMode,
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'selectionFingerprint': scopedSelection.fingerprint,
        'scopedEntryCount': scopedSelection.entries.length,
      },
    );
    final cachedPreparedFiles =
        _preparedTransferFilesByScopeKey[initialScopeCacheKey];
    if (cachedPreparedFiles != null) {
      _preparedTransferScopeCacheHits += 1;
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_prepared_scope_cache_hit',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'preparedFileCount': cachedPreparedFiles.length,
          'preparedTotalBytes': cachedPreparedFiles.fold<int>(
            0,
            (sum, file) => sum + file.announcement.sizeBytes,
          ),
        },
      );
      return cachedPreparedFiles;
    }

    final items = <_PreparedTransferFile>[];
    final refreshedManifestEntries = <SharedFolderIndexEntry>[];
    var traversedFileCount = 0;
    var skippedMissingSourceCount = 0;
    var skippedNonFileCount = 0;
    var preparedTotalBytes = 0;
    var reusedCachedHashCount = 0;
    var recomputedHashCount = 0;
    var deferredHashCount = 0;
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_live_filesystem_traversal_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'indexedEntryCount': scopedSelection.entries.length,
      },
    );
    if (hashPreparationMode == _TransferHashPreparationMode.full) {
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_hash_stage_start',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'indexedEntryCount': scopedSelection.entries.length,
        },
      );
    }
    for (final entry in scopedSelection.entries) {
      final filePath = _resolveCacheFilePath(cache: cache, entry: entry);
      if (filePath == null) {
        skippedMissingSourceCount += 1;
        continue;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        skippedMissingSourceCount += 1;
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        skippedNonFileCount += 1;
        continue;
      }
      traversedFileCount += 1;
      final currentSizeBytes = stat.size;
      final currentModifiedAtMs = stat.modified.millisecondsSinceEpoch;
      String sha256Hash = '';
      final cachedSha256 = entry.sha256?.trim() ?? '';
      final canReuseCachedManifest =
          cachedSha256.isNotEmpty &&
          entry.sizeBytes == currentSizeBytes &&
          entry.modifiedAtMs == currentModifiedAtMs;
      if (hashPreparationMode == _TransferHashPreparationMode.full) {
        if (canReuseCachedManifest) {
          sha256Hash = cachedSha256;
          reusedCachedHashCount += 1;
        } else {
          sha256Hash = await _fileHashService.computeSha256ForPath(filePath);
          recomputedHashCount += 1;
          refreshedManifestEntries.add(
            entry.copyWith(
              sizeBytes: currentSizeBytes,
              modifiedAtMs: currentModifiedAtMs,
              absolutePath: cache.rootPath.startsWith('selection://')
                  ? filePath
                  : null,
              clearAbsolutePath: !cache.rootPath.startsWith('selection://'),
              sha256: sha256Hash,
            ),
          );
        }
      } else if (hashPreparationMode ==
          _TransferHashPreparationMode.cachedOnly) {
        if (canReuseCachedManifest) {
          sha256Hash = cachedSha256;
          reusedCachedHashCount += 1;
        } else {
          deferredHashCount += 1;
        }
      }

      items.add(
        _PreparedTransferFile(
          sourcePath: filePath,
          announcement: TransferAnnouncementItem(
            fileName: entry.relativePath,
            sizeBytes: currentSizeBytes,
            sha256: sha256Hash,
          ),
        ),
      );
      preparedTotalBytes += currentSizeBytes;
    }
    if (hashPreparationMode == _TransferHashPreparationMode.full) {
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_hash_stage_complete',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'reusedCachedHashCount': reusedCachedHashCount,
          'recomputedHashCount': recomputedHashCount,
          'refreshedManifestEntryCount': refreshedManifestEntries.length,
        },
      );
    } else if (hashPreparationMode == _TransferHashPreparationMode.cachedOnly) {
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_hash_stage_deferred',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'reusedCachedHashCount': reusedCachedHashCount,
          'deferredHashCount': deferredHashCount,
        },
      );
    }
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_live_filesystem_traversal_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'traversedFileCount': traversedFileCount,
        'skippedMissingSourceCount': skippedMissingSourceCount,
        'skippedNonFileCount': skippedNonFileCount,
        'preparedFileCount': items.length,
        'preparedTotalBytes': preparedTotalBytes,
      },
    );
    if (refreshedManifestEntries.isNotEmpty) {
      await _sharedCacheIndexStore.persistCachedManifestEntries(
        record: cache,
        entries: refreshedManifestEntries,
      );
      scopedSelection = await _sharedCacheIndexStore.readScopedSelection(
        cache,
        relativePathFilter: relativePathFilter,
        folderPrefixFilter: folderPrefixFilter,
      );
    }
    final preparedItems = List<_PreparedTransferFile>.unmodifiable(items);
    _cachePreparedTransferFiles(
      cacheId: cache.cacheId,
      selectionFingerprint: scopedSelection.fingerprint,
      hashPreparationMode: hashPreparationMode,
      files: preparedItems,
    );
    return preparedItems;
  }

  Future<_WholeShareDirectStartSendPlan> _buildWholeShareDirectStartSendPlan(
    SharedFolderCacheRecord cache, {
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
  }) async {
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'relativePathFilterCount': 0,
        'folderPrefixFilterCount': 0,
        'hashPreparationMode': _TransferHashPreparationMode.cachedOnly.name,
      },
    );
    final scopedSelection = await _sharedCacheIndexStore.readScopedSelection(
      cache,
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'selectionFingerprint': scopedSelection.fingerprint,
        'scopedEntryCount': scopedSelection.entries.length,
      },
    );

    final manifestItems = List<TransferFileManifestItem>.generate(
      scopedSelection.entries.length,
      (index) {
        final entry = scopedSelection.entries[index];
        return TransferFileManifestItem(
          fileName: entry.relativePath,
          sizeBytes: entry.sizeBytes,
          sha256: entry.sha256?.trim() ?? '',
        );
      },
      growable: false,
    );

    final firstBatchTargetCount = min(
      _wholeShareDirectStartFirstBatchFileCount,
      scopedSelection.entries.length,
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_first_batch_prepare_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'manifestFileCount': manifestItems.length,
        'firstBatchTargetCount': firstBatchTargetCount,
      },
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_batch_prepare_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'batchNumber': 1,
        'batchStartIndex': 0,
        'batchFileCount': firstBatchTargetCount,
        'cumulativePreparedFileCount': firstBatchTargetCount,
        'totalManifestFileCount': manifestItems.length,
      },
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_live_filesystem_traversal_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'indexedEntryCount': scopedSelection.entries.length,
        'mode': 'first_batch_only',
      },
    );

    final refreshedManifestEntries = <SharedFolderIndexEntry>[];
    final firstBatchFiles = <TransferSourceFile>[];
    var skippedMissingSourceCount = 0;
    var skippedNonFileCount = 0;
    var firstBatchPreparedBytes = 0;
    var reusedCachedHashCount = 0;

    for (
      var index = 0;
      index < scopedSelection.entries.length &&
          firstBatchFiles.length < firstBatchTargetCount;
      index += 1
    ) {
      final entry = scopedSelection.entries[index];
      final filePath = _resolveCacheFilePath(cache: cache, entry: entry);
      if (filePath == null) {
        skippedMissingSourceCount += 1;
        continue;
      }
      final file = File(filePath);
      if (!await file.exists()) {
        skippedMissingSourceCount += 1;
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        skippedNonFileCount += 1;
        continue;
      }

      final currentSizeBytes = stat.size;
      final currentModifiedAtMs = stat.modified.millisecondsSinceEpoch;
      final cachedSha256 = entry.sha256?.trim() ?? '';
      final canReuseCachedManifest =
          cachedSha256.isNotEmpty &&
          entry.sizeBytes == currentSizeBytes &&
          entry.modifiedAtMs == currentModifiedAtMs;
      final effectiveSha256 = canReuseCachedManifest ? cachedSha256 : '';
      if (canReuseCachedManifest) {
        reusedCachedHashCount += 1;
      }

      manifestItems[index] = TransferFileManifestItem(
        fileName: entry.relativePath,
        sizeBytes: currentSizeBytes,
        sha256: effectiveSha256,
      );
      if (entry.sizeBytes != currentSizeBytes ||
          entry.modifiedAtMs != currentModifiedAtMs ||
          (entry.sha256?.trim() ?? '') != effectiveSha256) {
        refreshedManifestEntries.add(
          entry.copyWith(
            sizeBytes: currentSizeBytes,
            modifiedAtMs: currentModifiedAtMs,
            absolutePath: cache.rootPath.startsWith('selection://')
                ? filePath
                : null,
            clearAbsolutePath: !cache.rootPath.startsWith('selection://'),
            sha256: effectiveSha256.isEmpty ? null : effectiveSha256,
            clearSha256: effectiveSha256.isEmpty,
          ),
        );
      }

      firstBatchFiles.add(
        TransferSourceFile(
          sourcePath: filePath,
          fileName: entry.relativePath,
          sizeBytes: currentSizeBytes,
          sha256: effectiveSha256,
          modifiedAtMs: currentModifiedAtMs,
        ),
      );
      firstBatchPreparedBytes += currentSizeBytes;
    }

    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_live_filesystem_traversal_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'mode': 'first_batch_only',
        'preparedFileCount': firstBatchFiles.length,
        'preparedTotalBytes': firstBatchPreparedBytes,
        'skippedMissingSourceCount': skippedMissingSourceCount,
        'skippedNonFileCount': skippedNonFileCount,
      },
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_hash_stage_deferred',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'reusedCachedHashCount': reusedCachedHashCount,
        'deferredHashCount': manifestItems
            .where((item) => item.sha256.trim().isEmpty)
            .length,
      },
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_first_batch_prepare_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'manifestFileCount': manifestItems.length,
        'preparedFirstBatchCount': firstBatchFiles.length,
        'preparedFirstBatchBytes': firstBatchPreparedBytes,
        'reusedCachedHashCount': reusedCachedHashCount,
      },
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_batch_prepare_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'batchNumber': 1,
        'batchStartIndex': 0,
        'batchFileCount': firstBatchFiles.length,
        'cumulativePreparedFileCount': firstBatchFiles.length,
        'totalManifestFileCount': manifestItems.length,
      },
    );

    if (refreshedManifestEntries.isNotEmpty) {
      await _sharedCacheIndexStore.persistCachedManifestEntries(
        record: cache,
        entries: refreshedManifestEntries,
      );
    }

    return _WholeShareDirectStartSendPlan(
      manifestItems: List<TransferFileManifestItem>.unmodifiable(manifestItems),
      firstBatchFiles: List<TransferSourceFile>.unmodifiable(firstBatchFiles),
      resolveBatch: (startIndex) =>
          _prepareWholeShareDirectStartContinuationBatch(
            cache: cache,
            entries: scopedSelection.entries,
            manifestItems: manifestItems,
            startIndex: startIndex,
          ),
    );
  }

  Future<TransferSourceBatch> _prepareWholeShareDirectStartContinuationBatch({
    required SharedFolderCacheRecord cache,
    required List<SharedFolderIndexEntry> entries,
    required List<TransferFileManifestItem> manifestItems,
    required int startIndex,
  }) async {
    if (startIndex < 0 || startIndex >= entries.length) {
      throw RangeError.index(startIndex, entries, 'startIndex');
    }
    final batchNumber =
        (startIndex ~/ _wholeShareDirectStartFirstBatchFileCount) + 1;
    final endIndex = min(
      startIndex + _wholeShareDirectStartFirstBatchFileCount,
      entries.length,
    );
    final batchFileCount = endIndex - startIndex;
    _writeSharedDownloadDiagnostic(
      stage: 'sender_whole_share_batch_prepare_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'batchNumber': batchNumber,
        'batchStartIndex': startIndex,
        'batchFileCount': batchFileCount,
        'cumulativePreparedFileCount': endIndex,
        'totalManifestFileCount': manifestItems.length,
      },
    );
    final batchFiles = <TransferSourceFile>[];
    for (var index = startIndex; index < endIndex; index += 1) {
      batchFiles.add(
        await _resolveWholeShareDirectStartSourceFile(
          cache: cache,
          entry: entries[index],
          manifestItem: manifestItems[index],
        ),
      );
    }
    _writeSharedDownloadDiagnostic(
      stage: 'sender_whole_share_batch_prepare_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'batchNumber': batchNumber,
        'batchStartIndex': startIndex,
        'batchFileCount': batchFiles.length,
        'cumulativePreparedFileCount': endIndex,
        'totalManifestFileCount': manifestItems.length,
      },
    );
    return TransferSourceBatch(
      batchNumber: batchNumber,
      startIndex: startIndex,
      files: List<TransferSourceFile>.unmodifiable(batchFiles),
    );
  }

  Future<TransferSourceFile> _resolveWholeShareDirectStartSourceFile({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
    required TransferFileManifestItem manifestItem,
  }) async {
    final filePath = _resolveCacheFilePath(cache: cache, entry: entry);
    if (filePath == null) {
      throw StateError(
        'Source file does not exist for ${manifestItem.fileName}.',
      );
    }
    final file = File(filePath);
    if (!await file.exists()) {
      throw StateError(
        'Source file does not exist for ${manifestItem.fileName}.',
      );
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw StateError(
        'Source path is not a file for ${manifestItem.fileName}.',
      );
    }
    if (stat.size != manifestItem.sizeBytes) {
      throw StateError(
        'Sender file size mismatch for ${manifestItem.fileName}. '
        'File changed after first-batch preparation.',
      );
    }
    return TransferSourceFile(
      sourcePath: filePath,
      fileName: manifestItem.fileName,
      sizeBytes: manifestItem.sizeBytes,
      sha256: manifestItem.sha256,
      modifiedAtMs: stat.modified.millisecondsSinceEpoch,
    );
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

  String _preparedTransferScopeCacheKey({
    required String cacheId,
    required String selectionFingerprint,
    required _TransferHashPreparationMode hashPreparationMode,
  }) {
    return '$cacheId|$selectionFingerprint|${hashPreparationMode.name}';
  }

  void _cachePreparedTransferFiles({
    required String cacheId,
    required String selectionFingerprint,
    required _TransferHashPreparationMode hashPreparationMode,
    required List<_PreparedTransferFile> files,
  }) {
    final cacheKey = _preparedTransferScopeCacheKey(
      cacheId: cacheId,
      selectionFingerprint: selectionFingerprint,
      hashPreparationMode: hashPreparationMode,
    );
    _preparedTransferFilesByScopeKey[cacheKey] = files;

    const maxEntriesPerCache = 8;
    final keysForCache = _preparedTransferFilesByScopeKey.keys
        .where((key) => key.startsWith('$cacheId|'))
        .toList(growable: false);
    if (keysForCache.length <= maxEntriesPerCache) {
      return;
    }
    final keysToRemove = keysForCache.take(
      keysForCache.length - maxEntriesPerCache,
    );
    for (final key in keysToRemove) {
      _preparedTransferFilesByScopeKey.remove(key);
    }
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

  SharedDownloadReceiveLayout _resolveSharedDownloadReceiveLayout({
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
  }) {
    // File-only and nested-folder selections keep their relative paths.
    // Only whole-share downloads recreate the shared root as a top-level folder.
    if (selectedRelativePaths.isEmpty && selectedFolderPrefixes.isEmpty) {
      return SharedDownloadReceiveLayout.preserveSharedRoot;
    }
    return SharedDownloadReceiveLayout.preserveRelativeStructure;
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
    final pending = _pendingRemoteDownloads.remove(matchedKey);
    if (pending != null) {
      _pendingRemoteDownloadsByRequestId.remove(pending.requestId);
    }
    return pending;
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
    for (final session in _activeRemoteShareAccessSessions.values) {
      unawaited(session.close());
    }
    _activeRemoteShareAccessSessions.clear();
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

enum _TransferHashPreparationMode { full, cachedOnly, none }

class _PreparedTransferFile {
  _PreparedTransferFile({
    required this.sourcePath,
    required this.announcement,
    this.deleteAfterTransfer = false,
    this.diagnosticDetails = const <String, Object?>{},
  });

  final String sourcePath;
  final TransferAnnouncementItem announcement;
  final bool deleteAfterTransfer;
  final Map<String, Object?> diagnosticDetails;
}

class _StreamedTransferFileHash {
  const _StreamedTransferFileHash({
    required this.file,
    required this.computedSha256,
  });

  final TransferSourceFile file;
  final String computedSha256;
}

class _WholeShareDirectStartSendPlan {
  _WholeShareDirectStartSendPlan({
    required this.manifestItems,
    required this.firstBatchFiles,
    required this.resolveBatch,
  });

  final List<TransferFileManifestItem> manifestItems;
  final List<TransferSourceFile> firstBatchFiles;
  final Future<TransferSourceBatch> Function(int startIndex) resolveBatch;
}

class _PendingRemoteDownloadIntent {
  _PendingRemoteDownloadIntent({
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

class _PendingRemoteShareAccessIntent {
  _PendingRemoteShareAccessIntent({
    required this.requestId,
    required this.ownerIp,
    required this.ownerName,
    required this.destinationDirectoryPath,
    required this.createdAt,
  });

  final String requestId;
  final String ownerIp;
  final String ownerName;
  final String destinationDirectoryPath;
  final DateTime createdAt;
}

class _RemoteShareAccessSnapshotPayload {
  const _RemoteShareAccessSnapshotPayload({
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
}

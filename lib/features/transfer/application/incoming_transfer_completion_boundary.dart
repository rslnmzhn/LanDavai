import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../history/application/download_history_boundary.dart';
import '../../history/domain/transfer_history_record.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../data/transfer_storage_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'incoming_transfer_completion_models.dart';
import 'incoming_transfer_completion_path_verifier.dart';
import 'remote_file_preview_transfer_boundary.dart';
import 'shared_cache_catalog.dart';
import 'transfer_cache_preparation_boundary.dart';
import 'transfer_path_policy.dart';
import 'transfer_session_coordinator.dart';
import 'transfer_speed_tracker.dart';

class IncomingTransferCompletionBoundary extends ChangeNotifier {
  IncomingTransferCompletionBoundary({
    required SharedCacheCatalog sharedCacheCatalog,
    required FileHashService fileHashService,
    required TransferStorageService transferStorageService,
    required DownloadHistoryBoundary downloadHistoryBoundary,
    required TransferCachePreparationBoundary cachePreparationBoundary,
    required RemoteFilePreviewTransferBoundary
    remoteFilePreviewTransferBoundary,
    required String Function() localDeviceMacProvider,
    required void Function(TransferSessionNotice notice) publishNotice,
    required IncomingCompletionDiagnosticWriter writeDiagnostic,
    required Duration progressResetDelay,
  }) : _sharedCacheCatalog = sharedCacheCatalog,
       _fileHashService = fileHashService,
       _transferStorageService = transferStorageService,
       _downloadHistoryBoundary = downloadHistoryBoundary,
       _cachePreparationBoundary = cachePreparationBoundary,
       _remoteFilePreviewTransferBoundary = remoteFilePreviewTransferBoundary,
       _localDeviceMacProvider = localDeviceMacProvider,
       _publishNotice = publishNotice,
       _writeDiagnostic = writeDiagnostic,
       _progressResetDelay = progressResetDelay;

  final SharedCacheCatalog _sharedCacheCatalog;
  final FileHashService _fileHashService;
  final TransferStorageService _transferStorageService;
  final DownloadHistoryBoundary _downloadHistoryBoundary;
  final TransferCachePreparationBoundary _cachePreparationBoundary;
  final RemoteFilePreviewTransferBoundary _remoteFilePreviewTransferBoundary;
  final String Function() _localDeviceMacProvider;
  final void Function(TransferSessionNotice notice) _publishNotice;
  final IncomingCompletionDiagnosticWriter _writeDiagnostic;
  final Duration _progressResetDelay;
  final TransferSpeedTracker _speedTracker = TransferSpeedTracker();
  final TransferPathPolicy _pathPolicy = const TransferPathPolicy();
  final IncomingTransferCompletionPathVerifier _pathVerifier =
      const IncomingTransferCompletionPathVerifier();
  final Map<String, TransferReceiveSession> _activeReceiveSessions =
      <String, TransferReceiveSession>{};

  bool _disposed = false;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _lastCompletionError;
  String? _lastCompletedRequestId;
  List<String> _lastReceivedFilePaths = const <String>[];

  bool get isDownloading => _totalBytes > 0 && _receivedBytes < _totalBytes;
  double get downloadProgress =>
      _totalBytes == 0 ? 0 : _receivedBytes / _totalBytes;
  int get downloadReceivedBytes => _receivedBytes;
  int get downloadTotalBytes => _totalBytes;
  double get downloadSpeedBytesPerSecond =>
      _speedTracker.downloadSpeedBytesPerSecond;
  Duration? get downloadEta => _estimateEta(
    totalBytes: _totalBytes,
    transferredBytes: _receivedBytes,
    speedBytesPerSecond: downloadSpeedBytesPerSecond,
    isActive: isDownloading,
  );
  String? get lastCompletionError => _lastCompletionError;
  String? get lastCompletedRequestId => _lastCompletedRequestId;
  List<String> get lastReceivedFilePaths => _lastReceivedFilePaths;

  void updateDownloadProgress({
    required String requestId,
    required int receivedBytes,
    required int totalBytes,
  }) {
    _receivedBytes = receivedBytes;
    _totalBytes = totalBytes;
    _speedTracker.updateDownload(currentBytes: receivedBytes);
    _notify();
  }

  void resetDownloadProgress({int? totalBytes}) {
    _receivedBytes = 0;
    _totalBytes = totalBytes ?? 0;
    _speedTracker.resetDownload(currentBytes: 0);
    _notify();
  }

  void resetDownloadSpeed(int currentBytes) {
    _speedTracker.resetDownload(currentBytes: currentBytes);
  }

  void updateDownloadSpeed(int currentBytes) {
    _speedTracker.updateDownload(currentBytes: currentBytes);
  }

  void clearDownloadSpeed() {
    _speedTracker.clearDownload();
  }

  void registerActiveReceiveSession(
    String requestId,
    TransferReceiveSession session,
  ) {
    _activeReceiveSessions[requestId] = session;
  }

  TransferReceiveSession? removeActiveReceiveSession(String requestId) {
    return _activeReceiveSessions.remove(requestId);
  }

  TransferReceiveSession? activeReceiveSessionForRequest(String requestId) {
    return _activeReceiveSessions[requestId];
  }

  Future<void> waitForIncomingTransferResult({
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
      _cachePreparationBoundary.clearDownloadPreparation(
        requestId: request.requestId,
      );
      _writeDiagnostic(
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
        await _handleSuccessfulCompletion(
          request: request,
          result: result,
          acceptedItems: acceptedItems,
          persistToUserDownloads: persistToUserDownloads,
          recordHistory: recordHistory,
          sendCompletionNotification: sendCompletionNotification,
          destinationRelativeRootPrefix: destinationRelativeRootPrefix,
          previewCompleter: previewCompleter,
        );
      } else {
        _handleFailedCompletion(
          request: request,
          message: result.message,
          sendCompletionNotification: sendCompletionNotification,
          previewCompleter: previewCompleter,
        );
      }
    } catch (error, stackTrace) {
      _handleCompletionException(
        request: request,
        error: error,
        stackTrace: stackTrace,
        sendCompletionNotification: sendCompletionNotification,
        previewCompleter: previewCompleter,
      );
    } finally {
      _cachePreparationBoundary.clearDownloadPreparation(
        requestId: request.requestId,
      );
      _activeReceiveSessions.remove(request.requestId);
      Future<void>.delayed(_progressResetDelay, () {
        if (_disposed) {
          return;
        }
        _receivedBytes = 0;
        _totalBytes = 0;
        _speedTracker.clearDownload();
        _notify();
      });
      _notify();
    }
  }

  Future<void> _handleSuccessfulCompletion({
    required IncomingTransferRequest request,
    required FileTransferResult result,
    required List<TransferFileManifestItem> acceptedItems,
    required bool persistToUserDownloads,
    required bool recordHistory,
    required bool sendCompletionNotification,
    required String? destinationRelativeRootPrefix,
    required Completer<String?>? previewCompleter,
  }) async {
    var savedPaths = result.savedPaths;
    savedPaths = await _pathVerifier.verifyReceivedSavedPaths(savedPaths);
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
        savedPaths = await _pathVerifier.verifyReceivedSavedPaths(savedPaths);
      } catch (error) {
        throw StateError('Failed to publish files into user downloads: $error');
      }
    }

    final rootPath = _resolveReceivedRootPath(
      result: result,
      savedPaths: savedPaths,
      persistToUserDownloads: persistToUserDownloads,
      destinationRelativeRootPrefix: destinationRelativeRootPrefix,
    );
    await _persistReceiverCacheIfNeeded(
      request: request,
      result: result,
      previewCompleter: previewCompleter,
    );
    if (recordHistory) {
      await _recordDownloadHistory(
        request: request,
        rootPath: rootPath,
        savedPaths: savedPaths,
        totalBytes: result.totalBytes,
      );
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

    _lastCompletionError = null;
    _lastCompletedRequestId = request.requestId;
    _lastReceivedFilePaths = List<String>.unmodifiable(savedPaths);
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

    _receivedBytes = _totalBytes;
    _speedTracker.updateDownload(currentBytes: _receivedBytes);
  }

  void _handleFailedCompletion({
    required IncomingTransferRequest request,
    required String message,
    required bool sendCompletionNotification,
    required Completer<String?>? previewCompleter,
  }) {
    if (previewCompleter != null && !previewCompleter.isCompleted) {
      previewCompleter.complete(null);
    }
    _lastCompletionError = message;
    _remoteFilePreviewTransferBoundary.discardPreviewResultCompleter(
      request.requestId,
    );
    _log('Transfer from ${request.senderName} failed: $message');
    _publishNotice(
      TransferSessionNotice(
        errorMessage: previewCompleter != null
            ? 'Preview from ${request.senderName} failed: $message'
            : 'Transfer from ${request.senderName} failed: $message',
      ),
    );
    if (sendCompletionNotification) {
      unawaited(
        _transferStorageService.showAndroidDownloadFailedNotification(
          requestId: request.requestId,
          message: message,
        ),
      );
    }
  }

  void _handleCompletionException({
    required IncomingTransferRequest request,
    required Object error,
    required StackTrace stackTrace,
    required bool sendCompletionNotification,
    required Completer<String?>? previewCompleter,
  }) {
    if (previewCompleter != null && !previewCompleter.isCompleted) {
      previewCompleter.complete(null);
    }
    _remoteFilePreviewTransferBoundary.discardPreviewResultCompleter(
      request.requestId,
    );
    _writeDiagnostic(
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
    _lastCompletionError = error.toString();
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
  }

  String _resolveReceivedRootPath({
    required FileTransferResult result,
    required List<String> savedPaths,
    required bool persistToUserDownloads,
    required String? destinationRelativeRootPrefix,
  }) {
    final hasReceiveRootPrefix =
        destinationRelativeRootPrefix != null &&
        destinationRelativeRootPrefix.isNotEmpty;
    if (persistToUserDownloads &&
        _transferStorageService.publishesReceivedDownloadsToUserDownloads) {
      if (hasReceiveRootPrefix) {
        return _pathPolicy.sharedParentPath(savedPaths);
      }
      return savedPaths.isEmpty
          ? result.destinationDirectory
          : File(savedPaths.first).parent.path;
    }
    return hasReceiveRootPrefix
        ? p.join(result.destinationDirectory, destinationRelativeRootPrefix)
        : result.destinationDirectory;
  }

  Future<void> _persistReceiverCacheIfNeeded({
    required IncomingTransferRequest request,
    required FileTransferResult result,
    required Completer<String?>? previewCompleter,
  }) async {
    if (previewCompleter != null ||
        request.sharedCacheId.trim().isEmpty ||
        request.senderMacAddress.trim().isEmpty ||
        result.receivedItems.isEmpty) {
      return;
    }
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

  Future<void> _recordDownloadHistory({
    required IncomingTransferRequest request,
    required String rootPath,
    required List<String> savedPaths,
    required int totalBytes,
  }) async {
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
        totalBytes: totalBytes,
        status: TransferHistoryStatus.completed,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (error) {
      _log('Failed to persist transfer history: $error');
    }
  }

  Duration? _estimateEta({
    required int totalBytes,
    required int transferredBytes,
    required double speedBytesPerSecond,
    required bool isActive,
  }) {
    if (!isActive ||
        speedBytesPerSecond <= 0 ||
        totalBytes <= transferredBytes) {
      return null;
    }
    final remainingBytes = totalBytes - transferredBytes;
    return Duration(seconds: (remainingBytes / speedBytesPerSecond).ceil());
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'IncomingTransferCompletionBoundary');
  }

  String get _localDeviceMac => _localDeviceMacProvider();

  @override
  void dispose() {
    _disposed = true;
    for (final session in _activeReceiveSessions.values) {
      unawaited(session.close());
    }
    _activeReceiveSessions.clear();
    super.dispose();
  }
}

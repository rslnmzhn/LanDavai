import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

import '../../discovery/data/lan_discovery_service.dart';
import '../../discovery/data/lan_protocol_events.dart';
import '../data/file_transfer_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'outgoing_direct_shared_download_sender.dart';
import 'outgoing_transfer_send_file_ops.dart';
import 'shared_download_boundary.dart';
import 'transfer_cache_preparation_boundary.dart';
import 'transfer_session_coordinator.dart';
import 'transfer_speed_tracker.dart';

class OutgoingTransferSendBoundary extends ChangeNotifier {
  static const Duration _wholeShareUploadProgressMinEmitInterval = Duration(
    milliseconds: 250,
  );
  static const int _wholeShareUploadProgressMinEmitBytes = 512 * 1024;

  OutgoingTransferSendBoundary({
    required LanDiscoveryService lanDiscoveryService,
    required FileTransferService fileTransferService,
    required TransferCachePreparationBoundary cachePreparationBoundary,
    required OutgoingTransferSendFileOps fileOps,
    required OutgoingDirectSharedDownloadSender directSharedDownloadSender,
    required TransferSpeedTracker speedTracker,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required void Function(TransferSessionNotice notice) publishNotice,
    required void Function({String? requestId}) clearSharedUploadPreparation,
    required TransferRuntimeDiagnosticCallback Function({
      required String requestId,
      required Map<String, Object?> baseDetails,
    })
    fileTransferDiagnosticLogger,
    required void Function({
      required String stage,
      String? requestId,
      Map<String, Object?> details,
      Object? error,
      StackTrace? stackTrace,
    })
    writeDiagnostic,
    this.progressResetDelay = const Duration(seconds: 1),
  }) : _lanDiscoveryService = lanDiscoveryService,
       _fileTransferService = fileTransferService,
       _cachePreparationBoundary = cachePreparationBoundary,
       _fileOps = fileOps,
       _directSharedDownloadSender = directSharedDownloadSender,
       _speedTracker = speedTracker,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _publishNotice = publishNotice,
       _clearSharedUploadPreparation = clearSharedUploadPreparation,
       _fileTransferDiagnosticLogger = fileTransferDiagnosticLogger,
       _writeDiagnostic = writeDiagnostic;

  final LanDiscoveryService _lanDiscoveryService;
  final FileTransferService _fileTransferService;
  // ignore: unused_field
  final TransferCachePreparationBoundary _cachePreparationBoundary;
  final OutgoingTransferSendFileOps _fileOps;
  final OutgoingDirectSharedDownloadSender _directSharedDownloadSender;
  final TransferSpeedTracker _speedTracker;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final void Function(TransferSessionNotice notice) _publishNotice;
  final void Function({String? requestId}) _clearSharedUploadPreparation;
  final TransferRuntimeDiagnosticCallback Function({
    required String requestId,
    required Map<String, Object?> baseDetails,
  })
  _fileTransferDiagnosticLogger;
  final void Function({
    required String stage,
    String? requestId,
    Map<String, Object?> details,
    Object? error,
    StackTrace? stackTrace,
  })
  _writeDiagnostic;
  final Map<String, OutgoingTransferSession> _pendingOutgoingTransfers =
      <String, OutgoingTransferSession>{};

  final Duration progressResetDelay;

  bool _isSendingTransfer = false;
  int _uploadSentBytes = 0;
  int _uploadTotalBytes = 0;
  bool _disposed = false;

  bool get isSendingTransfer => _isSendingTransfer;
  bool get isUploading =>
      _uploadTotalBytes > 0 && _uploadSentBytes < _uploadTotalBytes;
  double get uploadProgress =>
      _uploadTotalBytes == 0 ? 0 : _uploadSentBytes / _uploadTotalBytes;
  int get uploadSentBytes => _uploadSentBytes;
  int get uploadTotalBytes => _uploadTotalBytes;
  double get uploadSpeedBytesPerSecond =>
      _speedTracker.uploadSpeedBytesPerSecond;
  Duration? get uploadEta => _estimateEta(
    totalBytes: _uploadTotalBytes,
    transferredBytes: _uploadSentBytes,
    speedBytesPerSecond: uploadSpeedBytesPerSecond,
    isActive: isUploading,
  );

  Future<void> sendFilesToDevice({
    required String targetIp,
    required String targetName,
    required List<String> selectedPaths,
  }) async {
    if (selectedPaths.isEmpty) return;

    _isSendingTransfer = true;
    String? pendingRequestId;
    _notify();
    try {
      final plan = await _fileOps.buildManualRequestPlan(
        targetIp: targetIp,
        targetName: targetName,
        ownerMacAddress: _localDeviceMac,
        selectedPaths: selectedPaths,
      );
      if (plan == null) {
        _publishNotice(
          const TransferSessionNotice(
            errorMessage: 'No readable files selected.',
          ),
        );
        return;
      }

      pendingRequestId = plan.requestId;
      registerOutgoingTransfer(
        requestId: plan.requestId,
        receiverName: targetName,
        files: plan.files,
      );
      await _lanDiscoveryService.sendTransferRequest(
        targetIp: targetIp,
        requestId: plan.requestId,
        senderName: _localName,
        senderMacAddress: _localDeviceMac,
        sharedCacheId: plan.sharedCacheId,
        sharedLabel: plan.sharedLabel,
        items: plan.items,
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

    final resolvedFiles = await _fileOps.resolveOutgoingSessionFiles(session);
    final filteredFiles = _fileOps.filterOutgoingFilesForDecision(
      files: resolvedFiles,
      acceptedFileNames: event.acceptedFileNames,
    );
    if (filteredFiles.isEmpty) {
      _pendingOutgoingTransfers.remove(event.requestId);
      _clearSharedUploadPreparation(requestId: event.requestId);
      unawaited(cleanupTemporaryOutgoingFiles(resolvedFiles));
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
        session: OutgoingTransferSession(
          receiverName: session.receiverName,
          files: filteredFiles,
        ),
      ),
    );
  }

  Future<void> sendDirectSharedDownload({
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
  }) async {
    _clearSharedUploadPreparation(requestId: requestId);
    _uploadSentBytes = 0;
    _uploadTotalBytes =
        manifestItems?.fold<int>(0, (sum, file) => sum + file.sizeBytes) ??
        files.fold<int>(0, (sum, file) => sum + file.sizeBytes);
    _speedTracker.resetUpload(currentBytes: 0);
    _notify();

    try {
      await _directSharedDownloadSender.send(
        requestId: requestId,
        targetIp: targetIp,
        receiverName: receiverName,
        transferPort: transferPort,
        files: files,
        manifestItems: manifestItems,
        resolveBatch: resolveBatch,
        onProgress: _buildUploadProgressEmitter(
          requestId: requestId,
          diagnosticDetails: diagnosticDetails,
          throttleForWholeShare: resolveBatch != null && manifestItems != null,
        ),
        onSuccessfulStreamedHashes: onSuccessfulStreamedHashes,
        diagnosticDetails: diagnosticDetails,
        logWholeShareConnectAttempt: logWholeShareConnectAttempt,
        wholeShareConnectAttemptDetails: wholeShareConnectAttemptDetails,
      );
      _uploadSentBytes = _uploadTotalBytes;
      _speedTracker.updateUpload(currentBytes: _uploadSentBytes);
      _notify();
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
      await cleanupTemporaryOutgoingFiles(files);
      _resetUploadProgressLater();
    }
  }

  void registerOutgoingTransfer({
    required String requestId,
    required String receiverName,
    required List<TransferSourceFile> files,
    Future<List<TransferSourceFile>>? finalizedFilesFuture,
  }) {
    _pendingOutgoingTransfers[requestId] = OutgoingTransferSession(
      receiverName: receiverName,
      files: files,
      finalizedFilesFuture: finalizedFilesFuture,
    );
  }

  void removeOutgoingTransfer(String requestId) {
    _pendingOutgoingTransfers.remove(requestId);
  }

  Future<void> cleanupTemporaryOutgoingFiles(List<TransferSourceFile> files) =>
      _fileOps.cleanupTemporaryOutgoingFiles(files);

  Future<List<TransferSourceFile>> hydrateTransferSourceFilesWithHashes(
    List<TransferSourceFile> files,
  ) => _fileOps.hydrateTransferSourceFilesWithHashes(files);

  Future<void> persistWholeShareTransferHashBackfill({
    required String requestId,
    required SharedFolderCacheRecord cache,
    required List<TransferStreamedFileHash> streamedHashes,
  }) => _fileOps.persistWholeShareTransferHashBackfill(
    requestId: requestId,
    cache: cache,
    streamedHashes: streamedHashes,
  );

  Future<void> _sendApprovedTransfer({
    required TransferDecisionEvent event,
    required OutgoingTransferSession session,
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
      await cleanupTemporaryOutgoingFiles(session.files);
      _resetUploadProgressLater();
      _notify();
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
      if (!shouldEmit) return;

      _uploadSentBytes = sent;
      _uploadTotalBytes = total;
      _speedTracker.updateUpload(currentBytes: sent);
      _notify();
      lastEmittedAt = now;
      lastEmittedBytes = sent;

      if (bucket > lastLoggedBucket || isTerminal) {
        lastLoggedBucket = bucket;
        _writeDiagnostic(
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

  Duration? _estimateEta({
    required int totalBytes,
    required int transferredBytes,
    required double speedBytesPerSecond,
    required bool isActive,
  }) {
    if (!isActive) return null;
    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) return Duration.zero;
    if (speedBytesPerSecond <= 1) return null;
    return Duration(seconds: (remaining / speedBytesPerSecond).ceil());
  }

  void _resetUploadProgressLater() {
    Future<void>.delayed(progressResetDelay, () {
      if (_disposed) return;
      _uploadSentBytes = 0;
      _uploadTotalBytes = 0;
      _speedTracker.clearUpload();
      _notify();
    });
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _log(String message) {
    developer.log(message, name: 'OutgoingTransferSendBoundary');
  }

  @override
  void dispose() { _disposed = true; super.dispose(); }

  String get _localName => _localNameProvider();
  String get _localDeviceMac => _localDeviceMacProvider();
}

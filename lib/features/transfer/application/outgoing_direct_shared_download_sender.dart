import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';
import 'shared_download_boundary.dart';

class OutgoingDirectSharedDownloadSender {
  const OutgoingDirectSharedDownloadSender({
    required FileTransferService fileTransferService,
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
  }) : _fileTransferService = fileTransferService,
       _fileTransferDiagnosticLogger = fileTransferDiagnosticLogger,
       _writeDiagnostic = writeDiagnostic;

  final FileTransferService _fileTransferService;
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

  Future<void> send({
    required String requestId,
    required String targetIp,
    required String receiverName,
    required int transferPort,
    required List<TransferSourceFile> files,
    List<TransferFileManifestItem>? manifestItems,
    Future<TransferSourceBatch> Function(int startIndex)? resolveBatch,
    required void Function(int sentBytes, int totalBytes) onProgress,
    Future<void> Function(List<TransferStreamedFileHash> hashes)?
    onSuccessfulStreamedHashes,
    Map<String, Object?> diagnosticDetails = const <String, Object?>{},
    bool logWholeShareConnectAttempt = false,
    Map<String, Object?> wholeShareConnectAttemptDetails =
        const <String, Object?>{},
  }) async {
    final streamedHashes = <TransferStreamedFileHash>[];
    if (logWholeShareConnectAttempt) {
      _writeDiagnostic(
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
      onProgress: onProgress,
      onFileHashed: ({required file, required computedSha256}) {
        streamedHashes.add(
          TransferStreamedFileHash(file: file, computedSha256: computedSha256),
        );
      },
    );
    await _backfillHashes(
      requestId: requestId,
      streamedHashes: streamedHashes,
      onSuccessfulStreamedHashes: onSuccessfulStreamedHashes,
      diagnosticDetails: diagnosticDetails,
    );
    if (logWholeShareConnectAttempt) {
      _writeDiagnostic(
        stage: 'sender_whole_share_session_complete',
        requestId: requestId,
        details: <String, Object?>{
          ...wholeShareConnectAttemptDetails,
          'manifestFileCount': manifestItems?.length ?? files.length,
          'preparedFirstBatchCount': files.length,
          'sentTotalBytes':
              manifestItems?.fold<int>(
                0,
                (sum, file) => sum + file.sizeBytes,
              ) ??
              files.fold<int>(0, (sum, file) => sum + file.sizeBytes),
        },
      );
    }
  }

  Future<void> _backfillHashes({
    required String requestId,
    required List<TransferStreamedFileHash> streamedHashes,
    required Future<void> Function(List<TransferStreamedFileHash> hashes)?
    onSuccessfulStreamedHashes,
    required Map<String, Object?> diagnosticDetails,
  }) async {
    if (onSuccessfulStreamedHashes == null || streamedHashes.isEmpty) return;
    try {
      await onSuccessfulStreamedHashes(
        List<TransferStreamedFileHash>.unmodifiable(streamedHashes),
      );
    } catch (error, stackTrace) {
      _writeDiagnostic(
        stage: 'sender_whole_share_hash_backfill_failure',
        requestId: requestId,
        details: <String, Object?>{...diagnosticDetails},
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}

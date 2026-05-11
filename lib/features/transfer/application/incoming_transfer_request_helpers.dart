import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../discovery/data/lan_protocol_events.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../domain/transfer_request.dart';
import 'transfer_path_policy.dart';

typedef IncomingDownloadProgressUpdater =
    void Function({
      required String requestId,
      required int receivedBytes,
      required int totalBytes,
    });

typedef IncomingTransferDiagnosticLoggerFactory =
    TransferRuntimeDiagnosticCallback Function({
      required String requestId,
      required Map<String, Object?> baseDetails,
    });

typedef IncomingTransferResultWaiter =
    Future<void> Function({
      required IncomingTransferRequest request,
      required TransferReceiveSession session,
      required List<TransferFileManifestItem> acceptedItems,
      required bool persistToUserDownloads,
      required bool recordHistory,
      required bool sendCompletionNotification,
      String? destinationRelativeRootPrefix,
      Completer<String?>? previewCompleter,
    });

IncomingTransferRequest mapIncomingTransferRequestEvent(
  TransferRequestEvent event,
) {
  final mappedItems = event.items
      .map(
        (item) => TransferFileManifestItem(
          fileName: item.fileName,
          sizeBytes: item.sizeBytes,
          sha256: item.sha256,
        ),
      )
      .toList(growable: false);

  return IncomingTransferRequest(
    requestId: event.requestId,
    senderIp: event.senderIp,
    senderName: event.senderName,
    senderMacAddress: event.senderMacAddress,
    sharedCacheId: event.sharedCacheId,
    sharedLabel: event.sharedLabel,
    items: mappedItems,
    createdAt: event.observedAt,
  );
}

class IncomingTransferMissingFileFilter {
  const IncomingTransferMissingFileFilter({
    required FileHashService fileHashService,
    required TransferPathPolicy pathPolicy,
  }) : _fileHashService = fileHashService,
       _pathPolicy = pathPolicy;

  final FileHashService _fileHashService;
  final TransferPathPolicy _pathPolicy;

  Future<List<TransferFileManifestItem>> filterMissingIncomingItems({
    required List<TransferFileManifestItem> items,
    required Directory destinationDirectory,
    String? destinationRelativeRootPrefix,
  }) async {
    final missing = <TransferFileManifestItem>[];
    for (final item in items) {
      final relativePath = _pathPolicy.buildReceiveRelativePath(
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
}

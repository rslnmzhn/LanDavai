import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../discovery/data/lan_packet_codec.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../domain/shared_folder_cache.dart';
import 'shared_cache_catalog.dart';
import 'shared_cache_index_store.dart';
import 'shared_download_boundary.dart';

class OutgoingTransferSendFileOps {
  const OutgoingTransferSendFileOps({
    required SharedCacheCatalog sharedCacheCatalog,
    required FileHashService fileHashService,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required void Function({
      required String stage,
      String? requestId,
      Map<String, Object?> details,
      Object? error,
      StackTrace? stackTrace,
    })
    writeDiagnostic,
  }) : _sharedCacheCatalog = sharedCacheCatalog,
       _fileHashService = fileHashService,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _writeDiagnostic = writeDiagnostic;

  final SharedCacheCatalog _sharedCacheCatalog;
  final FileHashService _fileHashService;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final void Function({
    required String stage,
    String? requestId,
    Map<String, Object?> details,
    Object? error,
    StackTrace? stackTrace,
  })
  _writeDiagnostic;

  Future<OutgoingTransferRequestPlan?> buildManualRequestPlan({
    required String targetIp,
    required String targetName,
    required String ownerMacAddress,
    required List<String> selectedPaths,
  }) async {
    final cache = await _sharedCacheCatalog.buildOwnerSelectionCache(
      ownerMacAddress: ownerMacAddress,
      filePaths: selectedPaths,
      displayName: 'Transfer to $targetName',
    );
    await _sharedCacheCatalog.loadOwnerCaches(ownerMacAddress: ownerMacAddress);

    final items = <TransferAnnouncementItem>[];
    final transferFiles = <TransferSourceFile>[];
    for (final filePath in selectedPaths) {
      final file = File(filePath);
      if (!await file.exists()) continue;
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) continue;

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

    if (items.isEmpty) return null;
    final requestId = _fileHashService.buildStableId(
      '${DateTime.now().microsecondsSinceEpoch}|$targetIp|${cache.cacheId}',
    );
    return OutgoingTransferRequestPlan(
      requestId: requestId,
      sharedCacheId: cache.cacheId,
      sharedLabel: cache.displayName,
      items: items,
      files: transferFiles,
    );
  }

  Future<void> cleanupTemporaryOutgoingFiles(
    List<TransferSourceFile> files,
  ) async {
    for (final file in files) {
      if (!file.deleteAfterTransfer) continue;
      try {
        final source = File(file.sourcePath);
        if (await source.exists()) await source.delete();
      } catch (_) {}
    }
  }

  Future<List<TransferSourceFile>> hydrateTransferSourceFilesWithHashes(
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

  Future<void> persistWholeShareTransferHashBackfill({
    required String requestId,
    required SharedFolderCacheRecord cache,
    required List<TransferStreamedFileHash> streamedHashes,
  }) async {
    if (streamedHashes.isEmpty) return;
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
    _writeDiagnostic(
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
    _writeDiagnostic(
      stage: 'sender_whole_share_hash_backfill_complete',
      requestId: requestId,
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'backfillCandidateCount': updatesByRelativePath.length,
        'indexChanged': changed,
      },
    );
  }

  List<TransferSourceFile> filterOutgoingFilesForDecision({
    required List<TransferSourceFile> files,
    required List<String>? acceptedFileNames,
  }) {
    if (acceptedFileNames == null) return files;
    final accepted = acceptedFileNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (accepted.isEmpty) return const <TransferSourceFile>[];
    return files
        .where((file) => accepted.contains(file.fileName))
        .toList(growable: false);
  }

  Future<List<TransferSourceFile>> resolveOutgoingSessionFiles(
    OutgoingTransferSession session,
  ) async {
    final finalizedFilesFuture = session.finalizedFilesFuture;
    if (finalizedFilesFuture == null) return session.files;
    final resolved = await finalizedFilesFuture;
    session.files = resolved;
    session.finalizedFilesFuture = null;
    return resolved;
  }
}

class OutgoingTransferSession {
  OutgoingTransferSession({
    required this.receiverName,
    required this.files,
    this.finalizedFilesFuture,
  });

  final String receiverName;
  List<TransferSourceFile> files;
  Future<List<TransferSourceFile>>? finalizedFilesFuture;
}

class OutgoingTransferRequestPlan {
  const OutgoingTransferRequestPlan({
    required this.requestId,
    required this.sharedCacheId,
    required this.sharedLabel,
    required this.items,
    required this.files,
  });

  final String requestId;
  final String sharedCacheId;
  final String sharedLabel;
  final List<TransferAnnouncementItem> items;
  final List<TransferSourceFile> files;
}

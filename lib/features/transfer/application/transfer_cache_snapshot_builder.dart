import 'dart:io';
import 'dart:math';

import '../../discovery/data/lan_packet_codec_models.dart';
import '../data/file_hash_service.dart';
import '../data/file_transfer_service.dart';
import '../domain/shared_folder_cache.dart';
import '../domain/transfer_request.dart';
import 'shared_cache_index_store.dart';
import 'transfer_cache_preparation_models.dart';
import 'transfer_cache_preparation_path_resolver.dart';

class TransferCacheSnapshotBuilder {
  TransferCacheSnapshotBuilder({
    required SharedCacheIndexStore sharedCacheIndexStore,
    required FileHashService fileHashService,
    TransferCachePreparationPathResolver pathResolver =
        const TransferCachePreparationPathResolver(),
  }) : _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _pathResolver = pathResolver;

  static const int _wholeShareDirectStartFirstBatchFileCount = 256;

  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final TransferCachePreparationPathResolver _pathResolver;
  Future<List<SharedDownloadPreparedFile>> buildTransferFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
    Set<String>? folderPrefixFilter,
    SharedDownloadHashPreparationMode hashPreparationMode =
        SharedDownloadHashPreparationMode.full,
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
    final scopedSelection = await _sharedCacheIndexStore.readScopedSelection(
      cache,
      relativePathFilter: relativePathFilter,
      folderPrefixFilter: folderPrefixFilter,
    );
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_complete',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'selectionFingerprint': scopedSelection.fingerprint,
        'scopedEntryCount': scopedSelection.entries.length,
      },
    );
    final items = <SharedDownloadPreparedFile>[];
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
    if (hashPreparationMode == SharedDownloadHashPreparationMode.full) {
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_hash_stage_start',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'indexedEntryCount': scopedSelection.entries.length,
        },
      );
    }
    for (final entry in scopedSelection.entries) {
      final filePath = _pathResolver.resolve(cache: cache, entry: entry);
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
      if (hashPreparationMode == SharedDownloadHashPreparationMode.full) {
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
          SharedDownloadHashPreparationMode.cachedOnly) {
        if (canReuseCachedManifest) {
          sha256Hash = cachedSha256;
          reusedCachedHashCount += 1;
        } else {
          deferredHashCount += 1;
        }
      }

      items.add(
        SharedDownloadPreparedFile(
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
    if (hashPreparationMode == SharedDownloadHashPreparationMode.full) {
      onDiagnosticEvent?.call(
        stage: 'sender_whole_share_hash_stage_complete',
        details: <String, Object?>{
          'cacheId': cache.cacheId,
          'reusedCachedHashCount': reusedCachedHashCount,
          'recomputedHashCount': recomputedHashCount,
          'refreshedManifestEntryCount': refreshedManifestEntries.length,
        },
      );
    } else if (hashPreparationMode ==
        SharedDownloadHashPreparationMode.cachedOnly) {
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
    }
    return List<SharedDownloadPreparedFile>.unmodifiable(items);
  }

  Future<SharedDownloadWholeShareSendPlan> buildWholeShareDirectStartSendPlan(
    SharedFolderCacheRecord cache, {
    TransferRuntimeDiagnosticCallback? onDiagnosticEvent,
  }) async {
    onDiagnosticEvent?.call(
      stage: 'sender_whole_share_scoped_selection_resolution_start',
      details: <String, Object?>{
        'cacheId': cache.cacheId,
        'relativePathFilterCount': 0,
        'folderPrefixFilterCount': 0,
        'hashPreparationMode':
            SharedDownloadHashPreparationMode.cachedOnly.name,
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
      final filePath = _pathResolver.resolve(cache: cache, entry: entry);
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

    return SharedDownloadWholeShareSendPlan(
      manifestItems: List<TransferFileManifestItem>.unmodifiable(manifestItems),
      firstBatchFiles: List<TransferSourceFile>.unmodifiable(firstBatchFiles),
      resolveBatch: (startIndex) => _prepareContinuationBatch(
        cache: cache,
        entries: scopedSelection.entries,
        manifestItems: manifestItems,
        startIndex: startIndex,
      ),
    );
  }

  Future<TransferSourceBatch> _prepareContinuationBatch({
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
    final filePath = _pathResolver.resolve(cache: cache, entry: entry);
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
}

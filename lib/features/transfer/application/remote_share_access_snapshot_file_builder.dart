import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/file_hash_service.dart';
import '../data/transfer_storage_service.dart';
import '../../discovery/data/lan_packet_codec.dart';
import 'remote_share_access_session_models.dart';
import 'shared_cache_catalog.dart';
import 'shared_cache_index_store.dart';

class RemoteShareAccessSnapshotFileBuilder {
  const RemoteShareAccessSnapshotFileBuilder({
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required FileHashService fileHashService,
    required TransferStorageService transferStorageService,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
  }) : _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _transferStorageService = transferStorageService,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider;

  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final TransferStorageService _transferStorageService;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;

  Future<RemoteShareAccessPreparedSnapshot> buildSnapshotFile({
    required String requestId,
  }) async {
    await _sharedCacheCatalog.loadOwnerCaches(
      ownerMacAddress: _localDeviceMacProvider(),
    );
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
      'ownerName': _localNameProvider(),
      'ownerMacAddress': _localDeviceMacProvider(),
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
      if (replacedExistingFinalPath) await existingFinalFile.delete();
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

  Future<({int sizeBytes, String sha256, int modifiedAtMs})> readMetrics(
    String filePath,
  ) async {
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
}

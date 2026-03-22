import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/storage/app_database.dart';
import '../../discovery/data/device_alias_repository.dart';
import '../domain/shared_folder_cache.dart';
import 'thumbnail_cache_service.dart';

class OwnerFolderCacheUpsertResult {
  const OwnerFolderCacheUpsertResult({
    required this.record,
    required this.created,
    required this.previousItemCount,
  });

  final SharedFolderCacheRecord record;
  final bool created;
  final int previousItemCount;
}

typedef OwnerCacheProgressCallback =
    void Function({
      required int processedFiles,
      required int totalFiles,
      required String relativePath,
      required OwnerCacheProgressStage stage,
    });

enum OwnerCacheProgressStage { scanning, indexing }

class SharedFolderCacheRepository {
  SharedFolderCacheRepository({
    required AppDatabase database,
    ThumbnailCacheService? thumbnailCacheService,
  }) : _database = database,
       _thumbnailCacheService =
           thumbnailCacheService ?? ThumbnailCacheService(database: database);

  final AppDatabase _database;
  final ThumbnailCacheService _thumbnailCacheService;
  static const int _schemaVersion = 1;

  bool supportsPreviewForPath(String relativePath) {
    return _thumbnailCacheService.supportsThumbnailForPath(relativePath);
  }

  bool isVideoPath(String relativePath) {
    return _thumbnailCacheService.isVideoPath(relativePath);
  }

  Future<SharedFolderCacheRecord> buildOwnerCache({
    required String ownerMacAddress,
    required String folderPath,
    String? displayName,
  }) async {
    final result = await upsertOwnerFolderCache(
      ownerMacAddress: ownerMacAddress,
      folderPath: folderPath,
      displayName: displayName,
    );
    return result.record;
  }

  Future<OwnerFolderCacheUpsertResult> upsertOwnerFolderCache({
    required String ownerMacAddress,
    required String folderPath,
    String? displayName,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final rootDirectory = Directory(folderPath);
    if (!await rootDirectory.exists()) {
      throw ArgumentError('Directory does not exist: $folderPath');
    }

    final normalizedRoot = await _normalizeExistingDirectoryPath(rootDirectory);
    final existing = await _findOwnerCacheByRootPath(
      ownerMacAddress: ownerMac,
      rootPath: normalizedRoot,
    );
    final resolvedDisplayName = _resolveDisplayName(
      providedName: displayName ?? existing?.displayName,
      fallbackPath: normalizedRoot,
    );
    final cacheId =
        existing?.cacheId ??
        _createCacheId(
          role: SharedFolderCacheRole.owner,
          ownerMacAddress: ownerMac,
          peerMacAddress: null,
          rootIdentity: normalizedRoot,
        );

    Map<String, SharedFolderIndexEntry>? previousEntriesByRelativePath;
    if (existing != null) {
      final previousEntries = await readIndexEntries(existing.cacheId);
      if (previousEntries.isNotEmpty) {
        previousEntriesByRelativePath = <String, SharedFolderIndexEntry>{
          for (final entry in previousEntries) entry.relativePath: entry,
        };
      }
    }

    final entries = await _indexFolder(
      normalizedRoot,
      cacheId: cacheId,
      previousEntriesByRelativePath: previousEntriesByRelativePath,
      parallelWorkers: parallelWorkers,
      onProgress: onProgress,
    );
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final now = DateTime.now().millisecondsSinceEpoch;

    final cacheDir = await _database.resolveSharedCacheDirectory();
    final indexPath =
        existing?.indexFilePath ??
        p.join(
          cacheDir.path,
          _createCacheFileName(
            role: SharedFolderCacheRole.owner,
            displayName: resolvedDisplayName,
            cacheId: cacheId,
          ),
        );

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: normalizedRoot,
      displayName: resolvedDisplayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return OwnerFolderCacheUpsertResult(
      record: record,
      created: existing == null,
      previousItemCount: existing?.itemCount ?? 0,
    );
  }

  Future<SharedFolderCacheRecord> buildOwnerSelectionCache({
    required String ownerMacAddress,
    required List<String> filePaths,
    String? displayName,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final normalizedPaths =
        filePaths
            .map((path) => p.normalize(File(path).absolute.path))
            .toSet()
            .toList(growable: false)
          ..sort();

    if (normalizedPaths.isEmpty) {
      throw ArgumentError('filePaths must not be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final rootIdentity = normalizedPaths.join('|');
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootIdentity: rootIdentity,
    );

    final entries = <SharedFolderIndexEntry>[];
    for (var index = 0; index < normalizedPaths.length; index++) {
      final absolutePath = normalizedPaths[index];
      final file = File(absolutePath);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }

      final relativePath = p.basename(absolutePath);
      final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
        cacheId: cacheId,
        relativePath: relativePath,
        sourcePath: absolutePath,
        sizeBytes: stat.size,
        modifiedAtMs: stat.modified.millisecondsSinceEpoch,
      );
      entries.add(
        SharedFolderIndexEntry(
          relativePath: relativePath,
          sizeBytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
          absolutePath: absolutePath,
          thumbnailId: thumbnail?.thumbnailId,
        ),
      );
      if ((index + 1) % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (entries.isEmpty) {
      throw ArgumentError('None of the selected files are accessible.');
    }

    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );

    final resolvedDisplayName = _resolveDisplayName(
      providedName: displayName,
      fallbackPath: 'Selected files',
    );
    final cacheDir = await _database.resolveSharedCacheDirectory();
    final fileName = _createCacheFileName(
      role: SharedFolderCacheRole.owner,
      displayName: resolvedDisplayName,
      cacheId: cacheId,
    );
    final indexPath = p.join(cacheDir.path, fileName);

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: 'selection://$cacheId',
      displayName: resolvedDisplayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return record;
  }

  Future<SharedFolderCacheRecord> saveReceiverCache({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required String remoteFolderIdentity,
    required String remoteDisplayName,
    required List<SharedFolderIndexEntry> entries,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final receiverMac = _normalizeOrThrow(
      receiverMacAddress,
      field: 'receiverMacAddress',
    );
    final rootIdentity = remoteFolderIdentity.trim();
    if (rootIdentity.isEmpty) {
      throw ArgumentError('remoteFolderIdentity must not be empty.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final totalBytes = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final displayName = remoteDisplayName.trim().isEmpty
        ? 'Shared folder'
        : remoteDisplayName.trim();
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootIdentity: rootIdentity,
    );

    final cacheDir = await _database.resolveSharedCacheDirectory();
    final fileName = _createCacheFileName(
      role: SharedFolderCacheRole.receiver,
      displayName: displayName,
      cacheId: cacheId,
    );
    final indexPath = p.join(cacheDir.path, fileName);

    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootPath: rootIdentity,
      displayName: displayName,
      indexFilePath: indexPath,
      itemCount: entries.length,
      totalBytes: totalBytes,
      updatedAtMs: now,
    );

    await _writeIndexFile(record, entries);
    await _upsertRecord(record);
    return record;
  }

  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) async {
    final db = await _database.database;
    final filters = <String>[];
    final args = <Object?>[];

    if (role != null) {
      filters.add('role = ?');
      args.add(role.name);
    }
    if (ownerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(ownerMacAddress);
      if (normalized != null) {
        filters.add('owner_mac_address = ?');
        args.add(normalized);
      }
    }
    if (peerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(peerMacAddress);
      if (normalized != null) {
        filters.add('peer_mac_address = ?');
        args.add(normalized);
      }
    }

    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(SharedFolderCacheRecord.fromDbMap).toList(growable: false);
  }

  Future<SharedFolderCacheRecord?> findCacheById(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SharedFolderCacheRecord.fromDbMap(rows.first);
  }

  Future<SharedFolderCacheRecord?> findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) {
    return _findOwnerCacheByRootPath(
      ownerMacAddress: ownerMacAddress,
      rootPath: rootPath,
    );
  }

  Future<void> upsertCacheRecord(SharedFolderCacheRecord record) {
    return _upsertRecord(record);
  }

  Future<void> deleteCacheRecord(String cacheId) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
    );
  }

  Future<SharedFolderCacheRecord> refreshOwnerSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    if (!cache.rootPath.startsWith('selection://')) {
      return cache;
    }
    return _refreshSelectionCacheEntries(cache, onProgress: onProgress);
  }

  Future<SharedFolderCacheRecord> refreshOwnerFolderSubdirectoryEntries(
    SharedFolderCacheRecord cache, {
    required String relativeFolderPath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) async {
    if (cache.rootPath.startsWith('selection://')) {
      return cache;
    }

    final normalizedFolder = _normalizeRelativeFolderPath(relativeFolderPath);
    if (normalizedFolder.isEmpty) {
      final result = await upsertOwnerFolderCache(
        ownerMacAddress: cache.ownerMacAddress,
        folderPath: cache.rootPath,
        displayName: cache.displayName,
        parallelWorkers: parallelWorkers,
        onProgress: onProgress,
      );
      return result.record;
    }

    final root = Directory(cache.rootPath);
    if (!await root.exists()) {
      throw ArgumentError('Directory does not exist: ${cache.rootPath}');
    }

    final existingEntries = await readIndexEntries(cache.cacheId);
    final untouched = <SharedFolderIndexEntry>[];
    final previousScoped = <String, SharedFolderIndexEntry>{};
    for (final entry in existingEntries) {
      if (_isRelativePathWithinFolder(entry.relativePath, normalizedFolder)) {
        previousScoped[entry.relativePath] = entry;
      } else {
        untouched.add(entry);
      }
    }

    final scopedRootPath = p.join(cache.rootPath, normalizedFolder);
    final scopedRoot = Directory(scopedRootPath);
    List<SharedFolderIndexEntry> refreshedScopedEntries =
        const <SharedFolderIndexEntry>[];
    if (await scopedRoot.exists()) {
      refreshedScopedEntries = await _indexFolder(
        scopedRootPath,
        cacheId: cache.cacheId,
        previousEntriesByRelativePath: previousScoped,
        parallelWorkers: parallelWorkers,
        onProgress: onProgress,
        relativePrefix: normalizedFolder,
      );
    }

    final merged = <SharedFolderIndexEntry>[
      ...untouched,
      ...refreshedScopedEntries,
    ]..sort((a, b) => a.relativePath.compareTo(b.relativePath));

    final totalBytes = merged.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final updated = SharedFolderCacheRecord(
      cacheId: cache.cacheId,
      role: cache.role,
      ownerMacAddress: cache.ownerMacAddress,
      peerMacAddress: cache.peerMacAddress,
      rootPath: cache.rootPath,
      displayName: cache.displayName,
      indexFilePath: cache.indexFilePath,
      itemCount: merged.length,
      totalBytes: totalBytes,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _writeIndexFile(updated, merged);
    await _upsertRecord(updated);
    return updated;
  }

  Future<List<SharedFolderIndexEntry>> readIndexEntries(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      columns: <String>['index_file_path'],
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return <SharedFolderIndexEntry>[];
    }

    final path = rows.first['index_file_path'] as String?;
    if (path == null || path.isEmpty) {
      return <SharedFolderIndexEntry>[];
    }

    final file = File(path);
    if (!await file.exists()) {
      return <SharedFolderIndexEntry>[];
    }

    final content = await file.readAsString();
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    final rawEntries = (jsonMap['entries'] as List<dynamic>? ?? <dynamic>[]);
    return rawEntries
        .whereType<Map<String, dynamic>>()
        .map(SharedFolderIndexEntry.fromCompactJson)
        .toList(growable: false);
  }

  Future<Uint8List?> readOwnerThumbnailBytes({
    required String cacheId,
    required String thumbnailId,
  }) {
    return _thumbnailCacheService.readOwnerThumbnailBytes(
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
  }

  Future<String?> resolveReceiverThumbnailPath({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
  }) {
    return _thumbnailCacheService.resolveReceiverThumbnailPath(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
  }

  Future<String> saveReceiverThumbnailBytes({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
    required Uint8List bytes,
  }) {
    return _thumbnailCacheService.saveReceiverThumbnailBytes(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
      bytes: bytes,
    );
  }

  Future<void> deleteCache(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      columns: <String>['index_file_path', 'role', 'owner_mac_address'],
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );

    SharedFolderCacheRole? role;
    String? ownerMacAddress;
    if (rows.isNotEmpty) {
      final row = rows.first;
      final path = row['index_file_path'] as String?;
      final roleRaw = row['role'] as String?;
      ownerMacAddress = row['owner_mac_address'] as String?;
      if (roleRaw != null) {
        role = SharedFolderCacheRole.values.byName(roleRaw);
      }
      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }

    await db.delete(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
    );

    if (role == SharedFolderCacheRole.owner) {
      await _thumbnailCacheService.deleteOwnerCacheThumbnails(cacheId);
    } else if (role == SharedFolderCacheRole.receiver &&
        ownerMacAddress != null &&
        ownerMacAddress.isNotEmpty) {
      await _thumbnailCacheService.deleteReceiverCacheThumbnails(
        ownerMacAddress: ownerMacAddress,
        cacheId: cacheId,
      );
    }
  }

  Future<List<String>> pruneUnavailableOwnerCaches({
    required String ownerMacAddress,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final ownerCaches = await listCaches(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
    );
    if (ownerCaches.isEmpty) {
      return <String>[];
    }

    final removedCacheIds = <String>[];
    for (final cache in ownerCaches) {
      if (cache.rootPath.startsWith('selection://')) {
        final updatedSelection = await _refreshSelectionCacheEntries(cache);
        if (updatedSelection.itemCount == 0) {
          await deleteCache(cache.cacheId);
          removedCacheIds.add(cache.cacheId);
        }
        continue;
      }

      final root = Directory(cache.rootPath);
      if (!await root.exists()) {
        await deleteCache(cache.cacheId);
        removedCacheIds.add(cache.cacheId);
        continue;
      }

      try {
        await root.list(recursive: false, followLinks: false).take(1).drain();
      } catch (_) {
        await deleteCache(cache.cacheId);
        removedCacheIds.add(cache.cacheId);
      }
    }

    return removedCacheIds;
  }

  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress}) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final db = await _database.database;
    return db.update(
      AppDatabase.sharedFolderCachesTable,
      <String, Object?>{'owner_mac_address': ownerMac},
      where: 'role = ? AND owner_mac_address != ?',
      whereArgs: <Object?>[SharedFolderCacheRole.owner.name, ownerMac],
    );
  }

  Future<List<String>> pruneReceiverCachesForOwner({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required Set<String> activeCacheIds,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final receiverMac = _normalizeOrThrow(
      receiverMacAddress,
      field: 'receiverMacAddress',
    );

    final receiverCaches = await listCaches(
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
    );

    if (receiverCaches.isEmpty) {
      return <String>[];
    }

    final active = activeCacheIds.where((id) => id.trim().isNotEmpty).toSet();
    final removed = <String>[];
    for (final cache in receiverCaches) {
      if (active.contains(cache.cacheId)) {
        continue;
      }
      await deleteCache(cache.cacheId);
      removed.add(cache.cacheId);
    }
    return removed;
  }

  Future<SharedFolderCacheRecord> _refreshSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    final entries = await readIndexEntries(cache.cacheId);
    final normalized = <SharedFolderIndexEntry>[];
    var changed = false;
    final total = entries.length;
    var processed = 0;

    for (final entry in entries) {
      processed += 1;
      final absolutePath = entry.absolutePath;
      if (absolutePath == null || absolutePath.trim().isEmpty) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final file = File(absolutePath);
      if (!await file.exists()) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        changed = true;
        onProgress?.call(
          processedFiles: processed,
          totalFiles: total,
          relativePath: entry.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        continue;
      }

      final sizeBytes = stat.size;
      final modifiedAtMs = stat.modified.millisecondsSinceEpoch;
      String? thumbnailId = entry.thumbnailId;
      if (sizeBytes != entry.sizeBytes || modifiedAtMs != entry.modifiedAtMs) {
        changed = true;
        final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
          cacheId: cache.cacheId,
          relativePath: entry.relativePath,
          sourcePath: absolutePath,
          sizeBytes: sizeBytes,
          modifiedAtMs: modifiedAtMs,
        );
        thumbnailId = thumbnail?.thumbnailId;
      }

      normalized.add(
        SharedFolderIndexEntry(
          relativePath: entry.relativePath,
          sizeBytes: sizeBytes,
          modifiedAtMs: modifiedAtMs,
          absolutePath: absolutePath,
          thumbnailId: thumbnailId,
        ),
      );
      onProgress?.call(
        processedFiles: processed,
        totalFiles: total,
        relativePath: entry.relativePath,
        stage: OwnerCacheProgressStage.indexing,
      );
      if (processed % 20 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (!changed) {
      return cache;
    }

    final totalBytes = normalized.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );
    final updated = SharedFolderCacheRecord(
      cacheId: cache.cacheId,
      role: cache.role,
      ownerMacAddress: cache.ownerMacAddress,
      peerMacAddress: cache.peerMacAddress,
      rootPath: cache.rootPath,
      displayName: cache.displayName,
      indexFilePath: cache.indexFilePath,
      itemCount: normalized.length,
      totalBytes: totalBytes,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    await _writeIndexFile(updated, normalized);
    await _upsertRecord(updated);
    return updated;
  }

  Future<void> _upsertRecord(SharedFolderCacheRecord record) async {
    final db = await _database.database;
    await db.insert(
      AppDatabase.sharedFolderCachesTable,
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _writeIndexFile(
    SharedFolderCacheRecord record,
    List<SharedFolderIndexEntry> entries,
  ) async {
    final file = File(record.indexFilePath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }

    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'cacheId': record.cacheId,
      'role': record.role.name,
      'ownerMacAddress': record.ownerMacAddress,
      'peerMacAddress': record.peerMacAddress,
      'displayName': record.displayName,
      'rootPath': record.rootPath,
      'updatedAtMs': record.updatedAtMs,
      'entries': entries.map((entry) => entry.toCompactJson()).toList(),
    };

    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<List<SharedFolderIndexEntry>> _indexFolder(
    String rootPath, {
    required String cacheId,
    Map<String, SharedFolderIndexEntry>? previousEntriesByRelativePath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
    String relativePrefix = '',
  }) async {
    final root = Directory(rootPath);
    final normalizedPrefix = _normalizeRelativeFolderPath(relativePrefix);
    final probes = <_FolderProbeEntry>[];
    var discoveredFiles = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final stat = await entity.stat();
      if (stat.type != FileSystemEntityType.file) {
        continue;
      }
      final relativePath = p
          .relative(entity.path, from: rootPath)
          .replaceAll('\\', '/');
      final cacheRelativePath = normalizedPrefix.isEmpty
          ? relativePath
          : '$normalizedPrefix/$relativePath';
      probes.add(
        _FolderProbeEntry(
          sourcePath: entity.path,
          relativePath: cacheRelativePath,
          sizeBytes: stat.size,
          modifiedAtMs: stat.modified.millisecondsSinceEpoch,
        ),
      );
      final reportedPath = probes.last.relativePath;
      discoveredFiles += 1;
      if (discoveredFiles == 1 || discoveredFiles % 32 == 0) {
        onProgress?.call(
          processedFiles: discoveredFiles,
          totalFiles: 0,
          relativePath: reportedPath,
          stage: OwnerCacheProgressStage.scanning,
        );
      }
      if (discoveredFiles % 64 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    if (discoveredFiles > 0 && discoveredFiles % 32 != 0) {
      final relativePath = probes.last.relativePath;
      onProgress?.call(
        processedFiles: discoveredFiles,
        totalFiles: 0,
        relativePath: relativePath,
        stage: OwnerCacheProgressStage.scanning,
      );
    }

    final total = probes.length;
    if (total == 0) {
      return <SharedFolderIndexEntry>[];
    }

    final entries = List<SharedFolderIndexEntry?>.filled(
      total,
      null,
      growable: false,
    );
    final workerCount = _resolveParallelWorkerCount(
      total,
      overrideWorkers: parallelWorkers,
    );
    var nextIndex = 0;
    var processedCount = 0;

    Future<void> runWorker() async {
      while (true) {
        final index = nextIndex;
        if (index >= total) {
          return;
        }
        nextIndex += 1;

        final probe = probes[index];
        final previous = previousEntriesByRelativePath?[probe.relativePath];
        if (previous != null &&
            previous.sizeBytes == probe.sizeBytes &&
            previous.modifiedAtMs == probe.modifiedAtMs) {
          entries[index] = previous;
        } else {
          final thumbnail = await _thumbnailCacheService.ensureOwnerThumbnail(
            cacheId: cacheId,
            relativePath: probe.relativePath,
            sourcePath: probe.sourcePath,
            sizeBytes: probe.sizeBytes,
            modifiedAtMs: probe.modifiedAtMs,
          );
          entries[index] = SharedFolderIndexEntry(
            relativePath: probe.relativePath,
            sizeBytes: probe.sizeBytes,
            modifiedAtMs: probe.modifiedAtMs,
            thumbnailId: thumbnail?.thumbnailId,
          );
        }

        processedCount += 1;
        onProgress?.call(
          processedFiles: processedCount,
          totalFiles: total,
          relativePath: probe.relativePath,
          stage: OwnerCacheProgressStage.indexing,
        );
        if (processedCount % 20 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => runWorker()),
    );

    final completedEntries = entries.whereType<SharedFolderIndexEntry>().toList(
      growable: false,
    );

    if (completedEntries.length != total) {
      throw StateError(
        'Folder indexing did not complete for all files '
        '($total expected, ${completedEntries.length} collected).',
      );
    }

    final sortedEntries = List<SharedFolderIndexEntry>.from(completedEntries);
    sortedEntries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return sortedEntries;
  }

  String _normalizeRelativeFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  bool _isRelativePathWithinFolder(String relativePath, String folderPath) {
    final normalizedRelative = _normalizeRelativeFolderPath(relativePath);
    final normalizedFolder = _normalizeRelativeFolderPath(folderPath);
    if (normalizedFolder.isEmpty) {
      return true;
    }
    return normalizedRelative == normalizedFolder ||
        normalizedRelative.startsWith('$normalizedFolder/');
  }

  int _resolveParallelWorkerCount(int totalFiles, {int? overrideWorkers}) {
    if (totalFiles <= 1) {
      return 1;
    }
    if (overrideWorkers != null && overrideWorkers > 0) {
      final capped = math.max(
        1,
        math.min(overrideWorkers, Platform.numberOfProcessors),
      );
      return math.min(totalFiles, capped);
    }
    // Auto mode: keep one logical core free for UI/system responsiveness.
    final availableWorkers = math.max(2, Platform.numberOfProcessors - 1);
    return math.min(totalFiles, availableWorkers);
  }

  String _resolveDisplayName({
    required String? providedName,
    required String fallbackPath,
  }) {
    final candidate = providedName?.trim() ?? '';
    if (candidate.isNotEmpty) {
      return candidate;
    }
    final normalized = p.normalize(fallbackPath);
    final baseName = p.basename(normalized);
    return baseName.isEmpty ? 'Shared folder' : baseName;
  }

  Future<SharedFolderCacheRecord?> _findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: 'role = ? AND owner_mac_address = ?',
      whereArgs: <Object?>[SharedFolderCacheRole.owner.name, ownerMacAddress],
    );
    if (rows.isEmpty) {
      return null;
    }

    final target = _normalizeComparablePath(rootPath);
    for (final row in rows) {
      final record = SharedFolderCacheRecord.fromDbMap(row);
      if (record.rootPath.startsWith('selection://')) {
        continue;
      }
      if (_normalizeComparablePath(record.rootPath) == target) {
        return record;
      }
    }
    return null;
  }

  Future<String> _normalizeExistingDirectoryPath(Directory directory) async {
    try {
      final resolved = await directory.resolveSymbolicLinks();
      return p.normalize(resolved);
    } catch (_) {
      return p.normalize(directory.absolute.path);
    }
  }

  String _normalizeComparablePath(String rawPath) {
    final normalized = p.normalize(rawPath).replaceAll('\\', '/');
    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  String _createCacheId({
    required SharedFolderCacheRole role,
    required String ownerMacAddress,
    required String? peerMacAddress,
    required String rootIdentity,
  }) {
    final raw = <String>[
      'v$_schemaVersion',
      role.name,
      ownerMacAddress,
      peerMacAddress ?? '-',
      rootIdentity.replaceAll('\\', '/').trim().toLowerCase(),
    ].join('|');
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'v${_schemaVersion}_$digest';
  }

  String _createCacheFileName({
    required SharedFolderCacheRole role,
    required String displayName,
    required String cacheId,
  }) {
    final sanitized = _sanitizeFileToken(displayName);
    return '${role.name}_${sanitized}_$cacheId.landa-cache.json';
  }

  String _sanitizeFileToken(String input) {
    final normalized = input.trim().toLowerCase();
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final collapsed = safe
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (collapsed.isEmpty) {
      return 'folder';
    }
    return collapsed.length > 24 ? collapsed.substring(0, 24) : collapsed;
  }

  String _normalizeOrThrow(String macAddress, {required String field}) {
    final normalized = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalized == null) {
      throw ArgumentError('Invalid $field: $macAddress');
    }
    return normalized;
  }
}

class _FolderProbeEntry {
  const _FolderProbeEntry({
    required this.sourcePath,
    required this.relativePath,
    required this.sizeBytes,
    required this.modifiedAtMs,
  });

  final String sourcePath;
  final String relativePath;
  final int sizeBytes;
  final int modifiedAtMs;
}

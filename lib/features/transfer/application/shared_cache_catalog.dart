import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../discovery/data/device_alias_repository.dart';
import '../data/shared_folder_cache_repository.dart';
import '../domain/shared_folder_cache.dart';
import 'shared_cache_index_store.dart';

class OwnerCacheCatalogLoadResult {
  const OwnerCacheCatalogLoadResult({
    required this.ownerCaches,
    required this.reboundCount,
  });

  final List<SharedFolderCacheRecord> ownerCaches;
  final int reboundCount;
}

class SharedCacheCatalog extends ChangeNotifier {
  SharedCacheCatalog({
    required SharedFolderCacheRepository sharedFolderCacheRepository,
    required SharedCacheIndexStore sharedCacheIndexStore,
  }) : _sharedFolderCacheRepository = sharedFolderCacheRepository,
       _sharedCacheIndexStore = sharedCacheIndexStore;

  final SharedFolderCacheRepository _sharedFolderCacheRepository;
  final SharedCacheIndexStore _sharedCacheIndexStore;

  List<SharedFolderCacheRecord> _ownerCaches =
      const <SharedFolderCacheRecord>[];
  String? _loadedOwnerMacAddress;

  List<SharedFolderCacheRecord> get ownerCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerCaches);

  Future<OwnerCacheCatalogLoadResult> loadOwnerCaches({
    required String ownerMacAddress,
    bool rebindOwnerCachesToMac = false,
  }) async {
    var reboundCount = 0;
    if (rebindOwnerCachesToMac) {
      reboundCount = await _sharedFolderCacheRepository.rebindOwnerCachesToMac(
        ownerMacAddress: ownerMacAddress,
      );
    }
    final caches = await _sharedFolderCacheRepository.listCaches(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMacAddress,
    );
    _loadedOwnerMacAddress = _normalizeMacKey(ownerMacAddress);
    _replaceOwnerCaches(caches);
    return OwnerCacheCatalogLoadResult(
      ownerCaches: ownerCaches,
      reboundCount: reboundCount,
    );
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
    final normalizedRoot = await _sharedCacheIndexStore
        .normalizeExistingDirectoryPath(folderPath);
    final existing = await _sharedFolderCacheRepository
        .findOwnerCacheByRootPath(
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
    final indexFilePath =
        existing?.indexFilePath ??
        await _sharedCacheIndexStore.resolveIndexFilePath(
          role: SharedFolderCacheRole.owner,
          displayName: resolvedDisplayName,
          cacheId: cacheId,
        );

    final draftRecord = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: normalizedRoot,
      displayName: resolvedDisplayName,
      indexFilePath: indexFilePath,
      itemCount: existing?.itemCount ?? 0,
      totalBytes: existing?.totalBytes ?? 0,
      updatedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final indexResult = await _sharedCacheIndexStore
        .materializeOwnerFolderIndex(
          record: draftRecord,
          folderPath: normalizedRoot,
          parallelWorkers: parallelWorkers,
          onProgress: onProgress,
        );
    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: normalizedRoot,
      displayName: resolvedDisplayName,
      indexFilePath: indexFilePath,
      itemCount: indexResult.itemCount,
      totalBytes: indexResult.totalBytes,
      updatedAtMs: draftRecord.updatedAtMs,
    );

    await _sharedFolderCacheRepository.upsertCacheRecord(record);
    _upsertLoadedOwnerCache(record);
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
            .where((path) => path.trim().isNotEmpty)
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
    final resolvedDisplayName = _resolveDisplayName(
      providedName: displayName,
      fallbackPath: 'Selected files',
    );
    final indexFilePath = await _sharedCacheIndexStore.resolveIndexFilePath(
      role: SharedFolderCacheRole.owner,
      displayName: resolvedDisplayName,
      cacheId: cacheId,
    );
    final draftRecord = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: 'selection://$cacheId',
      displayName: resolvedDisplayName,
      indexFilePath: indexFilePath,
      itemCount: 0,
      totalBytes: 0,
      updatedAtMs: now,
    );
    final indexResult = await _sharedCacheIndexStore
        .materializeOwnerSelectionIndex(
          record: draftRecord,
          filePaths: normalizedPaths,
        );
    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
      peerMacAddress: null,
      rootPath: 'selection://$cacheId',
      displayName: resolvedDisplayName,
      indexFilePath: indexFilePath,
      itemCount: indexResult.itemCount,
      totalBytes: indexResult.totalBytes,
      updatedAtMs: now,
    );

    await _sharedFolderCacheRepository.upsertCacheRecord(record);
    _upsertLoadedOwnerCache(record);
    return record;
  }

  Future<SharedFolderCacheRecord> refreshOwnerSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    if (!cache.rootPath.startsWith('selection://')) {
      return cache;
    }

    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final draftRecord = _rebuildRecord(
      cache,
      itemCount: cache.itemCount,
      totalBytes: cache.totalBytes,
      updatedAtMs: updatedAtMs,
    );
    final indexResult = await _sharedCacheIndexStore.refreshOwnerSelectionIndex(
      draftRecord,
      onProgress: onProgress,
    );
    if (!indexResult.changed) {
      return cache;
    }
    final updated = _rebuildRecord(
      cache,
      itemCount: indexResult.itemCount,
      totalBytes: indexResult.totalBytes,
      updatedAtMs: updatedAtMs,
    );
    await _sharedFolderCacheRepository.upsertCacheRecord(updated);
    _upsertLoadedOwnerCache(updated);
    return updated;
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

    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final draftRecord = _rebuildRecord(
      cache,
      itemCount: cache.itemCount,
      totalBytes: cache.totalBytes,
      updatedAtMs: updatedAtMs,
    );
    final indexResult = await _sharedCacheIndexStore
        .refreshOwnerFolderSubdirectoryIndex(
          draftRecord,
          relativeFolderPath: normalizedFolder,
          parallelWorkers: parallelWorkers,
          onProgress: onProgress,
        );
    final updated = _rebuildRecord(
      cache,
      itemCount: indexResult.itemCount,
      totalBytes: indexResult.totalBytes,
      updatedAtMs: updatedAtMs,
    );
    await _sharedFolderCacheRepository.upsertCacheRecord(updated);
    _upsertLoadedOwnerCache(updated);
    return updated;
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
    final displayName = remoteDisplayName.trim().isEmpty
        ? 'Shared folder'
        : remoteDisplayName.trim();
    final cacheId = _createCacheId(
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootIdentity: rootIdentity,
    );
    final indexFilePath = await _sharedCacheIndexStore.resolveIndexFilePath(
      role: SharedFolderCacheRole.receiver,
      displayName: displayName,
      cacheId: cacheId,
    );
    final draftRecord = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootPath: rootIdentity,
      displayName: displayName,
      indexFilePath: indexFilePath,
      itemCount: entries.length,
      totalBytes: 0,
      updatedAtMs: now,
    );
    final indexResult = await _sharedCacheIndexStore.materializeReceiverIndex(
      record: draftRecord,
      entries: entries,
    );
    final record = SharedFolderCacheRecord(
      cacheId: cacheId,
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: ownerMac,
      peerMacAddress: receiverMac,
      rootPath: rootIdentity,
      displayName: displayName,
      indexFilePath: indexFilePath,
      itemCount: indexResult.itemCount,
      totalBytes: indexResult.totalBytes,
      updatedAtMs: now,
    );

    await _sharedFolderCacheRepository.upsertCacheRecord(record);
    return record;
  }

  Future<List<SharedFolderCacheRecord>> listReceiverCaches({
    required String receiverMacAddress,
    String? ownerMacAddress,
  }) async {
    final receiverMac = _normalizeOrThrow(
      receiverMacAddress,
      field: 'receiverMacAddress',
    );
    final normalizedOwnerMac = ownerMacAddress == null
        ? null
        : _normalizeOrThrow(ownerMacAddress, field: 'ownerMacAddress');
    return _sharedFolderCacheRepository.listCaches(
      role: SharedFolderCacheRole.receiver,
      ownerMacAddress: normalizedOwnerMac,
      peerMacAddress: receiverMac,
    );
  }

  Future<void> deleteCache(String cacheId) async {
    final record = await _sharedFolderCacheRepository.findCacheById(cacheId);
    if (record != null) {
      await _sharedCacheIndexStore.deleteIndexArtifacts(record);
    }
    await _sharedFolderCacheRepository.deleteCacheRecord(cacheId);
    final next = _ownerCaches
        .where((cache) => cache.cacheId != cacheId)
        .toList(growable: false);
    _replaceOwnerCaches(next);
  }

  Future<List<String>> pruneUnavailableOwnerCaches({
    required String ownerMacAddress,
  }) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final ownerCaches = await _sharedFolderCacheRepository.listCaches(
      role: SharedFolderCacheRole.owner,
      ownerMacAddress: ownerMac,
    );
    if (ownerCaches.isEmpty) {
      return <String>[];
    }

    final removedCacheIds = <String>[];
    for (final cache in ownerCaches) {
      if (cache.rootPath.startsWith('selection://')) {
        final updatedSelection = await refreshOwnerSelectionCacheEntries(cache);
        if (updatedSelection.itemCount == 0) {
          await deleteCache(cache.cacheId);
          removedCacheIds.add(cache.cacheId);
        }
        continue;
      }

      final root = p.normalize(cache.rootPath);
      final directory = Directory(root);
      if (!await directory.exists()) {
        await deleteCache(cache.cacheId);
        removedCacheIds.add(cache.cacheId);
        continue;
      }

      try {
        await directory
            .list(recursive: false, followLinks: false)
            .take(1)
            .drain();
      } catch (_) {
        await deleteCache(cache.cacheId);
        removedCacheIds.add(cache.cacheId);
      }
    }

    return removedCacheIds;
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
    final receiverCaches = await _sharedFolderCacheRepository.listCaches(
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

  void _upsertLoadedOwnerCache(SharedFolderCacheRecord record) {
    if (record.role != SharedFolderCacheRole.owner) {
      return;
    }
    final normalizedOwnerMac = _normalizeMacKey(record.ownerMacAddress);
    _loadedOwnerMacAddress ??= normalizedOwnerMac;
    if (_loadedOwnerMacAddress != normalizedOwnerMac) {
      return;
    }
    final next = _ownerCaches.toList(growable: true);
    final existingIndex = next.indexWhere(
      (candidate) => candidate.cacheId == record.cacheId,
    );
    if (existingIndex >= 0) {
      next[existingIndex] = record;
    } else {
      next.add(record);
    }
    next.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    _replaceOwnerCaches(next);
  }

  void _replaceOwnerCaches(List<SharedFolderCacheRecord> caches) {
    _ownerCaches = List<SharedFolderCacheRecord>.unmodifiable(caches);
    notifyListeners();
  }

  SharedFolderCacheRecord _rebuildRecord(
    SharedFolderCacheRecord record, {
    required int itemCount,
    required int totalBytes,
    required int updatedAtMs,
  }) {
    return SharedFolderCacheRecord(
      cacheId: record.cacheId,
      role: record.role,
      ownerMacAddress: record.ownerMacAddress,
      peerMacAddress: record.peerMacAddress,
      rootPath: record.rootPath,
      displayName: record.displayName,
      indexFilePath: record.indexFilePath,
      itemCount: itemCount,
      totalBytes: totalBytes,
      updatedAtMs: updatedAtMs,
    );
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

  String _normalizeRelativeFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  String _createCacheId({
    required SharedFolderCacheRole role,
    required String ownerMacAddress,
    required String? peerMacAddress,
    required String rootIdentity,
  }) {
    final raw = <String>[
      'v${SharedCacheIndexStore.schemaVersion}',
      role.name,
      ownerMacAddress,
      peerMacAddress ?? '-',
      rootIdentity.replaceAll('\\', '/').trim().toLowerCase(),
    ].join('|');
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'v${SharedCacheIndexStore.schemaVersion}_$digest';
  }

  String _normalizeMacKey(String value) {
    return value.trim().toLowerCase().replaceAll('-', ':');
  }

  String _normalizeOrThrow(String macAddress, {required String field}) {
    final normalized = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalized == null) {
      throw ArgumentError('Invalid $field: $macAddress');
    }
    return normalized;
  }
}

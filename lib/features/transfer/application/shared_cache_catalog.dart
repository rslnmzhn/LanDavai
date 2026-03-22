import 'package:flutter/foundation.dart';

import '../data/shared_folder_cache_repository.dart';
import '../domain/shared_folder_cache.dart';

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
  }) : _sharedFolderCacheRepository = sharedFolderCacheRepository;

  final SharedFolderCacheRepository _sharedFolderCacheRepository;

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
    final result = await _sharedFolderCacheRepository.upsertOwnerFolderCache(
      ownerMacAddress: ownerMacAddress,
      folderPath: folderPath,
      displayName: displayName,
      parallelWorkers: parallelWorkers,
      onProgress: onProgress,
    );
    _upsertLoadedOwnerCache(result.record);
    return result;
  }

  Future<SharedFolderCacheRecord> buildOwnerSelectionCache({
    required String ownerMacAddress,
    required List<String> filePaths,
    String? displayName,
  }) async {
    final record = await _sharedFolderCacheRepository.buildOwnerSelectionCache(
      ownerMacAddress: ownerMacAddress,
      filePaths: filePaths,
      displayName: displayName,
    );
    _upsertLoadedOwnerCache(record);
    return record;
  }

  Future<SharedFolderCacheRecord> refreshOwnerSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    final updated = await _sharedFolderCacheRepository
        .refreshOwnerSelectionCacheEntries(cache, onProgress: onProgress);
    _upsertLoadedOwnerCache(updated);
    return updated;
  }

  Future<SharedFolderCacheRecord> refreshOwnerFolderSubdirectoryEntries(
    SharedFolderCacheRecord cache, {
    required String relativeFolderPath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) async {
    final updated = await _sharedFolderCacheRepository
        .refreshOwnerFolderSubdirectoryEntries(
          cache,
          relativeFolderPath: relativeFolderPath,
          parallelWorkers: parallelWorkers,
          onProgress: onProgress,
        );
    _upsertLoadedOwnerCache(updated);
    return updated;
  }

  Future<SharedFolderCacheRecord> saveReceiverCache({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required String remoteFolderIdentity,
    required String remoteDisplayName,
    required List<SharedFolderIndexEntry> entries,
  }) {
    return _sharedFolderCacheRepository.saveReceiverCache(
      ownerMacAddress: ownerMacAddress,
      receiverMacAddress: receiverMacAddress,
      remoteFolderIdentity: remoteFolderIdentity,
      remoteDisplayName: remoteDisplayName,
      entries: entries,
    );
  }

  Future<void> deleteCache(String cacheId) async {
    await _sharedFolderCacheRepository.deleteCache(cacheId);
    final next = _ownerCaches
        .where((cache) => cache.cacheId != cacheId)
        .toList(growable: false);
    _replaceOwnerCaches(next);
  }

  Future<List<String>> pruneUnavailableOwnerCaches({
    required String ownerMacAddress,
  }) async {
    final removed = await _sharedFolderCacheRepository
        .pruneUnavailableOwnerCaches(ownerMacAddress: ownerMacAddress);
    if (_loadedOwnerMacAddress == _normalizeMacKey(ownerMacAddress)) {
      await loadOwnerCaches(ownerMacAddress: ownerMacAddress);
    }
    return removed;
  }

  Future<List<String>> pruneReceiverCachesForOwner({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required Set<String> activeCacheIds,
  }) {
    return _sharedFolderCacheRepository.pruneReceiverCachesForOwner(
      ownerMacAddress: ownerMacAddress,
      receiverMacAddress: receiverMacAddress,
      activeCacheIds: activeCacheIds,
    );
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

  String _normalizeMacKey(String value) {
    return value.trim().toLowerCase().replaceAll('-', ':');
  }
}

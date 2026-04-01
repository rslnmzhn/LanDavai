import '../domain/shared_folder_cache.dart';

/// Thin row-persistence port for shared cache records.
///
/// Index materialization and thumbnail artifacts stay with their dedicated
/// collaborators.
abstract class SharedCacheRecordStore {
  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  });

  Future<SharedFolderCacheRecord?> findCacheById(String cacheId);

  Future<SharedFolderCacheRecord?> findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  });

  Future<void> upsertCacheRecord(SharedFolderCacheRecord record);

  Future<void> deleteCacheRecord(String cacheId);

  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress});
}

import '../domain/shared_folder_cache.dart';

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

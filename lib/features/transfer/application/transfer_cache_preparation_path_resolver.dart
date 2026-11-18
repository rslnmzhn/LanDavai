import 'package:path/path.dart' as p;

import '../domain/shared_folder_cache.dart';

class TransferCachePreparationPathResolver {
  const TransferCachePreparationPathResolver();

  String? resolve({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
  }) {
    if (cache.rootPath.startsWith('selection://')) {
      return entry.absolutePath;
    }
    final localRelative = entry.relativePath.replaceAll('/', p.separator);
    return p.join(cache.rootPath, localRelative);
  }
}

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
    final normalizedRoot = p.normalize(cache.rootPath);
    final rawSegments = entry.relativePath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (rawSegments.isEmpty ||
        rawSegments.any((part) => part == '.' || part == '..')) {
      return null;
    }
    final candidate = p.normalize(p.joinAll(<String>[normalizedRoot, ...rawSegments]));
    if (!p.isWithin(normalizedRoot, candidate)) {
      return null;
    }
    return candidate;
  }
}

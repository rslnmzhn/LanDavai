import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/data/thumbnail_cache_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import 'discovery_controller.dart'
    show
        ShareableLocalDirectoryListing,
        ShareableLocalFile,
        ShareableLocalFolder,
        ShareableVideoFile,
        SharedCacheSummary;

/// Temporary Phase 5 bridge that serves owner-backed shared-cache reads while
/// controller mirrors remain in place for compatibility until workpack 12.
class SharedCacheCatalogBridge {
  SharedCacheCatalogBridge({
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required String Function() ownerMacAddressProvider,
  }) : _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _ownerMacAddressProvider = ownerMacAddressProvider;

  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final String Function() _ownerMacAddressProvider;

  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    final caches = await _loadOwnerCaches();
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    if (normalizedFolder.isEmpty) {
      return _buildSharedCacheSummary(caches);
    }
    final targets = await _resolveScopedTargets(
      caches: caches,
      virtualFolderPath: normalizedFolder,
    );
    return _buildScopedSharedCacheSummary(targets);
  }

  Future<List<ShareableVideoFile>> listShareableVideoFiles({
    String? cacheId,
  }) async {
    final caches = await _loadOwnerCaches();
    final files = <ShareableVideoFile>[];
    for (final cache in caches) {
      if (cacheId != null && cache.cacheId != cacheId) {
        continue;
      }
      final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
      for (final entry in entries) {
        if (!_isVideoPath(entry.relativePath)) {
          continue;
        }
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }
        final file = File(absolutePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        files.add(
          ShareableVideoFile(
            id: '${cache.cacheId}|${entry.relativePath}',
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            absolutePath: absolutePath,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    files.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  Future<ShareableLocalDirectoryListing> listShareableLocalDirectory({
    required String virtualFolderPath,
  }) async {
    final caches = await _loadOwnerCaches();
    final folder = _normalizeVirtualFolderPath(virtualFolderPath);
    final foldersByPath = <String, ShareableLocalFolder>{};
    final files = <ShareableLocalFile>[];
    final seenFilePaths = <String>{};
    var processed = 0;

    for (final cache in caches) {
      final isSelection = cache.rootPath.startsWith('selection://');
      final cacheVirtualRoot = _normalizeVirtualFolderPath(cache.displayName);

      if (folder.isEmpty && !isSelection) {
        if (cacheVirtualRoot.isNotEmpty) {
          final key = Platform.isWindows
              ? cacheVirtualRoot.toLowerCase()
              : cacheVirtualRoot;
          foldersByPath.putIfAbsent(
            key,
            () => ShareableLocalFolder(
              name: cache.displayName,
              virtualPath: cacheVirtualRoot,
              removableSharedCacheId: cache.cacheId,
            ),
          );
        }
        continue;
      }

      if (!isSelection &&
          folder != cacheVirtualRoot &&
          !folder.startsWith('$cacheVirtualRoot/')) {
        continue;
      }
      if (isSelection && folder.isNotEmpty) {
        continue;
      }

      final subFolder = !isSelection && folder != cacheVirtualRoot
          ? folder.substring(cacheVirtualRoot.length + 1)
          : '';
      final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
      for (final entry in entries) {
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }

        final virtualPath = _buildShareVirtualPath(cache: cache, entry: entry);
        final relativeInsideCache = isSelection
            ? _normalizeVirtualFolderPath(virtualPath)
            : _normalizeVirtualFolderPath(entry.relativePath);
        final rest = _relativeRestForFolder(
          folder: subFolder,
          targetPath: relativeInsideCache,
        );
        if (rest == null || rest.isEmpty) {
          continue;
        }

        final slashIndex = rest.indexOf('/');
        if (!isSelection && slashIndex != -1) {
          final folderName = rest.substring(0, slashIndex);
          final folderPath = folder.isEmpty
              ? folderName
              : '$folder/$folderName';
          final normalizedFolderPath = _normalizeVirtualFolderPath(folderPath);
          final dedupeKey = Platform.isWindows
              ? normalizedFolderPath.toLowerCase()
              : normalizedFolderPath;
          foldersByPath.putIfAbsent(
            dedupeKey,
            () => ShareableLocalFolder(
              name: folderName,
              virtualPath: normalizedFolderPath,
            ),
          );
          continue;
        }

        final normalizedPath = p.normalize(absolutePath).replaceAll('\\', '/');
        final fileKey = Platform.isWindows
            ? normalizedPath.toLowerCase()
            : normalizedPath;
        if (!seenFilePaths.add(fileKey)) {
          continue;
        }

        files.add(
          ShareableLocalFile(
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            virtualPath: virtualPath,
            absolutePath: absolutePath,
            sizeBytes: entry.sizeBytes,
            modifiedAtMs: entry.modifiedAtMs,
            isSelectionCache: isSelection,
          ),
        );
        processed += 1;
        if (processed % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }

    final folders = foldersByPath.values.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    files.sort((a, b) {
      final nameCmp = p
          .basename(a.virtualPath)
          .toLowerCase()
          .compareTo(p.basename(b.virtualPath).toLowerCase());
      if (nameCmp != 0) {
        return nameCmp;
      }
      return a.virtualPath.toLowerCase().compareTo(b.virtualPath.toLowerCase());
    });

    return ShareableLocalDirectoryListing(folders: folders, files: files);
  }

  Future<List<SharedFolderCacheRecord>> _loadOwnerCaches() async {
    final ownerMacAddress = _ownerMacAddressProvider().trim();
    if (ownerMacAddress.isNotEmpty) {
      try {
        await _sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: ownerMacAddress,
        );
      } catch (_) {
        // Keep using the last loaded owner snapshot until mirror removal lands.
      }
    }
    return _sharedCacheCatalog.ownerCaches;
  }

  Future<List<_ScopedSharedCacheTarget>> _resolveScopedTargets({
    required List<SharedFolderCacheRecord> caches,
    required String virtualFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(virtualFolderPath);
    final targets = <_ScopedSharedCacheTarget>[];
    for (final cache in caches) {
      final isSelection = cache.rootPath.startsWith('selection://');
      if (isSelection) {
        if (normalizedFolder.isNotEmpty) {
          continue;
        }
        targets.add(
          _ScopedSharedCacheTarget(
            cache: cache,
            relativeFolderPath: '',
            estimatedFileCount: math.max(cache.itemCount, 0),
          ),
        );
        continue;
      }

      final cacheVirtualRoot = _normalizeVirtualFolderPath(cache.displayName);
      if (normalizedFolder.isNotEmpty &&
          normalizedFolder != cacheVirtualRoot &&
          !normalizedFolder.startsWith('$cacheVirtualRoot/')) {
        continue;
      }

      final relativeFolderPath =
          normalizedFolder.isEmpty || normalizedFolder == cacheVirtualRoot
          ? ''
          : normalizedFolder.substring(cacheVirtualRoot.length + 1);

      var estimatedFiles = math.max(cache.itemCount, 0);
      if (relativeFolderPath.isNotEmpty) {
        estimatedFiles = await _countFilesInCacheFolder(
          cache: cache,
          relativeFolderPath: relativeFolderPath,
        );
      }

      targets.add(
        _ScopedSharedCacheTarget(
          cache: cache,
          relativeFolderPath: relativeFolderPath,
          estimatedFileCount: estimatedFiles,
        ),
      );
    }
    return targets;
  }

  Future<int> _countFilesInCacheFolder({
    required SharedFolderCacheRecord cache,
    required String relativeFolderPath,
  }) async {
    final normalizedFolder = _normalizeVirtualFolderPath(relativeFolderPath);
    final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
    if (normalizedFolder.isEmpty) {
      return entries.length;
    }
    var count = 0;
    for (final entry in entries) {
      if (_isCacheEntryWithinFolder(entry.relativePath, normalizedFolder)) {
        count += 1;
      }
    }
    return count;
  }

  SharedCacheSummary _buildSharedCacheSummary(
    List<SharedFolderCacheRecord> caches,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final cache in caches) {
      totalFiles += cache.itemCount;
      if (cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: caches.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  SharedCacheSummary _buildScopedSharedCacheSummary(
    List<_ScopedSharedCacheTarget> targets,
  ) {
    var folderCaches = 0;
    var selectionCaches = 0;
    var totalFiles = 0;
    for (final target in targets) {
      totalFiles += math.max(target.estimatedFileCount, 0);
      if (target.cache.rootPath.startsWith('selection://')) {
        selectionCaches += 1;
      } else {
        folderCaches += 1;
      }
    }
    return SharedCacheSummary(
      totalCaches: targets.length,
      folderCaches: folderCaches,
      selectionCaches: selectionCaches,
      totalFiles: totalFiles,
    );
  }

  bool _isCacheEntryWithinFolder(String relativePath, String folderPath) {
    final normalizedRelative = _normalizeVirtualFolderPath(relativePath);
    final normalizedFolder = _normalizeVirtualFolderPath(folderPath);
    if (normalizedFolder.isEmpty) {
      return true;
    }
    return normalizedRelative == normalizedFolder ||
        normalizedRelative.startsWith('$normalizedFolder/');
  }

  bool _isVideoPath(String relativePath) {
    return ThumbnailCacheService.videoExtensions.contains(
      p.extension(relativePath).toLowerCase(),
    );
  }

  String _buildShareVirtualPath({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
  }) {
    final normalizedRelative = _normalizeVirtualFolderPath(entry.relativePath);
    if (cache.rootPath.startsWith('selection://')) {
      return p.basename(normalizedRelative);
    }
    final cacheRoot = _normalizeVirtualFolderPath(cache.displayName);
    if (cacheRoot.isEmpty) {
      return normalizedRelative;
    }
    if (normalizedRelative.isEmpty) {
      return cacheRoot;
    }
    return '$cacheRoot/$normalizedRelative';
  }

  String _normalizeVirtualFolderPath(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  String? _relativeRestForFolder({
    required String folder,
    required String targetPath,
  }) {
    if (folder.isEmpty) {
      return targetPath;
    }
    if (targetPath == folder) {
      return '';
    }
    if (!targetPath.startsWith('$folder/')) {
      return null;
    }
    return targetPath.substring(folder.length + 1);
  }

  String? _resolveCacheFilePath({
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

class _ScopedSharedCacheTarget {
  const _ScopedSharedCacheTarget({
    required this.cache,
    required this.relativeFolderPath,
    required this.estimatedFileCount,
  });

  final SharedFolderCacheRecord cache;
  final String relativeFolderPath;
  final int estimatedFileCount;
}

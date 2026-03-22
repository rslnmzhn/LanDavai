import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_spacing.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../application/file_explorer_contract.dart';
import '../application/files_feature_state_owner.dart';
import 'file_explorer_page.dart';

/// Temporary Phase 6 bridge that keeps the file-explorer entry surface stable
/// while explorer state ownership moves into [FilesFeatureStateOwner].
class FileExplorerFacade extends StatefulWidget {
  const FileExplorerFacade({
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.ownerMacAddressProvider,
    required this.receiveDirectoryPath,
    this.publicDownloadsDirectoryPath,
    this.onRecacheSharedFolders,
    this.onRemoveSharedCache,
    this.recacheStateListenable,
    this.isSharedRecacheInProgress,
    this.sharedRecacheProgress,
    this.sharedRecacheDetails,
    super.key,
  });

  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final String Function() ownerMacAddressProvider;
  final String receiveDirectoryPath;
  final String? publicDownloadsDirectoryPath;
  final Future<SharedRecacheActionResult> Function(String virtualFolderPath)?
  onRecacheSharedFolders;
  final Future<bool> Function(String cacheId, String cacheLabel)?
  onRemoveSharedCache;
  final Listenable? recacheStateListenable;
  final bool Function()? isSharedRecacheInProgress;
  final double? Function()? sharedRecacheProgress;
  final SharedRecacheProgressDetails? Function()? sharedRecacheDetails;

  @override
  State<FileExplorerFacade> createState() => _FileExplorerFacadeState();
}

class _FileExplorerFacadeState extends State<FileExplorerFacade> {
  FilesFeatureStateOwner? _owner;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _owner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = _owner;
    if (owner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Files')),
        body: Center(
          child: _errorMessage == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_errorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: _initialize,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return FileExplorerPage(
      owner: owner,
      onRecacheSharedFolders: widget.onRecacheSharedFolders,
      onRemoveSharedCache: widget.onRemoveSharedCache,
      recacheStateListenable: widget.recacheStateListenable,
      isSharedRecacheInProgress: widget.isSharedRecacheInProgress,
      sharedRecacheProgress: widget.sharedRecacheProgress,
      sharedRecacheDetails: widget.sharedRecacheDetails,
    );
  }

  Future<void> _initialize() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      final roots = await _buildRoots();
      final nextOwner = FilesFeatureStateOwner(roots: roots);
      await nextOwner.initialize();
      if (!mounted) {
        nextOwner.dispose();
        return;
      }
      final previousOwner = _owner;
      setState(() {
        _owner = nextOwner;
      });
      previousOwner?.dispose();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open files: $error';
      });
    }
  }

  Future<List<FileExplorerRoot>> _buildRoots() async {
    final roots = <FileExplorerRoot>[];
    final seenPaths = <String>{};

    void addLocalRoot({required String label, required String path}) {
      final normalized = _normalizePathKey(path);
      if (normalized.isEmpty || seenPaths.contains(normalized)) {
        return;
      }
      if (!Directory(path).existsSync()) {
        return;
      }
      seenPaths.add(normalized);
      roots.add(FileExplorerRoot(label: label, path: path));
    }

    final publicDownloadsPath = widget.publicDownloadsDirectoryPath?.trim();
    if (publicDownloadsPath != null && publicDownloadsPath.isNotEmpty) {
      addLocalRoot(label: 'Landa Downloads', path: publicDownloadsPath);
    }
    addLocalRoot(label: 'Incoming', path: widget.receiveDirectoryPath);

    final ownerCaches = await _loadOwnerCaches();
    final hasSharedFiles = ownerCaches.any((cache) => cache.itemCount > 0);
    if (hasSharedFiles) {
      roots.add(
        FileExplorerRoot(
          label: 'My files',
          path: 'virtual://my-files',
          isSharedFolder: true,
          virtualDirectoryLoader: _listShareableLocalDirectory,
        ),
      );
    }

    return roots;
  }

  Future<List<SharedFolderCacheRecord>> _loadOwnerCaches() async {
    final ownerMacAddress = widget.ownerMacAddressProvider().trim();
    if (ownerMacAddress.isNotEmpty) {
      try {
        await widget.sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: ownerMacAddress,
        );
      } catch (_) {
        // Keep using the last loaded owner snapshot in the current session.
      }
    }
    return widget.sharedCacheCatalog.ownerCaches;
  }

  Future<FileExplorerVirtualDirectory> _listShareableLocalDirectory(
    String virtualFolderPath,
  ) async {
    final caches = await _loadOwnerCaches();
    final folder = _normalizeVirtualFolderPath(virtualFolderPath);
    final foldersByPath = <String, FileExplorerVirtualFolder>{};
    final files = <FileExplorerVirtualFile>[];
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
            () => FileExplorerVirtualFolder(
              name: cache.displayName,
              folderPath: cacheVirtualRoot,
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
      final entries = await widget.sharedCacheIndexStore.readIndexEntries(
        cache,
      );
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
            () => FileExplorerVirtualFolder(
              name: folderName,
              folderPath: normalizedFolderPath,
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
          FileExplorerVirtualFile(
            path: absolutePath,
            subtitle: '${cache.displayName} / ${entry.relativePath}',
            virtualPath: virtualPath,
            sizeBytes: entry.sizeBytes,
            modifiedAt: DateTime.fromMillisecondsSinceEpoch(entry.modifiedAtMs),
            changedAt: DateTime.fromMillisecondsSinceEpoch(entry.modifiedAtMs),
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

    return FileExplorerVirtualDirectory(folders: folders, files: files);
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

  String _normalizePathKey(String value) {
    var normalized = p.normalize(value).replaceAll('\\', '/').trim();
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
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

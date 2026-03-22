import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_explorer_contract.dart';

enum FilesFeatureSortOption {
  nameAsc,
  nameDesc,
  modifiedNewest,
  modifiedOldest,
  changedNewest,
  changedOldest,
  sizeLargest,
  sizeSmallest,
}

enum FilesFeatureViewMode { list, grid }

class FilesFeatureEntry {
  const FilesFeatureEntry({
    required this.isDirectory,
    required this.name,
    required this.subtitle,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.changedAt,
    this.filePath,
    this.virtualFolderPath,
    this.removableSharedCacheId,
  });

  final bool isDirectory;
  final String name;
  final String subtitle;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime changedAt;
  final String? filePath;
  final String? virtualFolderPath;
  final String? removableSharedCacheId;

  static FilesFeatureEntry fromReal({
    required FileSystemEntity entity,
    required FileStat stat,
  }) {
    return FilesFeatureEntry(
      isDirectory: entity is Directory,
      name: p.basename(entity.path),
      subtitle: entity.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: entity.path,
    );
  }

  static FilesFeatureEntry virtualFolder({
    required String name,
    required String folderPath,
    String? removableSharedCacheId,
  }) {
    return FilesFeatureEntry(
      isDirectory: true,
      name: name,
      subtitle: folderPath,
      sizeBytes: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      changedAt: DateTime.fromMillisecondsSinceEpoch(0),
      virtualFolderPath: folderPath,
      removableSharedCacheId: removableSharedCacheId,
    );
  }

  static FilesFeatureEntry virtualFile({
    required File file,
    required FileStat stat,
    required String subtitle,
  }) {
    return FilesFeatureEntry(
      isDirectory: false,
      name: p.basename(file.path),
      subtitle: subtitle,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: file.path,
    );
  }

  static FilesFeatureEntry virtualFileCached({
    required String filePath,
    required String name,
    required String subtitle,
    required int sizeBytes,
    required DateTime modifiedAt,
    required DateTime changedAt,
  }) {
    return FilesFeatureEntry(
      isDirectory: false,
      name: name,
      subtitle: subtitle,
      sizeBytes: sizeBytes,
      modifiedAt: modifiedAt,
      changedAt: changedAt,
      filePath: filePath,
    );
  }
}

class FilesFeatureState {
  const FilesFeatureState({
    required this.roots,
    required this.selectedRootIndex,
    required this.currentPath,
    required this.virtualCurrentFolder,
    required this.searchQuery,
    required this.isLoading,
    required this.errorMessage,
    required this.entries,
    required this.sortOption,
    required this.viewMode,
    required this.gridTileExtent,
  });

  factory FilesFeatureState.initial({required List<FileExplorerRoot> roots}) {
    return FilesFeatureState(
      roots: List<FileExplorerRoot>.unmodifiable(roots),
      selectedRootIndex: 0,
      currentPath: '',
      virtualCurrentFolder: '',
      searchQuery: '',
      isLoading: false,
      errorMessage: null,
      entries: const <FilesFeatureEntry>[],
      sortOption: FilesFeatureSortOption.nameAsc,
      viewMode: FilesFeatureViewMode.list,
      gridTileExtent: 152,
    );
  }

  final List<FileExplorerRoot> roots;
  final int selectedRootIndex;
  final String currentPath;
  final String virtualCurrentFolder;
  final String searchQuery;
  final bool isLoading;
  final String? errorMessage;
  final List<FilesFeatureEntry> entries;
  final FilesFeatureSortOption sortOption;
  final FilesFeatureViewMode viewMode;
  final double gridTileExtent;

  static const Object _unset = Object();

  FileExplorerRoot? get selectedRoot {
    if (roots.isEmpty) {
      return null;
    }
    final safeIndex = selectedRootIndex.clamp(0, roots.length - 1);
    return roots[safeIndex];
  }

  List<FilesFeatureEntry> get visibleEntries {
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return entries;
    }
    return entries
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.subtitle.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  FilesFeatureState copyWith({
    List<FileExplorerRoot>? roots,
    int? selectedRootIndex,
    String? currentPath,
    String? virtualCurrentFolder,
    String? searchQuery,
    bool? isLoading,
    Object? errorMessage = _unset,
    List<FilesFeatureEntry>? entries,
    FilesFeatureSortOption? sortOption,
    FilesFeatureViewMode? viewMode,
    double? gridTileExtent,
  }) {
    return FilesFeatureState(
      roots: roots == null
          ? this.roots
          : List<FileExplorerRoot>.unmodifiable(roots),
      selectedRootIndex: selectedRootIndex ?? this.selectedRootIndex,
      currentPath: currentPath ?? this.currentPath,
      virtualCurrentFolder: virtualCurrentFolder ?? this.virtualCurrentFolder,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      entries: entries == null
          ? this.entries
          : List<FilesFeatureEntry>.unmodifiable(entries),
      sortOption: sortOption ?? this.sortOption,
      viewMode: viewMode ?? this.viewMode,
      gridTileExtent: gridTileExtent ?? this.gridTileExtent,
    );
  }
}

class FilesFeatureStateOwner extends ChangeNotifier {
  FilesFeatureStateOwner({required List<FileExplorerRoot> roots})
    : _state = FilesFeatureState.initial(
        roots: roots.where((root) => root.path.trim().isNotEmpty).toList(),
      );

  static const double minGridTileExtent = 104;
  static const double maxGridTileExtent = 232;

  FilesFeatureState _state;
  final Map<int, List<FileExplorerVirtualFile>> _virtualFilesByRootIndex =
      <int, List<FileExplorerVirtualFile>>{};
  final Map<String, FileExplorerVirtualDirectory> _virtualDirectoryByKey =
      <String, FileExplorerVirtualDirectory>{};

  FilesFeatureState get state => _state;
  FileExplorerRoot? get selectedRoot => _state.selectedRoot;
  String get normalizedVirtualCurrentFolder => _state.virtualCurrentFolder;
  List<FilesFeatureEntry> get visibleEntries => _state.visibleEntries;

  bool get canGoUp {
    final root = selectedRoot;
    if (root == null) {
      return false;
    }
    if (root.isVirtual) {
      return _state.virtualCurrentFolder.trim().isNotEmpty;
    }
    final normalizedRoot = _normalizePath(root.path);
    final normalizedCurrent = _normalizePath(_state.currentPath);
    if (normalizedRoot == normalizedCurrent) {
      return false;
    }
    return _isWithinRoot(normalizedCurrent, normalizedRoot);
  }

  String relativePathLabel() {
    final root = selectedRoot;
    if (root == null) {
      return '';
    }
    if (root.isVirtual) {
      return _state.virtualCurrentFolder;
    }
    var relative = p.relative(_state.currentPath, from: root.path);
    if (relative == '.') {
      relative = '';
    }
    return relative.replaceAll('\\', '/');
  }

  Future<void> initialize() async {
    if (_state.roots.isEmpty) {
      _replaceState(
        _state.copyWith(
          currentPath: Directory.current.path,
          errorMessage: 'No local folders available.',
        ),
      );
      return;
    }
    _replaceState(
      _state.copyWith(
        selectedRootIndex: 0,
        currentPath: _state.roots.first.path,
        virtualCurrentFolder: '',
        errorMessage: null,
      ),
    );
    await refreshCurrentRoot();
  }

  void setSearchQuery(String value) {
    if (_state.searchQuery == value) {
      return;
    }
    _replaceState(_state.copyWith(searchQuery: value));
  }

  void toggleViewMode() {
    final next = _state.viewMode == FilesFeatureViewMode.list
        ? FilesFeatureViewMode.grid
        : FilesFeatureViewMode.list;
    _replaceState(_state.copyWith(viewMode: next));
  }

  void setGridTileExtent(double value) {
    final next = value.clamp(minGridTileExtent, maxGridTileExtent).toDouble();
    if ((_state.gridTileExtent - next).abs() < 0.001) {
      return;
    }
    _replaceState(_state.copyWith(gridTileExtent: next));
  }

  void setSortOption(FilesFeatureSortOption option) {
    if (_state.sortOption == option) {
      return;
    }
    final sorted = List<FilesFeatureEntry>.from(_state.entries);
    _sortRecords(sorted, option);
    _replaceState(
      _state.copyWith(sortOption: option, entries: sorted, errorMessage: null),
    );
  }

  Future<void> selectRoot(int selectedIndex) async {
    if (selectedIndex < 0 || selectedIndex >= _state.roots.length) {
      return;
    }
    if (selectedIndex == _state.selectedRootIndex) {
      return;
    }
    final nextRoot = _state.roots[selectedIndex];
    _replaceState(
      _state.copyWith(
        selectedRootIndex: selectedIndex,
        currentPath: nextRoot.path,
        virtualCurrentFolder: '',
        errorMessage: null,
      ),
    );
    await refreshCurrentRoot();
  }

  void invalidateSelectedVirtualRootCache() {
    _virtualFilesByRootIndex.remove(_state.selectedRootIndex);
    final prefix = '${_state.selectedRootIndex}|';
    _virtualDirectoryByKey.removeWhere((key, _) => key.startsWith(prefix));
  }

  void clearVirtualFolderIfRemoved(String removedFolder) {
    final normalizedRemovedFolder = _normalizeVirtualFolder(removedFolder);
    final currentFolder = _normalizeVirtualFolder(_state.virtualCurrentFolder);
    if (normalizedRemovedFolder.isEmpty ||
        (currentFolder != normalizedRemovedFolder &&
            !currentFolder.startsWith('$normalizedRemovedFolder/'))) {
      return;
    }
    _replaceState(_state.copyWith(virtualCurrentFolder: ''));
  }

  Future<void> refreshCurrentRoot() async {
    final root = selectedRoot;
    if (root == null) {
      return;
    }
    final directoryLoader = root.virtualDirectoryLoader;
    if (directoryLoader != null) {
      await _loadVirtualDirectoryFromLoader(directoryLoader);
      return;
    }
    if (root.isVirtual) {
      _replaceState(_state.copyWith(isLoading: true, errorMessage: null));
      try {
        final virtualFiles = await _resolveVirtualFilesForSelectedRoot();
        await _loadVirtualEntries(virtualFiles);
      } catch (error) {
        _replaceState(
          _state.copyWith(
            entries: const <FilesFeatureEntry>[],
            isLoading: false,
            errorMessage: 'Cannot open files: $error',
          ),
        );
      }
      return;
    }
    await _loadDirectory(root.path);
  }

  Future<void> goUp() async {
    final root = selectedRoot;
    if (root == null) {
      return;
    }
    if (root.isVirtual) {
      final current = _normalizeVirtualFolder(_state.virtualCurrentFolder);
      if (current.isEmpty) {
        return;
      }
      final lastSlash = current.lastIndexOf('/');
      final nextFolder = lastSlash == -1 ? '' : current.substring(0, lastSlash);
      _replaceState(_state.copyWith(virtualCurrentFolder: nextFolder));
      await refreshCurrentRoot();
      return;
    }

    final parentPath = Directory(_state.currentPath).parent.path;
    final normalizedParent = _normalizePath(parentPath);
    final normalizedRoot = _normalizePath(root.path);
    final targetPath = _isWithinRoot(normalizedParent, normalizedRoot)
        ? parentPath
        : root.path;
    await _loadDirectory(targetPath);
  }

  Future<bool> openDirectory(FilesFeatureEntry entry) async {
    if (!entry.isDirectory) {
      return false;
    }
    final root = selectedRoot;
    if (root == null) {
      return false;
    }
    if (root.isVirtual) {
      final nextFolder = entry.virtualFolderPath;
      if (nextFolder == null) {
        return false;
      }
      _replaceState(_state.copyWith(virtualCurrentFolder: nextFolder));
      await refreshCurrentRoot();
      return true;
    }

    final nextPath = entry.filePath;
    if (nextPath == null || nextPath.trim().isEmpty) {
      return false;
    }
    await _loadDirectory(nextPath);
    return true;
  }

  Future<void> _loadVirtualDirectoryFromLoader(
    Future<FileExplorerVirtualDirectory> Function(String folderPath) loader,
  ) async {
    _replaceState(_state.copyWith(isLoading: true, errorMessage: null));

    try {
      final folder = _normalizeVirtualFolder(_state.virtualCurrentFolder);
      final cacheKey = '${_state.selectedRootIndex}|$folder';
      final directory =
          _virtualDirectoryByKey[cacheKey] ?? await loader(folder);
      _virtualDirectoryByKey[cacheKey] = directory;

      final records = <FilesFeatureEntry>[];
      for (final virtualFolder in directory.folders) {
        records.add(
          FilesFeatureEntry.virtualFolder(
            name: virtualFolder.name,
            folderPath: _normalizeVirtualFolder(virtualFolder.folderPath),
            removableSharedCacheId: virtualFolder.removableSharedCacheId,
          ),
        );
      }
      for (final virtualFile in directory.files) {
        final record = await _buildVirtualFileRecord(virtualFile);
        if (record != null) {
          records.add(record);
        }
      }
      _sortRecords(records, _state.sortOption);
      _replaceState(
        _state.copyWith(entries: records, isLoading: false, errorMessage: null),
      );
    } catch (error) {
      _replaceState(
        _state.copyWith(
          entries: const <FilesFeatureEntry>[],
          isLoading: false,
          errorMessage: 'Cannot open files: $error',
        ),
      );
    }
  }

  Future<List<FileExplorerVirtualFile>>
  _resolveVirtualFilesForSelectedRoot() async {
    final rootIndex = _state.selectedRootIndex;
    final cached = _virtualFilesByRootIndex[rootIndex];
    if (cached != null) {
      return cached;
    }

    final root = _state.roots[rootIndex];
    if (root.virtualFiles.isNotEmpty) {
      _virtualFilesByRootIndex[rootIndex] = root.virtualFiles;
      return root.virtualFiles;
    }

    final loader = root.virtualFilesLoader;
    if (loader == null) {
      _virtualFilesByRootIndex[rootIndex] = const <FileExplorerVirtualFile>[];
      return const <FileExplorerVirtualFile>[];
    }

    final loaded = await loader();
    _virtualFilesByRootIndex[rootIndex] = loaded;
    return loaded;
  }

  Future<FilesFeatureEntry?> _buildVirtualFileRecord(
    FileExplorerVirtualFile virtualFile,
  ) async {
    final modifiedAt = virtualFile.modifiedAt;
    final changedAt = virtualFile.changedAt;
    final sizeBytes = virtualFile.sizeBytes;
    if (modifiedAt != null && changedAt != null && sizeBytes != null) {
      return FilesFeatureEntry.virtualFileCached(
        filePath: virtualFile.path,
        name: p.basename(virtualFile.virtualPath),
        subtitle: virtualFile.subtitle ?? virtualFile.path,
        sizeBytes: sizeBytes,
        modifiedAt: modifiedAt,
        changedAt: changedAt,
      );
    }

    final file = File(virtualFile.path);
    if (!await file.exists()) {
      return null;
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }
    return FilesFeatureEntry.virtualFile(
      file: file,
      stat: stat,
      subtitle: virtualFile.subtitle ?? virtualFile.path,
    );
  }

  Future<void> _loadDirectory(String path) async {
    _replaceState(_state.copyWith(isLoading: true, errorMessage: null));

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory not found', path);
      }

      final entities = await directory.list(followLinks: false).toList();
      final records = <FilesFeatureEntry>[];
      for (final entity in entities) {
        try {
          final stat = await entity.stat();
          records.add(FilesFeatureEntry.fromReal(entity: entity, stat: stat));
        } catch (_) {
          // Skip unreadable entries.
        }
      }
      _sortRecords(records, _state.sortOption);
      _replaceState(
        _state.copyWith(
          currentPath: path,
          entries: records,
          isLoading: false,
          errorMessage: null,
        ),
      );
    } catch (error) {
      _replaceState(
        _state.copyWith(
          entries: const <FilesFeatureEntry>[],
          isLoading: false,
          errorMessage: 'Cannot open folder: $error',
        ),
      );
    }
  }

  Future<void> _loadVirtualEntries(
    List<FileExplorerVirtualFile> virtualFiles,
  ) async {
    _replaceState(_state.copyWith(isLoading: true, errorMessage: null));

    try {
      final folder = _normalizeVirtualFolder(_state.virtualCurrentFolder);
      final foldersByPath = <String, FilesFeatureEntry>{};
      final records = <FilesFeatureEntry>[];
      var processed = 0;
      for (final virtualFile in virtualFiles) {
        processed += 1;
        if (virtualFile.path.trim().isEmpty) {
          continue;
        }
        final virtualPath = _normalizeVirtualFolder(virtualFile.virtualPath);
        if (virtualPath.isEmpty) {
          continue;
        }
        if (folder.isNotEmpty &&
            virtualPath != folder &&
            !virtualPath.startsWith('$folder/')) {
          continue;
        }

        final rest = folder.isEmpty
            ? virtualPath
            : (virtualPath == folder
                  ? ''
                  : virtualPath.substring(folder.length + 1));
        if (rest.isEmpty) {
          continue;
        }
        final segments = rest
            .split('/')
            .where((part) => part.isNotEmpty)
            .toList();
        if (segments.isEmpty) {
          continue;
        }
        if (segments.length > 1) {
          final folderName = segments.first;
          final folderPath = folder.isEmpty
              ? folderName
              : '$folder/$folderName';
          foldersByPath.putIfAbsent(
            folderPath,
            () => FilesFeatureEntry.virtualFolder(
              name: folderName,
              folderPath: folderPath,
            ),
          );
          continue;
        }

        final fileRecord = await _buildVirtualFileRecord(virtualFile);
        if (fileRecord != null) {
          records.add(fileRecord);
        }
        if (processed % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      records.insertAll(0, foldersByPath.values);
      _sortRecords(records, _state.sortOption);
      _replaceState(
        _state.copyWith(entries: records, isLoading: false, errorMessage: null),
      );
    } catch (error) {
      _replaceState(
        _state.copyWith(
          entries: const <FilesFeatureEntry>[],
          isLoading: false,
          errorMessage: 'Cannot open files: $error',
        ),
      );
    }
  }

  void _sortRecords(
    List<FilesFeatureEntry> records,
    FilesFeatureSortOption sortOption,
  ) {
    records.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      final nameA = a.name.toLowerCase();
      final nameB = b.name.toLowerCase();
      switch (sortOption) {
        case FilesFeatureSortOption.nameAsc:
          return nameA.compareTo(nameB);
        case FilesFeatureSortOption.nameDesc:
          return nameB.compareTo(nameA);
        case FilesFeatureSortOption.modifiedNewest:
          final cmp = b.modifiedAt.compareTo(a.modifiedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case FilesFeatureSortOption.modifiedOldest:
          final cmp = a.modifiedAt.compareTo(b.modifiedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case FilesFeatureSortOption.changedNewest:
          final cmp = b.changedAt.compareTo(a.changedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case FilesFeatureSortOption.changedOldest:
          final cmp = a.changedAt.compareTo(b.changedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case FilesFeatureSortOption.sizeLargest:
          final cmp = b.sizeBytes.compareTo(a.sizeBytes);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case FilesFeatureSortOption.sizeSmallest:
          final cmp = a.sizeBytes.compareTo(b.sizeBytes);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
      }
    });
  }

  String _normalizePath(String value) {
    var normalized = p.normalize(value).replaceAll('\\', '/').trim();
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  bool _isWithinRoot(String candidate, String root) {
    if (candidate == root) {
      return true;
    }
    return candidate.startsWith('$root/');
  }

  String _normalizeVirtualFolder(String value) {
    return value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
  }

  void _replaceState(FilesFeatureState next) {
    _state = next;
    notifyListeners();
  }
}

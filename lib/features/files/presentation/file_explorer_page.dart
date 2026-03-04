import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class FileExplorerRoot {
  const FileExplorerRoot({
    required this.label,
    required this.path,
    this.isSharedFolder = false,
    this.virtualFiles = const <FileExplorerVirtualFile>[],
  });

  final String label;
  final String path;
  final bool isSharedFolder;
  final List<FileExplorerVirtualFile> virtualFiles;

  bool get isVirtual => virtualFiles.isNotEmpty;
}

class FileExplorerVirtualFile {
  const FileExplorerVirtualFile({
    required this.path,
    required this.virtualPath,
    this.subtitle,
  });

  final String path;
  final String virtualPath;
  final String? subtitle;
}

enum SharedRecacheActionResult { started, refreshedOnly, cancelled }

enum _ExplorerSortOption {
  nameAsc,
  nameDesc,
  modifiedNewest,
  modifiedOldest,
  changedNewest,
  changedOldest,
  sizeLargest,
  sizeSmallest,
}

enum _ExplorerViewMode { list, grid }

enum _ExplorerMenuAction {
  sortNameAsc,
  sortNameDesc,
  sortModifiedNewest,
  sortModifiedOldest,
  sortChangedNewest,
  sortChangedOldest,
  sortSizeLargest,
  sortSizeSmallest,
}

class _ExplorerEntityRecord {
  const _ExplorerEntityRecord({
    required this.isDirectory,
    required this.name,
    required this.subtitle,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.changedAt,
    this.filePath,
    this.virtualFolderPath,
  });

  final bool isDirectory;
  final String name;
  final String subtitle;
  final int sizeBytes;
  final DateTime modifiedAt;
  final DateTime changedAt;
  final String? filePath;
  final String? virtualFolderPath;

  static _ExplorerEntityRecord fromReal({
    required FileSystemEntity entity,
    required FileStat stat,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: entity is Directory,
      name: p.basename(entity.path),
      subtitle: entity.path,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: entity.path,
    );
  }

  static _ExplorerEntityRecord virtualFolder({
    required String name,
    required String folderPath,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: true,
      name: name,
      subtitle: folderPath,
      sizeBytes: 0,
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      changedAt: DateTime.fromMillisecondsSinceEpoch(0),
      virtualFolderPath: folderPath,
    );
  }

  static _ExplorerEntityRecord virtualFile({
    required File file,
    required FileStat stat,
    required String subtitle,
  }) {
    return _ExplorerEntityRecord(
      isDirectory: false,
      name: p.basename(file.path),
      subtitle: subtitle,
      sizeBytes: stat.size,
      modifiedAt: stat.modified,
      changedAt: stat.changed,
      filePath: file.path,
    );
  }
}

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({
    required this.roots,
    this.onRecacheSharedFolders,
    this.recacheStateListenable,
    this.isSharedRecacheInProgress,
    this.sharedRecacheProgress,
    super.key,
  });

  final List<FileExplorerRoot> roots;
  final Future<SharedRecacheActionResult> Function()? onRecacheSharedFolders;
  final Listenable? recacheStateListenable;
  final bool Function()? isSharedRecacheInProgress;
  final double? Function()? sharedRecacheProgress;

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  static const double _minGridTileExtent = 104;
  static const double _maxGridTileExtent = 232;

  late final List<FileExplorerRoot> _roots;
  final TextEditingController _searchController = TextEditingController();
  var _selectedRootIndex = 0;
  late String _currentPath;
  String _virtualCurrentFolder = '';
  String _searchQuery = '';

  bool _isLoading = false;
  String? _errorMessage;
  List<_ExplorerEntityRecord> _entries = const <_ExplorerEntityRecord>[];
  _ExplorerSortOption _sortOption = _ExplorerSortOption.nameAsc;
  _ExplorerViewMode _viewMode = _ExplorerViewMode.list;
  double _gridTileExtent = 152;

  FileExplorerRoot get _selectedRoot => _roots[_selectedRootIndex];

  bool get _isSharedRecacheRunning {
    final resolver = widget.isSharedRecacheInProgress;
    if (resolver == null) {
      return false;
    }
    return resolver();
  }

  double? get _sharedRecacheProgressValue {
    final resolver = widget.sharedRecacheProgress;
    if (resolver == null) {
      return null;
    }
    return resolver();
  }

  @override
  void initState() {
    super.initState();
    widget.recacheStateListenable?.addListener(_handleRecacheStateChanged);
    _roots = widget.roots.where((root) => root.path.trim().isNotEmpty).toList();
    if (_roots.isEmpty) {
      _errorMessage = 'No local folders available.';
      _currentPath = Directory.current.path;
      return;
    }

    _selectedRootIndex = 0;
    _currentPath = _roots.first.path;
    _loadCurrentRoot();
  }

  @override
  void didUpdateWidget(covariant FileExplorerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recacheStateListenable != widget.recacheStateListenable) {
      oldWidget.recacheStateListenable?.removeListener(
        _handleRecacheStateChanged,
      );
      widget.recacheStateListenable?.addListener(_handleRecacheStateChanged);
    }
  }

  @override
  void dispose() {
    widget.recacheStateListenable?.removeListener(_handleRecacheStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleRecacheStateChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            tooltip: _refreshActionTooltip,
            onPressed: _handleRefreshAction,
            icon: _buildRefreshActionIcon(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExplorerPathHeader(
                rootLabel: _selectedRoot.label,
                relativePath: _relativePathLabel(),
                canGoUp: _canGoUp,
                onGoUp: _canGoUp ? _goUp : null,
                canSelectRoot: _roots.isNotEmpty,
                onSelectRoot: _roots.isNotEmpty ? _pickRoot : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  _DisplayModeToggle(
                    isGrid: _viewMode == _ExplorerViewMode.grid,
                    onToggle: _toggleViewMode,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'Search files',
                          prefixIcon: Icon(Icons.search_rounded, size: 18),
                          prefixIconConstraints: BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.sm,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  PopupMenuButton<_ExplorerMenuAction>(
                    tooltip: 'Sort',
                    onSelected: _handleMenuAction,
                    itemBuilder: (context) {
                      var menuTileSize = _gridTileExtent;
                      return [
                        const PopupMenuItem<_ExplorerMenuAction>(
                          enabled: false,
                          child: Text('Sort'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortNameAsc,
                          checked: _sortOption == _ExplorerSortOption.nameAsc,
                          child: const Text('A-Z'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortNameDesc,
                          checked: _sortOption == _ExplorerSortOption.nameDesc,
                          child: const Text('Z-A'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortModifiedNewest,
                          checked:
                              _sortOption == _ExplorerSortOption.modifiedNewest,
                          child: const Text('Modified: newest'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortModifiedOldest,
                          checked:
                              _sortOption == _ExplorerSortOption.modifiedOldest,
                          child: const Text('Modified: oldest'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortChangedNewest,
                          checked:
                              _sortOption == _ExplorerSortOption.changedNewest,
                          child: const Text('Created/changed: newest'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortChangedOldest,
                          checked:
                              _sortOption == _ExplorerSortOption.changedOldest,
                          child: const Text('Created/changed: oldest'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortSizeLargest,
                          checked:
                              _sortOption == _ExplorerSortOption.sizeLargest,
                          child: const Text('Size: largest'),
                        ),
                        CheckedPopupMenuItem<_ExplorerMenuAction>(
                          value: _ExplorerMenuAction.sortSizeSmallest,
                          checked:
                              _sortOption == _ExplorerSortOption.sizeSmallest,
                          child: const Text('Size: smallest'),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem<_ExplorerMenuAction>(
                          enabled: false,
                          height: 86,
                          child: StatefulBuilder(
                            builder: (context, setMenuState) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tile size',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  Slider(
                                    value: menuTileSize,
                                    min: _minGridTileExtent,
                                    max: _maxGridTileExtent,
                                    divisions: 3,
                                    onChanged: (next) {
                                      setMenuState(() {
                                        menuTileSize = next;
                                      });
                                      setState(() {
                                        _gridTileExtent = next;
                                      });
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ];
                    },
                    padding: EdgeInsets.zero,
                    child: Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.mutedBorder),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.sort_rounded, size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_isLoading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: AppColors.brandPrimary,
                  backgroundColor: AppColors.mutedBorder,
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ExplorerErrorBanner(
                  message: _errorMessage!,
                  onRetry: _loadCurrentRoot,
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _visibleEntries.isEmpty
                    ? const Center(child: Text('Folder is empty'))
                    : _viewMode == _ExplorerViewMode.list
                    ? ListView.separated(
                        itemCount: _visibleEntries.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (_, index) {
                          final entry = _visibleEntries[index];
                          return _ExplorerEntityTile(
                            entry: entry,
                            onTap: () => _openEntry(entry),
                          );
                        },
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return GridView.builder(
                            itemCount: _visibleEntries.length,
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: _gridTileExtent,
                                  mainAxisSpacing: AppSpacing.xs,
                                  crossAxisSpacing: AppSpacing.xs,
                                  childAspectRatio: 0.9,
                                ),
                            itemBuilder: (_, index) {
                              final entry = _visibleEntries[index];
                              return _ExplorerEntityGridTile(
                                entry: entry,
                                tileExtent: _gridTileExtent,
                                onTap: () => _openEntry(entry),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canGoUp {
    if (_selectedRoot.isVirtual) {
      return _virtualCurrentFolder.trim().isNotEmpty;
    }
    final root = _normalizePath(_selectedRoot.path);
    final current = _normalizePath(_currentPath);
    if (root == current) {
      return false;
    }
    return _isWithinRoot(current, root);
  }

  bool get _canRecacheSelectedRoot =>
      _selectedRoot.isSharedFolder && widget.onRecacheSharedFolders != null;

  String get _refreshActionTooltip =>
      _canRecacheSelectedRoot ? 'Re-cache shared folders/files' : 'Refresh';

  IconData get _refreshActionIcon =>
      _canRecacheSelectedRoot ? Icons.cached_rounded : Icons.refresh_rounded;

  Widget _buildRefreshActionIcon() {
    if (_canRecacheSelectedRoot && _isSharedRecacheRunning) {
      return SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          value: _sharedRecacheProgressValue,
          color: AppColors.brandPrimary,
          backgroundColor: AppColors.mutedBorder,
        ),
      );
    }
    return Icon(_refreshActionIcon);
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == _ExplorerViewMode.list
          ? _ExplorerViewMode.grid
          : _ExplorerViewMode.list;
    });
  }

  void _handleMenuAction(_ExplorerMenuAction action) {
    final nextSort = _sortOptionFromMenuAction(action);
    if (nextSort == _sortOption) {
      return;
    }
    setState(() {
      _sortOption = nextSort;
      final sorted = List<_ExplorerEntityRecord>.from(_entries);
      _sortRecords(sorted);
      _entries = sorted;
    });
  }

  _ExplorerSortOption _sortOptionFromMenuAction(_ExplorerMenuAction action) {
    switch (action) {
      case _ExplorerMenuAction.sortNameAsc:
        return _ExplorerSortOption.nameAsc;
      case _ExplorerMenuAction.sortNameDesc:
        return _ExplorerSortOption.nameDesc;
      case _ExplorerMenuAction.sortModifiedNewest:
        return _ExplorerSortOption.modifiedNewest;
      case _ExplorerMenuAction.sortModifiedOldest:
        return _ExplorerSortOption.modifiedOldest;
      case _ExplorerMenuAction.sortChangedNewest:
        return _ExplorerSortOption.changedNewest;
      case _ExplorerMenuAction.sortChangedOldest:
        return _ExplorerSortOption.changedOldest;
      case _ExplorerMenuAction.sortSizeLargest:
        return _ExplorerSortOption.sizeLargest;
      case _ExplorerMenuAction.sortSizeSmallest:
        return _ExplorerSortOption.sizeSmallest;
    }
  }

  void _sortRecords(List<_ExplorerEntityRecord> records) {
    records.sort((a, b) {
      if (a.isDirectory != b.isDirectory) {
        return a.isDirectory ? -1 : 1;
      }

      final nameA = a.name.toLowerCase();
      final nameB = b.name.toLowerCase();
      switch (_sortOption) {
        case _ExplorerSortOption.nameAsc:
          return nameA.compareTo(nameB);
        case _ExplorerSortOption.nameDesc:
          return nameB.compareTo(nameA);
        case _ExplorerSortOption.modifiedNewest:
          final cmp = b.modifiedAt.compareTo(a.modifiedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case _ExplorerSortOption.modifiedOldest:
          final cmp = a.modifiedAt.compareTo(b.modifiedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case _ExplorerSortOption.changedNewest:
          final cmp = b.changedAt.compareTo(a.changedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case _ExplorerSortOption.changedOldest:
          final cmp = a.changedAt.compareTo(b.changedAt);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case _ExplorerSortOption.sizeLargest:
          final cmp = b.sizeBytes.compareTo(a.sizeBytes);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
        case _ExplorerSortOption.sizeSmallest:
          final cmp = a.sizeBytes.compareTo(b.sizeBytes);
          return cmp != 0 ? cmp : nameA.compareTo(nameB);
      }
    });
  }

  Future<void> _pickRoot() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _roots.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final root = _roots[index];
              return ListTile(
                leading: const Icon(Icons.folder_special_rounded),
                title: Text(root.label),
                subtitle: Text(root.isVirtual ? 'All shared files' : root.path),
                trailing: index == _selectedRootIndex
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );

    if (selected == null || selected == _selectedRootIndex || !mounted) {
      return;
    }

    setState(() {
      _selectedRootIndex = selected;
      _currentPath = _roots[selected].path;
      _virtualCurrentFolder = '';
      _errorMessage = null;
    });
    await _loadCurrentRoot();
  }

  Future<void> _loadCurrentRoot() async {
    final root = _selectedRoot;
    if (root.isVirtual) {
      await _loadVirtualEntries(root.virtualFiles);
      return;
    }
    await _loadDirectory(root.path);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory not found', path);
      }

      final entities = await directory.list(followLinks: false).toList();
      final records = <_ExplorerEntityRecord>[];
      for (final entity in entities) {
        try {
          final stat = await entity.stat();
          records.add(
            _ExplorerEntityRecord.fromReal(entity: entity, stat: stat),
          );
        } catch (_) {
          // Skip unreadable entries.
        }
      }
      _sortRecords(records);

      if (!mounted) {
        return;
      }
      setState(() {
        _currentPath = path;
        _entries = records;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const <_ExplorerEntityRecord>[];
        _isLoading = false;
        _errorMessage = 'Cannot open folder: $error';
      });
    }
  }

  Future<void> _loadVirtualEntries(
    List<FileExplorerVirtualFile> virtualFiles,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final folder = _normalizeVirtualFolder(_virtualCurrentFolder);
      final foldersByPath = <String, _ExplorerEntityRecord>{};
      final records = <_ExplorerEntityRecord>[];
      for (final virtualFile in virtualFiles) {
        if (virtualFile.path.trim().isEmpty) {
          continue;
        }
        final virtualPath = _normalizeVirtualFolder(virtualFile.virtualPath);
        if (virtualPath.isEmpty) {
          continue;
        }
        if (folder.isNotEmpty) {
          if (virtualPath != folder && !virtualPath.startsWith('$folder/')) {
            continue;
          }
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
            () => _ExplorerEntityRecord.virtualFolder(
              name: folderName,
              folderPath: folderPath,
            ),
          );
          continue;
        }

        final file = File(virtualFile.path);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        records.add(
          _ExplorerEntityRecord.virtualFile(
            file: file,
            stat: stat,
            subtitle: virtualFile.subtitle ?? virtualFile.path,
          ),
        );
      }
      records.insertAll(0, foldersByPath.values);
      _sortRecords(records);

      if (!mounted) {
        return;
      }
      setState(() {
        _entries = records;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entries = const <_ExplorerEntityRecord>[];
        _isLoading = false;
        _errorMessage = 'Cannot open files: $error';
      });
    }
  }

  Future<void> _handleRefreshAction() async {
    if (!_canRecacheSelectedRoot) {
      await _loadCurrentRoot();
      return;
    }
    final action = await widget.onRecacheSharedFolders!.call();
    if (action == SharedRecacheActionResult.cancelled) {
      return;
    }
    await _loadCurrentRoot();
  }

  Future<void> _goUp() async {
    if (_selectedRoot.isVirtual) {
      final current = _normalizeVirtualFolder(_virtualCurrentFolder);
      if (current.isEmpty) {
        return;
      }
      final lastSlash = current.lastIndexOf('/');
      final nextFolder = lastSlash == -1 ? '' : current.substring(0, lastSlash);
      setState(() {
        _virtualCurrentFolder = nextFolder;
      });
      await _loadCurrentRoot();
      return;
    }
    final parentPath = Directory(_currentPath).parent.path;
    final rootPath = _selectedRoot.path;
    final normalizedParent = _normalizePath(parentPath);
    final normalizedRoot = _normalizePath(rootPath);

    final targetPath = _isWithinRoot(normalizedParent, normalizedRoot)
        ? parentPath
        : rootPath;
    await _loadDirectory(targetPath);
  }

  Future<void> _openEntry(_ExplorerEntityRecord entry) async {
    if (entry.isDirectory) {
      if (_selectedRoot.isVirtual) {
        setState(() {
          _virtualCurrentFolder = entry.virtualFolderPath ?? '';
        });
        await _loadCurrentRoot();
        return;
      }
      final nextPath = entry.filePath;
      if (nextPath == null || nextPath.trim().isEmpty) {
        return;
      }
      await _loadDirectory(nextPath);
      return;
    }

    final filePath = entry.filePath;
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalFileViewerPage(filePath: filePath),
      ),
    );
  }

  String _relativePathLabel() {
    if (_selectedRoot.isVirtual) {
      return _virtualCurrentFolder;
    }
    final rootPath = _selectedRoot.path;
    final currentPath = _currentPath;
    var relative = p.relative(currentPath, from: rootPath);
    if (relative == '.') {
      relative = '';
    }
    return relative.replaceAll('\\', '/');
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

  List<_ExplorerEntityRecord> get _visibleEntries {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _entries;
    }
    return _entries
        .where(
          (entry) =>
              entry.name.toLowerCase().contains(query) ||
              entry.subtitle.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }
}

class LocalFileViewerPage extends StatelessWidget {
  const LocalFileViewerPage({required this.filePath, super.key});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(filePath);
    final fileKind = _resolveFileKind(filePath);

    Widget body;
    switch (fileKind) {
      case _LocalFileKind.image:
        body = _ImageFileViewer(filePath: filePath);
      case _LocalFileKind.video:
        body = _VideoFileViewer(filePath: filePath);
      case _LocalFileKind.text:
        body = _TextFileViewer(filePath: filePath);
      case _LocalFileKind.pdf:
        body = _PdfFileViewer(filePath: filePath);
      case _LocalFileKind.other:
        body = _UnsupportedFileViewer(filePath: filePath);
    }

    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: SafeArea(child: body),
    );
  }

  _LocalFileKind _resolveFileKind(String path) {
    final ext = p.extension(path).toLowerCase();
    if (_imageExtensions.contains(ext)) {
      return _LocalFileKind.image;
    }
    if (_videoExtensions.contains(ext)) {
      return _LocalFileKind.video;
    }
    if (_textExtensions.contains(ext)) {
      return _LocalFileKind.text;
    }
    if (ext == '.pdf') {
      return _LocalFileKind.pdf;
    }
    return _LocalFileKind.other;
  }

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.m4v',
    '.3gp',
    '.mpeg',
    '.mpg',
  };

  static const Set<String> _textExtensions = <String>{
    '.txt',
    '.md',
    '.log',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
  };
}

class _ImageFileViewer extends StatelessWidget {
  const _ImageFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.2,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(filePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const _ViewerError(message: 'Cannot open image file.');
          },
        ),
      ),
    );
  }
}

class _VideoFileViewer extends StatefulWidget {
  const _VideoFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_VideoFileViewer> createState() => _VideoFileViewerState();
}

class _VideoFileViewerState extends State<_VideoFileViewer> {
  VideoPlayerController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.filePath));
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Cannot open video in built-in player on this platform.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final isPlaying = controller.value.isPlaying;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: AppColors.brandPrimary,
            bufferedColor: AppColors.brandAccent,
            backgroundColor: AppColors.mutedBorder,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: () async {
                if (isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
                if (mounted) {
                  setState(() {});
                }
              },
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                size: 34,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _TextFileViewer extends StatefulWidget {
  const _TextFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_TextFileViewer> createState() => _TextFileViewerState();
}

class _TextFileViewerState extends State<_TextFileViewer> {
  static const int _previewLimitBytes = 2 * 1024 * 1024;

  bool _isLoading = true;
  String? _errorMessage;
  String _content = '';
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      final previewBytes = bytes.length > _previewLimitBytes
          ? bytes.sublist(0, _previewLimitBytes)
          : bytes;

      if (!mounted) {
        return;
      }
      setState(() {
        _content = utf8.decode(previewBytes, allowMalformed: true);
        _truncated = bytes.length > _previewLimitBytes;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot read text file: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ViewerError(message: _errorMessage!);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_truncated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                'Preview is truncated to 2 MB.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (_truncated) const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'JetBrainsMono',
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfFileViewer extends StatelessWidget {
  const _PdfFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return SfPdfViewer.file(
      file,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (details) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF load failed: ${details.error}')),
        );
      },
    );
  }
}

class _UnsupportedFileViewer extends StatelessWidget {
  const _UnsupportedFileViewer({required this.filePath, this.hintMessage});

  final String filePath;
  final String? hintMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 42),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hintMessage ??
                  'This file type is not supported by the built-in viewer yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () async {
                await OpenFilex.open(filePath);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open externally'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
        ),
      ),
    );
  }
}

class _ExplorerPathHeader extends StatelessWidget {
  const _ExplorerPathHeader({
    required this.rootLabel,
    required this.relativePath,
    required this.canGoUp,
    required this.onGoUp,
    required this.canSelectRoot,
    required this.onSelectRoot,
  });

  final String rootLabel;
  final String relativePath;
  final bool canGoUp;
  final VoidCallback? onGoUp;
  final bool canSelectRoot;
  final VoidCallback? onSelectRoot;

  @override
  Widget build(BuildContext context) {
    final full = relativePath.isEmpty
        ? rootLabel
        : '$rootLabel / $relativePath';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Up',
              onPressed: canGoUp ? onGoUp : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(full, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Select root',
              onPressed: canSelectRoot ? onSelectRoot : null,
              icon: const Icon(Icons.source_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExplorerEntityTile extends StatelessWidget {
  const _ExplorerEntityTile({required this.entry, required this.onTap});

  final _ExplorerEntityRecord entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      tileColor: AppColors.surface,
      leading: _ExplorerEntityLeading(
        isDirectory: entry.isDirectory,
        filePath: entry.filePath,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onTap,
    );
  }
}

class _ExplorerEntityLeading extends StatelessWidget {
  const _ExplorerEntityLeading({
    required this.isDirectory,
    required this.filePath,
    this.size = 44,
  });

  final bool isDirectory;
  final String? filePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isDirectory) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.brandPrimary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.folder_rounded, color: AppColors.brandPrimary),
      );
    }
    final path = filePath;
    if (path == null || path.trim().isEmpty) {
      return _ExplorerFilePreview(filePath: '', size: size);
    }
    return _ExplorerFilePreview(filePath: path, size: size);
  }
}

class _ExplorerFilePreview extends StatelessWidget {
  const _ExplorerFilePreview({required this.filePath, this.size = 44});

  final String filePath;
  final double size;

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.m4v',
    '.3gp',
    '.mpeg',
    '.mpg',
  };

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(filePath).toLowerCase();
    if (_imageExtensions.contains(ext)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.file(
          File(filePath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackIcon(Icons.image_rounded),
        ),
      );
    }
    if (_videoExtensions.contains(ext)) {
      return _ExplorerVideoPreview(filePath: filePath, size: size);
    }
    return _fallbackIcon(Icons.insert_drive_file_rounded);
  }

  Widget _fallbackIcon(IconData icon) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: AppColors.mutedIcon),
    );
  }
}

class _ExplorerVideoPreview extends StatefulWidget {
  const _ExplorerVideoPreview({required this.filePath, this.size = 44});

  final String filePath;
  final double size;

  @override
  State<_ExplorerVideoPreview> createState() => _ExplorerVideoPreviewState();
}

class _ExplorerVideoPreviewState extends State<_ExplorerVideoPreview> {
  static final Map<String, Uint8List?> _thumbnailCache = <String, Uint8List?>{};

  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  Future<Uint8List?> _loadThumbnail() async {
    final cached = _thumbnailCache[widget.filePath];
    if (cached != null) {
      return cached;
    }
    final bytes = await video_thumbnail.VideoThumbnail.thumbnailData(
      video: widget.filePath,
      imageFormat: video_thumbnail.ImageFormat.JPEG,
      maxHeight: 96,
      quality: 55,
      timeMs: 600,
    );
    _thumbnailCache[widget.filePath] = bytes;
    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildFallback();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.memory(
                bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
              ),
              Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: widget.size * 0.42,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(Icons.videocam_rounded, color: AppColors.mutedIcon),
    );
  }
}

class _ExplorerEntityGridTile extends StatelessWidget {
  const _ExplorerEntityGridTile({
    required this.entry,
    required this.tileExtent,
    required this.onTap,
  });

  final _ExplorerEntityRecord entry;
  final double tileExtent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const horizontalPadding = AppSpacing.xs;
            const verticalPadding = AppSpacing.xs;
            const nameHeight = 18.0;
            final availableWidth = constraints.maxWidth - horizontalPadding * 2;
            final availableHeight = constraints.maxHeight - verticalPadding * 2;
            final previewMaxHeight =
                availableHeight - nameHeight - AppSpacing.xs;
            final previewSize = math
                .min(availableWidth, previewMaxHeight)
                .clamp(44, 170)
                .toDouble();
            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: _ExplorerEntityLeading(
                        isDirectory: entry.isDirectory,
                        filePath: entry.filePath,
                        size: previewSize,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  SizedBox(
                    height: nameHeight,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: _GridNameLabel(
                        name: entry.name,
                        maxWidth: availableWidth,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GridNameLabel extends StatelessWidget {
  const _GridNameLabel({required this.name, required this.maxWidth});

  final String name;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = theme.textTheme.bodySmall ?? const TextStyle();
    if (_fits(
      context: context,
      text: TextSpan(text: name, style: baseStyle),
      maxWidth: maxWidth,
    )) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: baseStyle,
      );
    }

    final suffixStyle =
        theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted) ??
        baseStyle.copyWith(color: AppColors.textMuted, fontSize: 10);
    final compact = _resolveCompact(
      context: context,
      baseStyle: baseStyle,
      suffixStyle: suffixStyle,
    );
    final start = compact.$1;
    final end = compact.$2;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$start…', style: baseStyle),
          TextSpan(text: end, style: suffixStyle),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
  }

  (String, String) _resolveCompact({
    required BuildContext context,
    required TextStyle baseStyle,
    required TextStyle suffixStyle,
  }) {
    if (name.length <= 5) {
      return (name, '');
    }
    const suffixChars = 4;
    final suffix = name.length <= suffixChars
        ? name
        : name.substring(name.length - suffixChars);
    final maxPrefixChars = math.max(1, name.length - suffix.length);
    var bestPrefixChars = math.min(6, maxPrefixChars);

    for (var prefixChars = 1; prefixChars <= maxPrefixChars; prefixChars++) {
      final prefix = name.substring(0, prefixChars);
      final span = TextSpan(
        children: [
          TextSpan(text: '$prefix…', style: baseStyle),
          TextSpan(text: suffix, style: suffixStyle),
        ],
      );
      if (_fits(context: context, text: span, maxWidth: maxWidth)) {
        bestPrefixChars = prefixChars;
      } else {
        break;
      }
    }

    return (name.substring(0, bestPrefixChars), suffix);
  }

  bool _fits({
    required BuildContext context,
    required InlineSpan text,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: text,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: math.max(1, maxWidth));
    return !painter.didExceedMaxLines;
  }
}

class _DisplayModeToggle extends StatelessWidget {
  const _DisplayModeToggle({required this.isGrid, required this.onToggle});

  final bool isGrid;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        ),
        onPressed: onToggle,
        icon: Icon(
          isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          size: 18,
        ),
        label: Text(isGrid ? 'List view' : 'Tile view'),
      ),
    );
  }
}

class _ExplorerErrorBanner extends StatelessWidget {
  const _ExplorerErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

enum _LocalFileKind { image, video, text, pdf, other }

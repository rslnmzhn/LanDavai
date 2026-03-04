import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
    this.virtualFilesLoader,
    this.virtualDirectoryLoader,
  });

  final String label;
  final String path;
  final bool isSharedFolder;
  final List<FileExplorerVirtualFile> virtualFiles;
  final Future<List<FileExplorerVirtualFile>> Function()? virtualFilesLoader;
  final Future<FileExplorerVirtualDirectory> Function(String folderPath)?
  virtualDirectoryLoader;

  bool get isVirtual =>
      virtualFiles.isNotEmpty ||
      virtualFilesLoader != null ||
      virtualDirectoryLoader != null;
}

class FileExplorerVirtualFile {
  const FileExplorerVirtualFile({
    required this.path,
    required this.virtualPath,
    this.subtitle,
    this.sizeBytes,
    this.modifiedAt,
    this.changedAt,
  });

  final String path;
  final String virtualPath;
  final String? subtitle;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final DateTime? changedAt;
}

class FileExplorerVirtualFolder {
  const FileExplorerVirtualFolder({
    required this.name,
    required this.folderPath,
    this.removableSharedCacheId,
  });

  final String name;
  final String folderPath;
  final String? removableSharedCacheId;
}

class FileExplorerVirtualDirectory {
  const FileExplorerVirtualDirectory({
    this.folders = const <FileExplorerVirtualFolder>[],
    this.files = const <FileExplorerVirtualFile>[],
  });

  final List<FileExplorerVirtualFolder> folders;
  final List<FileExplorerVirtualFile> files;
}

const Set<String> _supportedImageExtensions = <String>{
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

const Set<String> _supportedVideoExtensions = <String>{
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

const Set<String> _supportedAudioExtensions = <String>{
  '.mp3',
  '.m4a',
  '.aac',
  '.flac',
  '.wav',
  '.ogg',
  '.opus',
  '.wma',
};

const Set<String> _supportedTextExtensions = <String>{
  '.txt',
  '.md',
  '.log',
  '.json',
  '.yaml',
  '.yml',
  '.csv',
  '.xml',
};

bool get _useMediaKitForPlayback =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

enum SharedRecacheActionResult { started, refreshedOnly, cancelled }

class SharedRecacheProgressDetails {
  const SharedRecacheProgressDetails({
    required this.processedFiles,
    required this.totalFiles,
    required this.currentCacheLabel,
    required this.currentRelativePath,
    required this.eta,
  });

  final int processedFiles;
  final int totalFiles;
  final String currentCacheLabel;
  final String currentRelativePath;
  final Duration? eta;
}

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
    String? removableSharedCacheId,
  }) {
    return _ExplorerEntityRecord(
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

  static _ExplorerEntityRecord virtualFileCached({
    required String filePath,
    required String name,
    required String subtitle,
    required int sizeBytes,
    required DateTime modifiedAt,
    required DateTime changedAt,
  }) {
    return _ExplorerEntityRecord(
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

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({
    required this.roots,
    this.onRecacheSharedFolders,
    this.onRemoveSharedCache,
    this.recacheStateListenable,
    this.isSharedRecacheInProgress,
    this.sharedRecacheProgress,
    this.sharedRecacheDetails,
    super.key,
  });

  final List<FileExplorerRoot> roots;
  final Future<SharedRecacheActionResult> Function(String virtualFolderPath)?
  onRecacheSharedFolders;
  final Future<bool> Function(String cacheId, String cacheLabel)?
  onRemoveSharedCache;
  final Listenable? recacheStateListenable;
  final bool Function()? isSharedRecacheInProgress;
  final double? Function()? sharedRecacheProgress;
  final SharedRecacheProgressDetails? Function()? sharedRecacheDetails;

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
  final Map<int, List<FileExplorerVirtualFile>> _virtualFilesByRootIndex =
      <int, List<FileExplorerVirtualFile>>{};
  final Map<String, FileExplorerVirtualDirectory> _virtualDirectoryByKey =
      <String, FileExplorerVirtualDirectory>{};

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

  SharedRecacheProgressDetails? get _sharedRecacheDetailsValue {
    final resolver = widget.sharedRecacheDetails;
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
              if (_canRecacheSelectedRoot && _isSharedRecacheRunning) ...[
                _SharedRecacheStatusCard(
                  progress: _sharedRecacheProgressValue,
                  details: _sharedRecacheDetailsValue,
                  formatEta: _formatEta,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
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
                            onDelete:
                                _canRemoveSharedCachesFromFiles &&
                                    entry.removableSharedCacheId != null
                                ? () => _removeSharedCacheFromEntry(entry)
                                : null,
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
                                onDelete:
                                    _canRemoveSharedCachesFromFiles &&
                                        entry.removableSharedCacheId != null
                                    ? () => _removeSharedCacheFromEntry(entry)
                                    : null,
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

  bool get _canRemoveSharedCachesFromFiles =>
      _selectedRoot.isSharedFolder && widget.onRemoveSharedCache != null;

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

  Future<void> _removeSharedCacheFromEntry(_ExplorerEntityRecord entry) async {
    final cacheId = entry.removableSharedCacheId;
    if (cacheId == null || cacheId.trim().isEmpty) {
      return;
    }
    final removeHandler = widget.onRemoveSharedCache;
    if (removeHandler == null) {
      return;
    }

    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove shared folder?'),
          content: Text(
            'The folder "${entry.name}" will be removed from shared access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (agreed != true || !mounted) {
      return;
    }

    final removed = await removeHandler(cacheId, entry.name);
    if (!removed || !mounted) {
      return;
    }

    final removedFolder = _normalizeVirtualFolder(
      entry.virtualFolderPath ?? '',
    );
    final currentFolder = _normalizeVirtualFolder(_virtualCurrentFolder);
    if (removedFolder.isNotEmpty &&
        (currentFolder == removedFolder ||
            currentFolder.startsWith('$removedFolder/'))) {
      setState(() {
        _virtualCurrentFolder = '';
      });
    }
    _invalidateSelectedVirtualRootCache();
    await _loadCurrentRoot();
  }

  String _formatEta(Duration eta) {
    final totalSeconds = eta.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
    final directoryLoader = root.virtualDirectoryLoader;
    if (directoryLoader != null) {
      await _loadVirtualDirectoryFromLoader(directoryLoader);
      return;
    }
    if (root.isVirtual) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      try {
        final virtualFiles = await _resolveVirtualFilesForSelectedRoot();
        await _loadVirtualEntries(virtualFiles);
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
      return;
    }
    await _loadDirectory(root.path);
  }

  Future<void> _loadVirtualDirectoryFromLoader(
    Future<FileExplorerVirtualDirectory> Function(String folderPath) loader,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final folder = _normalizeVirtualFolder(_virtualCurrentFolder);
      final cacheKey = '$_selectedRootIndex|$folder';
      final directory =
          _virtualDirectoryByKey[cacheKey] ?? await loader(folder);
      _virtualDirectoryByKey[cacheKey] = directory;

      final records = <_ExplorerEntityRecord>[];
      for (final virtualFolder in directory.folders) {
        records.add(
          _ExplorerEntityRecord.virtualFolder(
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

  Future<List<FileExplorerVirtualFile>>
  _resolveVirtualFilesForSelectedRoot() async {
    final rootIndex = _selectedRootIndex;
    final cached = _virtualFilesByRootIndex[rootIndex];
    if (cached != null) {
      return cached;
    }

    final root = _roots[rootIndex];
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

  Future<_ExplorerEntityRecord?> _buildVirtualFileRecord(
    FileExplorerVirtualFile virtualFile,
  ) async {
    final modifiedAt = virtualFile.modifiedAt;
    final changedAt = virtualFile.changedAt;
    final sizeBytes = virtualFile.sizeBytes;
    if (modifiedAt != null && changedAt != null && sizeBytes != null) {
      return _ExplorerEntityRecord.virtualFileCached(
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
    return _ExplorerEntityRecord.virtualFile(
      file: file,
      stat: stat,
      subtitle: virtualFile.subtitle ?? virtualFile.path,
    );
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

        final fileRecord = await _buildVirtualFileRecord(virtualFile);
        if (fileRecord == null) {
          continue;
        }
        records.add(fileRecord);
        if (processed % 500 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
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
      _invalidateSelectedVirtualRootCache();
      await _loadCurrentRoot();
      return;
    }
    final action = await widget.onRecacheSharedFolders!.call(
      _normalizeVirtualFolder(_virtualCurrentFolder),
    );
    if (action == SharedRecacheActionResult.cancelled) {
      return;
    }
    _invalidateSelectedVirtualRootCache();
    await _loadCurrentRoot();
  }

  void _invalidateSelectedVirtualRootCache() {
    _virtualFilesByRootIndex.remove(_selectedRootIndex);
    final prefix = '$_selectedRootIndex|';
    _virtualDirectoryByKey.removeWhere((key, _) => key.startsWith(prefix));
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

class _SharedRecacheStatusCard extends StatelessWidget {
  const _SharedRecacheStatusCard({
    required this.progress,
    required this.details,
    required this.formatEta,
  });

  final double? progress;
  final SharedRecacheProgressDetails? details;
  final String Function(Duration eta) formatEta;

  @override
  Widget build(BuildContext context) {
    final processedFiles = details?.processedFiles ?? 0;
    final totalFiles = details?.totalFiles ?? 0;
    final cacheLabel = details?.currentCacheLabel.trim() ?? '';
    final relativePath = details?.currentRelativePath.trim() ?? '';
    final eta = details?.eta;
    final etaText = eta == null ? 'ETA --:--' : 'ETA ${formatEta(eta)}';
    final filesText = totalFiles > 0
        ? '$processedFiles/$totalFiles files'
        : '$processedFiles files';
    final normalizedProgress = progress?.clamp(0.0, 1.0).toDouble();

    final locationText = [
      cacheLabel,
      relativePath,
    ].where((value) => value.isNotEmpty).join(' • ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cached_rounded,
                size: 16,
                color: AppColors.brandPrimaryDark,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'Re-caching shared files',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$filesText • $etaText',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (locationText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              locationText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          LinearProgressIndicator(
            value: normalizedProgress,
            minHeight: 4,
            color: AppColors.brandPrimary,
            backgroundColor: AppColors.mutedBorder,
          ),
        ],
      ),
    );
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
        body = _useMediaKitForPlayback
            ? _MediaKitVideoFileViewer(filePath: filePath)
            : _VideoFileViewer(filePath: filePath);
      case _LocalFileKind.audio:
        body = _useMediaKitForPlayback
            ? _MediaKitAudioFileViewer(filePath: filePath)
            : _AudioFileViewer(filePath: filePath);
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
    if (_supportedImageExtensions.contains(ext)) {
      return _LocalFileKind.image;
    }
    if (_supportedVideoExtensions.contains(ext)) {
      return _LocalFileKind.video;
    }
    if (_supportedAudioExtensions.contains(ext)) {
      return _LocalFileKind.audio;
    }
    if (_supportedTextExtensions.contains(ext)) {
      return _LocalFileKind.text;
    }
    if (ext == '.pdf') {
      return _LocalFileKind.pdf;
    }
    return _LocalFileKind.other;
  }
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

class _MediaKitVideoFileViewer extends StatefulWidget {
  const _MediaKitVideoFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_MediaKitVideoFileViewer> createState() =>
      _MediaKitVideoFileViewerState();
}

class _MediaKitVideoFileViewerState extends State<_MediaKitVideoFileViewer> {
  late final Player _player;
  late final VideoController _videoController;
  late final Future<Uint8List?> _previewFuture;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  String? _errorMessage;
  bool _opened = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _previewFuture = _MediaPreviewCache.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: 1280,
      quality: 82,
      timeMs: 700,
    );
    _player = Player();
    _videoController = VideoController(_player);
    _playingSubscription = _player.stream.playing.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = event;
      });
    });
    _positionSubscription = _player.stream.position.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = event;
      });
    });
    _durationSubscription = _player.stream.duration.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = event;
      });
    });
    _initialize();
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _player.open(
        Media(_mediaUriFromFilePath(widget.filePath)),
        play: false,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _opened = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open video in built-in player.\n$error';
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

    final totalMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, math.max(totalMs, 0));
    final sliderMax = math.max(totalMs, 1).toDouble();
    final aspect = _resolveVideoAspectRatio(_player.state);

    return Column(
      children: [
        Expanded(
          child: Center(
            child: !_opened
                ? FutureBuilder<Uint8List?>(
                    future: _previewFuture,
                    builder: (context, snapshot) {
                      final bytes = snapshot.data;
                      if (bytes != null && bytes.isNotEmpty) {
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                                child: Image.memory(bytes, fit: BoxFit.contain),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.32),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              child: const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Colors.white,
                                size: 46,
                              ),
                            ),
                          ],
                        );
                      }
                      return const CircularProgressIndicator();
                    },
                  )
                : AspectRatio(
                    aspectRatio: aspect,
                    child: Video(
                      controller: _videoController,
                      controls: null,
                      fit: BoxFit.contain,
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Slider(
            value: positionMs.toDouble().clamp(0, sliderMax),
            min: 0,
            max: sliderMax,
            onChanged: _duration == Duration.zero
                ? null
                : (value) {
                    _player.seek(Duration(milliseconds: value.round()));
                  },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Text(
                '${_formatPlaybackDuration(_position)} / ${_formatPlaybackDuration(_duration)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Back 10s',
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target.isNegative ? Duration.zero : target);
                },
                icon: const Icon(Icons.replay_10_rounded),
              ),
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 36,
                ),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  final bounded =
                      _duration == Duration.zero || target < _duration
                      ? target
                      : _duration;
                  _player.seek(bounded);
                },
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _MediaKitAudioFileViewer extends StatefulWidget {
  const _MediaKitAudioFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_MediaKitAudioFileViewer> createState() =>
      _MediaKitAudioFileViewerState();
}

class _MediaKitAudioFileViewerState extends State<_MediaKitAudioFileViewer> {
  late final Player _player;
  late final Future<Uint8List?> _coverFuture;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  String? _errorMessage;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _coverFuture = _MediaPreviewCache.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: 1200,
      quality: 86,
    );
    _player = Player();
    _playingSubscription = _player.stream.playing.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isPlaying = event;
      });
    });
    _positionSubscription = _player.stream.position.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = event;
      });
    });
    _durationSubscription = _player.stream.duration.listen((event) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = event;
      });
    });
    _initialize();
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await _player.open(
        Media(_mediaUriFromFilePath(widget.filePath)),
        play: false,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot open audio in built-in player.\n$error';
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

    final totalMs = _duration.inMilliseconds;
    final positionMs = _position.inMilliseconds.clamp(0, math.max(totalMs, 0));
    final sliderMax = math.max(totalMs, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 540,
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _coverFuture,
                  builder: (context, snapshot) {
                    final cover = snapshot.data;
                    if (cover != null && cover.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Image.memory(cover, fit: BoxFit.contain),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.mutedBorder),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: AppColors.mutedIcon,
                        size: 64,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          Slider(
            value: positionMs.toDouble().clamp(0, sliderMax),
            min: 0,
            max: sliderMax,
            onChanged: _duration == Duration.zero
                ? null
                : (value) {
                    _player.seek(Duration(milliseconds: value.round()));
                  },
          ),
          Row(
            children: [
              Text(
                '${_formatPlaybackDuration(_position)} / ${_formatPlaybackDuration(_duration)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Back 10s',
                onPressed: () {
                  final target = _position - const Duration(seconds: 10);
                  _player.seek(target.isNegative ? Duration.zero : target);
                },
                icon: const Icon(Icons.replay_10_rounded),
              ),
              IconButton(
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: () {
                  if (_isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                },
                icon: Icon(
                  _isPlaying
                      ? Icons.pause_circle_filled_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 36,
                ),
              ),
              IconButton(
                tooltip: 'Forward 10s',
                onPressed: () {
                  final target = _position + const Duration(seconds: 10);
                  final bounded =
                      _duration == Duration.zero || target < _duration
                      ? target
                      : _duration;
                  _player.seek(bounded);
                },
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
        ],
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
  late final Future<Uint8List?> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = _MediaPreviewCache.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: 1280,
      quality: 82,
      timeMs: 700,
    );
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
      return Center(
        child: FutureBuilder<Uint8List?>(
          future: _previewFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.32),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ],
              );
            }
            return const CircularProgressIndicator();
          },
        ),
      );
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

class _AudioFileViewer extends StatefulWidget {
  const _AudioFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_AudioFileViewer> createState() => _AudioFileViewerState();
}

class _AudioFileViewerState extends State<_AudioFileViewer> {
  VideoPlayerController? _controller;
  String? _errorMessage;
  late final Future<Uint8List?> _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _MediaPreviewCache.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: 1200,
      quality: 86,
    );
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
        _errorMessage = 'Cannot open audio in built-in player.\n$error';
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

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                  maxHeight: 540,
                ),
                child: FutureBuilder<Uint8List?>(
                  future: _coverFuture,
                  builder: (context, snapshot) {
                    final cover = snapshot.data;
                    if (cover != null && cover.isNotEmpty) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Image.memory(cover, fit: BoxFit.contain),
                      );
                    }
                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.mutedBorder),
                      ),
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: const Icon(
                        Icons.audiotrack_rounded,
                        color: AppColors.mutedIcon,
                        size: 64,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
          ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final isPlaying = value.isPlaying;
              final position = value.position;
              final duration = value.duration;
              return Row(
                children: [
                  Text(
                    '${_formatDuration(position)} / ${_formatDuration(duration)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Back 10s',
                    onPressed: () async {
                      final target = position - const Duration(seconds: 10);
                      await controller.seekTo(
                        target.isNegative ? Duration.zero : target,
                      );
                    },
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  IconButton(
                    tooltip: isPlaying ? 'Pause' : 'Play',
                    onPressed: () async {
                      if (isPlaying) {
                        await controller.pause();
                      } else {
                        await controller.play();
                      }
                    },
                    icon: Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 36,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Forward 10s',
                    onPressed: () async {
                      final target = position + const Duration(seconds: 10);
                      final bounded =
                          duration == Duration.zero || target < duration
                          ? target
                          : duration;
                      await controller.seekTo(bounded);
                    },
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration value) {
    final totalSeconds = value.inSeconds.clamp(0, 359999);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

String _mediaUriFromFilePath(String filePath) {
  return Uri.file(filePath).toString();
}

String _formatPlaybackDuration(Duration value) {
  final totalSeconds = value.inSeconds.clamp(0, 359999);
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

double _resolveVideoAspectRatio(PlayerState state) {
  final width = state.width ?? state.videoParams.dw ?? state.videoParams.w;
  final height = state.height ?? state.videoParams.dh ?? state.videoParams.h;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return 16 / 9;
  }
  return width / height;
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
  const _ExplorerEntityTile({
    required this.entry,
    required this.onTap,
    this.onDelete,
  });

  final _ExplorerEntityRecord entry;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;

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
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Remove from sharing',
              onPressed: () async {
                await onDelete!();
              },
              icon: const Icon(Icons.delete_outline_rounded),
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

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(filePath).toLowerCase();
    if (_supportedImageExtensions.contains(ext)) {
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
    if (_supportedVideoExtensions.contains(ext)) {
      return _ExplorerVideoPreview(filePath: filePath, size: size);
    }
    if (_supportedAudioExtensions.contains(ext)) {
      return _ExplorerAudioPreview(filePath: filePath, size: size);
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
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  Future<Uint8List?> _loadThumbnail() async {
    return _MediaPreviewCache.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: math.max(180, (widget.size * 2).round()),
      quality: 72,
      timeMs: 700,
    );
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

class _ExplorerAudioPreview extends StatefulWidget {
  const _ExplorerAudioPreview({required this.filePath, this.size = 44});

  final String filePath;
  final double size;

  @override
  State<_ExplorerAudioPreview> createState() => _ExplorerAudioPreviewState();
}

class _ExplorerAudioPreviewState extends State<_ExplorerAudioPreview> {
  late final Future<Uint8List?> _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = _MediaPreviewCache.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: math.max(180, (widget.size * 2).round()),
      quality: 78,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _coverFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildFallback();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
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
      child: const Icon(Icons.audiotrack_rounded, color: AppColors.mutedIcon),
    );
  }
}

class _MediaPreviewCache {
  static final Map<String, Uint8List?> _memoryByKey = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _pendingByKey =
      <String, Future<Uint8List?>>{};
  static Directory? _cacheDirectory;
  static const int _maxInMemoryItems = 320;

  static Future<Uint8List?> loadVideoPreview({
    required String filePath,
    required int maxExtent,
    required int quality,
    required int timeMs,
  }) {
    return _loadOrCreate(
      kind: 'video',
      filePath: filePath,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: 't$timeMs',
      builder: () async {
        if (_useMediaKitForPlayback) {
          final bytes = await _buildVideoPreviewWithMediaKit(
            filePath: filePath,
            timeMs: timeMs,
          );
          if (bytes == null || bytes.isEmpty) {
            return null;
          }
          return _normalizeArtworkBytes(
            bytes,
            maxExtent: maxExtent,
            quality: quality,
          );
        } else {
          final bytes = await video_thumbnail.VideoThumbnail.thumbnailData(
            video: filePath,
            imageFormat: video_thumbnail.ImageFormat.JPEG,
            maxWidth: maxExtent,
            quality: quality,
            timeMs: timeMs,
          );
          if (bytes == null || bytes.isEmpty) {
            return null;
          }
          return Uint8List.fromList(bytes);
        }
      },
    );
  }

  static Future<Uint8List?> loadAudioCover({
    required String filePath,
    required int maxExtent,
    required int quality,
  }) {
    return _loadOrCreate(
      kind: 'audio',
      filePath: filePath,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: 'cover',
      builder: () async {
        final metadata = await MetadataRetriever.fromFile(File(filePath));
        final rawCover = metadata.albumArt;
        if (rawCover == null || rawCover.isEmpty) {
          return null;
        }
        return _normalizeArtworkBytes(
          rawCover,
          maxExtent: maxExtent,
          quality: quality,
        );
      },
    );
  }

  static Future<Uint8List?> _loadOrCreate({
    required String kind,
    required String filePath,
    required int maxExtent,
    required int quality,
    required String extraKey,
    required Future<Uint8List?> Function() builder,
  }) async {
    if (filePath.trim().isEmpty) {
      return null;
    }

    final source = File(filePath);
    if (!await source.exists()) {
      return null;
    }

    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }

    final key = _buildCacheKey(
      kind: kind,
      filePath: filePath,
      stat: stat,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: extraKey,
    );
    if (_memoryByKey.containsKey(key)) {
      return _memoryByKey[key];
    }
    final pending = _pendingByKey[key];
    if (pending != null) {
      return pending;
    }

    final future = () async {
      try {
        final cacheDir = await _resolveCacheDirectory();
        final cacheFile = File(p.join(cacheDir.path, '$kind-$key.jpg'));
        if (await cacheFile.exists()) {
          final cachedBytes = await cacheFile.readAsBytes();
          _rememberInMemory(key, cachedBytes);
          return cachedBytes;
        }

        final generated = await builder();
        if (generated == null || generated.isEmpty) {
          _rememberInMemory(key, null);
          return null;
        }

        if (!await cacheFile.parent.exists()) {
          await cacheFile.parent.create(recursive: true);
        }
        await cacheFile.writeAsBytes(generated, flush: true);
        _rememberInMemory(key, generated);
        return generated;
      } catch (_) {
        return null;
      } finally {
        _pendingByKey.remove(key);
      }
    }();

    _pendingByKey[key] = future;
    return future;
  }

  static String _buildCacheKey({
    required String kind,
    required String filePath,
    required FileStat stat,
    required int maxExtent,
    required int quality,
    required String extraKey,
  }) {
    var normalizedPath = p.normalize(filePath).replaceAll('\\', '/');
    if (Platform.isWindows) {
      normalizedPath = normalizedPath.toLowerCase();
    }
    final input =
        '$kind|$normalizedPath|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$maxExtent|$quality|$extraKey';
    return sha256.convert(utf8.encode(input)).toString();
  }

  static void _rememberInMemory(String key, Uint8List? value) {
    _memoryByKey[key] = value;
    if (_memoryByKey.length <= _maxInMemoryItems) {
      return;
    }
    final firstKey = _memoryByKey.keys.first;
    _memoryByKey.remove(firstKey);
  }

  static Future<Directory> _resolveCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) {
      return existing;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'Landa', 'media_previews'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectory = dir;
    return dir;
  }

  static Future<Uint8List?> _normalizeArtworkBytes(
    Uint8List bytes, {
    required int maxExtent,
    required int quality,
  }) async {
    try {
      return await Isolate.run(
        () => _normalizeArtworkBytesSync(
          bytes: bytes,
          maxExtent: maxExtent,
          quality: quality,
        ),
      );
    } catch (_) {
      return bytes;
    }
  }

  static Future<Uint8List?> _buildVideoPreviewWithMediaKit({
    required String filePath,
    required int timeMs,
  }) async {
    final player = Player();
    try {
      await player.open(Media(_mediaUriFromFilePath(filePath)), play: false);
      if (timeMs > 0) {
        await player.seek(Duration(milliseconds: timeMs));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return player.screenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  static Uint8List? _normalizeArtworkBytesSync({
    required Uint8List bytes,
    required int maxExtent,
    required int quality,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    final resized = _resizeToLongestEdge(decoded, maxExtent: maxExtent);
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  static img.Image _resizeToLongestEdge(
    img.Image source, {
    required int maxExtent,
  }) {
    if (source.width <= maxExtent && source.height <= maxExtent) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxExtent);
    }
    return img.copyResize(source, height: maxExtent);
  }
}

class _ExplorerEntityGridTile extends StatelessWidget {
  const _ExplorerEntityGridTile({
    required this.entry,
    required this.tileExtent,
    required this.onTap,
    this.onDelete,
  });

  final _ExplorerEntityRecord entry;
  final double tileExtent;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: onDelete == null
          ? null
          : (details) async {
              final action = await showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                  details.globalPosition.dx,
                  details.globalPosition.dy,
                ),
                items: const [
                  PopupMenuItem<String>(
                    value: 'remove',
                    child: Text('Remove from sharing'),
                  ),
                ],
              );
              if (action == 'remove') {
                await onDelete!();
              }
            },
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        onLongPress: onDelete == null
            ? null
            : () async {
                await onDelete!();
              },
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
              final availableWidth =
                  constraints.maxWidth - horizontalPadding * 2;
              final availableHeight =
                  constraints.maxHeight - verticalPadding * 2;
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

enum _LocalFileKind { image, video, audio, text, pdf, other }

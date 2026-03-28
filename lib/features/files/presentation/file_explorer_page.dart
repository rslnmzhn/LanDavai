import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../discovery/application/shared_cache_maintenance_boundary.dart';
import '../application/file_explorer_contract.dart';
import '../application/files_feature_state_owner.dart';
import '../application/preview_cache_owner.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/domain/shared_folder_cache.dart';

part 'file_explorer/file_explorer_models.dart';
part 'file_explorer/file_explorer_recache_status.dart';
part 'file_explorer/local_file_viewer.dart';
part 'file_explorer/file_explorer_widgets.dart';
part 'file_explorer/file_explorer_tail_widgets.dart';

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({
    required this.owner,
    required this.previewCacheOwner,
    required this.sharedCacheMaintenanceBoundary,
    super.key,
  }) : _launchConfig = null;

  FileExplorerPage.launch({
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required this.previewCacheOwner,
    required this.sharedCacheMaintenanceBoundary,
    required String ownerMacAddress,
    required String receiveDirectoryPath,
    String? publicDownloadsDirectoryPath,
    super.key,
  }) : owner = null,
       _launchConfig = _FileExplorerLaunchConfig(
         sharedCacheCatalog: sharedCacheCatalog,
         sharedCacheIndexStore: sharedCacheIndexStore,
         ownerMacAddress: ownerMacAddress,
         receiveDirectoryPath: receiveDirectoryPath,
         publicDownloadsDirectoryPath: publicDownloadsDirectoryPath,
       );

  final FilesFeatureStateOwner? owner;
  final PreviewCacheOwner previewCacheOwner;
  final SharedCacheMaintenanceBoundary sharedCacheMaintenanceBoundary;
  final _FileExplorerLaunchConfig? _launchConfig;

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  final TextEditingController _searchController = TextEditingController();
  FilesFeatureStateOwner? _ownedOwner;
  FilesFeatureStateOwner? _attachedOwner;
  String? _launchErrorMessage;

  FilesFeatureStateOwner? get _owner => widget.owner ?? _ownedOwner;

  FilesFeatureStateOwner get _requiredOwner {
    final owner = _owner;
    if (owner == null) {
      throw StateError('File explorer owner is not ready.');
    }
    return owner;
  }

  bool get _isSharedRecacheRunning =>
      widget.sharedCacheMaintenanceBoundary.isRecacheInProgress;

  double? get _sharedRecacheProgressValue =>
      widget.sharedCacheMaintenanceBoundary.recacheProgressValue;

  SharedCacheMaintenanceProgress? get _sharedRecacheDetailsValue =>
      widget.sharedCacheMaintenanceBoundary.recacheProgress;

  @override
  void initState() {
    super.initState();
    _attachOwner(_owner);
    if (_owner == null) {
      unawaited(_initializeLaunchOwner());
    }
  }

  @override
  void didUpdateWidget(covariant FileExplorerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      _attachOwner(widget.owner);
      if (widget.owner != null) {
        _disposeOwnedOwner();
        setState(() {
          _launchErrorMessage = null;
        });
      }
    } else if (widget.owner == null &&
        _ownedOwner == null &&
        widget._launchConfig != null) {
      unawaited(_initializeLaunchOwner());
    }
  }

  @override
  void dispose() {
    _attachOwner(null);
    _disposeOwnedOwner();
    _searchController.dispose();
    super.dispose();
  }

  void _handleOwnerChanged() {
    _syncSearchController();
  }

  void _syncSearchController() {
    final owner = _owner;
    if (owner == null) {
      return;
    }
    final query = owner.state.searchQuery;
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = _owner;
    if (owner == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Files')),
        body: Center(
          child: _launchErrorMessage == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_launchErrorMessage!, textAlign: TextAlign.center),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: _initializeLaunchOwner,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    final animation = Listenable.merge(<Listenable>[
      owner,
      widget.sharedCacheMaintenanceBoundary,
    ]);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final state = owner.state;
        final selectedRoot = state.selectedRoot;
        final visibleEntries = state.visibleEntries;
        final canRecacheSelectedRoot = selectedRoot?.isSharedFolder == true;
        final canRemoveSharedCachesFromFiles =
            selectedRoot?.isSharedFolder == true;
        final refreshActionTooltip = canRecacheSelectedRoot
            ? 'Re-cache shared folders/files'
            : 'Refresh';
        final refreshActionIcon = canRecacheSelectedRoot
            ? Icons.cached_rounded
            : Icons.refresh_rounded;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Files'),
            actions: [
              IconButton(
                tooltip: refreshActionTooltip,
                onPressed: () => _handleRefreshAction(
                  canRecacheSelectedRoot: canRecacheSelectedRoot,
                ),
                icon: _buildRefreshActionIcon(
                  canRecacheSelectedRoot: canRecacheSelectedRoot,
                  refreshActionIcon: refreshActionIcon,
                ),
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
                    rootLabel: selectedRoot?.label ?? 'Files',
                    relativePath: owner.relativePathLabel(),
                    canGoUp: owner.canGoUp,
                    onGoUp: owner.canGoUp ? () => owner.goUp() : null,
                    canSelectRoot: state.roots.isNotEmpty,
                    onSelectRoot: state.roots.isNotEmpty ? _pickRoot : null,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      _DisplayModeToggle(
                        isGrid: state.viewMode == FilesFeatureViewMode.grid,
                        onToggle: owner.toggleViewMode,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchController,
                            onChanged: owner.setSearchQuery,
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
                          var menuTileSize = state.gridTileExtent;
                          return [
                            const PopupMenuItem<_ExplorerMenuAction>(
                              enabled: false,
                              child: Text('Sort'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortNameAsc,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.nameAsc,
                              child: const Text('A-Z'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortNameDesc,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.nameDesc,
                              child: const Text('Z-A'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortModifiedNewest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.modifiedNewest,
                              child: const Text('Modified: newest'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortModifiedOldest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.modifiedOldest,
                              child: const Text('Modified: oldest'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortChangedNewest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.changedNewest,
                              child: const Text('Created/changed: newest'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortChangedOldest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.changedOldest,
                              child: const Text('Created/changed: oldest'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortSizeLargest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.sizeLargest,
                              child: const Text('Size: largest'),
                            ),
                            CheckedPopupMenuItem<_ExplorerMenuAction>(
                              value: _ExplorerMenuAction.sortSizeSmallest,
                              checked:
                                  state.sortOption ==
                                  FilesFeatureSortOption.sizeSmallest,
                              child: const Text('Size: smallest'),
                            ),
                            const PopupMenuDivider(),
                            PopupMenuItem<_ExplorerMenuAction>(
                              enabled: false,
                              height: 86,
                              child: StatefulBuilder(
                                builder: (context, setMenuState) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tile size',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelMedium,
                                      ),
                                      Slider(
                                        value: menuTileSize,
                                        min: FilesFeatureStateOwner
                                            .minGridTileExtent,
                                        max: FilesFeatureStateOwner
                                            .maxGridTileExtent,
                                        divisions: 3,
                                        onChanged: (next) {
                                          setMenuState(() {
                                            menuTileSize = next;
                                          });
                                          owner.setGridTileExtent(next);
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
                  if (canRecacheSelectedRoot && _isSharedRecacheRunning) ...[
                    _SharedRecacheStatusCard(
                      progress: _sharedRecacheProgressValue,
                      details: _sharedRecacheDetailsValue,
                      formatEta: _formatEta,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (state.isLoading)
                    const LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.brandPrimary,
                      backgroundColor: AppColors.mutedBorder,
                    ),
                  if (state.errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _ExplorerErrorBanner(
                      message: state.errorMessage!,
                      onRetry: owner.refreshCurrentRoot,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: visibleEntries.isEmpty
                        ? const Center(child: Text('Folder is empty'))
                        : state.viewMode == FilesFeatureViewMode.list
                        ? ListView.separated(
                            itemCount: visibleEntries.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: AppSpacing.xs),
                            itemBuilder: (_, index) {
                              final entry = visibleEntries[index];
                              return _ExplorerEntityTile(
                                entry: entry,
                                previewCacheOwner: widget.previewCacheOwner,
                                onTap: () => _openEntry(entry),
                                onDelete:
                                    canRemoveSharedCachesFromFiles &&
                                        entry.removableSharedCacheId != null
                                    ? () => _removeSharedCacheFromEntry(entry)
                                    : null,
                              );
                            },
                          )
                        : GridView.builder(
                            itemCount: visibleEntries.length,
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: state.gridTileExtent,
                                  mainAxisSpacing: AppSpacing.xs,
                                  crossAxisSpacing: AppSpacing.xs,
                                  childAspectRatio: 0.9,
                                ),
                            itemBuilder: (_, index) {
                              final entry = visibleEntries[index];
                              return _ExplorerEntityGridTile(
                                entry: entry,
                                tileExtent: state.gridTileExtent,
                                previewCacheOwner: widget.previewCacheOwner,
                                onTap: () => _openEntry(entry),
                                onDelete:
                                    canRemoveSharedCachesFromFiles &&
                                        entry.removableSharedCacheId != null
                                    ? () => _removeSharedCacheFromEntry(entry)
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRefreshActionIcon({
    required bool canRecacheSelectedRoot,
    required IconData refreshActionIcon,
  }) {
    if (canRecacheSelectedRoot && _isSharedRecacheRunning) {
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
    return Icon(refreshActionIcon);
  }

  Future<void> _removeSharedCacheFromEntry(FilesFeatureEntry entry) async {
    final owner = _requiredOwner;
    final cacheId = entry.removableSharedCacheId;
    if (cacheId == null || cacheId.trim().isEmpty) {
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

    bool removed = false;
    try {
      removed = await widget.sharedCacheMaintenanceBoundary.removeCacheById(
        cacheId,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove shared folder: $error')),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (!removed || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shared folder is no longer available.')),
      );
      return;
    }

    owner.clearVirtualFolderIfRemoved(entry.virtualFolderPath ?? '');
    owner.invalidateSelectedVirtualRootCache();
    await owner.refreshCurrentRoot();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed from sharing: ${entry.name}')),
    );
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

  void _handleMenuAction(_ExplorerMenuAction action) {
    _requiredOwner.setSortOption(_sortOptionFromMenuAction(action));
  }

  FilesFeatureSortOption _sortOptionFromMenuAction(_ExplorerMenuAction action) {
    switch (action) {
      case _ExplorerMenuAction.sortNameAsc:
        return FilesFeatureSortOption.nameAsc;
      case _ExplorerMenuAction.sortNameDesc:
        return FilesFeatureSortOption.nameDesc;
      case _ExplorerMenuAction.sortModifiedNewest:
        return FilesFeatureSortOption.modifiedNewest;
      case _ExplorerMenuAction.sortModifiedOldest:
        return FilesFeatureSortOption.modifiedOldest;
      case _ExplorerMenuAction.sortChangedNewest:
        return FilesFeatureSortOption.changedNewest;
      case _ExplorerMenuAction.sortChangedOldest:
        return FilesFeatureSortOption.changedOldest;
      case _ExplorerMenuAction.sortSizeLargest:
        return FilesFeatureSortOption.sizeLargest;
      case _ExplorerMenuAction.sortSizeSmallest:
        return FilesFeatureSortOption.sizeSmallest;
    }
  }

  Future<void> _pickRoot() async {
    final owner = _requiredOwner;
    final state = owner.state;
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: state.roots.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final root = state.roots[index];
              return ListTile(
                leading: const Icon(Icons.folder_special_rounded),
                title: Text(root.label),
                subtitle: Text(root.isVirtual ? 'All shared files' : root.path),
                trailing: index == state.selectedRootIndex
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }
    await owner.selectRoot(selected);
  }

  Future<void> _handleRefreshAction({
    required bool canRecacheSelectedRoot,
  }) async {
    final owner = _requiredOwner;
    if (!canRecacheSelectedRoot) {
      owner.invalidateSelectedVirtualRootCache();
      await owner.refreshCurrentRoot();
      return;
    }
    final boundary = widget.sharedCacheMaintenanceBoundary;
    if (boundary.isRecacheInProgress || boundary.isRecacheCooldownActive) {
      owner.invalidateSelectedVirtualRootCache();
      await owner.refreshCurrentRoot();
      return;
    }

    final normalizedFolder = owner.normalizedVirtualCurrentFolder;
    final before = await boundary.summarizeOwnerSharedContent(
      virtualFolderPath: normalizedFolder,
    );
    if (!mounted) {
      return;
    }
    if (before.totalCaches == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            normalizedFolder.isEmpty
                ? 'No shared folders/files to re-cache yet.'
                : 'Selected folder has no shared files to re-cache.',
          ),
        ),
      );
      owner.invalidateSelectedVirtualRootCache();
      await owner.refreshCurrentRoot();
      return;
    }

    final agreed = await _confirmSharedRecacheAgreement(
      before,
      virtualFolderPath: normalizedFolder,
    );
    if (!agreed || !mounted) {
      return;
    }

    try {
      final report = await boundary.recacheOwner(
        virtualFolderPath: normalizedFolder,
      );
      if (mounted && report != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Before cache: ${report.before.totalFiles} files, '
              'after re-cache: ${report.after.totalFiles} files.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to re-cache shared folders/files: $error'),
          ),
        );
      }
      return;
    }
    owner.invalidateSelectedVirtualRootCache();
    await owner.refreshCurrentRoot();
  }

  Future<bool> _confirmSharedRecacheAgreement(
    SharedCacheSummary before, {
    required String virtualFolderPath,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        final folderLabel = before.folderCaches == 1 ? 'folder' : 'folders';
        final fileLabel = before.totalFiles == 1 ? 'file' : 'files';
        final selectionText = before.selectionCaches > 0
            ? '\nSelection caches: ${before.selectionCaches}'
            : '';
        final scopeText = virtualFolderPath.isEmpty
            ? 'Re-cache will rebuild indexes for all shared folders/files.'
            : 'Re-cache will rebuild indexes only in: $virtualFolderPath';
        return AlertDialog(
          title: const Text('Start re-cache?'),
          content: Text(
            'Currently cached: ${before.folderCaches} $folderLabel, '
            '${before.totalFiles} $fileLabel.$selectionText\n\n$scopeText',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _openEntry(FilesFeatureEntry entry) async {
    final openedDirectory = await _requiredOwner.openDirectory(entry);
    if (openedDirectory) {
      return;
    }

    final filePath = entry.filePath;
    if (filePath == null || filePath.trim().isEmpty || !mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalFileViewerPage(
          filePath: filePath,
          previewCacheOwner: widget.previewCacheOwner,
        ),
      ),
    );
  }

  void _attachOwner(FilesFeatureStateOwner? owner) {
    if (identical(_attachedOwner, owner)) {
      return;
    }
    _attachedOwner?.removeListener(_handleOwnerChanged);
    _attachedOwner = owner;
    _attachedOwner?.addListener(_handleOwnerChanged);
    _syncSearchController();
  }

  void _disposeOwnedOwner() {
    final owner = _ownedOwner;
    if (owner == null) {
      return;
    }
    if (identical(_attachedOwner, owner)) {
      _attachOwner(null);
    }
    _ownedOwner = null;
    owner.dispose();
  }

  Future<void> _initializeLaunchOwner() async {
    final config = widget._launchConfig;
    if (config == null) {
      return;
    }

    setState(() {
      _launchErrorMessage = null;
    });

    try {
      final roots = await _buildLaunchRoots(config);
      final nextOwner = FilesFeatureStateOwner(roots: roots);
      await nextOwner.initialize();
      if (!mounted) {
        nextOwner.dispose();
        return;
      }

      final previousOwner = _ownedOwner;
      setState(() {
        _ownedOwner = nextOwner;
        _launchErrorMessage = null;
      });
      _attachOwner(nextOwner);
      if (previousOwner != null && !identical(previousOwner, nextOwner)) {
        previousOwner.dispose();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _launchErrorMessage = 'Cannot open files: $error';
      });
    }
  }

  Future<List<FileExplorerRoot>> _buildLaunchRoots(
    _FileExplorerLaunchConfig config,
  ) async {
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

    final publicDownloadsPath = config.publicDownloadsDirectoryPath?.trim();
    if (publicDownloadsPath != null && publicDownloadsPath.isNotEmpty) {
      addLocalRoot(label: 'Landa Downloads', path: publicDownloadsPath);
    }
    addLocalRoot(label: 'Incoming', path: config.receiveDirectoryPath);

    final ownerCaches = await _loadOwnerCaches(config);
    final hasSharedFiles = ownerCaches.any((cache) => cache.itemCount > 0);
    if (hasSharedFiles) {
      roots.add(
        FileExplorerRoot(
          label: 'My files',
          path: 'virtual://my-files',
          isSharedFolder: true,
          virtualDirectoryLoader: (folderPath) =>
              _listShareableLocalDirectory(config, folderPath),
        ),
      );
    }

    return roots;
  }

  Future<List<SharedFolderCacheRecord>> _loadOwnerCaches(
    _FileExplorerLaunchConfig config,
  ) async {
    final ownerMacAddress = config.ownerMacAddress.trim();
    if (ownerMacAddress.isNotEmpty) {
      try {
        await config.sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: ownerMacAddress,
        );
      } catch (_) {
        // Keep using the last loaded owner snapshot in the current session.
      }
    }
    return config.sharedCacheCatalog.ownerCaches;
  }

  Future<FileExplorerVirtualDirectory> _listShareableLocalDirectory(
    _FileExplorerLaunchConfig config,
    String virtualFolderPath,
  ) async {
    final caches = await _loadOwnerCaches(config);
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
      final entries = await config.sharedCacheIndexStore.readIndexEntries(
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

class _FileExplorerLaunchConfig {
  const _FileExplorerLaunchConfig({
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.ownerMacAddress,
    required this.receiveDirectoryPath,
    this.publicDownloadsDirectoryPath,
  });

  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final String ownerMacAddress;
  final String receiveDirectoryPath;
  final String? publicDownloadsDirectoryPath;
}

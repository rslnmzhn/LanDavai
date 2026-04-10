import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../files/application/file_explorer_contract.dart';
import '../../files/application/files_feature_state_owner.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../files/presentation/file_explorer/file_explorer_models.dart';
import '../../files/presentation/file_explorer/file_explorer_tail_widgets.dart';
import '../../files/presentation/file_explorer/file_explorer_widgets.dart';
import '../../files/presentation/file_explorer/local_file_viewer.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../application/remote_share_browser.dart';

class RemoteDownloadBrowserPage extends StatefulWidget {
  const RemoteDownloadBrowserPage({
    required this.onRefreshRemoteShares,
    required this.remoteShareBrowser,
    required this.previewCacheOwner,
    required this.transferSessionCoordinator,
    required this.useStandardAppDownloadFolder,
    super.key,
  });

  final Future<void> Function() onRefreshRemoteShares;
  final RemoteShareBrowser remoteShareBrowser;
  final PreviewCacheOwner previewCacheOwner;
  final TransferSessionCoordinator transferSessionCoordinator;
  final bool useStandardAppDownloadFolder;

  @override
  State<RemoteDownloadBrowserPage> createState() =>
      _RemoteDownloadBrowserPageState();
}

class _RemoteDownloadBrowserPageState extends State<RemoteDownloadBrowserPage> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, FilesFeatureStateOwner> _ownersByFilterKey =
      <String, FilesFeatureStateOwner>{};
  final Set<String> _selectedTokens = <String>{};

  String _activeFilterKey = RemoteShareBrowser.allDevicesFilterKey;
  String? _previewingToken;
  bool _isDownloading = false;

  RemoteShareBrowser get _browser => widget.remoteShareBrowser;

  FilesFeatureStateOwner? get _activeOwner =>
      _ownersByFilterKey[_activeFilterKey];

  @override
  void initState() {
    super.initState();
    _browser.addListener(_handleBrowserChanged);
    unawaited(_ensureOwnerForFilter(_activeFilterKey));
  }

  @override
  void dispose() {
    _browser.removeListener(_handleBrowserChanged);
    _searchController.dispose();
    for (final owner in _ownersByFilterKey.values) {
      owner.dispose();
    }
    _ownersByFilterKey.clear();
    super.dispose();
  }

  void _handleBrowserChanged() {
    unawaited(_reconcileProjectionChange());
  }

  Future<void> _reconcileProjectionChange() async {
    final validTokens = _browser.currentFileTokens();
    _selectedTokens.removeWhere((token) => !validTokens.contains(token));

    final validFilterKeys = <String>{
      RemoteShareBrowser.allDevicesFilterKey,
      ..._browser.currentBrowseProjection.owners.map((owner) => owner.ip),
    };
    final removableKeys = _ownersByFilterKey.keys
        .where((key) => !validFilterKeys.contains(key))
        .toList(growable: false);
    for (final key in removableKeys) {
      _ownersByFilterKey.remove(key)?.dispose();
    }
    if (!validFilterKeys.contains(_activeFilterKey)) {
      _activeFilterKey = RemoteShareBrowser.allDevicesFilterKey;
    }
    await Future.wait(
      _ownersByFilterKey.values.map((owner) => owner.refreshCurrentRoot()),
    );
    if (!mounted) {
      return;
    }
    _syncSearchController();
    setState(() {});
  }

  Future<void> _ensureOwnerForFilter(String filterKey) async {
    final existing = _ownersByFilterKey[filterKey];
    if (existing != null) {
      return;
    }
    final owner = FilesFeatureStateOwner(
      roots: <FileExplorerRoot>[
        FileExplorerRoot(
          label: _browser.rootLabelForFilter(filterKey),
          path: 'virtual://remote/$filterKey',
          virtualDirectoryLoader: (folderPath) async {
            return _browser
                .buildExplorerDirectory(
                  filterKey: filterKey,
                  folderPath: folderPath,
                )
                .entries;
          },
        ),
      ],
    );
    _ownersByFilterKey[filterKey] = owner;
    await owner.initialize();
    if (!mounted) {
      owner.dispose();
      _ownersByFilterKey.remove(filterKey);
      return;
    }
    owner.addListener(_syncSearchController);
    _syncSearchController();
    setState(() {});
  }

  void _syncSearchController() {
    final owner = _activeOwner;
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
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _browser,
        ..._ownersByFilterKey.values,
      ]),
      builder: (context, _) {
        final projection = _browser.currentBrowseProjection;
        final activeOwner = _activeOwner;
        final owners = projection.owners;
        final filterChoices = <_DeviceFilterChoice>[
          const _DeviceFilterChoice(
            key: RemoteShareBrowser.allDevicesFilterKey,
            label: 'Все устройства',
          ),
          ...owners.map(
            (owner) => _DeviceFilterChoice(key: owner.ip, label: owner.name),
          ),
        ];
        final directory = _browser.buildExplorerDirectory(
          filterKey: _activeFilterKey,
          folderPath: activeOwner?.normalizedVirtualCurrentFolder ?? '',
        );
        final state = activeOwner?.state;
        final visibleEntries =
            activeOwner?.visibleEntries ?? const <FilesFeatureEntry>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Скачать из сети'),
            actions: [
              IconButton(
                tooltip: 'Обновить список',
                onPressed: _browser.isLoading
                    ? null
                    : widget.onRefreshRemoteShares,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: _DeviceFilterBar(
                    filters: filterChoices,
                    selectedKey: _activeFilterKey,
                    onSelected: _handleFilterSelected,
                  ),
                ),
                if (_browser.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      color: AppColors.brandPrimary,
                      backgroundColor: AppColors.mutedBorder,
                    ),
                  ),
                Expanded(
                  child: activeOwner == null
                      ? const Center(child: CircularProgressIndicator())
                      : Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ExplorerPathHeader(
                                rootLabel: _browser.rootLabelForFilter(
                                  _activeFilterKey,
                                ),
                                relativePath: activeOwner.relativePathLabel(),
                                canGoUp: activeOwner.canGoUp,
                                onGoUp: activeOwner.canGoUp
                                    ? () => activeOwner.goUp()
                                    : null,
                                canSelectRoot: false,
                                onSelectRoot: null,
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Row(
                                children: [
                                  DisplayModeToggle(
                                    isGrid:
                                        state!.viewMode ==
                                        FilesFeatureViewMode.grid,
                                    onToggle: activeOwner.toggleViewMode,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: SizedBox(
                                      height: 40,
                                      child: TextField(
                                        controller: _searchController,
                                        onChanged: activeOwner.setSearchQuery,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          border: OutlineInputBorder(),
                                          hintText: 'Search files',
                                          prefixIcon: Icon(
                                            Icons.search_rounded,
                                            size: 18,
                                          ),
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
                                  PopupMenuButton<ExplorerMenuAction>(
                                    tooltip: 'Sort',
                                    onSelected: (action) =>
                                        activeOwner.setSortOption(
                                          _sortOptionFromMenuAction(action),
                                        ),
                                    itemBuilder: (context) =>
                                        _sortMenuItems(state),
                                    padding: EdgeInsets.zero,
                                    child: Container(
                                      height: 40,
                                      width: 40,
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        border: Border.all(
                                          color: AppColors.mutedBorder,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.md,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.sort_rounded,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              if (directory.isFileListCapped)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.sm,
                                  ),
                                  child: Text(
                                    'Показаны первые ${directory.entries.files.length} файлов '
                                    '(скрыто: ${directory.hiddenFilesCount}) для стабильной работы.',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                  ),
                                ),
                              Expanded(
                                child: visibleEntries.isEmpty
                                    ? _RemoteDownloadEmptyState(
                                        hasOwners: owners.isNotEmpty,
                                        hasQuery: state.searchQuery
                                            .trim()
                                            .isNotEmpty,
                                      )
                                    : state.viewMode ==
                                          FilesFeatureViewMode.list
                                    ? ListView.separated(
                                        itemCount: visibleEntries.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(
                                              height: AppSpacing.xs,
                                            ),
                                        itemBuilder: (context, index) {
                                          final entry = visibleEntries[index];
                                          return _RemoteDownloadListTile(
                                            entry: entry,
                                            browser: _browser,
                                            previewCacheOwner:
                                                widget.previewCacheOwner,
                                            isSelected: _isSelected(entry),
                                            isBusy:
                                                _previewingToken ==
                                                    entry.sourceToken ||
                                                _isDownloading,
                                            onTap: () => _openEntry(entry),
                                            onSelectChanged: entry.isDirectory
                                                ? null
                                                : (value) => _toggleSelection(
                                                    entry,
                                                    value,
                                                  ),
                                          );
                                        },
                                      )
                                    : GridView.builder(
                                        itemCount: visibleEntries.length,
                                        gridDelegate:
                                            SliverGridDelegateWithMaxCrossAxisExtent(
                                              maxCrossAxisExtent:
                                                  state.gridTileExtent,
                                              mainAxisSpacing: AppSpacing.xs,
                                              crossAxisSpacing: AppSpacing.xs,
                                              childAspectRatio: 0.9,
                                            ),
                                        itemBuilder: (context, index) {
                                          final entry = visibleEntries[index];
                                          return _RemoteDownloadGridTile(
                                            entry: entry,
                                            browser: _browser,
                                            previewCacheOwner:
                                                widget.previewCacheOwner,
                                            isSelected: _isSelected(entry),
                                            isBusy:
                                                _previewingToken ==
                                                    entry.sourceToken ||
                                                _isDownloading,
                                            onTap: () => _openEntry(entry),
                                            onSelectChanged: entry.isDirectory
                                                ? null
                                                : (value) => _toggleSelection(
                                                    entry,
                                                    value,
                                                  ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _selectedTokens.isEmpty
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.xs,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _isDownloading
                                ? null
                                : () {
                                    setState(() {
                                      _selectedTokens.clear();
                                    });
                                  },
                            child: const Text('Очистить'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: _isDownloading
                                ? null
                                : _downloadSelectedFiles,
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.download_rounded),
                            label: Text(
                              'Скачать выбранные (${_selectedTokens.length})',
                            ),
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

  Future<void> _handleFilterSelected(String nextKey) async {
    if (_activeFilterKey == nextKey) {
      return;
    }
    await _ensureOwnerForFilter(nextKey);
    if (!mounted) {
      return;
    }
    setState(() {
      _activeFilterKey = nextKey;
    });
    _syncSearchController();
  }

  bool _isSelected(FilesFeatureEntry entry) {
    final token = entry.sourceToken;
    return token != null && _selectedTokens.contains(token);
  }

  void _toggleSelection(FilesFeatureEntry entry, bool nextValue) {
    final token = entry.sourceToken;
    if (token == null) {
      return;
    }
    setState(() {
      if (nextValue) {
        _selectedTokens.add(token);
      } else {
        _selectedTokens.remove(token);
      }
    });
  }

  Future<void> _openEntry(FilesFeatureEntry entry) async {
    final owner = _activeOwner;
    if (owner == null) {
      return;
    }
    final openedDirectory = await owner.openDirectory(entry);
    if (openedDirectory) {
      return;
    }
    final token = entry.sourceToken;
    if (token == null) {
      return;
    }
    await _previewToken(token);
  }

  Future<void> _previewToken(String token) async {
    final file = _browser.resolveFileToken(token);
    if (file == null) {
      return;
    }
    setState(() {
      _previewingToken = token;
    });
    try {
      final previewPath = await widget.transferSessionCoordinator
          .requestRemoteFilePreview(
            ownerIp: file.ownerIp,
            ownerName: file.ownerName,
            cacheId: file.cacheId,
            relativePath: file.relativePath,
          );
      if (!mounted || previewPath == null || previewPath.trim().isEmpty) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalFileViewerPage(
            filePath: previewPath,
            previewCacheOwner: widget.previewCacheOwner,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _previewingToken = null;
        });
      }
    }
  }

  Future<void> _downloadSelectedFiles() async {
    final requests = <String, _RemoteDownloadBatch>{};
    for (final token in _selectedTokens) {
      final file = _browser.resolveFileToken(token);
      if (file == null) {
        continue;
      }
      final batch = requests.putIfAbsent(
        file.ownerIp,
        () => _RemoteDownloadBatch(
          ownerIp: file.ownerIp,
          ownerName: file.ownerName,
        ),
      );
      batch.selectedRelativePathsByCache
          .putIfAbsent(file.cacheId, () => <String>{})
          .add(file.relativePath);
    }
    if (requests.isEmpty) {
      return;
    }

    setState(() {
      _isDownloading = true;
    });
    try {
      for (final batch in requests.values) {
        await widget.transferSessionCoordinator.requestDownloadFromRemoteFiles(
          ownerIp: batch.ownerIp,
          ownerName: batch.ownerName,
          selectedRelativePathsByCache: batch.selectedRelativePathsByCache,
          useStandardAppDownloadFolder: widget.useStandardAppDownloadFolder,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedTokens.clear();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  List<PopupMenuEntry<ExplorerMenuAction>> _sortMenuItems(
    FilesFeatureState state,
  ) {
    return <PopupMenuEntry<ExplorerMenuAction>>[
      const PopupMenuItem<ExplorerMenuAction>(
        enabled: false,
        child: Text('Sort'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortNameAsc,
        checked: state.sortOption == FilesFeatureSortOption.nameAsc,
        child: const Text('A-Z'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortNameDesc,
        checked: state.sortOption == FilesFeatureSortOption.nameDesc,
        child: const Text('Z-A'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortModifiedNewest,
        checked: state.sortOption == FilesFeatureSortOption.modifiedNewest,
        child: const Text('Modified: newest'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortModifiedOldest,
        checked: state.sortOption == FilesFeatureSortOption.modifiedOldest,
        child: const Text('Modified: oldest'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortChangedNewest,
        checked: state.sortOption == FilesFeatureSortOption.changedNewest,
        child: const Text('Created/changed: newest'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortChangedOldest,
        checked: state.sortOption == FilesFeatureSortOption.changedOldest,
        child: const Text('Created/changed: oldest'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortSizeLargest,
        checked: state.sortOption == FilesFeatureSortOption.sizeLargest,
        child: const Text('Size: largest'),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortSizeSmallest,
        checked: state.sortOption == FilesFeatureSortOption.sizeSmallest,
        child: const Text('Size: smallest'),
      ),
    ];
  }

  FilesFeatureSortOption _sortOptionFromMenuAction(ExplorerMenuAction action) {
    switch (action) {
      case ExplorerMenuAction.sortNameAsc:
        return FilesFeatureSortOption.nameAsc;
      case ExplorerMenuAction.sortNameDesc:
        return FilesFeatureSortOption.nameDesc;
      case ExplorerMenuAction.sortModifiedNewest:
        return FilesFeatureSortOption.modifiedNewest;
      case ExplorerMenuAction.sortModifiedOldest:
        return FilesFeatureSortOption.modifiedOldest;
      case ExplorerMenuAction.sortChangedNewest:
        return FilesFeatureSortOption.changedNewest;
      case ExplorerMenuAction.sortChangedOldest:
        return FilesFeatureSortOption.changedOldest;
      case ExplorerMenuAction.sortSizeLargest:
        return FilesFeatureSortOption.sizeLargest;
      case ExplorerMenuAction.sortSizeSmallest:
        return FilesFeatureSortOption.sizeSmallest;
    }
  }
}

class _DeviceFilterChoice {
  const _DeviceFilterChoice({required this.key, required this.label});

  final String key;
  final String label;
}

class _DeviceFilterBar extends StatelessWidget {
  const _DeviceFilterBar({
    required this.filters,
    required this.selectedKey,
    required this.onSelected,
  });

  final List<_DeviceFilterChoice> filters;
  final String selectedKey;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        key: const Key('remote-download-device-filter-bar'),
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final filter = filters[index];
          return ChoiceChip(
            label: Text(filter.label),
            selected: selectedKey == filter.key,
            onSelected: (_) => onSelected(filter.key),
          );
        },
      ),
    );
  }
}

class _RemoteDownloadListTile extends StatelessWidget {
  const _RemoteDownloadListTile({
    required this.entry,
    required this.browser,
    required this.previewCacheOwner,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
    required this.onSelectChanged,
  });

  final FilesFeatureEntry entry;
  final RemoteShareBrowser browser;
  final PreviewCacheOwner previewCacheOwner;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;
  final ValueChanged<bool>? onSelectChanged;

  @override
  Widget build(BuildContext context) {
    final resolvedFile = entry.sourceToken == null
        ? null
        : browser.resolveFileToken(entry.sourceToken!);
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      tileColor: AppColors.surface,
      leading: _RemoteExplorerLeading(
        entry: entry,
        resolvedFile: resolvedFile,
        previewCacheOwner: previewCacheOwner,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onSelectChanged == null
          ? null
          : Checkbox(
              value: isSelected,
              onChanged: isBusy
                  ? null
                  : (value) => onSelectChanged!(value == true),
            ),
      onTap: isBusy ? null : onTap,
    );
  }
}

class _RemoteDownloadGridTile extends StatelessWidget {
  const _RemoteDownloadGridTile({
    required this.entry,
    required this.browser,
    required this.previewCacheOwner,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
    required this.onSelectChanged,
  });

  final FilesFeatureEntry entry;
  final RemoteShareBrowser browser;
  final PreviewCacheOwner previewCacheOwner;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;
  final ValueChanged<bool>? onSelectChanged;

  @override
  Widget build(BuildContext context) {
    final resolvedFile = entry.sourceToken == null
        ? null
        : browser.resolveFileToken(entry.sourceToken!);
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: isBusy ? null : onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.brandPrimary : AppColors.mutedBorder,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Center(
                      child: _RemoteExplorerLeading(
                        entry: entry,
                        resolvedFile: resolvedFile,
                        previewCacheOwner: previewCacheOwner,
                        size: 92,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    entry.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (onSelectChanged != null)
              Positioned(
                top: AppSpacing.xxs,
                right: AppSpacing.xxs,
                child: Checkbox(
                  value: isSelected,
                  onChanged: isBusy
                      ? null
                      : (value) => onSelectChanged!(value == true),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemoteExplorerLeading extends StatelessWidget {
  const _RemoteExplorerLeading({
    required this.entry,
    required this.resolvedFile,
    required this.previewCacheOwner,
    this.size = 44,
  });

  final FilesFeatureEntry entry;
  final RemoteBrowseResolvedFile? resolvedFile;
  final PreviewCacheOwner previewCacheOwner;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory) {
      return ExplorerEntityLeading(
        isDirectory: true,
        filePath: null,
        previewCacheOwner: previewCacheOwner,
        size: size,
      );
    }
    final previewPath = resolvedFile?.previewPath;
    if (previewPath != null && previewPath.trim().isNotEmpty) {
      final kind = resolvedFile?.mediaKind ?? RemoteBrowseMediaKind.other;
      if (kind == RemoteBrowseMediaKind.image) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.file(
            File(previewPath),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _fallback(kind),
          ),
        );
      }
      return _fallback(kind);
    }
    return _fallback(resolvedFile?.mediaKind ?? RemoteBrowseMediaKind.other);
  }

  Widget _fallback(RemoteBrowseMediaKind kind) {
    final icon = switch (kind) {
      RemoteBrowseMediaKind.image => Icons.image_rounded,
      RemoteBrowseMediaKind.video => Icons.play_circle_fill_rounded,
      RemoteBrowseMediaKind.other => Icons.insert_drive_file_rounded,
    };
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

class _RemoteDownloadEmptyState extends StatelessWidget {
  const _RemoteDownloadEmptyState({
    required this.hasOwners,
    required this.hasQuery,
  });

  final bool hasOwners;
  final bool hasQuery;

  @override
  Widget build(BuildContext context) {
    final message = !hasOwners
        ? 'Нет доступных файлов в сети. Обновите список или убедитесь, что на другом устройстве открыт общий доступ.'
        : hasQuery
        ? 'По текущему запросу ничего не найдено.'
        : 'В этой категории пока нет доступных файлов.';
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}

class _RemoteDownloadBatch {
  _RemoteDownloadBatch({required this.ownerIp, required this.ownerName});

  final String ownerIp;
  final String ownerName;
  final Map<String, Set<String>> selectedRelativePathsByCache =
      <String, Set<String>>{};
}

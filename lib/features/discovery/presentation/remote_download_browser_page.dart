import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

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
import '../application/discovery_read_model.dart';
import '../application/remote_share_browser.dart';

class RemoteDownloadBrowserPage extends StatefulWidget {
  const RemoteDownloadBrowserPage({
    required this.readModel,
    required this.remoteShareBrowser,
    required this.previewCacheOwner,
    required this.transferSessionCoordinator,
    required this.useStandardAppDownloadFolder,
    super.key,
  });

  final DiscoveryReadModel readModel;
  final RemoteShareBrowser remoteShareBrowser;
  final PreviewCacheOwner previewCacheOwner;
  final TransferSessionCoordinator transferSessionCoordinator;
  final bool useStandardAppDownloadFolder;

  @override
  State<RemoteDownloadBrowserPage> createState() =>
      _RemoteDownloadBrowserPageState();
}

class _RemoteDownloadBrowserPageState extends State<RemoteDownloadBrowserPage> {
  static const Set<RemoteBrowseFlatFileCategory> _allFlatCategories =
      <RemoteBrowseFlatFileCategory>{
        RemoteBrowseFlatFileCategory.images,
        RemoteBrowseFlatFileCategory.videos,
        RemoteBrowseFlatFileCategory.music,
        RemoteBrowseFlatFileCategory.documents,
        RemoteBrowseFlatFileCategory.programs,
      };

  final TextEditingController _searchController = TextEditingController();
  final Map<String, FilesFeatureStateOwner> _ownersByFilterKey =
      <String, FilesFeatureStateOwner>{};
  final Set<String> _selectedTokens = <String>{};

  String _activeFilterKey = '';
  RemoteBrowseExplorerViewMode _viewMode =
      RemoteBrowseExplorerViewMode.structured;
  bool _showAllFlatCategories = true;
  Set<RemoteBrowseFlatFileCategory> _visibleFlatCategories = _allFlatCategories;
  String? _previewingToken;
  bool _isDownloading = false;

  RemoteShareBrowser get _browser => widget.remoteShareBrowser;
  List<RemoteBrowseOwnerChoice> get _availableDevices {
    final devices = widget.readModel.remoteClipboardDevices;
    if (devices.isEmpty) {
      return _browser.currentBrowseProjection.owners;
    }
    return devices
        .map(
          (device) => RemoteBrowseOwnerChoice(
            ip: device.ip,
            name: device.displayName,
            macAddress: device.macAddress ?? '',
            shareCount: _browser.currentBrowseProjection.options
                .where((option) => option.ownerIp == device.ip)
                .length,
            fileCount: _browser.currentBrowseProjection.options
                .where((option) => option.ownerIp == device.ip)
                .fold<int>(0, (sum, option) => sum + option.entry.itemCount),
            cachedShareCount: _browser.currentBrowseProjection.options
                .where(
                  (option) =>
                      option.ownerIp == device.ip &&
                      option.hasReceiverCacheSnapshot,
                )
                .length,
          ),
        )
        .toList(growable: false);
  }

  String? get _firstAvailableDeviceKey =>
      _availableDevices.isEmpty ? null : _availableDevices.first.ip;
  String get _rootLabelForActiveFilter {
    for (final device in _availableDevices) {
      if (device.ip == _activeFilterKey) {
        return device.name;
      }
    }
    return _activeFilterKey.trim().isEmpty
        ? 'remote_download.access_select_device'.tr()
        : _activeFilterKey;
  }

  bool get _canRequestAccess => _activeFilterKey.trim().isNotEmpty;
  bool get _hasLoadedCatalogForActiveDevice => _browser
      .currentBrowseProjection
      .options
      .any((option) => option.ownerIp == _activeFilterKey);

  String _labelForFilter(String filterKey) {
    for (final device in _availableDevices) {
      if (device.ip == filterKey) {
        return device.name;
      }
    }
    return filterKey;
  }

  String get _activeOwnerCacheKey => '${_viewMode.name}|$_activeFilterKey';

  Set<RemoteBrowseFlatFileCategory>? get _effectiveVisibleFlatCategories =>
      _showAllFlatCategories ? null : _visibleFlatCategories;

  FilesFeatureStateOwner? get _activeOwner =>
      _ownersByFilterKey[_activeOwnerCacheKey];

  @override
  void initState() {
    super.initState();
    _browser.addListener(_handleBrowserChanged);
    final initialFilterKey = _firstAvailableDeviceKey;
    if (initialFilterKey != null) {
      _activeFilterKey = initialFilterKey;
      unawaited(_ensureOwnerForFilter(_activeFilterKey));
    }
    widget.transferSessionCoordinator.logSharedDownloadDebug(
      stage: 'browser_opened',
      requestId: 'browser',
      details: <String, Object?>{
        'deviceCount': _availableDevices.length,
        'activeDeviceIp': _activeFilterKey,
      },
    );
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
    _selectedTokens.removeWhere(
      (token) => !_browser.containsDownloadToken(token),
    );

    final validFilterKeys = _availableDevices.map((owner) => owner.ip).toSet();
    final removableKeys = _ownersByFilterKey.keys
        .where((key) {
          final parts = key.split('|');
          final filterKey = parts.length < 2 ? key : parts.sublist(1).join('|');
          return !validFilterKeys.contains(filterKey);
        })
        .toList(growable: false);
    for (final key in removableKeys) {
      _ownersByFilterKey.remove(key)?.dispose();
    }
    if (!validFilterKeys.contains(_activeFilterKey)) {
      _activeFilterKey = _firstAvailableDeviceKey ?? '';
    }
    final activeFilterKey = _activeFilterKey;
    if (activeFilterKey.trim().isNotEmpty) {
      await _ensureOwnerForFilter(activeFilterKey);
    }
    for (final owner in _ownersByFilterKey.values) {
      owner.invalidateSelectedVirtualRootCache();
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
    if (filterKey.trim().isEmpty) {
      return;
    }
    final ownerCacheKey = '${_viewMode.name}|$filterKey';
    final existing = _ownersByFilterKey[ownerCacheKey];
    if (existing != null) {
      return;
    }
    final owner = FilesFeatureStateOwner(
      roots: <FileExplorerRoot>[
        FileExplorerRoot(
          label: _labelForFilter(filterKey),
          path: 'virtual://remote/${_viewMode.name}/$filterKey',
          virtualDirectoryLoader: (folderPath) async {
            return _browser
                .buildExplorerDirectory(
                  filterKey: filterKey,
                  folderPath: folderPath,
                  viewMode: _viewMode,
                  visibleFlatCategories: _effectiveVisibleFlatCategories,
                  showAllFlatCategories: _showAllFlatCategories,
                )
                .entries;
          },
        ),
      ],
    );
    _ownersByFilterKey[ownerCacheKey] = owner;
    await owner.initialize();
    if (!mounted) {
      owner.dispose();
      _ownersByFilterKey.remove(ownerCacheKey);
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
        widget.readModel,
        widget.transferSessionCoordinator,
        ..._ownersByFilterKey.values,
      ]),
      builder: (context, _) {
        final activeOwner = _activeOwner;
        final owners = _availableDevices;
        final filterChoices = owners
            .map(
              (owner) => _DeviceFilterChoice(key: owner.ip, label: owner.name),
            )
            .toList(growable: false);
        final directory = _browser.buildExplorerDirectory(
          filterKey: _activeFilterKey,
          folderPath: activeOwner?.normalizedVirtualCurrentFolder ?? '',
          viewMode: _viewMode,
          visibleFlatCategories: _effectiveVisibleFlatCategories,
          showAllFlatCategories: _showAllFlatCategories,
        );
        final state = activeOwner?.state;
        final visibleEntries =
            activeOwner?.visibleEntries ?? const <FilesFeatureEntry>[];

        return Scaffold(
          appBar: AppBar(
            title: Text('remote_download.title'.tr()),
            actions: [
              IconButton(
                tooltip: 'remote_download.request_access_tooltip'.tr(),
                onPressed: _canRequestAccess
                    ? () => unawaited(_requestAccessForActiveDevice())
                    : null,
                icon: const Icon(Icons.lock_open_rounded),
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
                  child: Column(
                    children: [
                      _RemoteDownloadViewModeToggle(
                        viewMode: _viewMode,
                        onChanged: _handleViewModeChanged,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (filterChoices.isNotEmpty)
                        _DeviceFilterBar(
                          filters: filterChoices,
                          selectedKey: _activeFilterKey,
                          onSelected: _handleFilterSelected,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      _RemoteShareAccessActionRow(
                        deviceLabel: _rootLabelForActiveFilter,
                        activeOwnerIp: _activeFilterKey,
                        accessState: widget
                            .transferSessionCoordinator
                            .remoteShareAccessState,
                        onRequestAccess: _canRequestAccess
                            ? _requestAccessForActiveDevice
                            : null,
                      ),
                      if (_viewMode == RemoteBrowseExplorerViewMode.flat) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _FlatCategoryFilterBar(
                          showAll: _showAllFlatCategories,
                          selectedCategories: _visibleFlatCategories,
                          onShowAllChanged: _handleShowAllFlatCategoriesChanged,
                          onCategoryChanged: _handleFlatCategoryChanged,
                        ),
                      ],
                    ],
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
                if (widget
                        .transferSessionCoordinator
                        .isPreparingSharedDownload ||
                    widget.transferSessionCoordinator.isDownloading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      0,
                    ),
                    child: _SharedDownloadStatusCard(
                      coordinator: widget.transferSessionCoordinator,
                    ),
                  ),
                Expanded(
                  child: activeOwner == null
                      ? _RemoteDownloadEmptyState(
                          hasOwners: owners.isNotEmpty,
                          hasQuery: false,
                          hasLoadedCatalog: false,
                        )
                      : Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: _buildExplorerContent(
                            context: context,
                            activeOwner: activeOwner,
                            state: state!,
                            owners: owners,
                            directory: directory,
                            visibleEntries: visibleEntries,
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
                            child: Text('remote_download.clear'.tr()),
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
                              'remote_download.download_selected'.tr(
                                namedArgs: <String, String>{
                                  'count': '${_selectedTokens.length}',
                                },
                              ),
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

  Widget _buildExplorerContent({
    required BuildContext context,
    required FilesFeatureStateOwner activeOwner,
    required FilesFeatureState state,
    required List<RemoteBrowseOwnerChoice> owners,
    required RemoteBrowseExplorerDirectory directory,
    required List<FilesFeatureEntry> visibleEntries,
  }) {
    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExplorerPathHeader(
              rootLabel: _rootLabelForActiveFilter,
              relativePath: activeOwner.relativePathLabel(),
              canGoUp: activeOwner.canGoUp,
              onGoUp: activeOwner.canGoUp ? () => activeOwner.goUp() : null,
              canSelectRoot: false,
              onSelectRoot: null,
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                DisplayModeToggle(
                  isGrid: state.viewMode == FilesFeatureViewMode.grid,
                  onToggle: activeOwner.toggleViewMode,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: activeOwner.setSearchQuery,
                      decoration: InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: 'common.search_files'.tr(),
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
                PopupMenuButton<ExplorerMenuAction>(
                  tooltip: 'common.sort'.tr(),
                  onSelected: (action) => activeOwner.setSortOption(
                    _sortOptionFromMenuAction(action),
                  ),
                  itemBuilder: (context) => _sortMenuItems(state, activeOwner),
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
            if (state.errorMessage != null) ...[
              ExplorerErrorBanner(
                message: state.errorMessage!,
                onRetry: activeOwner.refreshCurrentRoot,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (directory.isFileListCapped)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'remote_download.file_list_capped'.tr(
                    namedArgs: <String, String>{
                      'shown': '${directory.entries.files.length}',
                      'hidden': '${directory.hiddenFilesCount}',
                    },
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];

    if (visibleEntries.isEmpty) {
      slivers.add(
        SliverFillRemaining(
          hasScrollBody: false,
          child: _RemoteDownloadEmptyState(
            hasOwners: owners.isNotEmpty,
            hasQuery: state.searchQuery.trim().isNotEmpty,
            hasLoadedCatalog: _hasLoadedCatalogForActiveDevice,
          ),
        ),
      );
      return CustomScrollView(slivers: slivers);
    }

    if (state.viewMode == FilesFeatureViewMode.list) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate((context, index) {
              if (index.isOdd) {
                return const SizedBox(height: AppSpacing.xs);
              }
              final entry = visibleEntries[index ~/ 2];
              return _RemoteDownloadListTile(
                entry: entry,
                previewCacheOwner: widget.previewCacheOwner,
                isSelected: _isSelected(entry),
                isBusy: _previewingToken == entry.sourceToken || _isDownloading,
                onTap: () => _openEntry(entry),
                onSelectChanged: entry.sourceToken == null
                    ? null
                    : (value) => _toggleSelection(entry, value),
              );
            }, childCount: visibleEntries.length * 2 - 1),
          ),
        ),
      );
      return CustomScrollView(slivers: slivers);
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate((context, index) {
            final entry = visibleEntries[index];
            return _RemoteDownloadGridTile(
              entry: entry,
              tileExtent: state.gridTileExtent,
              previewCacheOwner: widget.previewCacheOwner,
              isSelected: _isSelected(entry),
              isBusy: _previewingToken == entry.sourceToken || _isDownloading,
              onTap: () => _openEntry(entry),
              onSelectChanged: entry.sourceToken == null
                  ? null
                  : (value) => _toggleSelection(entry, value),
            );
          }, childCount: visibleEntries.length),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: state.gridTileExtent,
            mainAxisSpacing: AppSpacing.xs,
            crossAxisSpacing: AppSpacing.xs,
            childAspectRatio: 0.9,
          ),
        ),
      ),
    );
    return CustomScrollView(slivers: slivers);
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
    widget.transferSessionCoordinator.logSharedDownloadDebug(
      stage: 'browser_device_selected',
      requestId: 'browser',
      details: <String, Object?>{'ownerIp': nextKey},
    );
    widget.transferSessionCoordinator.clearRemoteShareAccessState(
      ownerIp: nextKey,
    );
    _syncSearchController();
  }

  Future<void> _requestAccessForActiveDevice() async {
    final ownerIp = _activeFilterKey.trim();
    if (ownerIp.isEmpty) {
      return;
    }
    widget.transferSessionCoordinator.logSharedDownloadDebug(
      stage: 'browser_request_access_tapped',
      requestId: 'browser',
      details: <String, Object?>{
        'ownerIp': ownerIp,
        'ownerName': _rootLabelForActiveFilter,
      },
    );
    await widget.transferSessionCoordinator.requestRemoteShareAccess(
      ownerIp: ownerIp,
      ownerName: _rootLabelForActiveFilter,
    );
  }

  Future<void> _handleViewModeChanged(
    RemoteBrowseExplorerViewMode nextMode,
  ) async {
    if (_viewMode == nextMode) {
      return;
    }
    setState(() {
      _viewMode = nextMode;
    });
    await _ensureOwnerForFilter(_activeFilterKey);
    if (!mounted) {
      return;
    }
    _syncSearchController();
    setState(() {});
  }

  Future<void> _handleShowAllFlatCategoriesChanged(bool nextValue) async {
    if (_showAllFlatCategories == nextValue) {
      return;
    }
    setState(() {
      _showAllFlatCategories = nextValue;
      if (nextValue &&
          _visibleFlatCategories.length != _allFlatCategories.length) {
        _visibleFlatCategories = _allFlatCategories;
      }
    });
    await _refreshFlatOwners();
  }

  Future<void> _handleFlatCategoryChanged(
    RemoteBrowseFlatFileCategory category,
    bool nextValue,
  ) async {
    final nextCategories = _showAllFlatCategories
        ? <RemoteBrowseFlatFileCategory>{category}
        : Set<RemoteBrowseFlatFileCategory>.from(_visibleFlatCategories);
    if (nextValue) {
      nextCategories.add(category);
    } else {
      nextCategories.remove(category);
    }
    if (setEquals(nextCategories, _visibleFlatCategories) &&
        !_showAllFlatCategories) {
      return;
    }
    setState(() {
      _showAllFlatCategories = false;
      _visibleFlatCategories = nextCategories;
    });
    await _refreshFlatOwners();
  }

  Future<void> _refreshFlatOwners() async {
    final flatOwners = _ownersByFilterKey.entries
        .where(
          (entry) => entry.key.startsWith(
            '${RemoteBrowseExplorerViewMode.flat.name}|',
          ),
        )
        .map((entry) => entry.value)
        .toList(growable: false);
    if (flatOwners.isNotEmpty) {
      for (final owner in flatOwners) {
        owner.invalidateSelectedVirtualRootCache();
      }
      await Future.wait(flatOwners.map((owner) => owner.refreshCurrentRoot()));
    }
    if (!mounted) {
      return;
    }
    setState(() {});
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
      final target = _browser.resolveDownloadToken(token);
      if (target == null) {
        continue;
      }
      final batch = requests.putIfAbsent(
        target.ownerIp,
        () => _RemoteDownloadBatch(
          ownerIp: target.ownerIp,
          ownerName: target.ownerName,
        ),
      );
      for (final entry in target.selectedRelativePathsByCache.entries) {
        batch.addSelection(cacheId: entry.key, relativePaths: entry.value);
      }
      for (final entry in target.selectedFolderPrefixesByCache.entries) {
        batch.addFolderPrefixes(
          cacheId: entry.key,
          folderPrefixes: entry.value,
        );
      }
      for (final entry in target.sharedLabelsByCache.entries) {
        batch.addSharedLabel(cacheId: entry.key, sharedLabel: entry.value);
      }
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
          selectedFolderPrefixesByCache: batch.selectedFolderPrefixesByCache,
          sharedLabelsByCache: batch.sharedLabelsByCache,
          preferDirectStart: true,
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
    FilesFeatureStateOwner owner,
  ) {
    return <PopupMenuEntry<ExplorerMenuAction>>[
      PopupMenuItem<ExplorerMenuAction>(
        enabled: false,
        child: Text('common.sort'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortNameAsc,
        checked: state.sortOption == FilesFeatureSortOption.nameAsc,
        child: Text('remote_download.sort_name_asc'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortNameDesc,
        checked: state.sortOption == FilesFeatureSortOption.nameDesc,
        child: Text('remote_download.sort_name_desc'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortModifiedNewest,
        checked: state.sortOption == FilesFeatureSortOption.modifiedNewest,
        child: Text('remote_download.sort_modified_newest'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortModifiedOldest,
        checked: state.sortOption == FilesFeatureSortOption.modifiedOldest,
        child: Text('remote_download.sort_modified_oldest'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortChangedNewest,
        checked: state.sortOption == FilesFeatureSortOption.changedNewest,
        child: Text('remote_download.sort_changed_newest'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortChangedOldest,
        checked: state.sortOption == FilesFeatureSortOption.changedOldest,
        child: Text('remote_download.sort_changed_oldest'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortSizeLargest,
        checked: state.sortOption == FilesFeatureSortOption.sizeLargest,
        child: Text('remote_download.sort_size_largest'.tr()),
      ),
      CheckedPopupMenuItem<ExplorerMenuAction>(
        value: ExplorerMenuAction.sortSizeSmallest,
        checked: state.sortOption == FilesFeatureSortOption.sizeSmallest,
        child: Text('remote_download.sort_size_smallest'.tr()),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<ExplorerMenuAction>(
        enabled: false,
        height: 86,
        child: StatefulBuilder(
          builder: (context, setMenuState) {
            var menuTileSize = state.gridTileExtent;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'remote_download.sort_tile_size'.tr(),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Slider(
                  value: menuTileSize,
                  min: FilesFeatureStateOwner.minGridTileExtent,
                  max: FilesFeatureStateOwner.maxGridTileExtent,
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

class _SharedDownloadStatusCard extends StatelessWidget {
  const _SharedDownloadStatusCard({required this.coordinator});

  final TransferSessionCoordinator coordinator;

  @override
  Widget build(BuildContext context) {
    final preparation = coordinator.sharedDownloadPreparationState;
    final isDownloading = coordinator.isDownloading;
    final title = isDownloading
        ? 'remote_download.status_downloading'.tr()
        : 'remote_download.status_preparing'.tr();
    final message = isDownloading
        ? 'remote_download.status_downloading_message'.tr()
        : preparation?.message ??
              'remote_download.status_preparing_default'.tr();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isDownloading ? Icons.download_rounded : Icons.hourglass_bottom,
                color: isDownloading
                    ? AppColors.success
                    : AppColors.brandPrimaryDark,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isDownloading) ...[
            LinearProgressIndicator(
              value: coordinator.downloadProgress.clamp(0, 1),
              minHeight: 6,
              color: AppColors.success,
              backgroundColor: AppColors.mutedBorder,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${(coordinator.downloadProgress * 100).toStringAsFixed(0)}% • '
              '${_formatBytes(coordinator.downloadReceivedBytes)} / '
              '${_formatBytes(coordinator.downloadTotalBytes)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ] else
            const LinearProgressIndicator(
              minHeight: 6,
              color: AppColors.brandPrimary,
              backgroundColor: AppColors.mutedBorder,
            ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return 'common.format_size_b'.tr(
        namedArgs: <String, String>{'value': '$bytes'},
      );
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return 'common.format_size_kb'.tr(
        namedArgs: <String, String>{'value': kb.toStringAsFixed(1)},
      );
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return 'common.format_size_mb'.tr(
        namedArgs: <String, String>{'value': mb.toStringAsFixed(1)},
      );
    }
    final gb = mb / 1024;
    return 'common.format_size_gb'.tr(
      namedArgs: <String, String>{'value': gb.toStringAsFixed(2)},
    );
  }
}

String _flatCategoryLabel(RemoteBrowseFlatFileCategory category) {
  switch (category) {
    case RemoteBrowseFlatFileCategory.images:
      return 'remote_download.flat_category_images';
    case RemoteBrowseFlatFileCategory.videos:
      return 'remote_download.flat_category_videos';
    case RemoteBrowseFlatFileCategory.music:
      return 'remote_download.flat_category_music';
    case RemoteBrowseFlatFileCategory.documents:
      return 'remote_download.flat_category_documents';
    case RemoteBrowseFlatFileCategory.programs:
      return 'remote_download.flat_category_programs';
  }
}

class _DeviceFilterChoice {
  const _DeviceFilterChoice({required this.key, required this.label});

  final String key;
  final String label;
}

class _RemoteDownloadViewModeToggle extends StatelessWidget {
  const _RemoteDownloadViewModeToggle({
    required this.viewMode,
    required this.onChanged,
  });

  final RemoteBrowseExplorerViewMode viewMode;
  final ValueChanged<RemoteBrowseExplorerViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SegmentedButton<RemoteBrowseExplorerViewMode>(
            key: const Key('remote-download-view-mode-toggle'),
            segments: <ButtonSegment<RemoteBrowseExplorerViewMode>>[
              ButtonSegment<RemoteBrowseExplorerViewMode>(
                value: RemoteBrowseExplorerViewMode.structured,
                icon: const Icon(Icons.account_tree_outlined),
                label: Text('remote_download.view_structured'.tr()),
              ),
              ButtonSegment<RemoteBrowseExplorerViewMode>(
                value: RemoteBrowseExplorerViewMode.flat,
                icon: const Icon(Icons.view_stream_rounded),
                label: Text('remote_download.view_flat'.tr()),
              ),
            ],
            selected: <RemoteBrowseExplorerViewMode>{viewMode},
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
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

class _FlatCategoryFilterBar extends StatelessWidget {
  const _FlatCategoryFilterBar({
    required this.showAll,
    required this.selectedCategories,
    required this.onShowAllChanged,
    required this.onCategoryChanged,
  });

  final bool showAll;
  final Set<RemoteBrowseFlatFileCategory> selectedCategories;
  final ValueChanged<bool> onShowAllChanged;
  final void Function(RemoteBrowseFlatFileCategory category, bool value)
  onCategoryChanged;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      FilterChip(
        key: const Key('remote-download-show-all-chip'),
        label: Text('remote_download.show_all'.tr()),
        selected: showAll,
        onSelected: onShowAllChanged,
      ),
      ...RemoteBrowseFlatFileCategory.values.map((category) {
        return FilterChip(
          key: Key('remote-download-category-${category.name}'),
          label: Text(_flatCategoryLabel(category).tr()),
          selected: !showAll && selectedCategories.contains(category),
          onSelected: (value) => onCategoryChanged(category, value),
        );
      }),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'remote_download.categories_title'.tr(),
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 40,
          child: ListView.separated(
            key: const Key('remote-download-flat-category-filter-bar'),
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) => chips[index],
          ),
        ),
      ],
    );
  }
}

class _RemoteShareAccessActionRow extends StatelessWidget {
  const _RemoteShareAccessActionRow({
    required this.deviceLabel,
    required this.activeOwnerIp,
    required this.accessState,
    required this.onRequestAccess,
  });

  final String deviceLabel;
  final String activeOwnerIp;
  final RemoteShareAccessState? accessState;
  final Future<void> Function()? onRequestAccess;

  @override
  Widget build(BuildContext context) {
    final isActiveState =
        accessState != null && accessState!.ownerIp == activeOwnerIp;
    final message = isActiveState ? accessState!.statusMessage : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deviceLabel.trim().isEmpty
                      ? 'remote_download.access_select_device'.tr()
                      : 'remote_download.access_title'.tr(
                          namedArgs: <String, String>{'device': deviceLabel},
                        ),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message ?? 'remote_download.access_description'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            key: const Key('remote-download-request-access-button'),
            onPressed: onRequestAccess == null
                ? null
                : () => onRequestAccess!(),
            icon: const Icon(Icons.lock_open_rounded),
            label: Text('remote_download.request_access'.tr()),
          ),
        ],
      ),
    );
  }
}

class _RemoteDownloadListTile extends StatelessWidget {
  const _RemoteDownloadListTile({
    required this.entry,
    required this.previewCacheOwner,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
    required this.onSelectChanged,
  });

  final FilesFeatureEntry entry;
  final PreviewCacheOwner previewCacheOwner;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;
  final ValueChanged<bool>? onSelectChanged;

  bool get _canSelect => onSelectChanged != null;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: isBusy ? null : onTap,
        onLongPress: !_canSelect || isBusy
            ? null
            : () => onSelectChanged!(!isSelected),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.lg),
              child: ExplorerEntityTile(
                entry: entry,
                previewCacheOwner: previewCacheOwner,
                onTap: onTap,
              ),
            ),
            if (_canSelect)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: _SelectionCircleButton(
                  token: entry.sourceToken!,
                  isSelected: isSelected,
                  isBusy: isBusy,
                  onChanged: onSelectChanged!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RemoteDownloadGridTile extends StatelessWidget {
  const _RemoteDownloadGridTile({
    required this.entry,
    required this.tileExtent,
    required this.previewCacheOwner,
    required this.isSelected,
    required this.isBusy,
    required this.onTap,
    required this.onSelectChanged,
  });

  final FilesFeatureEntry entry;
  final double tileExtent;
  final PreviewCacheOwner previewCacheOwner;
  final bool isSelected;
  final bool isBusy;
  final VoidCallback onTap;
  final ValueChanged<bool>? onSelectChanged;

  bool get _canSelect => onSelectChanged != null;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: isBusy ? null : onTap,
      onLongPress: !_canSelect || isBusy
          ? null
          : () => onSelectChanged!(!isSelected),
      child: Stack(
        children: [
          ExplorerEntityGridTile(
            entry: entry,
            tileExtent: tileExtent,
            previewCacheOwner: previewCacheOwner,
            onTap: onTap,
          ),
          if (_canSelect)
            Positioned(
              top: AppSpacing.xxs,
              right: AppSpacing.xxs,
              child: _SelectionCircleButton(
                token: entry.sourceToken!,
                isSelected: isSelected,
                isBusy: isBusy,
                onChanged: onSelectChanged!,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectionCircleButton extends StatelessWidget {
  const _SelectionCircleButton({
    required this.token,
    required this.isSelected,
    required this.isBusy,
    required this.onChanged,
  });

  final String token;
  final bool isSelected;
  final bool isBusy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('remote-download-select-$token'),
        customBorder: const CircleBorder(),
        onTap: isBusy ? null : () => onChanged(!isSelected),
        child: Ink(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? AppColors.brandPrimary : AppColors.surface,
            border: Border.all(
              color: isSelected
                  ? AppColors.brandPrimary
                  : AppColors.mutedBorder,
              width: 1.5,
            ),
          ),
          child: isSelected
              ? const Icon(
                  Icons.check_rounded,
                  size: 16,
                  color: AppColors.surface,
                )
              : null,
        ),
      ),
    );
  }
}

class _RemoteDownloadEmptyState extends StatelessWidget {
  const _RemoteDownloadEmptyState({
    required this.hasOwners,
    required this.hasQuery,
    required this.hasLoadedCatalog,
  });

  final bool hasOwners;
  final bool hasQuery;
  final bool hasLoadedCatalog;

  @override
  Widget build(BuildContext context) {
    final message = !hasOwners
        ? 'remote_download.empty_no_devices'.tr()
        : hasQuery
        ? 'remote_download.empty_no_results'.tr()
        : hasLoadedCatalog
        ? 'remote_download.empty_no_files'.tr()
        : 'remote_download.empty_request_access'.tr();
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}

class _RemoteDownloadBatch {
  _RemoteDownloadBatch({required this.ownerIp, required this.ownerName});

  final String ownerIp;
  final String ownerName;
  final Map<String, Set<String>> selectedRelativePathsByCache =
      <String, Set<String>>{};
  final Map<String, Set<String>> selectedFolderPrefixesByCache =
      <String, Set<String>>{};
  final Map<String, String> sharedLabelsByCache = <String, String>{};

  void addSelection({
    required String cacheId,
    required Set<String> relativePaths,
  }) {
    final hadExisting = selectedRelativePathsByCache.containsKey(cacheId);
    final existing = selectedRelativePathsByCache.putIfAbsent(
      cacheId,
      () => <String>{},
    );
    if (relativePaths.isEmpty) {
      selectedRelativePathsByCache[cacheId] = <String>{};
      return;
    }
    if (hadExisting && existing.isEmpty) {
      return;
    }
    existing.addAll(relativePaths);
  }

  void addFolderPrefixes({
    required String cacheId,
    required Set<String> folderPrefixes,
  }) {
    if (folderPrefixes.isEmpty) {
      return;
    }
    final existing = selectedFolderPrefixesByCache.putIfAbsent(
      cacheId,
      () => <String>{},
    );
    existing.addAll(folderPrefixes);
  }

  void addSharedLabel({required String cacheId, required String sharedLabel}) {
    final normalized = sharedLabel.trim();
    if (normalized.isEmpty) {
      return;
    }
    sharedLabelsByCache.putIfAbsent(cacheId, () => normalized);
  }
}

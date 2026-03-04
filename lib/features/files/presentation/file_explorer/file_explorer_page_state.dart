part of '../file_explorer_page.dart';

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

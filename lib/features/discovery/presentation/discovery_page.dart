import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/app_notification_service.dart';
import '../../../core/utils/desktop_window_service.dart';
import '../../../core/utils/path_opener.dart';
import '../../history/data/transfer_history_repository.dart';
import '../../files/presentation/file_explorer_page.dart';
import '../../settings/data/app_settings_repository.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/app_settings_sheet.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/shared_folder_cache_repository.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../application/discovery_controller.dart';
import '../data/device_alias_repository.dart';
import '../data/friend_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  late final DiscoveryController _controller;
  final DesktopWindowService _desktopWindowService = DesktopWindowService();
  String? _lastInfoMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final settingsRepository = AppSettingsRepository(
      database: AppDatabase.instance,
    );
    _controller = DiscoveryController(
      deviceAliasRepository: DeviceAliasRepository(
        database: AppDatabase.instance,
      ),
      friendRepository: FriendRepository(database: AppDatabase.instance),
      appSettingsRepository: settingsRepository,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: TransferHistoryRepository(
        database: AppDatabase.instance,
      ),
      sharedFolderCacheRepository: SharedFolderCacheRepository(
        database: AppDatabase.instance,
      ),
      fileHashService: FileHashService(),
      fileTransferService: FileTransferService(),
      transferStorageService: TransferStorageService(),
      pathOpener: PathOpener(),
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(),
    );
    _controller.addListener(_handleInfoMessages);
    unawaited(_initializeController());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleInfoMessages);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _controller.setAppForegroundState(isForeground);
  }

  Future<void> _initializeController() async {
    await _controller.start();
    if (!mounted) {
      return;
    }
    await _desktopWindowService.setMinimizeToTrayEnabled(
      _controller.settings.minimizeToTrayOnClose,
    );
  }

  void _handleInfoMessages() {
    final info = _controller.infoMessage;
    if (!mounted || info == null || info == _lastInfoMessage) {
      return;
    }
    _lastInfoMessage = info;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
    _controller.clearInfoMessage();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final devices = _controller.devices;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Landa devices'),
            actions: [
              IconButton(
                tooltip: 'Friends',
                onPressed: _openFriendsSheet,
                icon: const Icon(Icons.group_rounded),
              ),
              IconButton(
                tooltip: 'Settings',
                onPressed: _openSettingsSheet,
                icon: const Icon(Icons.tune_rounded),
              ),
              IconButton(
                tooltip: 'Download history',
                onPressed: _openHistorySheet,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Files',
                onPressed: _openFileExplorer,
                icon: const Icon(Icons.folder_open_rounded),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _controller.isManualRefreshInProgress
                    ? null
                    : _controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _NetworkSummaryCard(
                  controller: _controller,
                  total: devices.length,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_controller.errorMessage != null) ...[
                  _ErrorBanner(message: _controller.errorMessage!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_controller.isUploading || _controller.isDownloading) ...[
                  _TransferProgressCard(controller: _controller),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_controller.isManualRefreshInProgress) ...[
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.brandPrimary,
                    backgroundColor: AppColors.mutedBorder,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Expanded(
                  child: devices.isEmpty
                      ? _EmptyState(onRefresh: _controller.refresh)
                      : ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (_, index) => _DeviceTile(
                            device: devices[index],
                            selected:
                                _controller.selectedDevice?.ip ==
                                devices[index].ip,
                            onSelect: _controller.selectDeviceByIp,
                            onOpenActionsMenu: _openDeviceActionsMenu,
                          ),
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _ActionBar(
            controller: _controller,
            onReceive: _openReceivePanel,
            onAdd: _openAddShareMenu,
            onSend: _controller.sendFilesToSelectedDevice,
          ),
        );
      },
    );
  }

  Future<void> _openFriendsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.84,
          child: DefaultTabController(
            length: 2,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final friends = _controller.friendDevices;
                final requests = _controller.incomingFriendRequests;
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Friends',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Friendship requires confirmation from both devices.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TabBar(
                          tabs: [
                            Tab(text: 'Friends (${friends.length})'),
                            Tab(text: 'Requests (${requests.length})'),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Expanded(
                          child: TabBarView(
                            children: [
                              friends.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No friends yet.\\nOpen a device menu and send a friend request.',
                                        textAlign: TextAlign.center,
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: friends.length,
                                      separatorBuilder: (_, index) =>
                                          const SizedBox(height: AppSpacing.xs),
                                      itemBuilder: (_, index) {
                                        final friend = friends[index];
                                        final subtitleParts = <String>[
                                          friend.ip,
                                          if (friend.macAddress != null)
                                            'MAC ${friend.macAddress}',
                                          if (friend.operatingSystem != null &&
                                              friend
                                                  .operatingSystem!
                                                  .isNotEmpty)
                                            'OS ${friend.operatingSystem}',
                                        ];
                                        return Card(
                                          child: ListTile(
                                            leading: const Icon(
                                              Icons.star,
                                              color: AppColors.warning,
                                            ),
                                            title: Text(friend.displayName),
                                            subtitle: Text(
                                              subtitleParts.join(' • '),
                                            ),
                                            trailing: IconButton(
                                              tooltip: 'Remove from friends',
                                              onPressed:
                                                  _controller
                                                      .isFriendMutationInProgress
                                                  ? null
                                                  : () {
                                                      unawaited(
                                                        _controller
                                                            .removeDeviceFromFriends(
                                                              friend,
                                                            ),
                                                      );
                                                    },
                                              icon: const Icon(
                                                Icons
                                                    .person_remove_alt_1_rounded,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                              requests.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No pending friend requests.',
                                      ),
                                    )
                                  : ListView.separated(
                                      itemCount: requests.length,
                                      separatorBuilder: (_, index) =>
                                          const SizedBox(height: AppSpacing.xs),
                                      itemBuilder: (_, index) {
                                        final request = requests[index];
                                        return Card(
                                          child: ListTile(
                                            leading: const Icon(
                                              Icons.person_add_alt_1_rounded,
                                            ),
                                            title: Text(request.senderName),
                                            subtitle: Text(
                                              '${request.senderIp} • '
                                              'MAC ${request.senderMacAddress}\n'
                                              'Received ${_formatTime(request.createdAt)}',
                                            ),
                                            isThreeLine: true,
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  tooltip: 'Decline',
                                                  onPressed:
                                                      _controller
                                                          .isFriendMutationInProgress
                                                      ? null
                                                      : () {
                                                          unawaited(
                                                            _controller
                                                                .respondToFriendRequest(
                                                                  requestId: request
                                                                      .requestId,
                                                                  accept: false,
                                                                ),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                    Icons.close_rounded,
                                                  ),
                                                ),
                                                IconButton(
                                                  tooltip: 'Accept',
                                                  onPressed:
                                                      _controller
                                                          .isFriendMutationInProgress
                                                      ? null
                                                      : () {
                                                          unawaited(
                                                            _controller
                                                                .respondToFriendRequest(
                                                                  requestId: request
                                                                      .requestId,
                                                                  accept: true,
                                                                ),
                                                          );
                                                        },
                                                  icon: const Icon(
                                                    Icons.check_rounded,
                                                    color: AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return AppSettingsSheet(
              settings: _controller.settings,
              onBackgroundIntervalChanged: (interval) {
                unawaited(_controller.updateBackgroundScanInterval(interval));
              },
              onDownloadAttemptNotificationsChanged: (enabled) {
                unawaited(
                  _controller.setDownloadAttemptNotificationsEnabled(enabled),
                );
              },
              onMinimizeToTrayChanged: (enabled) {
                unawaited(_controller.setMinimizeToTrayOnClose(enabled));
                unawaited(
                  _desktopWindowService.setMinimizeToTrayEnabled(enabled),
                );
              },
              onPreviewCacheMaxSizeGbChanged: (value) {
                unawaited(_controller.setPreviewCacheMaxSizeGb(value));
              },
              onPreviewCacheMaxAgeDaysChanged: (value) {
                unawaited(_controller.setPreviewCacheMaxAgeDays(value));
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showRenameDialog(DiscoveredDevice device) async {
    final initialValue = device.aliasName ?? device.deviceName ?? '';
    final controller = TextEditingController(text: initialValue);
    final newAlias = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Custom name',
              helperText: 'Name is bound to device MAC address.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newAlias == null) {
      return;
    }

    await _controller.renameDeviceAlias(device: device, alias: newAlias);
    if (!mounted || _controller.errorMessage == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_controller.errorMessage!)));
  }

  Future<bool> _confirmSharedCacheRemoval({required String displayName}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove shared folder?'),
          content: Text(
            '"$displayName" will be removed from shared access on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _openDeviceActionsMenu(
    DiscoveredDevice device,
    Offset? globalPosition,
  ) async {
    final isFriend = device.isTrusted;
    final hasPendingRequest = _controller.hasPendingFriendRequestForDevice(
      device,
    );

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final position = globalPosition == null || overlay == null
        ? null
        : RelativeRect.fromRect(
            Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
            Offset.zero & overlay.size,
          );

    final action = await showMenu<String>(
      context: context,
      position: position ?? const RelativeRect.fromLTRB(24, 180, 24, 0),
      items: [
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Rename device'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<String>(
          value: isFriend || hasPendingRequest ? null : 'friend',
          enabled: !isFriend && !hasPendingRequest,
          child: ListTile(
            leading: Icon(
              isFriend
                  ? Icons.check_circle_outline
                  : hasPendingRequest
                  ? Icons.schedule_rounded
                  : Icons.person_add_alt_1_rounded,
            ),
            title: Text(
              isFriend
                  ? 'Already friends'
                  : hasPendingRequest
                  ? 'Friend request pending'
                  : 'Add to friends',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );

    if (!mounted || action == null) {
      return;
    }

    if (action == 'rename') {
      await _showRenameDialog(device);
      return;
    }
    if (action == 'friend') {
      await _controller.sendFriendRequest(device);
    }
  }

  Future<void> _openAddShareMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Add shared folder'),
                subtitle: const Text(
                  'Create lightweight cache index for folder',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _controller.addSharedFolder();
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Re-cache shared folders'),
                subtitle: const Text(
                  'Refresh index and generate missing previews',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _controller.recacheSharedFolders();
                },
              ),
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('View shared folders'),
                subtitle: const Text('See all currently shared caches'),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openSharedFoldersSheet();
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Add shared files'),
                subtitle: const Text(
                  'Create lightweight cache index for files',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _controller.addSharedFiles();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSharedFoldersSheet() async {
    await _controller.reloadOwnerSharedCaches();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.78,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final sharedCaches = _controller.ownerSharedCaches;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Shared folders',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: sharedCaches.isEmpty
                            ? const Center(
                                child: Text('No shared folders yet.'),
                              )
                            : ListView.separated(
                                itemCount: sharedCaches.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (_, index) {
                                  final cache = sharedCaches[index];
                                  final isSelection = cache.rootPath.startsWith(
                                    'selection://',
                                  );
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                isSelection
                                                    ? Icons.list_alt_rounded
                                                    : Icons.folder_open,
                                                color: AppColors.brandPrimary,
                                              ),
                                              const SizedBox(
                                                width: AppSpacing.sm,
                                              ),
                                              Expanded(
                                                child: Text(
                                                  cache.displayName,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                              ),
                                              IconButton(
                                                tooltip: 'Remove from sharing',
                                                onPressed:
                                                    _controller.isAddingShare
                                                    ? null
                                                    : () async {
                                                        final confirmed =
                                                            await _confirmSharedCacheRemoval(
                                                              displayName: cache
                                                                  .displayName,
                                                            );
                                                        if (!mounted ||
                                                            !confirmed) {
                                                          return;
                                                        }
                                                        await _controller
                                                            .removeSharedCache(
                                                              cache,
                                                            );
                                                      },
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: AppColors.error,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Text(
                                            '${cache.itemCount} files • '
                                            '${_formatBytes(cache.totalBytes)}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs,
                                          ),
                                          Text(
                                            isSelection
                                                ? 'Selection cache'
                                                : cache.rootPath,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs,
                                          ),
                                          Text(
                                            'Updated: ${_formatTime(DateTime.fromMillisecondsSinceEpoch(cache.updatedAtMs))}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          if (!isSelection) ...[
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            Align(
                                              alignment: Alignment.centerLeft,
                                              child: OutlinedButton.icon(
                                                onPressed: () async {
                                                  await _controller
                                                      .openHistoryPath(
                                                        cache.rootPath,
                                                      );
                                                },
                                                icon: const Icon(
                                                  Icons.folder_open,
                                                ),
                                                label: const Text(
                                                  'Open folder',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openFileExplorer() async {
    final storageService = TransferStorageService();
    final receiveDirectory = await storageService.resolveReceiveDirectory();
    Directory? publicDownloadsDirectory;
    if (Platform.isAndroid) {
      final basePublic = await storageService
          .resolveAndroidPublicDownloadsDirectory();
      if (basePublic != null) {
        publicDownloadsDirectory = Directory(p.join(basePublic.path, 'Landa'));
      }
    }
    await _controller.reloadOwnerSharedCaches();

    final roots = <FileExplorerRoot>[];
    final seenPaths = <String>{};

    void addRoot({required String label, required String path}) {
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

    if (publicDownloadsDirectory != null) {
      addRoot(label: 'Landa Downloads', path: publicDownloadsDirectory.path);
    }
    addRoot(label: 'Incoming', path: receiveDirectory.path);
    for (final cache in _controller.ownerSharedCaches) {
      if (cache.rootPath.startsWith('selection://')) {
        continue;
      }
      addRoot(label: 'Shared: ${cache.displayName}', path: cache.rootPath);
    }

    if (!mounted) {
      return;
    }
    if (roots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No local folders available for viewer.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => FileExplorerPage(roots: roots)),
    );
  }

  String _normalizePathKey(String value) {
    var normalized = p.normalize(value).replaceAll('\\\\', '/').trim();
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  Future<void> _openHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final history = _controller.downloadHistory;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'История загрузок',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: history.isEmpty
                            ? const Center(
                                child: Text('История загрузок пока пустая'),
                              )
                            : ListView.separated(
                                itemCount: history.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (_, index) {
                                  final item = history[index];
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.peerName,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                              ),
                                              Text(
                                                _formatTime(item.createdAt),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs,
                                          ),
                                          Text(
                                            '${item.fileCount} files • ${_formatBytes(item.totalBytes)}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Wrap(
                                            spacing: AppSpacing.xs,
                                            runSpacing: AppSpacing.xs,
                                            children: item.savedPaths
                                                .take(6)
                                                .map(
                                                  (path) => ActionChip(
                                                    label: Text(
                                                      p.basename(path),
                                                    ),
                                                    onPressed: () async {
                                                      await _controller
                                                          .openHistoryPath(
                                                            path,
                                                          );
                                                    },
                                                  ),
                                                )
                                                .toList(growable: false),
                                          ),
                                          if (item.savedPaths.length > 6) ...[
                                            const SizedBox(
                                              height: AppSpacing.xxs,
                                            ),
                                            Text(
                                              '+${item.savedPaths.length - 6} more files',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                          const SizedBox(height: AppSpacing.sm),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              await _controller.openHistoryPath(
                                                item.rootPath,
                                              );
                                            },
                                            icon: const Icon(Icons.folder_open),
                                            label: const Text('Открыть папку'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openReceivePanel() async {
    unawaited(_controller.loadRemoteShareOptions());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: _ReceivePanelSheet(controller: _controller),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  String _formatTime(DateTime time) {
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.controller, required this.total});

  final DiscoveryController controller;
  final int total;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.lan, color: AppColors.brandPrimary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.localName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Local IP: ${controller.localIp ?? "Detecting..."}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Devices: $total • App detected: ${controller.appDetectedCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    controller.isAppInForeground
                        ? 'Auto scan interval: ${controller.settings.backgroundScanInterval.label}'
                        : 'Background mode: ${controller.settings.backgroundScanInterval.label}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    selected == null
                        ? 'Target: not selected'
                        : 'Target: ${selected.displayName} (${selected.ip})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _TransferProgressCard extends StatelessWidget {
  const _TransferProgressCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer Progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (controller.isUploading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Upload: ${(controller.uploadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _formatRateAndEta(
                  speedBytesPerSecond: controller.uploadSpeedBytesPerSecond,
                  eta: controller.uploadEta,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: controller.uploadProgress,
                minHeight: 6,
                color: AppColors.brandPrimary,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
            if (controller.isDownloading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Download: ${(controller.downloadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _formatRateAndEta(
                  speedBytesPerSecond: controller.downloadSpeedBytesPerSecond,
                  eta: controller.downloadEta,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: controller.downloadProgress,
                minHeight: 6,
                color: AppColors.success,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRateAndEta({
    required double speedBytesPerSecond,
    required Duration? eta,
  }) {
    final speedText = speedBytesPerSecond > 0
        ? _formatSpeed(speedBytesPerSecond)
        : '-- B/s';
    final etaText = eta == null ? 'ETA --:--' : 'ETA ${_formatEta(eta)}';
    return '$speedText • $etaText';
  }

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    }
    final kb = bytesPerSecond / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB/s';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB/s';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB/s';
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
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onSelect,
    required this.onOpenActionsMenu,
  });

  final DiscoveredDevice device;
  final bool selected;
  final void Function(String ip) onSelect;
  final Future<void> Function(DiscoveredDevice device, Offset? globalPosition)
  onOpenActionsMenu;

  @override
  Widget build(BuildContext context) {
    final targetPlatform = Theme.of(context).platform;
    final isDesktopPlatform =
        targetPlatform == TargetPlatform.windows ||
        targetPlatform == TargetPlatform.linux ||
        targetPlatform == TargetPlatform.macOS;
    final isHighlighted = device.isAppDetected;
    final tileBackground = selected
        ? AppColors.brandAccent.withValues(alpha: 0.22)
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.09)
        : AppColors.surface;
    final borderColor = selected
        ? AppColors.brandPrimary
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.45)
        : AppColors.mutedBorder;
    final iconColor = isHighlighted
        ? AppColors.brandPrimary
        : AppColors.mutedIcon;
    final iconData = switch (device.deviceCategory) {
      DeviceCategory.phone => Icons.smartphone_rounded,
      DeviceCategory.pc => Icons.computer_rounded,
      DeviceCategory.unknown => Icons.devices,
    };
    final subtitle = [
      device.ip,
      if (device.macAddress != null) 'MAC ${device.macAddress}',
      if (device.operatingSystem != null && device.operatingSystem!.isNotEmpty)
        'OS ${device.operatingSystem}',
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPressStart: isDesktopPlatform
            ? null
            : (details) =>
                  unawaited(onOpenActionsMenu(device, details.globalPosition)),
        onSecondaryTapDown: isDesktopPlatform
            ? (details) =>
                  unawaited(onOpenActionsMenu(device, details.globalPosition))
            : null,
        child: ListTile(
          minTileHeight: 56,
          onTap: () => onSelect(device.ip),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          leading: Icon(iconData, color: iconColor),
          title: Text(
            device.displayName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: device.isTrusted ? 'Friend' : 'Not a friend yet',
                child: Icon(
                  device.isTrusted ? Icons.star : Icons.star_border,
                  color: device.isTrusted
                      ? AppColors.warning
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatusChip(device: device, selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.device, required this.selected});

  final DiscoveredDevice device;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandPrimary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'Target',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.brandPrimaryDark),
        ),
      );
    }
    if (device.isAppDetected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'App found',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.success),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.mutedIcon.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        device.isReachable ? 'LAN host' : 'Stale',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_find, size: 48, color: AppColors.mutedIcon),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No devices found yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Make sure you are on the same Wi-Fi / LAN and refresh.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onRefresh,
                child: const Text('Refresh scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceivePanelSheet extends StatefulWidget {
  const _ReceivePanelSheet({required this.controller});

  final DiscoveryController controller;

  @override
  State<_ReceivePanelSheet> createState() => _ReceivePanelSheetState();
}

class _ReceivePanelSheetState extends State<_ReceivePanelSheet> {
  String? _selectedOwnerIp;
  final Set<String> _selectedFileIds = <String>{};
  final Set<String> _selectedFolderIds = <String>{};
  String? _previewingFileId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final remoteOptions = widget.controller.remoteShareOptions;
        final owners = _buildOwnerChoices(remoteOptions);
        final selectedOwner = _selectedOwnerIp == null
            ? null
            : _findOwnerByIp(owners, _selectedOwnerIp!);
        if (selectedOwner == null && _selectedOwnerIp != null) {
          _selectedOwnerIp = null;
          _selectedFileIds.clear();
          _selectedFolderIds.clear();
        }

        final fileChoices = _selectedOwnerIp == null
            ? const <_RemoteFileChoice>[]
            : _buildFileChoices(
                remoteOptions: remoteOptions,
                ownerIp: _selectedOwnerIp!,
              );
        final folderChoices = _selectedOwnerIp == null
            ? const <_RemoteFolderChoice>[]
            : _buildFolderChoices(fileChoices);

        final validFileIds = fileChoices.map((file) => file.id).toSet();
        _selectedFileIds.removeWhere((id) => !validFileIds.contains(id));

        final validFolderIds = folderChoices.map((folder) => folder.id).toSet();
        _selectedFolderIds.removeWhere((id) => !validFolderIds.contains(id));

        final selectedFolderPathsByCache = _buildSelectedFolderPathsByCache(
          folderChoices,
        );
        final effectiveSelectedFileIds = _resolveEffectiveSelectedFileIds(
          files: fileChoices,
          selectedFolderPathsByCache: selectedFolderPathsByCache,
        );

        final selectedCount = effectiveSelectedFileIds.length;
        final requests = widget.controller.incomingRequests;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Выбор файлов из LAN',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Обновить список',
                      onPressed: widget.controller.isLoadingRemoteShares
                          ? null
                          : widget.controller.loadRemoteShareOptions,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.controller.isLoadingRemoteShares) ...[
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.brandPrimary,
                    backgroundColor: AppColors.mutedBorder,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                OutlinedButton.icon(
                  onPressed: owners.isEmpty ? null : () => _pickOwner(owners),
                  icon: const Icon(Icons.devices_rounded),
                  label: Text(
                    selectedOwner == null
                        ? 'Выбрать устройство'
                        : 'Устройство: ${selectedOwner.name}',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: owners.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет доступных общих папок/файлов на устройствах LAN',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : selectedOwner == null
                      ? const Center(
                          child: Text(
                            'Нажмите "Выбрать устройство", чтобы увидеть файлы.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selectedOwner.name} • ${selectedOwner.ip}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Доступно: ${selectedOwner.fileCount} файлов',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedFolderIds.clear();
                                      _selectedFileIds
                                        ..clear()
                                        ..addAll(
                                          fileChoices.map((file) => file.id),
                                        );
                                    });
                                  },
                                  child: const Text('Выбрать все файлы'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedFileIds.clear();
                                      _selectedFolderIds.clear();
                                    });
                                  },
                                  child: const Text('Очистить'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: folderChoices.isEmpty
                                      ? null
                                      : () => _pickFolders(folderChoices),
                                  icon: const Icon(Icons.folder_copy_outlined),
                                  label: Text(
                                    'Папки целиком (${_selectedFolderIds.length})',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Выбрано файлов: $selectedCount',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Expanded(
                              child: ListView.separated(
                                itemCount: fileChoices.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.xs),
                                itemBuilder: (_, index) {
                                  final file = fileChoices[index];
                                  final coveredByFolder =
                                      _isFileCoveredByFolderSelection(
                                        file: file,
                                        selectedFolderPathsByCache:
                                            selectedFolderPathsByCache,
                                      );
                                  final checked = effectiveSelectedFileIds
                                      .contains(file.id);
                                  final subtitle =
                                      '${file.cacheDisplayName} • ${_formatBytes(file.sizeBytes)}'
                                      '${coveredByFolder ? ' • из выбранной папки' : ''}';
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: coveredByFolder
                                        ? null
                                        : (value) {
                                            setState(() {
                                              if (value == true) {
                                                _selectedFileIds.add(file.id);
                                              } else {
                                                _selectedFileIds.remove(
                                                  file.id,
                                                );
                                              }
                                            });
                                          },
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                    ),
                                    title: Text(
                                      file.relativePath,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    secondary: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Preview before download',
                                          onPressed: _previewingFileId == null
                                              ? () => _previewRemoteFile(file)
                                              : null,
                                          icon: _previewingFileId == file.id
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                        ),
                                        _RemoteFilePreview(file: file),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: selectedCount == 0
                                    ? null
                                    : () => _requestSelectedFiles(
                                        owner: selectedOwner,
                                        files: fileChoices,
                                        selectedFolderPathsByCache:
                                            selectedFolderPathsByCache,
                                      ),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  'Скачать выбранные ($selectedCount)',
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const Divider(height: AppSpacing.lg),
                Text(
                  'Входящие запросы на передачу',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (requests.isEmpty)
                  Text(
                    'Нет ожидающих запросов.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  SizedBox(
                    height: 150,
                    child: ListView.separated(
                      itemCount: requests.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (_, index) {
                        final request = requests[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${request.senderName} • ${request.sharedLabel}\n'
                                '${request.items.length} files • ${_formatBytes(request.totalBytes)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await widget.controller
                                    .respondToTransferRequest(
                                      requestId: request.requestId,
                                      approved: false,
                                    );
                              },
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                await widget.controller
                                    .respondToTransferRequest(
                                      requestId: request.requestId,
                                      approved: true,
                                    );
                              },
                              child: const Text('Accept'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickOwner(List<_RemoteOwnerChoice> owners) async {
    final selectedIp = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: owners.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final owner = owners[index];
              return ListTile(
                title: Text(owner.name),
                subtitle: Text(
                  '${owner.ip} • ${owner.fileCount} файлов • ${owner.shareCount} шар',
                ),
                onTap: () => Navigator.of(context).pop(owner.ip),
              );
            },
          ),
        );
      },
    );

    if (selectedIp == null || !mounted) {
      return;
    }
    setState(() {
      _selectedOwnerIp = selectedIp;
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
    });
  }

  Future<void> _pickFolders(List<_RemoteFolderChoice> folders) async {
    final validIds = folders.map((folder) => folder.id).toSet();
    final initialSelection = _selectedFolderIds
        .where(validIds.contains)
        .toSet();

    final selectedIds = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final draftSelection = <String>{...initialSelection};
        return FractionallySizedBox(
          heightFactor: 0.8,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Скачать папки целиком',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Отметьте папки. Их содержимое будет скачано с сохранением структуры.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: ListView.separated(
                          itemCount: folders.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (_, index) {
                            final folder = folders[index];
                            final checked = draftSelection.contains(folder.id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    draftSelection.add(folder.id);
                                  } else {
                                    draftSelection.remove(folder.id);
                                  }
                                });
                              },
                              title: Text(folder.displayLabel),
                              subtitle: Text(
                                '${folder.fileCount} файлов • ${_formatBytes(folder.totalBytes)}',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Отмена'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(context).pop(draftSelection),
                            child: const Text('Применить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    if (selectedIds == null || !mounted) {
      return;
    }

    setState(() {
      _selectedFolderIds
        ..clear()
        ..addAll(selectedIds);
    });
  }

  Future<void> _previewRemoteFile(_RemoteFileChoice file) async {
    setState(() {
      _previewingFileId = file.id;
    });

    try {
      final previewPath = await widget.controller.requestRemoteFilePreview(
        ownerIp: file.ownerIp,
        ownerName: _selectedOwnerIp ?? file.ownerIp,
        cacheId: file.cacheId,
        relativePath: file.relativePath,
      );
      if (!mounted || previewPath == null || previewPath.trim().isEmpty) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalFileViewerPage(filePath: previewPath),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _previewingFileId = null;
        });
      }
    }
  }

  Future<void> _requestSelectedFiles({
    required _RemoteOwnerChoice owner,
    required List<_RemoteFileChoice> files,
    required Map<String, Set<String>> selectedFolderPathsByCache,
  }) async {
    final selectedByCache = <String, Set<String>>{};
    for (final file in files) {
      final cacheKey = _cacheSelectionKey(
        ownerIp: file.ownerIp,
        cacheId: file.cacheId,
      );
      final pickedByFolder = _matchesFolderSelection(
        relativePath: file.relativePath,
        selectedFolderPaths: selectedFolderPathsByCache[cacheKey],
      );
      if (!_selectedFileIds.contains(file.id) && !pickedByFolder) {
        continue;
      }
      selectedByCache
          .putIfAbsent(file.cacheId, () => <String>{})
          .add(file.relativePath);
    }

    await widget.controller.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedFileIds.clear();
      _selectedFolderIds.clear();
    });
  }

  _RemoteOwnerChoice? _findOwnerByIp(
    List<_RemoteOwnerChoice> owners,
    String ip,
  ) {
    for (final owner in owners) {
      if (owner.ip == ip) {
        return owner;
      }
    }
    return null;
  }

  List<_RemoteOwnerChoice> _buildOwnerChoices(List<RemoteShareOption> options) {
    final ownersByIp = <String, _RemoteOwnerDraft>{};
    for (final option in options) {
      final draft = ownersByIp.putIfAbsent(
        option.ownerIp,
        () => _RemoteOwnerDraft(
          ip: option.ownerIp,
          name: option.ownerName,
          macAddress: option.ownerMacAddress,
        ),
      );
      draft.shareCount += 1;
      for (final file in option.entry.files) {
        draft.uniqueFiles.add('${option.entry.cacheId}|${file.relativePath}');
      }
    }

    final list = ownersByIp.values
        .map(
          (draft) => _RemoteOwnerChoice(
            ip: draft.ip,
            name: draft.name,
            macAddress: draft.macAddress,
            shareCount: draft.shareCount,
            fileCount: draft.uniqueFiles.length,
          ),
        )
        .toList(growable: false);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<_RemoteFileChoice> _buildFileChoices({
    required List<RemoteShareOption> remoteOptions,
    required String ownerIp,
  }) {
    final files = <_RemoteFileChoice>[];
    for (final option in remoteOptions) {
      if (option.ownerIp != ownerIp) {
        continue;
      }
      for (final file in option.entry.files) {
        files.add(
          _RemoteFileChoice(
            ownerIp: option.ownerIp,
            cacheId: option.entry.cacheId,
            cacheDisplayName: option.entry.displayName,
            relativePath: file.relativePath,
            sizeBytes: file.sizeBytes,
            thumbnailId: file.thumbnailId,
            previewPath: widget.controller.remoteThumbnailPath(
              ownerIp: option.ownerIp,
              cacheId: option.entry.cacheId,
              relativePath: file.relativePath,
            ),
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

  List<_RemoteFolderChoice> _buildFolderChoices(List<_RemoteFileChoice> files) {
    final byId = <String, _RemoteFolderDraft>{};
    for (final file in files) {
      final folderPaths = <String>[
        '',
        ..._extractFolderPaths(file.relativePath),
      ];
      for (final folderPath in folderPaths) {
        final id = _folderId(
          ownerIp: file.ownerIp,
          cacheId: file.cacheId,
          folderPath: folderPath,
        );
        final draft = byId.putIfAbsent(
          id,
          () => _RemoteFolderDraft(
            ownerIp: file.ownerIp,
            cacheId: file.cacheId,
            cacheDisplayName: file.cacheDisplayName,
            folderPath: folderPath,
          ),
        );
        if (draft.fileIds.add(file.id)) {
          draft.fileCount += 1;
          draft.totalBytes += file.sizeBytes;
        }
      }
    }

    final folders = byId.values
        .map(
          (draft) => _RemoteFolderChoice(
            ownerIp: draft.ownerIp,
            cacheId: draft.cacheId,
            cacheDisplayName: draft.cacheDisplayName,
            folderPath: draft.folderPath,
            fileCount: draft.fileCount,
            totalBytes: draft.totalBytes,
          ),
        )
        .toList(growable: false);
    folders.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      final depthCmp = a.depth.compareTo(b.depth);
      if (depthCmp != 0) {
        return depthCmp;
      }
      return a.folderPath.toLowerCase().compareTo(b.folderPath.toLowerCase());
    });
    return folders;
  }

  Map<String, Set<String>> _buildSelectedFolderPathsByCache(
    List<_RemoteFolderChoice> folders,
  ) {
    final byCache = <String, Set<String>>{};
    for (final folder in folders) {
      if (!_selectedFolderIds.contains(folder.id)) {
        continue;
      }
      final cacheKey = _cacheSelectionKey(
        ownerIp: folder.ownerIp,
        cacheId: folder.cacheId,
      );
      byCache.putIfAbsent(cacheKey, () => <String>{}).add(folder.folderPath);
    }
    return byCache;
  }

  Set<String> _resolveEffectiveSelectedFileIds({
    required List<_RemoteFileChoice> files,
    required Map<String, Set<String>> selectedFolderPathsByCache,
  }) {
    final selected = <String>{};
    for (final file in files) {
      if (_selectedFileIds.contains(file.id)) {
        selected.add(file.id);
        continue;
      }
      final cacheKey = _cacheSelectionKey(
        ownerIp: file.ownerIp,
        cacheId: file.cacheId,
      );
      if (_matchesFolderSelection(
        relativePath: file.relativePath,
        selectedFolderPaths: selectedFolderPathsByCache[cacheKey],
      )) {
        selected.add(file.id);
      }
    }
    return selected;
  }

  bool _isFileCoveredByFolderSelection({
    required _RemoteFileChoice file,
    required Map<String, Set<String>> selectedFolderPathsByCache,
  }) {
    final cacheKey = _cacheSelectionKey(
      ownerIp: file.ownerIp,
      cacheId: file.cacheId,
    );
    return _matchesFolderSelection(
      relativePath: file.relativePath,
      selectedFolderPaths: selectedFolderPathsByCache[cacheKey],
    );
  }

  bool _matchesFolderSelection({
    required String relativePath,
    required Set<String>? selectedFolderPaths,
  }) {
    if (selectedFolderPaths == null || selectedFolderPaths.isEmpty) {
      return false;
    }
    final normalizedPath = _normalizeRelativePath(relativePath);
    for (final folderPath in selectedFolderPaths) {
      final normalizedFolder = _normalizeRelativePath(folderPath);
      if (normalizedFolder.isEmpty) {
        return true;
      }
      if (normalizedPath == normalizedFolder ||
          normalizedPath.startsWith('$normalizedFolder/')) {
        return true;
      }
    }
    return false;
  }

  String _cacheSelectionKey({
    required String ownerIp,
    required String cacheId,
  }) {
    return '$ownerIp|$cacheId';
  }

  String _folderId({
    required String ownerIp,
    required String cacheId,
    required String folderPath,
  }) {
    return '$ownerIp|$cacheId|$folderPath';
  }

  List<String> _extractFolderPaths(String relativePath) {
    final normalized = _normalizeRelativePath(relativePath);
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length < 2) {
      return const <String>[];
    }

    final folders = <String>[];
    for (var i = 1; i < parts.length; i++) {
      folders.add(parts.take(i).join('/'));
    }
    return folders;
  }

  String _normalizeRelativePath(String value) {
    return value.replaceAll('\\', '/').trim();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

enum _RemoteMediaKind { image, video, other }

class _RemoteFilePreview extends StatelessWidget {
  const _RemoteFilePreview({required this.file});

  final _RemoteFileChoice file;

  @override
  Widget build(BuildContext context) {
    final scheme = _resolveScheme(file.mediaKind);
    final hasPreview = file.previewPath != null && file.previewPath!.isNotEmpty;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPreview)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.file(
                File(file.previewPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) {
                  return Center(
                    child: Icon(scheme.icon, color: scheme.iconColor, size: 26),
                  );
                },
              ),
            )
          else
            Center(child: Icon(scheme.icon, color: scheme.iconColor, size: 26)),
          if (file.mediaKind == _RemoteMediaKind.video)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          Positioned(
            left: AppSpacing.xxs,
            right: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                file.previewLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _PreviewScheme _resolveScheme(_RemoteMediaKind kind) {
    switch (kind) {
      case _RemoteMediaKind.image:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.brandAccent,
          iconColor: AppColors.brandPrimaryDark,
          icon: Icons.image_rounded,
        );
      case _RemoteMediaKind.video:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.warning,
          iconColor: AppColors.warning,
          icon: Icons.play_circle_fill_rounded,
        );
      case _RemoteMediaKind.other:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.mutedBorder,
          iconColor: AppColors.mutedIcon,
          icon: Icons.insert_drive_file_rounded,
        );
    }
  }
}

class _PreviewScheme {
  const _PreviewScheme({
    required this.background,
    required this.border,
    required this.iconColor,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color iconColor;
  final IconData icon;
}

class _RemoteOwnerChoice {
  const _RemoteOwnerChoice({
    required this.ip,
    required this.name,
    required this.macAddress,
    required this.shareCount,
    required this.fileCount,
  });

  final String ip;
  final String name;
  final String macAddress;
  final int shareCount;
  final int fileCount;
}

class _RemoteOwnerDraft {
  _RemoteOwnerDraft({
    required this.ip,
    required this.name,
    required this.macAddress,
  });

  final String ip;
  final String name;
  final String macAddress;
  int shareCount = 0;
  final Set<String> uniqueFiles = <String>{};
}

class _RemoteFolderChoice {
  const _RemoteFolderChoice({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.folderPath,
    required this.fileCount,
    required this.totalBytes,
  });

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String folderPath;
  final int fileCount;
  final int totalBytes;

  String get id => '$ownerIp|$cacheId|$folderPath';

  int get depth =>
      folderPath.isEmpty ? 0 : '/'.allMatches(folderPath).length + 1;

  String get displayLabel => folderPath.isEmpty
      ? '$cacheDisplayName (вся расшаренная папка)'
      : '$cacheDisplayName / $folderPath';
}

class _RemoteFolderDraft {
  _RemoteFolderDraft({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.folderPath,
  });

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String folderPath;
  int fileCount = 0;
  int totalBytes = 0;
  final Set<String> fileIds = <String>{};
}

class _RemoteFileChoice {
  const _RemoteFileChoice({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.sizeBytes,
    this.thumbnailId,
    this.previewPath,
  });

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

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final int sizeBytes;
  final String? thumbnailId;
  final String? previewPath;

  String get id => '$ownerIp|$cacheId|$relativePath';

  _RemoteMediaKind get mediaKind {
    if (_imageExtensions.contains(extension)) {
      return _RemoteMediaKind.image;
    }
    if (_videoExtensions.contains(extension)) {
      return _RemoteMediaKind.video;
    }
    return _RemoteMediaKind.other;
  }

  String get extension => p.extension(relativePath).toLowerCase();

  String get previewLabel {
    final ext = extension;
    if (ext.isNotEmpty) {
      return ext.substring(1).toUpperCase();
    }
    switch (mediaKind) {
      case _RemoteMediaKind.image:
        return 'IMG';
      case _RemoteMediaKind.video:
        return 'VID';
      case _RemoteMediaKind.other:
        return 'FILE';
    }
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.onReceive,
    required this.onAdd,
    required this.onSend,
  });

  final DiscoveryController controller;
  final Future<void> Function() onReceive;
  final Future<void> Function() onAdd;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              child: FilledButton.icon(
                onPressed: onReceive,
                icon: const Icon(Icons.arrow_downward),
                label: const Text('Принять'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.isAddingShare ? null : onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Общий доступ'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.isSendingTransfer ? null : onSend,
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Отправить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

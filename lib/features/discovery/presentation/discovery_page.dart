import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/utils/desktop_window_service.dart';
import '../../clipboard/presentation/clipboard_sheet.dart';
import '../../files/presentation/file_explorer_page.dart';
import '../../settings/domain/app_settings.dart';
import '../../settings/presentation/app_settings_sheet.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../application/discovery_controller.dart';
import '../application/discovery_read_model.dart';
import '../application/remote_share_browser.dart';
import '../application/shared_cache_catalog_bridge.dart';
import '../domain/discovered_device.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    required this.controller,
    required this.readModel,
    required this.remoteShareBrowser,
    required this.sharedCacheCatalogBridge,
    required this.desktopWindowService,
    required this.transferStorageService,
    required this.isBoundaryReady,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final RemoteShareBrowser remoteShareBrowser;
  final SharedCacheCatalogBridge sharedCacheCatalogBridge;
  final DesktopWindowService desktopWindowService;
  final TransferStorageService transferStorageService;
  final bool isBoundaryReady;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  List<ShareableVideoFile> _shareableVideoFiles = const <ShareableVideoFile>[];
  String? _selectedShareableVideoId;
  bool _isLoadingShareableVideoFiles = false;

  DiscoveryController get _controller => widget.controller;
  DiscoveryReadModel get _readModel => widget.readModel;
  RemoteShareBrowser get _remoteShareBrowser => widget.remoteShareBrowser;
  SharedCacheCatalogBridge get _sharedCacheCatalogBridge =>
      widget.sharedCacheCatalogBridge;
  DesktopWindowService get _desktopWindowService => widget.desktopWindowService;
  TransferStorageService get _transferStorageService =>
      widget.transferStorageService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleInfoMessages);
    if (widget.isBoundaryReady) {
      unawaited(_reloadShareableVideoFiles());
    }
  }

  @override
  void didUpdateWidget(covariant DiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleInfoMessages);
      widget.controller.addListener(_handleInfoMessages);
      if (widget.isBoundaryReady) {
        unawaited(_reloadShareableVideoFiles());
      }
    } else if (oldWidget.sharedCacheCatalogBridge !=
            widget.sharedCacheCatalogBridge ||
        (!oldWidget.isBoundaryReady && widget.isBoundaryReady)) {
      unawaited(_reloadShareableVideoFiles());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleInfoMessages);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isForeground = state == AppLifecycleState.resumed;
    _controller.setAppForegroundState(isForeground);
  }

  void _handleInfoMessages() {
    final info = _controller.infoMessage;
    if (!mounted || info == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
    _controller.clearInfoMessage();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _readModel]),
      builder: (context, _) {
        final devices = _readModel.devices;
        final isLeftHanded = _readModel.settings.isLeftHandedMode;
        final isTabletLayout = MediaQuery.sizeOf(context).width >= 900;
        final sideMenu = _SideMenuDrawer(
          onOpenFriends: _openFriendsSheet,
          onOpenSettings: _openSettingsSheet,
          onOpenClipboard: _openClipboardSheet,
          onOpenHistory: _openHistorySheet,
          onOpenFiles: _openFileExplorer,
          onRefresh: _controller.isManualRefreshInProgress
              ? null
              : _controller.refresh,
          controller: _controller,
          videos: _shareableVideoFiles,
          selectedVideoId: _selectedShareableVideoId,
          isLoadingVideos: _isLoadingShareableVideoFiles,
          onSelectedVideoChanged: (next) {
            setState(() {
              _selectedShareableVideoId = next;
            });
          },
          onOpenVideoList: () => unawaited(_reloadShareableVideoFiles()),
          onToggleVideoServer: _toggleVideoLinkServer,
          onCopyVideoLink: _controller.videoLinkWatchUrl == null
              ? null
              : () =>
                    unawaited(_copyToClipboard(_controller.videoLinkWatchUrl!)),
        );
        final sideMenuPanel = SizedBox(
          width: 296,
          child: ColoredBox(
            color: AppColors.surface,
            child: _SideMenuActions(
              onOpenFriends: _openFriendsSheet,
              onOpenSettings: _openSettingsSheet,
              onOpenClipboard: _openClipboardSheet,
              onOpenHistory: _openHistorySheet,
              onOpenFiles: _openFileExplorer,
              onRefresh: _controller.isManualRefreshInProgress
                  ? null
                  : _controller.refresh,
              controller: _controller,
              videos: _shareableVideoFiles,
              selectedVideoId: _selectedShareableVideoId,
              isLoadingVideos: _isLoadingShareableVideoFiles,
              onSelectedVideoChanged: (next) {
                setState(() {
                  _selectedShareableVideoId = next;
                });
              },
              onOpenVideoList: () => unawaited(_reloadShareableVideoFiles()),
              onToggleVideoServer: _toggleVideoLinkServer,
              onCopyVideoLink: _controller.videoLinkWatchUrl == null
                  ? null
                  : () => unawaited(
                      _copyToClipboard(_controller.videoLinkWatchUrl!),
                    ),
              closeOnTap: false,
            ),
          ),
        );
        final mainContent = Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              _NetworkSummaryCard(readModel: _readModel, total: devices.length),
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
                              _readModel.selectedDevice?.ip ==
                              devices[index].ip,
                          onSelect: _controller.selectDeviceByIp,
                          onOpenActionsMenu: _openDeviceActionsMenu,
                        ),
                      ),
              ),
            ],
          ),
        );
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: isLeftHanded && !isTabletLayout
                ? Builder(
                    builder: (buttonContext) {
                      return IconButton(
                        tooltip: 'Menu',
                        onPressed: () {
                          unawaited(_reloadShareableVideoFiles());
                          Scaffold.of(buttonContext).openDrawer();
                        },
                        icon: const Icon(Icons.menu_rounded),
                      );
                    },
                  )
                : null,
            title: const Text('Landa devices'),
            actions: [
              if (!isLeftHanded && !isTabletLayout)
                Builder(
                  builder: (buttonContext) {
                    return IconButton(
                      tooltip: 'Menu',
                      onPressed: () {
                        unawaited(_reloadShareableVideoFiles());
                        Scaffold.of(buttonContext).openEndDrawer();
                      },
                      icon: const Icon(Icons.menu_rounded),
                    );
                  },
                ),
            ],
          ),
          drawer: !isTabletLayout && isLeftHanded ? sideMenu : null,
          endDrawer: !isTabletLayout && !isLeftHanded ? sideMenu : null,
          drawerEnableOpenDragGesture: !isTabletLayout && isLeftHanded,
          endDrawerEnableOpenDragGesture: !isTabletLayout && !isLeftHanded,
          body: isTabletLayout
              ? Row(
                  children: [
                    if (isLeftHanded) ...[
                      sideMenuPanel,
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.mutedBorder,
                      ),
                    ],
                    Expanded(child: mainContent),
                    if (!isLeftHanded) ...[
                      const VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: AppColors.mutedBorder,
                      ),
                      sideMenuPanel,
                    ],
                  ],
                )
              : mainContent,
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
              animation: Listenable.merge(<Listenable>[
                _controller,
                _readModel,
              ]),
              builder: (context, _) {
                final friends = _readModel.friendDevices;
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

  Future<void> _openClipboardSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: ClipboardSheet(controller: _controller, readModel: _readModel),
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
          animation: Listenable.merge(<Listenable>[_controller, _readModel]),
          builder: (context, _) {
            return AppSettingsSheet(
              settings: _readModel.settings,
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
              onLeftHandedModeChanged: (enabled) {
                unawaited(_controller.setLeftHandedMode(enabled));
              },
              onVideoLinkPasswordChanged: (value) {
                unawaited(_controller.setVideoLinkPassword(value));
              },
              onPreviewCacheMaxSizeGbChanged: (value) {
                unawaited(_controller.setPreviewCacheMaxSizeGb(value));
              },
              onPreviewCacheMaxAgeDaysChanged: (value) {
                unawaited(_controller.setPreviewCacheMaxAgeDays(value));
              },
              onClipboardHistoryMaxEntriesChanged: (value) {
                unawaited(_controller.setClipboardHistoryMaxEntries(value));
              },
              onRecacheParallelWorkersChanged: (value) {
                unawaited(_controller.setRecacheParallelWorkers(value));
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

  Future<SharedRecacheActionResult> _handleSharedRecacheFromFiles(
    String virtualFolderPath,
  ) async {
    final normalizedFolder = virtualFolderPath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .join('/');
    if (_controller.isSharedRecacheInProgress) {
      return SharedRecacheActionResult.refreshedOnly;
    }
    if (_controller.isSharedRecacheCooldownActive) {
      return SharedRecacheActionResult.refreshedOnly;
    }

    final before = await _sharedCacheCatalogBridge.summarizeOwnerSharedContent(
      virtualFolderPath: normalizedFolder,
    );
    if (!mounted) {
      return SharedRecacheActionResult.cancelled;
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
      return SharedRecacheActionResult.refreshedOnly;
    }

    final agreed = await _confirmSharedRecacheAgreement(
      before,
      virtualFolderPath: normalizedFolder,
    );
    if (!agreed) {
      return SharedRecacheActionResult.cancelled;
    }

    final report = await _controller.recacheSharedContent(
      virtualFolderPath: normalizedFolder,
    );
    if (!mounted) {
      return SharedRecacheActionResult.started;
    }
    if (report != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Before cache: ${report.before.totalFiles} files, '
            'after re-cache: ${report.after.totalFiles} files.',
          ),
        ),
      );
    }
    await _reloadShareableVideoFiles();
    return SharedRecacheActionResult.started;
  }

  Future<bool> _handleRemoveSharedCacheFromFiles(
    String cacheId,
    String cacheLabel,
  ) async {
    final removed = await _controller.removeSharedCacheById(cacheId);
    if (!mounted) {
      return removed;
    }

    if (removed) {
      await _reloadShareableVideoFiles();
      if (!mounted) {
        return removed;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed from sharing: $cacheLabel')),
      );
    } else if (_controller.errorMessage != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_controller.errorMessage!)));
    }
    return removed;
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

  Future<void> _copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  ShareableVideoFile? get _selectedShareableVideoFile {
    final selectedId = _selectedShareableVideoId;
    if (selectedId == null) {
      return null;
    }
    for (final file in _shareableVideoFiles) {
      if (file.id == selectedId) {
        return file;
      }
    }
    return null;
  }

  Future<void> _reloadShareableVideoFiles({bool notifyIfEmpty = false}) async {
    if (_isLoadingShareableVideoFiles) {
      return;
    }
    setState(() {
      _isLoadingShareableVideoFiles = true;
    });
    try {
      final files = await _sharedCacheCatalogBridge.listShareableVideoFiles();
      if (!mounted) {
        return;
      }
      var selectedId = _selectedShareableVideoId;
      if (selectedId == null || files.every((file) => file.id != selectedId)) {
        selectedId = files.isEmpty ? null : files.first.id;
      }
      setState(() {
        _shareableVideoFiles = files;
        _selectedShareableVideoId = selectedId;
      });
      if (notifyIfEmpty && files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No shared video files available. Add shared files first.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingShareableVideoFiles = false;
        });
      }
    }
  }

  Future<void> _publishSelectedVideoLink() async {
    final selected = _selectedShareableVideoFile;
    if (selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a video file first.')),
      );
      return;
    }
    final password = _readModel.settings.videoLinkPassword.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set a web-link password in Settings.')),
      );
      return;
    }

    await _controller.publishVideoLinkShare(file: selected, password: password);
  }

  Future<void> _toggleVideoLinkServer(bool enabled) async {
    if (enabled) {
      if (_shareableVideoFiles.isEmpty) {
        await _reloadShareableVideoFiles(notifyIfEmpty: true);
      }
      if (_shareableVideoFiles.isEmpty) {
        return;
      }
      await _publishSelectedVideoLink();
      return;
    }

    final activeSession = _controller.videoLinkShareSession;
    if (activeSession == null) {
      return;
    }
    final shouldStop = await _confirmStopVideoLinkShare();
    if (!shouldStop) {
      return;
    }
    await _controller.stopVideoLinkShare();
  }

  Future<bool> _confirmStopVideoLinkShare() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Stop video link sharing?'),
          content: const Text(
            'The active video link will stop working until you publish a file again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Stop'),
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
                  if (!mounted) {
                    return;
                  }
                  await _reloadShareableVideoFiles();
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
                  if (!mounted) {
                    return;
                  }
                  await _reloadShareableVideoFiles();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openFileExplorer() async {
    final receiveDirectory = await _transferStorageService
        .resolveReceiveDirectory();
    Directory? publicDownloadsDirectory;
    if (Platform.isAndroid) {
      final basePublic = await _transferStorageService
          .resolveAndroidPublicDownloadsDirectory();
      if (basePublic != null) {
        publicDownloadsDirectory = Directory(p.join(basePublic.path, 'Landa'));
      }
    }
    final sharedSummary = await _sharedCacheCatalogBridge
        .summarizeOwnerSharedContent();

    final roots = <FileExplorerRoot>[];
    final seenPaths = <String>{};

    void addRoot({
      required String label,
      required String path,
      bool isSharedFolder = false,
      List<FileExplorerVirtualFile> virtualFiles =
          const <FileExplorerVirtualFile>[],
      Future<List<FileExplorerVirtualFile>> Function()? virtualFilesLoader,
      Future<FileExplorerVirtualDirectory> Function(String folderPath)?
      virtualDirectoryLoader,
    }) {
      if (virtualFiles.isNotEmpty ||
          virtualFilesLoader != null ||
          virtualDirectoryLoader != null) {
        roots.add(
          FileExplorerRoot(
            label: label,
            path: path,
            isSharedFolder: isSharedFolder,
            virtualFiles: virtualFiles,
            virtualFilesLoader: virtualFilesLoader,
            virtualDirectoryLoader: virtualDirectoryLoader,
          ),
        );
        return;
      }
      final normalized = _normalizePathKey(path);
      if (normalized.isEmpty || seenPaths.contains(normalized)) {
        return;
      }
      if (!Directory(path).existsSync()) {
        return;
      }
      seenPaths.add(normalized);
      roots.add(
        FileExplorerRoot(
          label: label,
          path: path,
          isSharedFolder: isSharedFolder,
          virtualFiles: virtualFiles,
          virtualFilesLoader: virtualFilesLoader,
          virtualDirectoryLoader: virtualDirectoryLoader,
        ),
      );
    }

    if (publicDownloadsDirectory != null) {
      addRoot(label: 'Landa Downloads', path: publicDownloadsDirectory.path);
    }
    addRoot(label: 'Incoming', path: receiveDirectory.path);
    if (sharedSummary.totalFiles > 0) {
      addRoot(
        label: 'My files',
        path: 'virtual://my-files',
        isSharedFolder: true,
        virtualDirectoryLoader: (folderPath) async {
          final directory = await _sharedCacheCatalogBridge
              .listShareableLocalDirectory(virtualFolderPath: folderPath);
          return FileExplorerVirtualDirectory(
            folders: directory.folders
                .map(
                  (folder) => FileExplorerVirtualFolder(
                    name: folder.name,
                    folderPath: folder.virtualPath,
                    removableSharedCacheId: folder.removableSharedCacheId,
                  ),
                )
                .toList(growable: false),
            files: directory.files
                .map(
                  (file) => FileExplorerVirtualFile(
                    path: file.absolutePath,
                    subtitle: '${file.cacheDisplayName} / ${file.relativePath}',
                    virtualPath: file.virtualPath,
                    sizeBytes: file.sizeBytes,
                    modifiedAt: DateTime.fromMillisecondsSinceEpoch(
                      file.modifiedAtMs,
                    ),
                    changedAt: DateTime.fromMillisecondsSinceEpoch(
                      file.modifiedAtMs,
                    ),
                  ),
                )
                .toList(growable: false),
          );
        },
      );
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
      MaterialPageRoute<void>(
        builder: (_) => FileExplorerPage(
          roots: roots,
          onRecacheSharedFolders: _handleSharedRecacheFromFiles,
          onRemoveSharedCache: _handleRemoveSharedCacheFromFiles,
          recacheStateListenable: _controller,
          isSharedRecacheInProgress: () =>
              _controller.isSharedRecacheInProgress,
          sharedRecacheProgress: () => _controller.sharedRecacheProgress,
          sharedRecacheDetails: () {
            final details = _controller.sharedRecacheDetails;
            if (details == null) {
              return null;
            }
            return SharedRecacheProgressDetails(
              processedFiles: details.processedFiles,
              totalFiles: details.totalFiles,
              currentCacheLabel: details.currentCacheLabel,
              currentRelativePath: details.currentRelativePath,
              eta: details.eta,
            );
          },
        ),
      ),
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
          child: _ReceivePanelSheet(
            controller: _controller,
            remoteShareBrowser: _remoteShareBrowser,
          ),
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

class _SideMenuDrawer extends StatelessWidget {
  const _SideMenuDrawer({
    required this.onOpenFriends,
    required this.onOpenSettings,
    required this.onOpenClipboard,
    required this.onOpenHistory,
    required this.onOpenFiles,
    required this.onRefresh,
    required this.controller,
    required this.videos,
    required this.selectedVideoId,
    required this.isLoadingVideos,
    required this.onSelectedVideoChanged,
    required this.onOpenVideoList,
    required this.onToggleVideoServer,
    required this.onCopyVideoLink,
  });

  final Future<void> Function() onOpenFriends;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenClipboard;
  final Future<void> Function() onOpenHistory;
  final Future<void> Function() onOpenFiles;
  final Future<void> Function()? onRefresh;
  final DiscoveryController controller;
  final List<ShareableVideoFile> videos;
  final String? selectedVideoId;
  final bool isLoadingVideos;
  final ValueChanged<String?> onSelectedVideoChanged;
  final VoidCallback onOpenVideoList;
  final ValueChanged<bool> onToggleVideoServer;
  final VoidCallback? onCopyVideoLink;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: _SideMenuActions(
        onOpenFriends: onOpenFriends,
        onOpenSettings: onOpenSettings,
        onOpenClipboard: onOpenClipboard,
        onOpenHistory: onOpenHistory,
        onOpenFiles: onOpenFiles,
        onRefresh: onRefresh,
        controller: controller,
        videos: videos,
        selectedVideoId: selectedVideoId,
        isLoadingVideos: isLoadingVideos,
        onSelectedVideoChanged: onSelectedVideoChanged,
        onOpenVideoList: onOpenVideoList,
        onToggleVideoServer: onToggleVideoServer,
        onCopyVideoLink: onCopyVideoLink,
        closeOnTap: true,
      ),
    );
  }
}

class _SideMenuActions extends StatelessWidget {
  const _SideMenuActions({
    required this.onOpenFriends,
    required this.onOpenSettings,
    required this.onOpenClipboard,
    required this.onOpenHistory,
    required this.onOpenFiles,
    required this.onRefresh,
    required this.controller,
    required this.videos,
    required this.selectedVideoId,
    required this.isLoadingVideos,
    required this.onSelectedVideoChanged,
    required this.onOpenVideoList,
    required this.onToggleVideoServer,
    required this.onCopyVideoLink,
    required this.closeOnTap,
  });

  final Future<void> Function() onOpenFriends;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenClipboard;
  final Future<void> Function() onOpenHistory;
  final Future<void> Function() onOpenFiles;
  final Future<void> Function()? onRefresh;
  final DiscoveryController controller;
  final List<ShareableVideoFile> videos;
  final String? selectedVideoId;
  final bool isLoadingVideos;
  final ValueChanged<String?> onSelectedVideoChanged;
  final VoidCallback onOpenVideoList;
  final ValueChanged<bool> onToggleVideoServer;
  final VoidCallback? onCopyVideoLink;
  final bool closeOnTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Text('Menu', style: Theme.of(context).textTheme.titleLarge),
          ),
          _buildItem(
            context: context,
            icon: Icons.group_rounded,
            title: 'Friends',
            onTap: onOpenFriends,
          ),
          _buildItem(
            context: context,
            icon: Icons.tune_rounded,
            title: 'Settings',
            onTap: onOpenSettings,
          ),
          _buildItem(
            context: context,
            icon: Icons.content_paste_rounded,
            title: 'Clipboard',
            onTap: onOpenClipboard,
          ),
          _buildItem(
            context: context,
            icon: Icons.history,
            title: 'Download history',
            onTap: onOpenHistory,
          ),
          _buildItem(
            context: context,
            icon: Icons.folder_open_rounded,
            title: 'Files',
            onTap: onOpenFiles,
          ),
          _buildItem(
            context: context,
            icon: Icons.refresh_rounded,
            title: 'Refresh',
            onTap: onRefresh,
          ),
          _VideoLinkServerCard(
            controller: controller,
            videos: videos,
            selectedVideoId: selectedVideoId,
            isLoadingVideos: isLoadingVideos,
            onSelectedVideoChanged: onSelectedVideoChanged,
            onOpenVideoList: onOpenVideoList,
            onToggle: onToggleVideoServer,
            onCopyLink: onCopyVideoLink,
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Future<void> Function()? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      enabled: onTap != null,
      onTap: onTap == null
          ? null
          : () {
              if (closeOnTap) {
                Navigator.of(context).pop();
              }
              unawaited(onTap());
            },
    );
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.readModel, required this.total});

  final DiscoveryReadModel readModel;
  final int total;

  @override
  Widget build(BuildContext context) {
    final selected = readModel.selectedDevice;
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
                    readModel.localName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Local IP: ${readModel.localIp ?? "Detecting..."}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Devices: $total • App detected: ${readModel.appDetectedCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    readModel.isAppInForeground
                        ? 'Auto scan interval: ${readModel.settings.backgroundScanInterval.label}'
                        : 'Background mode: ${readModel.settings.backgroundScanInterval.label}',
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

class _VideoLinkServerCard extends StatelessWidget {
  const _VideoLinkServerCard({
    required this.controller,
    required this.videos,
    required this.selectedVideoId,
    required this.isLoadingVideos,
    required this.onSelectedVideoChanged,
    required this.onOpenVideoList,
    required this.onToggle,
    this.onCopyLink,
  });

  final DiscoveryController controller;
  final List<ShareableVideoFile> videos;
  final String? selectedVideoId;
  final bool isLoadingVideos;
  final ValueChanged<String?> onSelectedVideoChanged;
  final VoidCallback onOpenVideoList;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final activeSession = controller.videoLinkShareSession;
    final activeUrl = controller.videoLinkWatchUrl;
    final enabled = activeSession != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          secondary: Icon(
            enabled ? Icons.language_rounded : Icons.link_off_rounded,
            color: enabled ? AppColors.success : AppColors.textMuted,
          ),
          value: enabled,
          onChanged: onToggle,
          title: const Text('Web server for video'),
        ),
        ListTile(
          title: DropdownButtonFormField<String>(
            initialValue: selectedVideoId,
            isExpanded: true,
            onTap: onOpenVideoList,
            items: videos
                .map(
                  (file) => DropdownMenuItem<String>(
                    value: file.id,
                    child: Text(
                      '${file.cacheDisplayName} • ${file.relativePath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                )
                .toList(growable: false),
            selectedItemBuilder: (context) {
              return videos
                  .map(
                    (file) => Text(
                      '${file.cacheDisplayName} • ${file.relativePath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  )
                  .toList(growable: false);
            },
            onChanged: videos.isEmpty ? null : onSelectedVideoChanged,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Video from shared files',
            ),
          ),
        ),
        if (isLoadingVideos)
          const ListTile(title: LinearProgressIndicator(minHeight: 2)),
        if (activeSession != null)
          ListTile(dense: true, title: Text('File: ${activeSession.fileName}')),
        if (activeUrl != null)
          ListTile(
            dense: true,
            title: SelectableText(
              activeUrl,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'JetBrainsMono'),
            ),
            trailing: OutlinedButton.icon(
              onPressed: onCopyLink,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
          ),
      ],
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
  const _ReceivePanelSheet({
    required this.controller,
    required this.remoteShareBrowser,
  });

  final DiscoveryController controller;
  final RemoteShareBrowser remoteShareBrowser;

  @override
  State<_ReceivePanelSheet> createState() => _ReceivePanelSheetState();
}

class _ReceivePanelSheetState extends State<_ReceivePanelSheet> {
  String? _previewingFileId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.controller,
        widget.remoteShareBrowser,
      ]),
      builder: (context, _) {
        final browse = widget.remoteShareBrowser.currentBrowseProjection;
        final owners = browse.owners;
        final selectedOwner = browse.selectedOwner;
        final fileChoices = browse.files;
        final folderChoices = browse.folders;
        final selectedCount = browse.selectedCount;
        final isFileListCapped = browse.isFileListCapped;
        final hiddenFilesCount = browse.hiddenFilesCount;
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
                      onPressed: widget.remoteShareBrowser.isLoading
                          ? null
                          : widget.controller.loadRemoteShareOptions,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.remoteShareBrowser.isLoading) ...[
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
                            if (isFileListCapped) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Показаны первые ${fileChoices.length} файлов '
                                '(скрыто: $hiddenFilesCount) для стабильной работы.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    widget.remoteShareBrowser
                                        .selectVisibleFiles(
                                          fileChoices.map((file) => file.id),
                                        );
                                  },
                                  child: Text(
                                    browse.isFileListCapped
                                        ? 'Выбрать все видимые'
                                        : 'Выбрать все файлы',
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _requestAllSharesFromOwner(
                                    owner: selectedOwner,
                                  ),
                                  icon: const Icon(Icons.download_for_offline),
                                  label: const Text('Скачать всё с устройства'),
                                ),
                                TextButton(
                                  onPressed:
                                      widget.remoteShareBrowser.clearSelections,
                                  child: const Text('Очистить'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      folderChoices.isEmpty ||
                                          browse.isFileListCapped
                                      ? null
                                      : () => _pickFolders(folderChoices),
                                  icon: const Icon(Icons.folder_copy_outlined),
                                  label: Text(
                                    'Папки целиком (${browse.selectedFolderIds.length})',
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
                                  final coveredByFolder = browse
                                      .folderCoveredFileIds
                                      .contains(file.id);
                                  final checked = browse
                                      .effectiveSelectedFileIds
                                      .contains(file.id);
                                  final subtitle =
                                      '${file.cacheDisplayName} • ${_formatBytes(file.sizeBytes)}'
                                      '${coveredByFolder ? ' • из выбранной папки' : ''}';
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: coveredByFolder
                                        ? null
                                        : (value) {
                                            widget.remoteShareBrowser
                                                .setFileSelected(
                                                  fileId: file.id,
                                                  isSelected: value == true,
                                                );
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

  Future<void> _pickOwner(List<RemoteBrowseOwnerChoice> owners) async {
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
    widget.remoteShareBrowser.selectOwner(selectedIp);
  }

  Future<void> _pickFolders(List<RemoteBrowseFolderChoice> folders) async {
    final validIds = folders.map((folder) => folder.id).toSet();
    final initialSelection = widget
        .remoteShareBrowser
        .currentBrowseProjection
        .selectedFolderIds
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

    widget.remoteShareBrowser.setSelectedFolderIds(selectedIds);
  }

  Future<void> _previewRemoteFile(RemoteBrowseFileChoice file) async {
    setState(() {
      _previewingFileId = file.id;
    });

    try {
      final previewPath = await widget.controller.requestRemoteFilePreview(
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
    required RemoteBrowseOwnerChoice owner,
  }) async {
    final selectedByCache = widget.remoteShareBrowser
        .buildSelectedRelativePathsByCache();
    await widget.controller.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
    );

    if (!mounted) {
      return;
    }
    widget.remoteShareBrowser.clearSelections();
  }

  Future<void> _requestAllSharesFromOwner({
    required RemoteBrowseOwnerChoice owner,
  }) async {
    final selectedByCache = widget.remoteShareBrowser
        .buildDownloadAllRequestForOwner(owner.ip);
    if (selectedByCache.isEmpty) {
      return;
    }

    await widget.controller.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
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
}

class _RemoteFilePreview extends StatelessWidget {
  const _RemoteFilePreview({required this.file});

  final RemoteBrowseFileChoice file;

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
          if (file.mediaKind == RemoteBrowseMediaKind.video)
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

  _PreviewScheme _resolveScheme(RemoteBrowseMediaKind kind) {
    switch (kind) {
      case RemoteBrowseMediaKind.image:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.brandAccent,
          iconColor: AppColors.brandPrimaryDark,
          icon: Icons.image_rounded,
        );
      case RemoteBrowseMediaKind.video:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.warning,
          iconColor: AppColors.warning,
          icon: Icons.play_circle_fill_rounded,
        );
      case RemoteBrowseMediaKind.other:
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
    final indexingProgress = controller.sharedFolderIndexingProgress;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalSpacing = AppSpacing.xs * 2;
            final availableWidth = (constraints.maxWidth - totalSpacing)
                .clamp(0, double.infinity)
                .toDouble();
            final perButtonWidth = availableWidth / 3;
            return Row(
              children: [
                Expanded(
                  child: _AdaptiveActionButton.filled(
                    onPressed: onReceive,
                    icon: Icons.arrow_downward,
                    label: 'Принять',
                    compactLabel: 'Приём',
                    tooltip: 'Принять файлы',
                    availableWidth: perButtonWidth,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: controller.isSharedRecacheInProgress
                      ? _SharedRecacheActionButton(
                          progress: controller.sharedRecacheProgress,
                          eta: controller.sharedRecacheDetails?.eta,
                        )
                      : indexingProgress != null
                      ? _SharedRecacheActionButton(
                          progress:
                              controller.sharedFolderIndexingProgressValue,
                          eta: indexingProgress.eta,
                        )
                      : _AdaptiveActionButton.outlined(
                          onPressed: controller.isAddingShare ? null : onAdd,
                          icon: Icons.add,
                          label: 'Общий доступ',
                          compactLabel: 'Доступ',
                          tooltip: 'Добавить общий доступ',
                          availableWidth: perButtonWidth,
                        ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _AdaptiveActionButton.filled(
                    onPressed: controller.isSendingTransfer ? null : onSend,
                    icon: Icons.arrow_upward,
                    label: 'Отправить',
                    compactLabel: 'Отпр.',
                    tooltip: 'Отправить файлы',
                    availableWidth: perButtonWidth,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _ActionButtonDensity { regular, compact, iconOnly }

class _AdaptiveActionButton extends StatelessWidget {
  const _AdaptiveActionButton.filled({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.tooltip,
    required this.availableWidth,
  }) : _outlined = false;

  const _AdaptiveActionButton.outlined({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.compactLabel,
    required this.tooltip,
    required this.availableWidth,
  }) : _outlined = true;

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String compactLabel;
  final String tooltip;
  final double availableWidth;
  final bool _outlined;

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final buttonHeight =
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS
        ? 40.0
        : 44.0;
    final density = _resolveDensity(context);
    final horizontalPadding = switch (density) {
      _ActionButtonDensity.regular => AppSpacing.sm,
      _ActionButtonDensity.compact => AppSpacing.xs,
      _ActionButtonDensity.iconOnly => AppSpacing.xs,
    };
    final labelText = switch (density) {
      _ActionButtonDensity.regular => label,
      _ActionButtonDensity.compact => compactLabel,
      _ActionButtonDensity.iconOnly => '',
    };

    final content = density == _ActionButtonDensity.iconOnly
        ? Icon(icon, size: 18)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  labelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ],
          );

    final style = (_outlined
        ? OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(buttonHeight),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          )
        : FilledButton.styleFrom(
            minimumSize: Size.fromHeight(buttonHeight),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          ));

    final button = SizedBox(
      height: buttonHeight,
      child: _outlined
          ? OutlinedButton(onPressed: onPressed, style: style, child: content)
          : FilledButton(onPressed: onPressed, style: style, child: content),
    );

    if (density == _ActionButtonDensity.iconOnly) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  _ActionButtonDensity _resolveDensity(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final fullWidth = _requiredLabelWidth(
      context: context,
      labelText: label,
      style: style,
    );
    if (availableWidth >= fullWidth) {
      return _ActionButtonDensity.regular;
    }

    final compactWidth = _requiredLabelWidth(
      context: context,
      labelText: compactLabel,
      style: style,
    );
    if (availableWidth >= compactWidth) {
      return _ActionButtonDensity.compact;
    }

    return _ActionButtonDensity.iconOnly;
  }

  double _requiredLabelWidth({
    required BuildContext context,
    required String labelText,
    required TextStyle? style,
  }) {
    return AppSpacing.sm * 2 +
        18 +
        6 +
        _measureSingleLineTextWidth(
          context: context,
          text: labelText,
          style: style,
        );
  }
}

class _SharedRecacheActionButton extends StatelessWidget {
  const _SharedRecacheActionButton({required this.progress, required this.eta});

  final double? progress;
  final Duration? eta;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = (progress ?? 0).clamp(0.0, 1.0).toDouble();
    final percentText = '${(normalizedProgress * 100).round()}%';
    final etaTextFull = eta == null ? 'ETA --:--' : 'ETA ${_formatEta(eta!)}';
    final etaTextCompact = eta == null ? '--:--' : _formatEta(eta!);
    final platform = Theme.of(context).platform;
    final buttonHeight =
        platform == TargetPlatform.windows ||
            platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS
        ? 40.0
        : 44.0;

    final percentStyle = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: AppColors.textPrimary);
    final etaStyle = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary);

    return SizedBox(
      height: buttonHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.mutedBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasSpaceForFullEta = _fitsProgressContent(
                context: context,
                maxWidth: constraints.maxWidth,
                percentText: percentText,
                etaText: etaTextFull,
                percentStyle: percentStyle,
                etaStyle: etaStyle,
                horizontalPadding: AppSpacing.sm,
              );
              final hasSpaceForCompactEta =
                  !hasSpaceForFullEta &&
                  _fitsProgressContent(
                    context: context,
                    maxWidth: constraints.maxWidth,
                    percentText: percentText,
                    etaText: etaTextCompact,
                    percentStyle: percentStyle,
                    etaStyle: etaStyle,
                    horizontalPadding: AppSpacing.xs,
                  );
              final shownEtaText = hasSpaceForFullEta
                  ? etaTextFull
                  : hasSpaceForCompactEta
                  ? etaTextCompact
                  : null;
              final horizontalPadding = shownEtaText == etaTextFull
                  ? AppSpacing.sm
                  : AppSpacing.xs;

              return Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: normalizedProgress,
                      child: Container(
                        color: AppColors.brandPrimary.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding,
                    ),
                    child: Row(
                      children: [
                        Text(
                          percentText,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: percentStyle,
                        ),
                        if (shownEtaText != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              shownEtaText,
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              textAlign: TextAlign.right,
                              style: etaStyle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  bool _fitsProgressContent({
    required BuildContext context,
    required double maxWidth,
    required String percentText,
    required String etaText,
    required TextStyle? percentStyle,
    required TextStyle? etaStyle,
    required double horizontalPadding,
  }) {
    final percentWidth = _measureSingleLineTextWidth(
      context: context,
      text: percentText,
      style: percentStyle,
    );
    final etaWidth = _measureSingleLineTextWidth(
      context: context,
      text: etaText,
      style: etaStyle,
    );
    final requiredWidth =
        horizontalPadding * 2 + percentWidth + AppSpacing.xs + etaWidth;
    return requiredWidth <= maxWidth;
  }

  static String _formatEta(Duration eta) {
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

double _measureSingleLineTextWidth({
  required BuildContext context,
  required String text,
  required TextStyle? style,
}) {
  if (text.isEmpty) {
    return 0;
  }
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout(minWidth: 0, maxWidth: double.infinity);
  return painter.width;
}

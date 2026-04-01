import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/desktop_window_service.dart';
import '../../clipboard/application/clipboard_history_store.dart';
import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../clipboard/presentation/clipboard_sheet.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../files/presentation/file_explorer_page.dart';
import '../../history/application/download_history_boundary.dart';
import '../../settings/presentation/app_settings_sheet.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../application/discovery_controller.dart';
import '../application/discovery_read_model.dart';
import '../application/remote_share_browser.dart';
import '../application/shared_cache_maintenance_boundary.dart';
import '../application/video_link_session_boundary.dart';
import '../domain/discovered_device.dart';
import 'discovery_action_bar.dart';
import 'discovery_add_share_sheet.dart';
import 'discovery_device_actions.dart';
import 'discovery_device_list_section.dart';
import 'discovery_friends_sheet.dart';
import 'discovery_history_sheet.dart';
import 'discovery_receive_panel_sheet.dart';
import 'discovery_side_menu_surface.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    required this.controller,
    required this.readModel,
    required this.remoteShareBrowser,
    required this.sharedCacheMaintenanceBoundary,
    required this.videoLinkSessionBoundary,
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.previewCacheOwner,
    required this.transferSessionCoordinator,
    required this.downloadHistoryBoundary,
    required this.clipboardHistoryStore,
    required this.remoteClipboardProjectionStore,
    required this.desktopWindowService,
    required this.transferStorageService,
    required this.isBoundaryReady,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final RemoteShareBrowser remoteShareBrowser;
  final SharedCacheMaintenanceBoundary sharedCacheMaintenanceBoundary;
  final VideoLinkSessionBoundary videoLinkSessionBoundary;
  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final PreviewCacheOwner previewCacheOwner;
  final TransferSessionCoordinator transferSessionCoordinator;
  final DownloadHistoryBoundary downloadHistoryBoundary;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;
  final DesktopWindowService desktopWindowService;
  final TransferStorageService transferStorageService;
  final bool isBoundaryReady;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  int _videoSurfaceReloadVersion = 0;

  DiscoveryController get _controller => widget.controller;
  DiscoveryReadModel get _readModel => widget.readModel;
  RemoteShareBrowser get _remoteShareBrowser => widget.remoteShareBrowser;
  SharedCacheMaintenanceBoundary get _sharedCacheMaintenanceBoundary =>
      widget.sharedCacheMaintenanceBoundary;
  VideoLinkSessionBoundary get _videoLinkSessionBoundary =>
      widget.videoLinkSessionBoundary;
  SharedCacheCatalog get _sharedCacheCatalog => widget.sharedCacheCatalog;
  SharedCacheIndexStore get _sharedCacheIndexStore =>
      widget.sharedCacheIndexStore;
  PreviewCacheOwner get _previewCacheOwner => widget.previewCacheOwner;
  TransferSessionCoordinator get _transferSessionCoordinator =>
      widget.transferSessionCoordinator;
  DownloadHistoryBoundary get _downloadHistoryBoundary =>
      widget.downloadHistoryBoundary;
  ClipboardHistoryStore get _clipboardHistoryStore =>
      widget.clipboardHistoryStore;
  RemoteClipboardProjectionStore get _remoteClipboardProjectionStore =>
      widget.remoteClipboardProjectionStore;
  DesktopWindowService get _desktopWindowService => widget.desktopWindowService;
  TransferStorageService get _transferStorageService =>
      widget.transferStorageService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_handleInfoMessages);
  }

  @override
  void didUpdateWidget(covariant DiscoveryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleInfoMessages);
      widget.controller.addListener(_handleInfoMessages);
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
    _controller.setAppForegroundState(state == AppLifecycleState.resumed);
  }

  void _handleInfoMessages() {
    final info = _controller.infoMessage;
    if (!mounted || info == null) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
    _controller.clearInfoMessage();
  }

  void _requestVideoSurfaceReload() {
    if (!mounted) {
      return;
    }
    setState(() {
      _videoSurfaceReloadVersion += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _controller,
        _readModel,
        _sharedCacheMaintenanceBoundary,
        _transferSessionCoordinator,
      ]),
      builder: (context, _) {
        final devices = _readModel.devices;
        final isLeftHanded = _readModel.settings.isLeftHandedMode;
        final isTabletLayout = MediaQuery.sizeOf(context).width >= 900;

        final drawerSurface = Drawer(
          child: DiscoverySideMenuSurface(
            onOpenFriends: _openFriendsSheet,
            onOpenSettings: _openSettingsSheet,
            onOpenClipboard: _openClipboardSheet,
            onOpenHistory: _openHistorySheet,
            onOpenFiles: _openFileExplorer,
            onRefresh: _controller.isManualRefreshInProgress
                ? null
                : _controller.refresh,
            videoLinkSessionBoundary: _videoLinkSessionBoundary,
            sharedCacheCatalog: _sharedCacheCatalog,
            sharedCacheIndexStore: _sharedCacheIndexStore,
            settings: _readModel.settings,
            ownerMacAddress: _controller.localDeviceMac,
            isBoundaryReady: widget.isBoundaryReady,
            reloadVersion: _videoSurfaceReloadVersion,
            closeOnTap: true,
          ),
        );
        final panelSurface = SizedBox(
          width: 296,
          child: ColoredBox(
            color: AppColors.surface,
            child: DiscoverySideMenuSurface(
              onOpenFriends: _openFriendsSheet,
              onOpenSettings: _openSettingsSheet,
              onOpenClipboard: _openClipboardSheet,
              onOpenHistory: _openHistorySheet,
              onOpenFiles: _openFileExplorer,
              onRefresh: _controller.isManualRefreshInProgress
                  ? null
                  : _controller.refresh,
              videoLinkSessionBoundary: _videoLinkSessionBoundary,
              sharedCacheCatalog: _sharedCacheCatalog,
              sharedCacheIndexStore: _sharedCacheIndexStore,
              settings: _readModel.settings,
              ownerMacAddress: _controller.localDeviceMac,
              isBoundaryReady: widget.isBoundaryReady,
              reloadVersion: _videoSurfaceReloadVersion,
              closeOnTap: false,
            ),
          ),
        );
        final mainContent = DiscoveryDeviceListSection(
          readModel: _readModel,
          devices: devices,
          errorMessage: _controller.errorMessage,
          isManualRefreshInProgress: _controller.isManualRefreshInProgress,
          transferSessionCoordinator: _transferSessionCoordinator,
          onRefresh: _controller.refresh,
          onSelectDeviceByIp: _controller.selectDeviceByIp,
          onOpenDeviceActionsMenu: _openDeviceActionsMenu,
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
                          _requestVideoSurfaceReload();
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
                        _requestVideoSurfaceReload();
                        Scaffold.of(buttonContext).openEndDrawer();
                      },
                      icon: const Icon(Icons.menu_rounded),
                    );
                  },
                ),
            ],
          ),
          drawer: !isTabletLayout && isLeftHanded ? drawerSurface : null,
          endDrawer: !isTabletLayout && !isLeftHanded ? drawerSurface : null,
          drawerEnableOpenDragGesture: !isTabletLayout && isLeftHanded,
          endDrawerEnableOpenDragGesture: !isTabletLayout && !isLeftHanded,
          body: isTabletLayout
              ? Row(
                  children: [
                    if (isLeftHanded) ...[
                      panelSurface,
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
                      panelSurface,
                    ],
                  ],
                )
              : mainContent,
          bottomNavigationBar: DiscoveryActionBar(
            sharedCacheMaintenanceBoundary: _sharedCacheMaintenanceBoundary,
            sharedFolderIndexingProgress:
                _controller.sharedFolderIndexingProgress,
            sharedFolderIndexingProgressValue:
                _controller.sharedFolderIndexingProgressValue,
            isAddingShare: _controller.isAddingShare,
            isSendingTransfer: _transferSessionCoordinator.isSendingTransfer,
            onReceive: _openReceivePanel,
            onAdd: _openAddShareMenu,
            onSend: _controller.sendFilesToSelectedDevice,
          ),
        );
      },
    );
  }

  Future<void> _openFriendsSheet() async {
    await showDiscoveryFriendsSheet(
      context: context,
      controller: _controller,
      readModel: _readModel,
    );
  }

  Future<void> _openClipboardSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.9,
          child: ClipboardSheet(
            controller: _controller,
            readModel: _readModel,
            clipboardHistoryStore: _clipboardHistoryStore,
            remoteClipboardProjectionStore: _remoteClipboardProjectionStore,
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

  Future<void> _openHistorySheet() async {
    await showDiscoveryHistorySheet(
      context: context,
      downloadHistoryBoundary: _downloadHistoryBoundary,
      onOpenPath: (path) => _controller.openHistoryPath(path),
    );
  }

  Future<void> _openDeviceActionsMenu(
    DiscoveredDevice device,
    Offset? globalPosition,
  ) async {
    await showDiscoveryDeviceActionsMenu(
      context: context,
      controller: _controller,
      device: device,
      globalPosition: globalPosition,
    );
  }

  Future<void> _openAddShareMenu() async {
    final changed = await showDiscoveryAddShareSheet(
      context: context,
      controller: _controller,
    );
    if (changed) {
      _requestVideoSurfaceReload();
    }
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
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileExplorerPage.launch(
          sharedCacheMaintenanceBoundary: _sharedCacheMaintenanceBoundary,
          sharedCacheCatalog: _sharedCacheCatalog,
          sharedCacheIndexStore: _sharedCacheIndexStore,
          previewCacheOwner: _previewCacheOwner,
          ownerMacAddress: _controller.localDeviceMac,
          receiveDirectoryPath: receiveDirectory.path,
          publicDownloadsDirectoryPath: publicDownloadsDirectory?.path,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    _requestVideoSurfaceReload();
  }

  Future<void> _openReceivePanel() async {
    unawaited(_controller.loadRemoteShareOptions());
    await showDiscoveryReceivePanel(
      context: context,
      onRefreshRemoteShares: _controller.loadRemoteShareOptions,
      remoteShareBrowser: _remoteShareBrowser,
      previewCacheOwner: _previewCacheOwner,
      transferSessionCoordinator: _transferSessionCoordinator,
    );
  }
}

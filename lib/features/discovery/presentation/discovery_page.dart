import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/utils/desktop_window_service.dart';
import '../../clipboard/application/clipboard_history_store.dart';
import '../../clipboard/application/remote_clipboard_projection_store.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../files/presentation/file_explorer_page.dart';
import '../../history/application/download_history_boundary.dart';
import '../../nearby_transfer/application/nearby_transfer_session_store.dart';
import '../../nearby_transfer/presentation/nearby_transfer_entry_sheet.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../application/discovery_controller.dart';
import '../application/configured_discovery_targets_store.dart';
import '../application/discovery_read_model.dart';
import '../application/remote_share_browser.dart';
import '../application/shared_cache_maintenance_boundary.dart';
import '../application/video_link_session_boundary.dart';
import '../domain/discovered_device.dart';
import 'discovery_action_bar.dart';
import 'discovery_add_share_sheet.dart';
import 'discovery_destination_pages.dart';
import 'discovery_device_actions.dart';
import 'discovery_device_list_section.dart';
import 'discovery_receive_panel_sheet.dart';
import 'discovery_side_menu_surface.dart';
import 'discovery_wide_layout_surface.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({
    required this.controller,
    required this.readModel,
    required this.configuredDiscoveryTargetsStore,
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
    required this.createNearbyTransferSessionStore,
    required this.isBoundaryReady,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore;
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
  final NearbyTransferSessionStore Function() createNearbyTransferSessionStore;
  final bool isBoundaryReady;

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage>
    with WidgetsBindingObserver {
  int _videoSurfaceReloadVersion = 0;

  DiscoveryController get _controller => widget.controller;
  DiscoveryReadModel get _readModel => widget.readModel;
  ConfiguredDiscoveryTargetsStore get _configuredDiscoveryTargetsStore =>
      widget.configuredDiscoveryTargetsStore;
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
  NearbyTransferSessionStore Function() get _createNearbyTransferSessionStore =>
      widget.createNearbyTransferSessionStore;

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
        final isWideLayout = MediaQuery.sizeOf(context).width >= 900;

        final panelSurface = SizedBox(
          width: 296,
          child: ColoredBox(
            color: AppColors.surface,
            child: _buildSideMenuSurface(closeOnTap: false),
          ),
        );
        final actionBar = DiscoveryActionBar(
          sharedCacheMaintenanceBoundary: _sharedCacheMaintenanceBoundary,
          sharedFolderIndexingProgress:
              _controller.sharedFolderIndexingProgress,
          sharedFolderIndexingProgressValue:
              _controller.sharedFolderIndexingProgressValue,
          isAddingShare: _controller.isAddingShare,
          isSendingTransfer: _transferSessionCoordinator.isSendingTransfer,
          onReceive: _openReceivePanel,
          onAdd: _openAddShareMenu,
          onSend: _openNearbyTransferSheet,
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
          padding: isWideLayout
              ? const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                )
              : const EdgeInsets.all(AppSpacing.md),
        );

        return Scaffold(
          appBar: isWideLayout
              ? null
              : AppBar(
                  automaticallyImplyLeading: false,
                  leading: isLeftHanded
                      ? Builder(
                          builder: (_) {
                            return IconButton(
                              tooltip: 'Menu',
                              onPressed: _openMenuPage,
                              icon: const Icon(Icons.menu_rounded),
                            );
                          },
                        )
                      : null,
                  title: const Text('Landa devices'),
                  actions: [
                    if (!isLeftHanded)
                      Builder(
                        builder: (_) {
                          return IconButton(
                            tooltip: 'Menu',
                            onPressed: _openMenuPage,
                            icon: const Icon(Icons.menu_rounded),
                          );
                        },
                      ),
                  ],
                ),
          body: isWideLayout
              ? DiscoveryWideLayoutSurface(
                  title: 'Landa devices',
                  mainContent: mainContent,
                  sidePanel: panelSurface,
                  actionBar: actionBar,
                  isLeftHanded: isLeftHanded,
                )
              : mainContent,
          bottomNavigationBar: isWideLayout ? null : actionBar,
        );
      },
    );
  }

  Widget _buildSideMenuSurface({required bool closeOnTap}) {
    return DiscoverySideMenuSurface(
      onOpenFriends: _openFriendsPage,
      onOpenSettings: _openSettingsPage,
      onOpenClipboard: _openClipboardPage,
      onOpenHistory: _openHistoryPage,
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
      closeOnTap: closeOnTap,
    );
  }

  Future<void> _openMenuPage() async {
    _requestVideoSurfaceReload();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryMenuPage(
          child: ColoredBox(
            color: AppColors.surface,
            child: _buildSideMenuSurface(closeOnTap: true),
          ),
        ),
      ),
    );
  }

  Future<void> _openFriendsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryFriendsPage(
          controller: _controller,
          readModel: _readModel,
        ),
      ),
    );
  }

  Future<void> _openClipboardPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryClipboardPage(
          controller: _controller,
          readModel: _readModel,
          clipboardHistoryStore: _clipboardHistoryStore,
          remoteClipboardProjectionStore: _remoteClipboardProjectionStore,
        ),
      ),
    );
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoverySettingsPage(
          controller: _controller,
          readModel: _readModel,
          configuredDiscoveryTargetsStore: _configuredDiscoveryTargetsStore,
          desktopWindowService: _desktopWindowService,
        ),
      ),
    );
  }

  Future<void> _openHistoryPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiscoveryHistoryPage(
          downloadHistoryBoundary: _downloadHistoryBoundary,
          onOpenPath: _controller.openHistoryPath,
        ),
      ),
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
      useStandardAppDownloadFolder:
          _readModel.settings.useStandardAppDownloadFolder,
    );
  }

  Future<void> _openNearbyTransferSheet() async {
    final sessionStore = _createNearbyTransferSessionStore();
    try {
      await showNearbyTransferEntrySheet(
        context: context,
        sessionStore: sessionStore,
      );
    } finally {
      sessionStore.dispose();
    }
  }
}

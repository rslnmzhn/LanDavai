import 'dart:async';
import 'dart:io';

import '../core/storage/app_database.dart';
import '../core/utils/app_notification_service.dart';
import '../core/utils/desktop_window_service.dart';
import '../core/utils/path_opener.dart';
import '../features/clipboard/data/clipboard_capture_service.dart';
import '../features/clipboard/data/clipboard_history_repository.dart';
import '../features/discovery/application/discovery_controller.dart';
import '../features/discovery/application/discovery_read_model.dart';
import '../features/discovery/application/device_registry.dart';
import '../features/discovery/application/internet_peer_endpoint_store.dart';
import '../features/discovery/application/remote_share_browser.dart';
import '../features/discovery/application/shared_cache_catalog_bridge.dart';
import '../features/discovery/application/trusted_lan_peer_store.dart';
import '../features/discovery/data/device_alias_repository.dart';
import '../features/discovery/data/friend_repository.dart';
import '../features/discovery/data/lan_discovery_service.dart';
import '../features/discovery/data/network_host_scanner.dart';
import '../features/discovery/presentation/discovery_page.dart';
import '../features/files/application/preview_cache_owner.dart';
import '../features/history/data/transfer_history_repository.dart';
import '../features/settings/application/settings_store.dart';
import '../features/settings/data/app_settings_repository.dart';
import '../features/transfer/application/shared_cache_catalog.dart';
import '../features/transfer/application/shared_cache_index_store.dart';
import '../features/transfer/application/transfer_session_coordinator.dart';
import '../features/transfer/data/file_hash_service.dart';
import '../features/transfer/data/file_transfer_service.dart';
import '../features/transfer/data/shared_folder_cache_repository.dart';
import '../features/transfer/data/transfer_storage_service.dart';
import '../features/transfer/data/video_link_share_service.dart';
import 'package:flutter/widgets.dart';

class DiscoveryPageEntry extends StatefulWidget {
  const DiscoveryPageEntry({
    super.key,
    this.controller,
    this.readModel,
    this.remoteShareBrowser,
    this.sharedCacheCatalogBridge,
    this.sharedCacheCatalog,
    this.sharedCacheIndexStore,
    this.previewCacheOwner,
    this.desktopWindowService,
    this.transferStorageService,
    this.autoStartController = true,
  }) : assert(
         controller == null ||
             (readModel != null &&
                 remoteShareBrowser != null &&
                 sharedCacheCatalogBridge != null &&
                 sharedCacheCatalog != null &&
                 sharedCacheIndexStore != null &&
                 previewCacheOwner != null),
         'DiscoveryPageEntry requires readModel, remoteShareBrowser, and '
         'shared-cache boundaries when controller is injected.',
       );

  final DiscoveryController? controller;
  final DiscoveryReadModel? readModel;
  final RemoteShareBrowser? remoteShareBrowser;
  final SharedCacheCatalogBridge? sharedCacheCatalogBridge;
  final SharedCacheCatalog? sharedCacheCatalog;
  final SharedCacheIndexStore? sharedCacheIndexStore;
  final PreviewCacheOwner? previewCacheOwner;
  final DesktopWindowService? desktopWindowService;
  final TransferStorageService? transferStorageService;
  final bool autoStartController;

  @override
  State<DiscoveryPageEntry> createState() => _DiscoveryPageEntryState();
}

class _DiscoveryPageEntryState extends State<DiscoveryPageEntry> {
  late final DiscoveryController _controller;
  late final DiscoveryReadModel _readModel;
  late final RemoteShareBrowser _remoteShareBrowser;
  late final SharedCacheCatalogBridge _sharedCacheCatalogBridge;
  late final SharedCacheCatalog _sharedCacheCatalog;
  late final SharedCacheIndexStore _sharedCacheIndexStore;
  late final PreviewCacheOwner _previewCacheOwner;
  late final DesktopWindowService _desktopWindowService;
  late final TransferStorageService _transferStorageService;
  late final bool _ownsController;
  late final bool _ownsReadModel;
  late final bool _ownsRemoteShareBrowser;
  late final bool _ownsPreviewCacheOwner;
  bool _isBoundaryReady = false;

  @override
  void initState() {
    super.initState();
    _transferStorageService =
        widget.transferStorageService ?? TransferStorageService();
    if (widget.controller != null) {
      _controller = widget.controller!;
      _readModel = widget.readModel!;
      _remoteShareBrowser = widget.remoteShareBrowser!;
      _sharedCacheCatalogBridge = widget.sharedCacheCatalogBridge!;
      _sharedCacheCatalog = widget.sharedCacheCatalog!;
      _sharedCacheIndexStore = widget.sharedCacheIndexStore!;
      _previewCacheOwner = widget.previewCacheOwner!;
      _ownsController = false;
      _ownsReadModel = false;
      _ownsRemoteShareBrowser = false;
      _ownsPreviewCacheOwner = false;
    } else {
      final boundary = _buildDiscoveryBoundary();
      _controller = boundary.controller;
      _readModel = boundary.readModel;
      _remoteShareBrowser = boundary.remoteShareBrowser;
      _sharedCacheCatalogBridge = boundary.sharedCacheCatalogBridge;
      _sharedCacheCatalog = boundary.sharedCacheCatalog;
      _sharedCacheIndexStore = boundary.sharedCacheIndexStore;
      _previewCacheOwner = boundary.previewCacheOwner;
      _ownsController = true;
      _ownsReadModel = true;
      _ownsRemoteShareBrowser = true;
      _ownsPreviewCacheOwner = true;
    }
    _desktopWindowService =
        widget.desktopWindowService ?? DesktopWindowService();

    if (widget.autoStartController) {
      unawaited(_initializeBoundary());
    }
  }

  @override
  void dispose() {
    if (_ownsReadModel) {
      _readModel.dispose();
    }
    if (_ownsRemoteShareBrowser) {
      _remoteShareBrowser.dispose();
    }
    if (_ownsPreviewCacheOwner) {
      _previewCacheOwner.dispose();
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DiscoveryPage(
      controller: _controller,
      readModel: _readModel,
      remoteShareBrowser: _remoteShareBrowser,
      sharedCacheCatalogBridge: _sharedCacheCatalogBridge,
      sharedCacheCatalog: _sharedCacheCatalog,
      sharedCacheIndexStore: _sharedCacheIndexStore,
      previewCacheOwner: _previewCacheOwner,
      desktopWindowService: _desktopWindowService,
      transferStorageService: _transferStorageService,
      isBoundaryReady: _isBoundaryReady,
    );
  }

  Future<void> _initializeBoundary() async {
    await _controller.start();
    await _desktopWindowService.setMinimizeToTrayEnabled(
      _readModel.settings.minimizeToTrayOnClose,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isBoundaryReady = true;
    });
  }

  _DiscoveryBoundary _buildDiscoveryBoundary() {
    final database = AppDatabase.instance;
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final friendRepository = FriendRepository(database: database);
    final settingsRepository = AppSettingsRepository(database: database);
    final settingsStore = SettingsStore(
      appSettingsRepository: settingsRepository,
    );
    final deviceRegistry = DeviceRegistry(
      deviceAliasRepository: deviceAliasRepository,
    );
    final internetPeerEndpointStore = InternetPeerEndpointStore(
      friendRepository: friendRepository,
    );
    final trustedLanPeerStore = TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    );
    final sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: database,
    );
    final sharedCacheIndexStore = SharedCacheIndexStore(database: database);
    final sharedCacheCatalog = SharedCacheCatalog(
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    final fileHashService = FileHashService();
    final previewCacheOwner = PreviewCacheOwner(
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
    );
    final lanDiscoveryService = LanDiscoveryService();
    final fileTransferService = FileTransferService();
    final transferHistoryRepository = TransferHistoryRepository(
      database: database,
    );
    final remoteShareBrowser = RemoteShareBrowser(
      sharedCacheCatalog: sharedCacheCatalog,
    );
    late final DiscoveryController controller;
    final transferSessionCoordinator = TransferSessionCoordinator(
      lanDiscoveryService: lanDiscoveryService,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: _transferStorageService,
      transferHistoryRepository: transferHistoryRepository,
      previewCacheOwner: previewCacheOwner,
      appNotificationService: AppNotificationService.instance,
      settingsProvider: () => settingsStore.settings,
      localNameProvider: () => controller.localName,
      localDeviceMacProvider: () => controller.localDeviceMac,
      isTrustedSender: (normalizedMac) =>
          trustedLanPeerStore.isTrustedMac(normalizedMac),
      resolveRemoteOwnerMac:
          ({required String ownerIp, required String cacheId}) =>
              remoteShareBrowser.ownerMacForCache(
                ownerIp: ownerIp,
                cacheId: cacheId,
              ),
    );
    controller = DiscoveryController(
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      friendRepository: friendRepository,
      settingsStore: settingsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: transferHistoryRepository,
      clipboardHistoryRepository: ClipboardHistoryRepository(
        database: database,
      ),
      clipboardCaptureService: ClipboardCaptureService(),
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: _transferStorageService,
      previewCacheOwner: previewCacheOwner,
      videoLinkShareService: VideoLinkShareService(),
      pathOpener: PathOpener(),
      lanDiscoveryService: lanDiscoveryService,
      networkHostScanner: NetworkHostScanner(
        allowTcpFallback: Platform.isAndroid,
      ),
      transferSessionCoordinator: transferSessionCoordinator,
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      settingsStore: settingsStore,
    );
    final sharedCacheCatalogBridge = SharedCacheCatalogBridge(
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      ownerMacAddressProvider: () => controller.localDeviceMac,
    );
    return _DiscoveryBoundary(
      controller: controller,
      readModel: readModel,
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheCatalogBridge: sharedCacheCatalogBridge,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      previewCacheOwner: previewCacheOwner,
    );
  }
}

class _DiscoveryBoundary {
  const _DiscoveryBoundary({
    required this.controller,
    required this.readModel,
    required this.remoteShareBrowser,
    required this.sharedCacheCatalogBridge,
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.previewCacheOwner,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final RemoteShareBrowser remoteShareBrowser;
  final SharedCacheCatalogBridge sharedCacheCatalogBridge;
  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final PreviewCacheOwner previewCacheOwner;
}

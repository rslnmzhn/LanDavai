import 'package:landa/app/discovery/discovery_composition.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/desktop_window_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/application/clipboard_history_store.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/application/discovery_read_model.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/shared_cache_maintenance_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/application/video_link_session_boundary.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/history/application/download_history_boundary.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/application/transfer_session_coordinator.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_app_database.dart';
import 'stub_discovery_network_interface_catalog.dart';

class TestDiscoveryControllerHarness {
  TestDiscoveryControllerHarness._({
    required this.databaseHarness,
    required this.controller,
    required this.readModel,
    required this.discoveryNetworkInterfaceCatalog,
    required this.discoveryNetworkScopeStore,
    required this.remoteShareBrowser,
    required this.sharedCacheMaintenanceBoundary,
    required this.videoLinkSessionBoundary,
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.transferSessionCoordinator,
    required this.downloadHistoryBoundary,
    required this.clipboardHistoryStore,
    required this.remoteClipboardProjectionStore,
    required this.previewCacheOwner,
    required this.pathOpener,
  });

  final TestAppDatabaseHarness databaseHarness;
  final TrackingDiscoveryController controller;
  final DiscoveryReadModel readModel;
  final StubDiscoveryNetworkInterfaceCatalog discoveryNetworkInterfaceCatalog;
  final DiscoveryNetworkScopeStore discoveryNetworkScopeStore;
  final TrackingRemoteShareBrowser remoteShareBrowser;
  final SharedCacheMaintenanceBoundary sharedCacheMaintenanceBoundary;
  final VideoLinkSessionBoundary videoLinkSessionBoundary;
  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final TransferSessionCoordinator transferSessionCoordinator;
  final DownloadHistoryBoundary downloadHistoryBoundary;
  final ClipboardHistoryStore clipboardHistoryStore;
  final RemoteClipboardProjectionStore remoteClipboardProjectionStore;
  final PreviewCacheOwner previewCacheOwner;
  final PathOpener pathOpener;

  DiscoveryCompositionResult createEntryComposition({
    required DesktopWindowService desktopWindowService,
    required TransferStorageService transferStorageService,
  }) {
    return DiscoveryCompositionResult.injected(
      pageDependencies: DiscoveryPageDependencies(
        controller: controller,
        readModel: readModel,
        remoteShareBrowser: remoteShareBrowser,
        sharedCacheMaintenanceBoundary: sharedCacheMaintenanceBoundary,
        videoLinkSessionBoundary: videoLinkSessionBoundary,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        previewCacheOwner: previewCacheOwner,
        transferSessionCoordinator: transferSessionCoordinator,
        downloadHistoryBoundary: downloadHistoryBoundary,
        clipboardHistoryStore: clipboardHistoryStore,
        remoteClipboardProjectionStore: remoteClipboardProjectionStore,
        desktopWindowService: desktopWindowService,
        transferStorageService: transferStorageService,
      ),
    );
  }

  static Future<TestDiscoveryControllerHarness> create({
    PathOpener? pathOpener,
  }) async {
    final databaseHarness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_ui_',
    );
    final database = databaseHarness.database;
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final friendRepository = FriendRepository(database: database);
    final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
    final discoveryNetworkInterfaceCatalog =
        StubDiscoveryNetworkInterfaceCatalog();
    final discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
      interfaceCatalog: discoveryNetworkInterfaceCatalog,
    );
    final settingsStore = SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: database),
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
    final thumbnailCacheService = ThumbnailCacheService(database: database);
    final sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: database,
    );
    final sharedCacheIndexStore = SharedCacheIndexStore(
      database: database,
      thumbnailCacheService: thumbnailCacheService,
    );
    final sharedCacheCatalog = SharedCacheCatalog(
      sharedCacheRecordStore: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    final fileHashService = FileHashService();
    final previewCacheOwner = PreviewCacheOwner(
      sharedCacheThumbnailStore: thumbnailCacheService,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
    );
    final lanDiscoveryService = LanDiscoveryService();
    final fileTransferService = FileTransferService();
    final transferHistoryRepository = TransferHistoryRepository(
      database: database,
    );
    final downloadHistoryBoundary = DownloadHistoryBoundary(
      transferHistoryRepository: transferHistoryRepository,
    );
    final transferStorageService = TransferStorageService();
    final clipboardHistoryRepository = ClipboardHistoryRepository(
      database: database,
    );
    final clipboardCaptureService = ClipboardCaptureService();
    final clipboardHistoryStore = ClipboardHistoryStore(
      clipboardHistoryRepository: clipboardHistoryRepository,
      clipboardCaptureService: clipboardCaptureService,
      transferStorageService: transferStorageService,
    );
    final remoteClipboardProjectionStore = RemoteClipboardProjectionStore(
      fileHashService: fileHashService,
    );
    final remoteShareBrowser = TrackingRemoteShareBrowser(
      sharedCacheCatalog: sharedCacheCatalog,
    );
    final remoteShareMediaProjectionBoundary =
        RemoteShareMediaProjectionBoundary(
          remoteShareBrowser: remoteShareBrowser,
          sharedCacheCatalog: sharedCacheCatalog,
          sharedCacheIndexStore: sharedCacheIndexStore,
          sharedCacheThumbnailStore: thumbnailCacheService,
          fileHashService: fileHashService,
          lanDiscoveryService: lanDiscoveryService,
        );
    final videoLinkShareService = VideoLinkShareService();
    late final TrackingDiscoveryController controller;
    final transferSessionCoordinator = TransferSessionCoordinator(
      lanDiscoveryService: lanDiscoveryService,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: transferStorageService,
      downloadHistoryBoundary: downloadHistoryBoundary,
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
    final resolvedPathOpener = pathOpener ?? PathOpener();
    controller = TrackingDiscoveryController(
      lanDiscoveryService: lanDiscoveryService,
      networkHostScanner: NetworkHostScanner(allowTcpFallback: false),
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      localPeerIdentityStore: localPeerIdentityStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: transferHistoryRepository,
      downloadHistoryBoundary: downloadHistoryBoundary,
      clipboardHistoryRepository: clipboardHistoryRepository,
      clipboardCaptureService: clipboardCaptureService,
      clipboardHistoryStore: clipboardHistoryStore,
      remoteClipboardProjectionStore: remoteClipboardProjectionStore,
      remoteShareBrowser: remoteShareBrowser,
      remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      fileHashService: fileHashService,
      fileTransferService: fileTransferService,
      transferStorageService: transferStorageService,
      previewCacheOwner: previewCacheOwner,
      pathOpener: resolvedPathOpener,
      transferSessionCoordinator: transferSessionCoordinator,
    );
    final videoLinkSessionBoundary = VideoLinkSessionBoundary(
      videoLinkShareService: videoLinkShareService,
      hostAddressProvider: () => controller.localIp,
      hostChangeListenable: controller,
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
    );
    final sharedCacheMaintenanceBoundary = SharedCacheMaintenanceBoundary(
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      appNotificationService: AppNotificationService.instance,
      ownerMacAddressProvider: () => controller.localDeviceMac,
      settingsProvider: () => settingsStore.settings,
    );

    return TestDiscoveryControllerHarness._(
      databaseHarness: databaseHarness,
      controller: controller,
      readModel: readModel,
      discoveryNetworkInterfaceCatalog: discoveryNetworkInterfaceCatalog,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheMaintenanceBoundary: sharedCacheMaintenanceBoundary,
      videoLinkSessionBoundary: videoLinkSessionBoundary,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      transferSessionCoordinator: transferSessionCoordinator,
      downloadHistoryBoundary: downloadHistoryBoundary,
      clipboardHistoryStore: clipboardHistoryStore,
      remoteClipboardProjectionStore: remoteClipboardProjectionStore,
      previewCacheOwner: previewCacheOwner,
      pathOpener: resolvedPathOpener,
    );
  }

  Future<void> dispose() async {
    readModel.dispose();
    discoveryNetworkScopeStore.dispose();
    videoLinkSessionBoundary.dispose();
    if (!controller.wasDisposed) {
      controller.dispose();
    }
    remoteShareBrowser.dispose();
    previewCacheOwner.dispose();
    await databaseHarness.dispose();
  }
}

class TrackingDiscoveryController extends DiscoveryController {
  TrackingDiscoveryController({
    required super.lanDiscoveryService,
    required super.networkHostScanner,
    required super.deviceRegistry,
    required super.internetPeerEndpointStore,
    required super.trustedLanPeerStore,
    required super.localPeerIdentityStore,
    required super.discoveryNetworkScopeStore,
    required super.settingsStore,
    required super.appNotificationService,
    required super.transferHistoryRepository,
    super.downloadHistoryBoundary,
    required super.clipboardHistoryRepository,
    required super.clipboardCaptureService,
    super.clipboardHistoryStore,
    super.remoteClipboardProjectionStore,
    required super.remoteShareBrowser,
    required super.remoteShareMediaProjectionBoundary,
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.fileHashService,
    required super.fileTransferService,
    required super.transferStorageService,
    required super.previewCacheOwner,
    required super.pathOpener,
    super.transferSessionCoordinator,
  });

  int startCalls = 0;
  int disposeCalls = 0;
  bool wasDisposed = false;
  Future<void>? lastLoadRemoteShareOptionsFuture;
  List<DiscoveredDevice>? _testDevices;
  String? _testSelectedDeviceIp;

  void setTestDevices(List<DiscoveredDevice> devices) {
    _testDevices = List<DiscoveredDevice>.unmodifiable(devices);
    if (_testSelectedDeviceIp != null &&
        devices.every((device) => device.ip != _testSelectedDeviceIp)) {
      _testSelectedDeviceIp = null;
    }
    notifyListeners();
  }

  @override
  List<DiscoveredDevice> get devices {
    final testDevices = _testDevices;
    if (testDevices == null) {
      return super.devices;
    }
    return testDevices;
  }

  @override
  DiscoveredDevice? get selectedDevice {
    final testDevices = _testDevices;
    final selectedIp = _testSelectedDeviceIp;
    if (testDevices == null || selectedIp == null) {
      return super.selectedDevice;
    }
    for (final device in testDevices) {
      if (device.ip == selectedIp) {
        return device;
      }
    }
    return null;
  }

  @override
  int get appDetectedCount {
    final testDevices = _testDevices;
    if (testDevices == null) {
      return super.appDetectedCount;
    }
    return testDevices.where((device) => device.isAppDetected).length;
  }

  @override
  Future<void> start() async {
    startCalls += 1;
    notifyListeners();
  }

  @override
  Future<void> loadRemoteShareOptions() {
    final future = super.loadRemoteShareOptions();
    lastLoadRemoteShareOptionsFuture = future;
    return future;
  }

  @override
  void selectDeviceByIp(String ip) {
    if (_testDevices == null) {
      super.selectDeviceByIp(ip);
      return;
    }
    _testSelectedDeviceIp = _testSelectedDeviceIp == ip ? null : ip;
    notifyListeners();
  }

  @override
  void dispose() {
    if (wasDisposed) {
      return;
    }
    disposeCalls += 1;
    wasDisposed = true;
    super.dispose();
  }
}

class TrackingRemoteShareBrowser extends RemoteShareBrowser {
  TrackingRemoteShareBrowser({required super.sharedCacheCatalog});

  int startBrowseCalls = 0;
  int applyRemoteCatalogCalls = 0;
  int selectOwnerCalls = 0;
  String? lastSelectedOwnerIp;

  @override
  Future<RemoteBrowseStartResult> startBrowse({
    required List<DiscoveredDevice> targets,
    required String receiverMacAddress,
    required String requesterName,
    required String requestId,
    required Future<void> Function({
      required String targetIp,
      required String requestId,
      required String requesterName,
    })
    sendShareQuery,
    Duration responseWindow = const Duration(milliseconds: 900),
  }) async {
    startBrowseCalls += 1;
    return RemoteBrowseStartResult(
      hadTargets: targets.isNotEmpty,
      optionCount: currentBrowseProjection.options.length,
    );
  }

  @override
  Future<void> applyRemoteCatalog({
    required ShareCatalogEvent event,
    required String ownerDisplayName,
    required String ownerMacAddress,
  }) async {
    applyRemoteCatalogCalls += 1;
    await super.applyRemoteCatalog(
      event: event,
      ownerDisplayName: ownerDisplayName,
      ownerMacAddress: ownerMacAddress,
    );
  }

  @override
  void selectOwner(String? ownerIp) {
    selectOwnerCalls += 1;
    lastSelectedOwnerIp = ownerIp;
    super.selectOwner(ownerIp);
  }
}

class TrackingDesktopWindowService extends DesktopWindowService {
  int setMinimizeCalls = 0;
  bool? lastEnabled;

  @override
  Future<void> setMinimizeToTrayEnabled(bool enabled) async {
    setMinimizeCalls += 1;
    lastEnabled = enabled;
  }
}

class RecordingPathOpener extends PathOpener {
  int openCalls = 0;
  String? lastPath;

  @override
  Future<void> openContainingFolder(String path) async {
    openCalls += 1;
    lastPath = path;
  }
}

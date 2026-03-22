import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/desktop_window_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/discovery_read_model.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/shared_cache_catalog_bridge.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_app_database.dart';

class TestDiscoveryControllerHarness {
  TestDiscoveryControllerHarness._({
    required this.databaseHarness,
    required this.controller,
    required this.readModel,
    required this.sharedCacheCatalogBridge,
  });

  final TestAppDatabaseHarness databaseHarness;
  final TrackingDiscoveryController controller;
  final DiscoveryReadModel readModel;
  final TrackingSharedCacheCatalogBridge sharedCacheCatalogBridge;

  static Future<TestDiscoveryControllerHarness> create() async {
    final databaseHarness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_ui_',
    );
    final database = databaseHarness.database;
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final friendRepository = FriendRepository(database: database);
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
    final sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: database,
    );
    final sharedCacheIndexStore = SharedCacheIndexStore(database: database);
    final sharedCacheCatalog = SharedCacheCatalog(
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    final controller = TrackingDiscoveryController(
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(allowTcpFallback: false),
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      friendRepository: friendRepository,
      settingsStore: settingsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: TransferHistoryRepository(database: database),
      clipboardHistoryRepository: ClipboardHistoryRepository(
        database: database,
      ),
      clipboardCaptureService: ClipboardCaptureService(),
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      fileHashService: FileHashService(),
      fileTransferService: FileTransferService(),
      transferStorageService: TransferStorageService(),
      videoLinkShareService: VideoLinkShareService(),
      pathOpener: PathOpener(),
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      settingsStore: settingsStore,
    );
    final sharedCacheCatalogBridge = TrackingSharedCacheCatalogBridge(
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      ownerMacAddressProvider: () => controller.localDeviceMac,
    );

    return TestDiscoveryControllerHarness._(
      databaseHarness: databaseHarness,
      controller: controller,
      readModel: readModel,
      sharedCacheCatalogBridge: sharedCacheCatalogBridge,
    );
  }

  Future<void> dispose() async {
    readModel.dispose();
    if (!controller.wasDisposed) {
      controller.dispose();
    }
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
    required super.friendRepository,
    required super.settingsStore,
    required super.appNotificationService,
    required super.transferHistoryRepository,
    required super.clipboardHistoryRepository,
    required super.clipboardCaptureService,
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.sharedFolderCacheRepository,
    required super.fileHashService,
    required super.fileTransferService,
    required super.transferStorageService,
    required super.videoLinkShareService,
    required super.pathOpener,
  });

  int startCalls = 0;
  int disposeCalls = 0;
  bool wasDisposed = false;

  @override
  Future<void> start() async {
    startCalls += 1;
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

class TrackingSharedCacheCatalogBridge extends SharedCacheCatalogBridge {
  TrackingSharedCacheCatalogBridge({
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.ownerMacAddressProvider,
  });

  int shareableVideoListCalls = 0;
  int summarizeOwnerSharedContentCalls = 0;
  final List<String> listShareableLocalDirectoryFolders = <String>[];

  @override
  Future<List<ShareableVideoFile>> listShareableVideoFiles({
    String? cacheId,
  }) async {
    shareableVideoListCalls += 1;
    return const <ShareableVideoFile>[];
  }

  @override
  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    summarizeOwnerSharedContentCalls += 1;
    return const SharedCacheSummary(
      totalCaches: 1,
      folderCaches: 1,
      selectionCaches: 0,
      totalFiles: 1,
    );
  }

  @override
  Future<ShareableLocalDirectoryListing> listShareableLocalDirectory({
    required String virtualFolderPath,
  }) async {
    listShareableLocalDirectoryFolders.add(virtualFolderPath);
    return const ShareableLocalDirectoryListing(
      folders: <ShareableLocalFolder>[],
      files: <ShareableLocalFile>[],
    );
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

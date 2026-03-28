import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
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
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late RecordingSharedCacheCatalog sharedCacheCatalog;
  late ThrowingMetadataSharedFolderCacheRepository controllerRepository;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_shared_cache_catalog_',
    );
    sharedCacheCatalog = RecordingSharedCacheCatalog(
      sharedFolderCacheRepository: SharedFolderCacheRepository(
        database: harness.database,
      ),
      sharedCacheIndexStore: SharedCacheIndexStore(database: harness.database),
      ownerCaches: <SharedFolderCacheRecord>[
        _ownerCacheRecord(cacheId: 'cache-1', displayName: 'Shared docs'),
      ],
    );
    controllerRepository = ThrowingMetadataSharedFolderCacheRepository(
      database: harness.database,
    );
  });

  tearDown(() async {
    controller?.dispose();
    sharedCacheCatalog.dispose();
    await harness.dispose();
  });

  test(
    'removeSharedCacheById resolves owner cache lookup through SharedCacheCatalog',
    () async {
      controller = _buildController(
        database: harness.database,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: SharedCacheIndexStore(
          database: harness.database,
        ),
        sharedFolderCacheRepository: controllerRepository,
      );

      final removed = await controller!.removeSharedCacheById('cache-1');

      expect(removed, isTrue);
      expect(sharedCacheCatalog.loadOwnerCachesCalls, 2);
      expect(
        sharedCacheCatalog.lastOwnerMacAddress,
        controller!.localDeviceMac,
      );
      expect(sharedCacheCatalog.deletedCacheIds, <String>['cache-1']);
      expect(controller!.errorMessage, isNull);
    },
  );

  test(
    'removeSharedCacheById routes metadata deletion through SharedCacheCatalog',
    () async {
      controller = _buildController(
        database: harness.database,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: SharedCacheIndexStore(
          database: harness.database,
        ),
        sharedFolderCacheRepository: controllerRepository,
      );

      final removed = await controller!.removeSharedCacheById('cache-1');

      expect(removed, isTrue);
      expect(sharedCacheCatalog.deletedCacheIds, <String>['cache-1']);
      expect(sharedCacheCatalog.loadOwnerCachesCalls, 2);
      expect(controller!.errorMessage, isNull);
    },
  );

  test(
    'removeSharedCacheById reports unavailable cache when catalog has no match',
    () async {
      controller = _buildController(
        database: harness.database,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: SharedCacheIndexStore(
          database: harness.database,
        ),
        sharedFolderCacheRepository: controllerRepository,
      );

      final removed = await controller!.removeSharedCacheById('missing-cache');

      expect(removed, isFalse);
      expect(sharedCacheCatalog.loadOwnerCachesCalls, 1);
      expect(sharedCacheCatalog.deletedCacheIds, isEmpty);
      expect(controller!.errorMessage, 'Shared folder is no longer available.');
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required SharedCacheCatalog sharedCacheCatalog,
  required SharedCacheIndexStore sharedCacheIndexStore,
  required SharedFolderCacheRepository sharedFolderCacheRepository,
}) {
  final deviceAliasRepository = DeviceAliasRepository(database: database);
  final deviceRegistry = DeviceRegistry(
    deviceAliasRepository: deviceAliasRepository,
  );
  final endpointRepository = FriendRepository(database: database);
  final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
  final remoteShareBrowser = RemoteShareBrowser(
    sharedCacheCatalog: sharedCacheCatalog,
  );
  final fileHashService = FileHashService();
  final previewCacheOwner = PreviewCacheOwner(
    sharedFolderCacheRepository: sharedFolderCacheRepository,
    sharedCacheIndexStore: sharedCacheIndexStore,
    fileHashService: fileHashService,
  );
  return DiscoveryController(
    lanDiscoveryService: LanDiscoveryService(),
    networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: InternetPeerEndpointStore(
      friendRepository: endpointRepository,
    ),
    trustedLanPeerStore: TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    ),
    localPeerIdentityStore: localPeerIdentityStore,
    settingsStore: SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: database),
    ),
    appNotificationService: AppNotificationService.instance,
    transferHistoryRepository: TransferHistoryRepository(database: database),
    clipboardHistoryRepository: ClipboardHistoryRepository(database: database),
    clipboardCaptureService: ClipboardCaptureService(),
    remoteShareBrowser: remoteShareBrowser,
    sharedCacheCatalog: sharedCacheCatalog,
    sharedCacheIndexStore: sharedCacheIndexStore,
    sharedFolderCacheRepository: sharedFolderCacheRepository,
    fileHashService: fileHashService,
    fileTransferService: FileTransferService(),
    transferStorageService: TransferStorageService(),
    previewCacheOwner: previewCacheOwner,
    videoLinkShareService: VideoLinkShareService(),
    pathOpener: PathOpener(),
  );
}

class RecordingSharedCacheCatalog extends SharedCacheCatalog {
  RecordingSharedCacheCatalog({
    required super.sharedFolderCacheRepository,
    required super.sharedCacheIndexStore,
    required List<SharedFolderCacheRecord> ownerCaches,
  }) : _ownerCachesSnapshot = List<SharedFolderCacheRecord>.from(ownerCaches);

  int loadOwnerCachesCalls = 0;
  String? lastOwnerMacAddress;
  bool? lastRebindOwnerCachesToMac;
  final List<String> deletedCacheIds = <String>[];
  List<SharedFolderCacheRecord> _ownerCachesSnapshot;

  @override
  List<SharedFolderCacheRecord> get ownerCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerCachesSnapshot);

  @override
  Future<OwnerCacheCatalogLoadResult> loadOwnerCaches({
    required String ownerMacAddress,
    bool rebindOwnerCachesToMac = false,
  }) async {
    loadOwnerCachesCalls += 1;
    lastOwnerMacAddress = ownerMacAddress;
    lastRebindOwnerCachesToMac = rebindOwnerCachesToMac;
    return OwnerCacheCatalogLoadResult(
      ownerCaches: ownerCaches,
      reboundCount: rebindOwnerCachesToMac ? 1 : 0,
    );
  }

  @override
  Future<void> deleteCache(String cacheId) async {
    deletedCacheIds.add(cacheId);
    _ownerCachesSnapshot = _ownerCachesSnapshot
        .where((cache) => cache.cacheId != cacheId)
        .toList(growable: false);
  }
}

class ThrowingMetadataSharedFolderCacheRepository
    extends SharedFolderCacheRepository {
  ThrowingMetadataSharedFolderCacheRepository({required super.database});

  @override
  Future<OwnerFolderCacheUpsertResult> upsertOwnerFolderCache({
    required String ownerMacAddress,
    required String folderPath,
    String? displayName,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) {
    throw StateError(
      'DiscoveryController must not write owner cache metadata directly',
    );
  }

  @override
  Future<SharedFolderCacheRecord> buildOwnerSelectionCache({
    required String ownerMacAddress,
    required List<String> filePaths,
    String? displayName,
  }) {
    throw StateError(
      'DiscoveryController must not create cache metadata directly',
    );
  }

  @override
  Future<SharedFolderCacheRecord> saveReceiverCache({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required String remoteFolderIdentity,
    required String remoteDisplayName,
    required List<SharedFolderIndexEntry> entries,
  }) {
    throw StateError(
      'DiscoveryController must not save receiver cache metadata directly',
    );
  }

  @override
  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) {
    throw StateError(
      'DiscoveryController must not read cache metadata directly',
    );
  }

  @override
  Future<void> deleteCache(String cacheId) {
    throw StateError(
      'DiscoveryController must not delete cache metadata directly',
    );
  }

  @override
  Future<List<String>> pruneUnavailableOwnerCaches({
    required String ownerMacAddress,
  }) {
    throw StateError(
      'DiscoveryController must not prune owner cache metadata directly',
    );
  }

  @override
  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress}) {
    throw StateError(
      'DiscoveryController must not rebind owner cache metadata directly',
    );
  }

  @override
  Future<SharedFolderCacheRecord> refreshOwnerSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) {
    throw StateError(
      'DiscoveryController must not refresh selection cache metadata directly',
    );
  }

  @override
  Future<SharedFolderCacheRecord> refreshOwnerFolderSubdirectoryEntries(
    SharedFolderCacheRecord cache, {
    required String relativeFolderPath,
    int? parallelWorkers,
    OwnerCacheProgressCallback? onProgress,
  }) {
    throw StateError(
      'DiscoveryController must not refresh folder cache metadata directly',
    );
  }

  @override
  Future<List<String>> pruneReceiverCachesForOwner({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required Set<String> activeCacheIds,
  }) {
    throw StateError(
      'DiscoveryController must not prune receiver cache metadata directly',
    );
  }
}

class StubNetworkHostScanner extends NetworkHostScanner {
  StubNetworkHostScanner(this.result) : super(allowTcpFallback: false);

  final Map<String, String?> result;

  @override
  Future<Map<String, String?>> scanActiveHosts({
    String? preferredSourceIp,
  }) async {
    return result;
  }
}

SharedFolderCacheRecord _ownerCacheRecord({
  required String cacheId,
  required String displayName,
}) {
  return SharedFolderCacheRecord(
    cacheId: cacheId,
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: '02:00:00:00:00:01',
    peerMacAddress: null,
    rootPath: 'selection://$cacheId',
    displayName: displayName,
    indexFilePath: 'C:/tmp/$cacheId.landa-cache.json',
    itemCount: 2,
    totalBytes: 123,
    updatedAtMs: 1000,
  );
}

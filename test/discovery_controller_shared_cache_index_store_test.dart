import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
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
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late RecordingSharedCacheCatalog sharedCacheCatalog;
  late RecordingSharedCacheIndexStore sharedCacheIndexStore;
  late ThrowingIndexSharedFolderCacheRepository controllerRepository;
  late File indexedFile;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_shared_cache_index_store_',
    );
    indexedFile = File(p.join(harness.rootDirectory.path, 'alpha.txt'));
    await indexedFile.writeAsString('alpha', flush: true);

    sharedCacheCatalog = RecordingSharedCacheCatalog(
      sharedFolderCacheRepository: SharedFolderCacheRepository(
        database: harness.database,
      ),
      sharedCacheIndexStore: SharedCacheIndexStore(database: harness.database),
      ownerCaches: <SharedFolderCacheRecord>[
        _ownerSelectionCacheRecord(
          cacheId: 'cache-1',
          displayName: 'Selected files',
          absolutePath: indexedFile.path,
        ),
      ],
    );
    sharedCacheIndexStore = RecordingSharedCacheIndexStore(
      database: harness.database,
      entriesByCacheId: <String, List<SharedFolderIndexEntry>>{
        'cache-1': <SharedFolderIndexEntry>[
          SharedFolderIndexEntry(
            relativePath: 'alpha.txt',
            sizeBytes: 5,
            modifiedAtMs: 1000,
            absolutePath: indexedFile.path,
          ),
        ],
      },
    );
    controllerRepository = ThrowingIndexSharedFolderCacheRepository(
      database: harness.database,
    );
  });

  tearDown(() async {
    controller?.dispose();
    sharedCacheCatalog.dispose();
    await harness.dispose();
  });

  test(
    'listShareableLocalFiles compatibility surface reads index entries through SharedCacheIndexStore',
    () async {
      controller = _buildController(
        database: harness.database,
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        sharedFolderCacheRepository: controllerRepository,
      );

      final files = await controller!.listShareableLocalFiles();

      expect(sharedCacheCatalog.loadOwnerCachesCalls, 1);
      expect(sharedCacheIndexStore.readCacheIds, <String>['cache-1']);
      expect(files, hasLength(1));
      expect(files.single.cacheId, 'cache-1');
      expect(files.single.relativePath, 'alpha.txt');
      expect(controller!.errorMessage, isNull);
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
    friendRepository: FriendRepository(database: database),
    settingsStore: SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: database),
    ),
    appNotificationService: AppNotificationService.instance,
    transferHistoryRepository: TransferHistoryRepository(database: database),
    clipboardHistoryRepository: ClipboardHistoryRepository(database: database),
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
}

class RecordingSharedCacheCatalog extends SharedCacheCatalog {
  RecordingSharedCacheCatalog({
    required super.sharedFolderCacheRepository,
    required super.sharedCacheIndexStore,
    required List<SharedFolderCacheRecord> ownerCaches,
  }) : _ownerCachesSnapshot = List<SharedFolderCacheRecord>.from(ownerCaches);

  int loadOwnerCachesCalls = 0;
  final List<SharedFolderCacheRecord> _ownerCachesSnapshot;

  @override
  List<SharedFolderCacheRecord> get ownerCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerCachesSnapshot);

  @override
  Future<OwnerCacheCatalogLoadResult> loadOwnerCaches({
    required String ownerMacAddress,
    bool rebindOwnerCachesToMac = false,
  }) async {
    loadOwnerCachesCalls += 1;
    return OwnerCacheCatalogLoadResult(
      ownerCaches: ownerCaches,
      reboundCount: rebindOwnerCachesToMac ? 1 : 0,
    );
  }
}

class RecordingSharedCacheIndexStore extends SharedCacheIndexStore {
  RecordingSharedCacheIndexStore({
    required super.database,
    required Map<String, List<SharedFolderIndexEntry>> entriesByCacheId,
  }) : _entriesByCacheId = entriesByCacheId;

  final Map<String, List<SharedFolderIndexEntry>> _entriesByCacheId;
  final List<String> readCacheIds = <String>[];

  @override
  Future<List<SharedFolderIndexEntry>> readIndexEntries(
    SharedFolderCacheRecord record,
  ) async {
    readCacheIds.add(record.cacheId);
    return List<SharedFolderIndexEntry>.from(
      _entriesByCacheId[record.cacheId] ?? const <SharedFolderIndexEntry>[],
    );
  }
}

class ThrowingIndexSharedFolderCacheRepository
    extends SharedFolderCacheRepository {
  ThrowingIndexSharedFolderCacheRepository({required super.database});

  @override
  Future<List<SharedFolderIndexEntry>> readIndexEntries(String cacheId) {
    throw StateError(
      'DiscoveryController must not read canonical index entries directly from the repository',
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

SharedFolderCacheRecord _ownerSelectionCacheRecord({
  required String cacheId,
  required String displayName,
  required String absolutePath,
}) {
  return SharedFolderCacheRecord(
    cacheId: cacheId,
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: '02:00:00:00:00:01',
    peerMacAddress: null,
    rootPath: 'selection://$cacheId',
    displayName: displayName,
    indexFilePath: absolutePath,
    itemCount: 1,
    totalBytes: 5,
    updatedAtMs: 1000,
  );
}

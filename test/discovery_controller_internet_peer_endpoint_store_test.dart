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
import 'package:landa/features/discovery/domain/friend_peer.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late FriendRepository storeRepository;
  late ThrowingEndpointFriendRepository controllerRepository;
  late InternetPeerEndpointStore endpointStore;
  late RecordingLanDiscoveryService lanDiscoveryService;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_endpoint_store_',
    );
    storeRepository = FriendRepository(database: harness.database);
    controllerRepository = ThrowingEndpointFriendRepository(
      database: harness.database,
    );
    endpointStore = InternetPeerEndpointStore(
      friendRepository: storeRepository,
    );
    lanDiscoveryService = RecordingLanDiscoveryService();
  });

  tearDown(() async {
    controller?.dispose();
    endpointStore.dispose();
    await harness.dispose();
  });

  test(
    'saveFriend routes endpoint writes and legacy projection refresh through InternetPeerEndpointStore',
    () async {
      controller = _buildController(
        database: harness.database,
        lanDiscoveryService: lanDiscoveryService,
        endpointStore: endpointStore,
        friendRepository: controllerRepository,
      );

      await controller!.saveFriend(
        friendId: 'peer-1',
        displayName: 'Remote peer',
        endpoint: '203.0.113.7:40404',
      );

      expect(controller!.friends, hasLength(1));
      expect(controller!.friends.single.friendId, 'peer-1');
      expect(controller!.friends.single.endpointHost, '203.0.113.7');
      expect(lanDiscoveryService.lastInternetPeers, hasLength(1));
      expect(lanDiscoveryService.lastInternetPeers.single.friendId, 'peer-1');
      expect(controller!.errorMessage, isNull);
    },
  );

  test(
    'setFriendEnabled and removeFriend no longer use FriendRepository as endpoint owner API',
    () async {
      await endpointStore.saveEndpoint(
        friendId: 'peer-1',
        displayName: 'Remote peer',
        endpointHost: '203.0.113.7',
        endpointPort: 40404,
        isEnabled: true,
      );
      controller = _buildController(
        database: harness.database,
        lanDiscoveryService: lanDiscoveryService,
        endpointStore: endpointStore,
        friendRepository: controllerRepository,
      );

      await controller!.setFriendEnabled(friendId: 'peer-1', enabled: false);

      expect(controller!.friends, hasLength(1));
      expect(controller!.friends.single.isEnabled, isFalse);
      expect(lanDiscoveryService.lastInternetPeers, isEmpty);

      await controller!.removeFriend('peer-1');

      expect(controller!.friends, isEmpty);
      expect(lanDiscoveryService.lastInternetPeers, isEmpty);
      expect(controller!.errorMessage, isNull);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required RecordingLanDiscoveryService lanDiscoveryService,
  required InternetPeerEndpointStore endpointStore,
  required FriendRepository friendRepository,
}) {
  final deviceAliasRepository = DeviceAliasRepository(database: database);
  final deviceRegistry = DeviceRegistry(
    deviceAliasRepository: deviceAliasRepository,
  );
  final settingsStore = SettingsStore(
    appSettingsRepository: AppSettingsRepository(database: database),
  );
  return DiscoveryController(
    lanDiscoveryService: lanDiscoveryService,
    networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: endpointStore,
    trustedLanPeerStore: TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    ),
    friendRepository: friendRepository,
    settingsStore: settingsStore,
    appNotificationService: AppNotificationService.instance,
    transferHistoryRepository: TransferHistoryRepository(database: database),
    clipboardHistoryRepository: ClipboardHistoryRepository(database: database),
    clipboardCaptureService: ClipboardCaptureService(),
    sharedFolderCacheRepository: SharedFolderCacheRepository(
      database: database,
    ),
    fileHashService: FileHashService(),
    fileTransferService: FileTransferService(),
    transferStorageService: TransferStorageService(),
    videoLinkShareService: VideoLinkShareService(),
    pathOpener: PathOpener(),
  );
}

class ThrowingEndpointFriendRepository extends FriendRepository {
  ThrowingEndpointFriendRepository({required super.database});

  @override
  Future<List<FriendPeer>> listFriends() {
    throw StateError(
      'DiscoveryController must not read endpoint rows directly',
    );
  }

  @override
  Future<void> upsertFriend({
    required String friendId,
    required String displayName,
    required String endpointHost,
    required int endpointPort,
    required bool isEnabled,
  }) {
    throw StateError(
      'DiscoveryController must not write endpoint rows directly',
    );
  }

  @override
  Future<void> removeFriend(String friendId) {
    throw StateError(
      'DiscoveryController must not remove endpoint rows directly',
    );
  }

  @override
  Future<void> setFriendEnabled({
    required String friendId,
    required bool isEnabled,
  }) {
    throw StateError(
      'DiscoveryController must not toggle endpoint rows directly',
    );
  }
}

class RecordingLanDiscoveryService extends LanDiscoveryService {
  List<InternetPeerEndpoint> lastInternetPeers = const <InternetPeerEndpoint>[];

  @override
  void updateInternetPeers(List<InternetPeerEndpoint> peers) {
    lastInternetPeers = List<InternetPeerEndpoint>.from(peers);
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

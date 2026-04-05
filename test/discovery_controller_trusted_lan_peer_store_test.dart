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
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_app_database.dart';
import 'test_support/stub_discovery_network_interface_catalog.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late DeviceAliasRepository repository;
  late DeviceRegistry deviceRegistry;
  late TrackingTrustedLanPeerStore trustedLanPeerStore;
  late RecordingLanDiscoveryService lanDiscoveryService;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_trust_store_',
    );
    repository = DeviceAliasRepository(database: harness.database);
    deviceRegistry = DeviceRegistry(deviceAliasRepository: repository);
    trustedLanPeerStore = TrackingTrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: repository,
    );
    lanDiscoveryService = RecordingLanDiscoveryService();
  });

  tearDown(() async {
    controller?.dispose();
    trustedLanPeerStore.dispose();
    deviceRegistry.dispose();
    await harness.dispose();
  });

  test(
    'requestRemoteClipboardHistory reads trust from TrustedLanPeerStore instead of controller mirror',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.80';
      await deviceRegistry.recordSeenDevices(<String, String>{mac: ip});
      await trustedLanPeerStore.trustDevice(macAddress: mac);
      controller = _buildController(
        database: harness.database,
        lanDiscoveryService: lanDiscoveryService,
        deviceRegistry: deviceRegistry,
        trustedLanPeerStore: trustedLanPeerStore,
      );

      await controller!.requestRemoteClipboardHistory(
        DiscoveredDevice(
          ip: ip,
          macAddress: mac,
          isAppDetected: true,
          lastSeen: DateTime(2026),
        ),
      );

      expect(lanDiscoveryService.clipboardQueryCalls, 1);
      expect(controller!.errorMessage, isNull);
      expect(trustedLanPeerStore.isTrustedMac(mac), isTrue);
    },
  );

  test(
    'removeDeviceFromFriends revokes trust through TrustedLanPeerStore and does not touch friends table',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      await trustedLanPeerStore.trustDevice(macAddress: mac);
      controller = _buildController(
        database: harness.database,
        lanDiscoveryService: lanDiscoveryService,
        deviceRegistry: deviceRegistry,
        trustedLanPeerStore: trustedLanPeerStore,
      );

      await controller!.removeDeviceFromFriends(
        DiscoveredDevice(
          ip: '192.168.1.90',
          macAddress: mac,
          isTrusted: true,
          lastSeen: DateTime(2026),
        ),
      );

      final friends = await FriendRepository(
        database: harness.database,
      ).listFriends();

      expect(trustedLanPeerStore.revokeTrustCalls, 1);
      expect(trustedLanPeerStore.isTrustedMac(mac), isFalse);
      expect(friends, isEmpty);
      expect(controller!.errorMessage, isNull);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required LanDiscoveryService lanDiscoveryService,
  required DeviceRegistry deviceRegistry,
  required TrackingTrustedLanPeerStore trustedLanPeerStore,
}) {
  final endpointRepository = FriendRepository(database: database);
  final settingsStore = SettingsStore(
    appSettingsRepository: AppSettingsRepository(database: database),
  );
  final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
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
  final discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore();
  final remoteShareBrowser = RemoteShareBrowser(
    sharedCacheCatalog: sharedCacheCatalog,
  );
  final remoteShareMediaProjectionBoundary = RemoteShareMediaProjectionBoundary(
    remoteShareBrowser: remoteShareBrowser,
    sharedCacheCatalog: sharedCacheCatalog,
    sharedCacheIndexStore: sharedCacheIndexStore,
    sharedCacheThumbnailStore: thumbnailCacheService,
    fileHashService: fileHashService,
    lanDiscoveryService: lanDiscoveryService,
  );
  return DiscoveryController(
    lanDiscoveryService: lanDiscoveryService,
    networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: InternetPeerEndpointStore(
      friendRepository: endpointRepository,
    ),
    trustedLanPeerStore: trustedLanPeerStore,
    localPeerIdentityStore: localPeerIdentityStore,
    discoveryNetworkScopeStore: discoveryNetworkScopeStore,
    settingsStore: settingsStore,
    appNotificationService: AppNotificationService.instance,
    transferHistoryRepository: TransferHistoryRepository(database: database),
    clipboardHistoryRepository: ClipboardHistoryRepository(database: database),
    clipboardCaptureService: ClipboardCaptureService(),
    remoteShareBrowser: remoteShareBrowser,
    remoteShareMediaProjectionBoundary: remoteShareMediaProjectionBoundary,
    sharedCacheCatalog: sharedCacheCatalog,
    sharedCacheIndexStore: sharedCacheIndexStore,
    fileHashService: fileHashService,
    fileTransferService: FileTransferService(),
    transferStorageService: TransferStorageService(),
    previewCacheOwner: previewCacheOwner,
    pathOpener: PathOpener(),
  );
}

class TrackingTrustedLanPeerStore extends TrustedLanPeerStore {
  TrackingTrustedLanPeerStore({
    required super.deviceRegistry,
    required super.deviceAliasRepository,
  });

  int trustDeviceCalls = 0;
  int revokeTrustCalls = 0;

  @override
  Future<void> trustDevice({required String macAddress}) async {
    trustDeviceCalls += 1;
    await super.trustDevice(macAddress: macAddress);
  }

  @override
  Future<void> revokeTrust({required String macAddress}) async {
    revokeTrustCalls += 1;
    await super.revokeTrust(macAddress: macAddress);
  }
}

class RecordingLanDiscoveryService extends LanDiscoveryService {
  int clipboardQueryCalls = 0;

  @override
  Future<void> sendClipboardQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  }) async {
    clipboardQueryCalls += 1;
  }
}

class StubNetworkHostScanner extends NetworkHostScanner {
  StubNetworkHostScanner(this.result) : super(allowTcpFallback: false);

  final Map<String, String?> result;

  @override
  Future<Map<String, String?>> scanActiveHosts({
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
  }) async {
    return result;
  }
}

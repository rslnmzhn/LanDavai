import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
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
  late DeviceAliasRepository registryRepository;
  TrackingDeviceRegistry? registry;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_registry_',
    );
    registryRepository = DeviceAliasRepository(database: harness.database);
  });

  tearDown(() async {
    controller?.dispose();
    registry?.dispose();
    await harness.dispose();
  });

  test(
    'renameDeviceAlias resolves stable identity through DeviceRegistry and not controller repository writes',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.55';
      registry = TrackingDeviceRegistry(database: harness.database);
      await registry!.recordSeenDevices(<String, String>{mac: ip});
      controller = _buildController(
        database: harness.database,
        deviceRegistry: registry!,
        networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
      );

      await controller!.renameDeviceAlias(
        device: DiscoveredDevice(ip: ip, lastSeen: DateTime(2026)),
        alias: 'Office laptop',
      );

      final aliasMap = await registryRepository.loadAliasMap();

      expect(registry!.setAliasCalls, 1);
      expect(aliasMap['aa:bb:cc:dd:ee:ff'], 'Office laptop');
      expect(controller!.errorMessage, isNull);
    },
  );

  test(
    'refresh records seen devices through DeviceRegistry and compatibility reads stay registry-backed',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.77';
      await registryRepository.setAlias(
        macAddress: mac,
        alias: 'Office laptop',
      );
      registry = TrackingDeviceRegistry(database: harness.database);
      await registry!.load();
      controller = _buildController(
        database: harness.database,
        deviceRegistry: registry!,
        networkHostScanner: StubNetworkHostScanner(<String, String?>{ip: mac}),
      );

      await controller!.refresh();
      controller!.selectDeviceByIp(ip);

      await registry!.setAlias(macAddress: mac, alias: 'Renamed laptop');

      final device = controller!.devices.single;
      final lastKnownIpMap = await registryRepository.loadLastKnownIpMap();

      expect(registry!.recordSeenDevicesCalls, 1);
      expect(device.ip, ip);
      expect(device.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(device.aliasName, 'Renamed laptop');
      expect(controller!.selectedDevice?.displayName, 'Renamed laptop');
      expect(lastKnownIpMap['aa:bb:cc:dd:ee:ff'], ip);
      expect(controller!.errorMessage, isNull);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required DeviceRegistry deviceRegistry,
  required NetworkHostScanner networkHostScanner,
}) {
  final trustRepository = DeviceAliasRepository(database: database);
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
  final lanDiscoveryService = LanDiscoveryService();
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
    networkHostScanner: networkHostScanner,
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: InternetPeerEndpointStore(
      friendRepository: endpointRepository,
    ),
    trustedLanPeerStore: TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: trustRepository,
    ),
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

class TrackingDeviceRegistry extends DeviceRegistry {
  TrackingDeviceRegistry({required this.database})
    : super(deviceAliasRepository: DeviceAliasRepository(database: database));

  final AppDatabase database;
  int recordSeenDevicesCalls = 0;
  int setAliasCalls = 0;

  @override
  Future<void> recordSeenDevices(Map<String, String> macToIp) async {
    recordSeenDevicesCalls += 1;
    await super.recordSeenDevices(macToIp);
  }

  @override
  Future<void> setAlias({
    required String macAddress,
    required String alias,
  }) async {
    setAliasCalls += 1;
    await super.setAlias(macAddress: macAddress, alias: alias);
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

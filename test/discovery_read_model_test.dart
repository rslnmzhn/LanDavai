import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/configured_discovery_targets_store.dart';
import 'package:landa/features/discovery/application/discovery_read_model.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/configured_discovery_targets_repository.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
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
  late DeviceAliasRepository deviceAliasRepository;
  late DeviceRegistry deviceRegistry;
  late InternetPeerEndpointStore internetPeerEndpointStore;
  late TrustedLanPeerStore trustedLanPeerStore;
  late SettingsStore settingsStore;
  late StubDiscoveryNetworkInterfaceCatalog discoveryNetworkInterfaceCatalog;
  late DiscoveryNetworkScopeStore discoveryNetworkScopeStore;
  late ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore;
  late DiscoveryController controller;
  late DiscoveryReadModel readModel;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_read_model_',
    );
    deviceAliasRepository = DeviceAliasRepository(database: harness.database);
    deviceRegistry = DeviceRegistry(
      deviceAliasRepository: deviceAliasRepository,
    );
    internetPeerEndpointStore = InternetPeerEndpointStore(
      friendRepository: FriendRepository(database: harness.database),
    );
    trustedLanPeerStore = TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    );
    settingsStore = SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: harness.database),
    );
    discoveryNetworkInterfaceCatalog = StubDiscoveryNetworkInterfaceCatalog();
    discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
      interfaceCatalog: discoveryNetworkInterfaceCatalog,
    );
    configuredDiscoveryTargetsStore = ConfiguredDiscoveryTargetsStore(
      repository: ConfiguredDiscoveryTargetsRepository(
        database: harness.database,
      ),
    );
    controller = _buildController(
      database: harness.database,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      settingsStore: settingsStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
    );
    readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
    );
  });

  tearDown(() async {
    readModel.dispose();
    controller.dispose();
    internetPeerEndpointStore.dispose();
    trustedLanPeerStore.dispose();
    deviceRegistry.dispose();
    configuredDiscoveryTargetsStore.dispose();
    settingsStore.dispose();
    await harness.dispose();
  });

  test(
    'keeps controller compatibility projections owner-backed while read model remains canonical',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.77';

      await controller.refresh();
      controller.selectDeviceByIp(ip);

      expect(controller.devices, hasLength(1));
      expect(controller.devices.single.aliasName, isNull);
      expect(controller.devices.single.isTrusted, isFalse);
      expect(controller.friends, isEmpty);
      expect(
        controller.settings.backgroundScanInterval,
        AppSettings.defaults.backgroundScanInterval,
      );

      await deviceRegistry.setAlias(macAddress: mac, alias: 'Office laptop');
      await trustedLanPeerStore.trustDevice(macAddress: mac);
      await internetPeerEndpointStore.saveEndpoint(
        friendId: 'peer-1',
        displayName: 'Remote peer',
        endpointHost: '203.0.113.7',
        endpointPort: 40404,
        isEnabled: true,
      );
      await settingsStore.save(
        AppSettings.defaults.copyWith(
          backgroundScanInterval: BackgroundScanIntervalOption.fifteenMinutes,
          isLeftHandedMode: true,
        ),
      );

      expect(readModel.devices, hasLength(1));
      expect(readModel.devices.single.aliasName, 'Office laptop');
      expect(readModel.devices.single.isTrusted, isTrue);
      expect(readModel.selectedDevice?.displayName, 'Office laptop');
      expect(readModel.friendDevices, hasLength(1));
      expect(readModel.appDetectedCount, 0);
      expect(readModel.internetPeers, hasLength(1));
      expect(
        readModel.settings.backgroundScanInterval,
        BackgroundScanIntervalOption.fifteenMinutes,
      );
      expect(readModel.settings.isLeftHandedMode, isTrue);

      expect(controller.devices.single.aliasName, 'Office laptop');
      expect(controller.devices.single.isTrusted, isTrue);
      expect(controller.selectedDevice?.displayName, 'Office laptop');
      expect(controller.friends, hasLength(1));
      expect(
        controller.settings.backgroundScanInterval,
        BackgroundScanIntervalOption.fifteenMinutes,
      );
      expect(controller.settings.isLeftHandedMode, isTrue);
    },
  );

  test(
    'filters devices by the selected network scope as projection only',
    () async {
      discoveryNetworkInterfaceCatalog.replaceInterfaces(
        const <DiscoveryRawNetworkInterface>[
          DiscoveryRawNetworkInterface(
            name: 'Ethernet',
            index: 1,
            ipv4Addresses: <String>['192.168.1.10'],
          ),
          DiscoveryRawNetworkInterface(
            name: 'Tailscale',
            index: 2,
            ipv4Addresses: <String>['100.90.1.10'],
          ),
        ],
      );
      controller.dispose();
      readModel.dispose();
      discoveryNetworkScopeStore.dispose();

      discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
        interfaceCatalog: discoveryNetworkInterfaceCatalog,
      );
      controller = _buildController(
        database: harness.database,
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: internetPeerEndpointStore,
        trustedLanPeerStore: trustedLanPeerStore,
        settingsStore: settingsStore,
        discoveryNetworkScopeStore: discoveryNetworkScopeStore,
        configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
        hostScanResult: const <String, String?>{
          '192.168.1.77': 'AA-BB-CC-DD-EE-FF',
          '100.90.1.77': '11-22-33-44-55-66',
        },
      );
      readModel = DiscoveryReadModel(
        legacyController: controller,
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: internetPeerEndpointStore,
        trustedLanPeerStore: trustedLanPeerStore,
        discoveryNetworkScopeStore: discoveryNetworkScopeStore,
        settingsStore: settingsStore,
        configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
      );

      await controller.refresh();

      expect(readModel.devices.map((device) => device.ip), <String>[
        '100.90.1.77',
        '192.168.1.77',
      ]);
      expect(readModel.appDetectedCount, 0);

      final tailscaleRange = readModel.availableNetworkRanges.singleWhere(
        (range) => range.subnetCidr == '100.90.1.0/24',
      );
      final changed = discoveryNetworkScopeStore.selectScope(tailscaleRange.id);

      expect(changed, isTrue);
      expect(readModel.selectedNetworkScopeId, tailscaleRange.id);
      expect(readModel.devices.map((device) => device.ip), <String>[
        '100.90.1.77',
      ]);
    },
  );

  test(
    'keeps configured discovery target visible even outside selected subnet scope',
    () async {
      discoveryNetworkInterfaceCatalog.replaceInterfaces(
        const <DiscoveryRawNetworkInterface>[
          DiscoveryRawNetworkInterface(
            name: 'Ethernet',
            index: 1,
            ipv4Addresses: <String>['192.168.1.10'],
          ),
        ],
      );
      await configuredDiscoveryTargetsStore.addTarget('100.64.0.8');

      controller.dispose();
      readModel.dispose();
      discoveryNetworkScopeStore.dispose();

      discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
        interfaceCatalog: discoveryNetworkInterfaceCatalog,
      );
      controller = _buildController(
        database: harness.database,
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: internetPeerEndpointStore,
        trustedLanPeerStore: trustedLanPeerStore,
        settingsStore: settingsStore,
        discoveryNetworkScopeStore: discoveryNetworkScopeStore,
        configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
        hostScanResult: const <String, String?>{
          '192.168.1.77': 'AA-BB-CC-DD-EE-FF',
          '100.64.0.8': null,
        },
      );
      readModel = DiscoveryReadModel(
        legacyController: controller,
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: internetPeerEndpointStore,
        trustedLanPeerStore: trustedLanPeerStore,
        discoveryNetworkScopeStore: discoveryNetworkScopeStore,
        settingsStore: settingsStore,
        configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
      );

      await controller.refresh();

      expect(readModel.devices.map((device) => device.ip), <String>[
        '100.64.0.8',
        '192.168.1.77',
      ]);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required DeviceRegistry deviceRegistry,
  required InternetPeerEndpointStore internetPeerEndpointStore,
  required TrustedLanPeerStore trustedLanPeerStore,
  required SettingsStore settingsStore,
  required DiscoveryNetworkScopeStore discoveryNetworkScopeStore,
  required ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore,
  Map<String, String?> hostScanResult = const <String, String?>{
    '192.168.1.77': 'AA-BB-CC-DD-EE-FF',
  },
}) {
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
  final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
  final previewCacheOwner = PreviewCacheOwner(
    sharedCacheThumbnailStore: thumbnailCacheService,
    sharedCacheIndexStore: sharedCacheIndexStore,
    fileHashService: fileHashService,
  );
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
    networkHostScanner: StubNetworkHostScanner(hostScanResult),
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: internetPeerEndpointStore,
    trustedLanPeerStore: trustedLanPeerStore,
    localPeerIdentityStore: localPeerIdentityStore,
    discoveryNetworkScopeStore: discoveryNetworkScopeStore,
    settingsStore: settingsStore,
    configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
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

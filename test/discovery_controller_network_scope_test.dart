import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/configured_discovery_targets_store.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/configured_discovery_targets_repository.dart';
import 'package:landa/features/discovery/data/discovery_network_interface_catalog.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
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
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/stub_discovery_network_interface_catalog.dart';
import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late RecordingLanDiscoveryService lanDiscoveryService;
  late RecordingNetworkHostScanner networkHostScanner;
  late StubDiscoveryNetworkInterfaceCatalog interfaceCatalog;
  late DiscoveryNetworkScopeStore discoveryNetworkScopeStore;
  late ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore;
  late DiscoveryController controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_network_scope_',
    );
    lanDiscoveryService = RecordingLanDiscoveryService();
    networkHostScanner = RecordingNetworkHostScanner();
    interfaceCatalog = StubDiscoveryNetworkInterfaceCatalog(
      const <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Office LAN',
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
    discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
      interfaceCatalog: interfaceCatalog,
    );
    configuredDiscoveryTargetsStore = ConfiguredDiscoveryTargetsStore(
      repository: ConfiguredDiscoveryTargetsRepository(
        database: harness.database,
      ),
    );
    controller = _buildController(
      database: harness.database,
      lanDiscoveryService: lanDiscoveryService,
      networkHostScanner: networkHostScanner,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      configuredDiscoveryTargetsStore: configuredDiscoveryTargetsStore,
    );
  });

  tearDown(() async {
    controller.dispose();
    configuredDiscoveryTargetsStore.dispose();
    discoveryNetworkScopeStore.dispose();
    await harness.dispose();
  });

  test(
    'applies selected scope IPs to discovery runtime and host scanning',
    () async {
      await controller.start();

      expect(lanDiscoveryService.startLocalSourceIps.single, <String>{
        '192.168.1.10',
        '100.90.1.10',
      });
      expect(networkHostScanner.localSourceIpsCalls.single, <String>{
        '192.168.1.10',
        '100.90.1.10',
      });

      final tailscaleRange = discoveryNetworkScopeStore.ranges.singleWhere(
        (range) => range.subnetCidr == '100.90.1.0/24',
      );

      await controller.selectNetworkScope(tailscaleRange.id);

      expect(controller.localIp, '100.90.1.10');
      expect(lanDiscoveryService.startLocalSourceIps.last, <String>{
        '100.90.1.10',
      });
      expect(networkHostScanner.localSourceIpsCalls.last, <String>{
        '100.90.1.10',
      });
      expect(lanDiscoveryService.stopCalls, 1);
    },
  );

  test(
    'does not restart discovery when the effective IP set does not change',
    () async {
      interfaceCatalog.replaceInterfaces(const <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Office LAN',
          index: 1,
          ipv4Addresses: <String>['192.168.1.10'],
        ),
      ]);

      await controller.start();

      expect(lanDiscoveryService.startCalls, 1);
      expect(networkHostScanner.localSourceIpsCalls, hasLength(1));

      interfaceCatalog.replaceInterfaces(const <DiscoveryRawNetworkInterface>[
        DiscoveryRawNetworkInterface(
          name: 'Office LAN renamed',
          index: 1,
          ipv4Addresses: <String>['192.168.1.10'],
        ),
      ]);

      await controller.refresh();

      expect(lanDiscoveryService.startCalls, 1);
      expect(lanDiscoveryService.stopCalls, 0);
      expect(networkHostScanner.localSourceIpsCalls, hasLength(2));
    },
  );

  test('applies configured discovery targets to runtime and scanner', () async {
    await configuredDiscoveryTargetsStore.addTarget('100.64.0.8');
    await configuredDiscoveryTargetsStore.addTarget('100.64.0.9');

    await controller.start();

    expect(lanDiscoveryService.startConfiguredTargetIps.single, <String>{
      '100.64.0.8',
      '100.64.0.9',
    });
    expect(networkHostScanner.configuredTargetIpsCalls.single, <String>{
      '100.64.0.8',
      '100.64.0.9',
    });

    await configuredDiscoveryTargetsStore.addTarget('100.64.0.10');
    await Future<void>.delayed(Duration.zero);

    expect(lanDiscoveryService.startConfiguredTargetIps.last, <String>{
      '100.64.0.8',
      '100.64.0.9',
      '100.64.0.10',
    });
    expect(networkHostScanner.configuredTargetIpsCalls.last, <String>{
      '100.64.0.8',
      '100.64.0.9',
      '100.64.0.10',
    });
    expect(lanDiscoveryService.stopCalls, 1);
  });
}

DiscoveryController _buildController({
  required AppDatabase database,
  required RecordingLanDiscoveryService lanDiscoveryService,
  required RecordingNetworkHostScanner networkHostScanner,
  required DiscoveryNetworkScopeStore discoveryNetworkScopeStore,
  required ConfiguredDiscoveryTargetsStore configuredDiscoveryTargetsStore,
}) {
  final deviceAliasRepository = DeviceAliasRepository(database: database);
  final deviceRegistry = DeviceRegistry(
    deviceAliasRepository: deviceAliasRepository,
  );
  final internetPeerEndpointStore = InternetPeerEndpointStore(
    friendRepository: FriendRepository(database: database),
  );
  final trustedLanPeerStore = TrustedLanPeerStore(
    deviceRegistry: deviceRegistry,
    deviceAliasRepository: deviceAliasRepository,
  );
  final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
  final settingsStore = SettingsStore(
    appSettingsRepository: AppSettingsRepository(database: database),
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

class RecordingLanDiscoveryService extends LanDiscoveryService {
  final List<Set<String>> startLocalSourceIps = <Set<String>>[];
  final List<Set<String>> startConfiguredTargetIps = <Set<String>>[];
  int startCalls = 0;
  int stopCalls = 0;

  @override
  Future<void> start({
    required String deviceName,
    required String localPeerId,
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
    required void Function(AppPresenceEvent event) onAppDetected,
    void Function(TransferRequestEvent event)? onTransferRequest,
    void Function(TransferDecisionEvent event)? onTransferDecision,
    void Function(FriendRequestEvent event)? onFriendRequest,
    void Function(FriendResponseEvent event)? onFriendResponse,
    void Function(ShareQueryEvent event)? onShareQuery,
    void Function(ShareAccessRequestEvent event)? onShareAccessRequest,
    void Function(ShareAccessResponseEvent event)? onShareAccessResponse,
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(DownloadResponseEvent event)? onDownloadResponse,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) async {
    startCalls += 1;
    startLocalSourceIps.add(Set<String>.from(localSourceIps));
    startConfiguredTargetIps.add(Set<String>.from(configuredTargetIps));
  }

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }
}

class RecordingNetworkHostScanner extends NetworkHostScanner {
  RecordingNetworkHostScanner() : super(allowTcpFallback: false);

  final List<Set<String>> localSourceIpsCalls = <Set<String>>[];
  final List<Set<String>> configuredTargetIpsCalls = <Set<String>>[];

  @override
  Future<Map<String, String?>> scanActiveHosts({
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
  }) async {
    localSourceIpsCalls.add(Set<String>.from(localSourceIps));
    configuredTargetIpsCalls.add(Set<String>.from(configuredTargetIps));
    return const <String, String?>{};
  }
}

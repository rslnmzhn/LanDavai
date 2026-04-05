import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/discovery_network_scope_store.dart';
import 'package:landa/features/discovery/application/discovery_read_model.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/files/application/preview_cache_owner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_availability_store.dart';
import 'package:landa/features/nearby_transfer/application/nearby_transfer_candidate_projection.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAppDatabaseHarness databaseHarness;
  late _PresenceExpiryHarness harness;

  setUp(() async {
    databaseHarness = await TestAppDatabaseHarness.create(
      prefix: 'landa_presence_expiry_',
    );
    harness = await _PresenceExpiryHarness.create(databaseHarness.database);
  });

  tearDown(() async {
    await harness.dispose();
    await databaseHarness.dispose();
  });

  test(
    'remote silent disappearance expires nearby availability before app presence and then removes stale app-only presence',
    () async {
      await harness.controller.start();

      harness.lanDiscoveryService.emitAppPresence(
        AppPresenceEvent(
          ip: '192.168.1.80',
          deviceName: 'Peer A',
          observedAt: DateTime.now(),
          nearbyTransferPort: 45321,
        ),
      );

      await _waitFor(
        () => harness.candidateProjection.snapshotCandidates().length == 1,
        reason: 'nearby candidate should appear after app presence is received',
      );

      await _waitFor(
        () {
          final devices = harness.readModel.devices;
          if (devices.length != 1) {
            return false;
          }
          final device = devices.single;
          return device.ip == '192.168.1.80' &&
              device.isAppDetected &&
              !device.isNearbyTransferAvailable;
        },
        reason:
            'nearby availability should age out before the wider app presence TTL',
      );
      expect(harness.candidateProjection.snapshotCandidates(), isEmpty);

      await _waitFor(
        () => harness.readModel.devices.every(
          (device) => device.ip != '192.168.1.80',
        ),
        reason:
            'stale app presence without newer host evidence should be removed',
      );
    },
  );

  test(
    'presence refresh without nearby advertisement clears lingering nearby availability immediately',
    () async {
      await harness.controller.start();

      harness.lanDiscoveryService.emitAppPresence(
        AppPresenceEvent(
          ip: '192.168.1.81',
          deviceName: 'Peer B',
          observedAt: DateTime.now(),
          nearbyTransferPort: 45322,
        ),
      );

      await _waitFor(
        () => harness.candidateProjection.snapshotCandidates().length == 1,
        reason: 'nearby candidate should appear while advertisement is present',
      );

      harness.lanDiscoveryService.emitAppPresence(
        AppPresenceEvent(
          ip: '192.168.1.81',
          deviceName: 'Peer B',
          observedAt: DateTime.now(),
        ),
      );

      await _waitFor(
        () {
          final devices = harness.readModel.devices;
          if (devices.length != 1) {
            return false;
          }
          final device = devices.single;
          return device.ip == '192.168.1.81' &&
              device.isAppDetected &&
              !device.isNearbyTransferAvailable;
        },
        reason:
            'a newer presence packet without nearby advertisement should clear the lingering nearby flag',
      );
      expect(harness.candidateProjection.snapshotCandidates(), isEmpty);
    },
  );

  test(
    'local nearby availability changes rebroadcast presence immediately',
    () async {
      await harness.controller.start();

      expect(harness.lanDiscoveryService.broadcastPresenceNowCalls, 0);

      harness.availabilityStore.advertiseLanFallback(47890);
      await _waitFor(
        () => harness.lanDiscoveryService.broadcastPresenceNowCalls == 1,
        reason: 'starting nearby availability should rebroadcast presence',
      );

      harness.availabilityStore.clear();
      await _waitFor(
        () => harness.lanDiscoveryService.broadcastPresenceNowCalls == 2,
        reason: 'clearing nearby availability should rebroadcast presence',
      );
    },
  );
}

Future<void> _waitFor(
  bool Function() predicate, {
  required String reason,
  Duration timeout = const Duration(seconds: 2),
  Duration interval = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await Future<void>.delayed(interval);
  }
}

class _PresenceExpiryHarness {
  _PresenceExpiryHarness({
    required this.controller,
    required this.readModel,
    required this.candidateProjection,
    required this.availabilityStore,
    required this.lanDiscoveryService,
    required this.discoveryNetworkScopeStore,
    required this.previewCacheOwner,
    required this.deviceRegistry,
    required this.trustedLanPeerStore,
    required this.internetPeerEndpointStore,
    required this.settingsStore,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final NearbyTransferCandidateProjection candidateProjection;
  final NearbyTransferAvailabilityStore availabilityStore;
  final _RecordingLanDiscoveryService lanDiscoveryService;
  final DiscoveryNetworkScopeStore discoveryNetworkScopeStore;
  final PreviewCacheOwner previewCacheOwner;
  final DeviceRegistry deviceRegistry;
  final TrustedLanPeerStore trustedLanPeerStore;
  final InternetPeerEndpointStore internetPeerEndpointStore;
  final SettingsStore settingsStore;

  static Future<_PresenceExpiryHarness> create(AppDatabase database) async {
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
    final settingsStore = SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: database),
    );
    final discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore(
      interfaceCatalog: StubDiscoveryNetworkInterfaceCatalog(),
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
    final availabilityStore = NearbyTransferAvailabilityStore();
    final lanDiscoveryService = _RecordingLanDiscoveryService();
    final remoteShareBrowser = RemoteShareBrowser(
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
    final controller = DiscoveryController(
      lanDiscoveryService: lanDiscoveryService,
      networkHostScanner: _StubNetworkHostScanner(const <String, String?>{}),
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      localPeerIdentityStore: LocalPeerIdentityStore(database: database),
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: TransferHistoryRepository(database: database),
      clipboardHistoryRepository: ClipboardHistoryRepository(
        database: database,
      ),
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
      nearbyTransferAvailabilityStore: availabilityStore,
      nearbyAvailabilityTtl: const Duration(milliseconds: 60),
      appPresenceTtl: const Duration(milliseconds: 160),
      presenceExpiryCheckInterval: const Duration(milliseconds: 20),
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
    );

    return _PresenceExpiryHarness(
      controller: controller,
      readModel: readModel,
      candidateProjection: NearbyTransferCandidateProjection(
        readModel: readModel,
      ),
      availabilityStore: availabilityStore,
      lanDiscoveryService: lanDiscoveryService,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      previewCacheOwner: previewCacheOwner,
      deviceRegistry: deviceRegistry,
      trustedLanPeerStore: trustedLanPeerStore,
      internetPeerEndpointStore: internetPeerEndpointStore,
      settingsStore: settingsStore,
    );
  }

  Future<void> dispose() async {
    readModel.dispose();
    controller.dispose();
    trustedLanPeerStore.dispose();
    internetPeerEndpointStore.dispose();
    settingsStore.dispose();
    discoveryNetworkScopeStore.dispose();
    previewCacheOwner.dispose();
    deviceRegistry.dispose();
  }
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  void Function(AppPresenceEvent event)? _onAppDetected;
  int broadcastPresenceNowCalls = 0;

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
    void Function(ShareCatalogEvent event)? onShareCatalog,
    void Function(DownloadRequestEvent event)? onDownloadRequest,
    void Function(ThumbnailSyncRequestEvent event)? onThumbnailSyncRequest,
    void Function(ThumbnailPacketEvent event)? onThumbnailPacket,
    void Function(ClipboardQueryEvent event)? onClipboardQuery,
    void Function(ClipboardCatalogEvent event)? onClipboardCatalog,
  }) async {
    _onAppDetected = onAppDetected;
  }

  void emitAppPresence(AppPresenceEvent event) {
    _onAppDetected?.call(event);
  }

  @override
  Future<void> broadcastPresenceNow({required String deviceName}) async {
    broadcastPresenceNowCalls += 1;
  }

  @override
  Future<void> stop() async {}
}

class _StubNetworkHostScanner extends NetworkHostScanner {
  _StubNetworkHostScanner(this.result) : super(allowTcpFallback: false);

  final Map<String, String?> result;

  @override
  Future<Map<String, String?>> scanActiveHosts({
    required Set<String> localSourceIps,
    Set<String> configuredTargetIps = const <String>{},
  }) async {
    return result;
  }
}

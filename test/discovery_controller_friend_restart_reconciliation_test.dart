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

  setUp(() async {
    databaseHarness = await TestAppDatabaseHarness.create(
      prefix: 'landa_friend_restart_reconcile_',
    );
  });

  tearDown(() async {
    await databaseHarness.dispose();
  });

  test(
    'accepted friendship survives restart and reconciles back into visible trusted peer without re-request',
    () async {
      final firstSession = await _FriendRestartHarness.create(
        databaseHarness.database,
      );
      await firstSession.controller.start();

      firstSession.lanDiscoveryService.emitAppPresence(
        AppPresenceEvent(
          ip: '192.168.1.80',
          deviceName: 'Alice',
          peerId: 'LN-REMOTE-ALICE',
          observedAt: DateTime(2026, 1, 1, 10),
        ),
      );
      firstSession.lanDiscoveryService.emitIncomingFriendRequest(
        FriendRequestEvent(
          requestId: 'incoming-1',
          requesterIp: '192.168.1.80',
          requesterName: 'Alice',
          requesterMacAddress: 'AA-BB-CC-DD-EE-FF',
          observedAt: DateTime(2026, 1, 1, 10, 1),
        ),
      );

      await firstSession.controller.respondToFriendRequest(
        requestId: 'incoming-1',
        accept: true,
      );

      expect(firstSession.readModel.friendDevices, hasLength(1));
      expect(
        firstSession.deviceRegistry.macForPeerId('LN-REMOTE-ALICE'),
        'aa:bb:cc:dd:ee:ff',
      );

      await firstSession.dispose();

      final secondSession = await _FriendRestartHarness.create(
        databaseHarness.database,
      );
      addTearDown(secondSession.dispose);
      await secondSession.controller.start();

      expect(
        secondSession.trustedLanPeerStore.isTrustedMac('AA-BB-CC-DD-EE-FF'),
        isTrue,
      );
      expect(
        secondSession.deviceRegistry.macForPeerId('LN-REMOTE-ALICE'),
        'aa:bb:cc:dd:ee:ff',
      );

      secondSession.lanDiscoveryService.emitAppPresence(
        AppPresenceEvent(
          ip: '192.168.1.95',
          deviceName: 'Alice',
          peerId: 'LN-REMOTE-ALICE',
          observedAt: DateTime(2026, 1, 1, 11),
        ),
      );

      await _waitFor(
        () => secondSession.readModel.friendDevices.length == 1,
        reason:
            'trusted peer should reconcile into the visible friend list after restart',
      );

      final friend = secondSession.readModel.friendDevices.single;
      expect(friend.ip, '192.168.1.95');
      expect(friend.peerId, 'LN-REMOTE-ALICE');
      expect(friend.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(friend.isTrusted, isTrue);
      expect(
        secondSession.controller.devices.where(
          (device) => device.macAddress == 'aa:bb:cc:dd:ee:ff',
        ),
        hasLength(1),
      );

      await _waitFor(
        () =>
            secondSession.deviceRegistry.macForIp('192.168.1.95') ==
            'aa:bb:cc:dd:ee:ff',
        reason: 'newly observed IP should replace stale persisted ip mapping',
      );
      expect(secondSession.deviceRegistry.macForIp('192.168.1.80'), isNull);

      await secondSession.controller.requestRemoteClipboardHistory(friend);

      expect(secondSession.lanDiscoveryService.clipboardQueryCalls, 1);
      expect(secondSession.controller.errorMessage, isNull);
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

class _FriendRestartHarness {
  _FriendRestartHarness({
    required this.controller,
    required this.readModel,
    required this.deviceRegistry,
    required this.trustedLanPeerStore,
    required this.internetPeerEndpointStore,
    required this.settingsStore,
    required this.discoveryNetworkScopeStore,
    required this.previewCacheOwner,
    required this.lanDiscoveryService,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;
  final DeviceRegistry deviceRegistry;
  final TrustedLanPeerStore trustedLanPeerStore;
  final InternetPeerEndpointStore internetPeerEndpointStore;
  final SettingsStore settingsStore;
  final DiscoveryNetworkScopeStore discoveryNetworkScopeStore;
  final PreviewCacheOwner previewCacheOwner;
  final _RecordingRestartLanDiscoveryService lanDiscoveryService;

  static Future<_FriendRestartHarness> create(AppDatabase database) async {
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
    final lanDiscoveryService = _RecordingRestartLanDiscoveryService();
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
    );
    final readModel = DiscoveryReadModel(
      legacyController: controller,
      deviceRegistry: deviceRegistry,
      internetPeerEndpointStore: internetPeerEndpointStore,
      trustedLanPeerStore: trustedLanPeerStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      settingsStore: settingsStore,
    );

    return _FriendRestartHarness(
      controller: controller,
      readModel: readModel,
      deviceRegistry: deviceRegistry,
      trustedLanPeerStore: trustedLanPeerStore,
      internetPeerEndpointStore: internetPeerEndpointStore,
      settingsStore: settingsStore,
      discoveryNetworkScopeStore: discoveryNetworkScopeStore,
      previewCacheOwner: previewCacheOwner,
      lanDiscoveryService: lanDiscoveryService,
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

class _RecordingRestartLanDiscoveryService extends LanDiscoveryService {
  int clipboardQueryCalls = 0;
  void Function(AppPresenceEvent event)? _onAppDetected;
  void Function(FriendRequestEvent event)? _onFriendRequest;

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
    _onAppDetected = onAppDetected;
    _onFriendRequest = onFriendRequest;
  }

  void emitAppPresence(AppPresenceEvent event) {
    _onAppDetected?.call(event);
  }

  void emitIncomingFriendRequest(FriendRequestEvent event) {
    _onFriendRequest?.call(event);
  }

  @override
  Future<void> sendFriendResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {}

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

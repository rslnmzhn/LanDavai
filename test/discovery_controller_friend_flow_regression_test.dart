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
import 'package:landa/features/discovery/data/lan_packet_codec_models.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestAppDatabaseHarness harness;
  late _FriendFlowHarness flow;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_friend_flow_regression_',
    );
    flow = await _FriendFlowHarness.create(harness.database);
  });

  tearDown(() async {
    await flow.dispose();
    await harness.dispose();
  });

  test(
    'accepting an incoming friend request makes the friend visible and usable for remote clipboard',
    () async {
      await flow.controller.start();

      flow.lanDiscoveryService.emitIncomingFriendRequest(
        FriendRequestEvent(
          requestId: 'incoming-1',
          requesterIp: '192.168.1.80',
          requesterName: 'Alice',
          requesterMacAddress: 'AA-BB-CC-DD-EE-FF',
          observedAt: DateTime(2026, 1, 1, 10),
        ),
      );

      expect(flow.controller.incomingFriendRequests, hasLength(1));

      await flow.controller.respondToFriendRequest(
        requestId: 'incoming-1',
        accept: true,
      );

      final friend = flow.readModel.friendDevices.single;
      expect(friend.ip, '192.168.1.80');
      expect(friend.displayName, 'Alice');
      expect(friend.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(friend.isTrusted, isTrue);
      expect(flow.deviceRegistry.macForIp('192.168.1.80'), friend.macAddress);
      expect(flow.controller.devices.single.isTrusted, isTrue);

      await flow.controller.requestRemoteClipboardHistory(friend);

      expect(flow.lanDiscoveryService.friendResponseCalls, 1);
      expect(flow.lanDiscoveryService.clipboardQueryCalls, 1);
      expect(flow.controller.errorMessage, isNull);
    },
  );

  test(
    'accepted outgoing friend response makes the responder visible in the friend list',
    () async {
      await flow.controller.start();

      await flow.controller.sendFriendRequest(
        DiscoveredDevice(
          ip: '192.168.1.81',
          macAddress: '11-22-33-44-55-66',
          deviceName: 'Bob',
          isAppDetected: true,
          isReachable: true,
          lastSeen: DateTime(2026, 1, 1, 11),
        ),
      );

      final requestId = flow.lanDiscoveryService.lastFriendRequestId;
      expect(requestId, isNotNull);

      flow.lanDiscoveryService.emitFriendResponse(
        FriendResponseEvent(
          requestId: requestId!,
          responderIp: '192.168.1.81',
          responderName: 'Bob',
          responderMacAddress: '11-22-33-44-55-66',
          accepted: true,
          observedAt: DateTime(2026, 1, 1, 11, 1),
        ),
      );
      await _waitFor(
        () => flow.readModel.friendDevices.isNotEmpty,
        reason: 'accepted friend response should project into friend list',
      );

      final friend = flow.readModel.friendDevices.single;
      expect(friend.ip, '192.168.1.81');
      expect(friend.displayName, 'Bob');
      expect(friend.macAddress, '11:22:33:44:55:66');
      expect(friend.isTrusted, isTrue);
      expect(flow.deviceRegistry.macForIp('192.168.1.81'), friend.macAddress);
      expect(flow.controller.errorMessage, isNull);
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

class _FriendFlowHarness {
  _FriendFlowHarness({
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
  final _RecordingFriendLanDiscoveryService lanDiscoveryService;

  static Future<_FriendFlowHarness> create(AppDatabase database) async {
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
    final discoveryNetworkScopeStore = buildTestDiscoveryNetworkScopeStore();
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
    final lanDiscoveryService = _RecordingFriendLanDiscoveryService();
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

    return _FriendFlowHarness(
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

class _RecordingFriendLanDiscoveryService extends LanDiscoveryService {
  int friendResponseCalls = 0;
  int clipboardQueryCalls = 0;
  String? lastFriendRequestId;

  void Function(FriendRequestEvent event)? _onFriendRequest;
  void Function(FriendResponseEvent event)? _onFriendResponse;
  void Function(ClipboardCatalogEvent event)? _onClipboardCatalog;

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
    _onFriendRequest = onFriendRequest;
    _onFriendResponse = onFriendResponse;
    _onClipboardCatalog = onClipboardCatalog;
  }

  void emitIncomingFriendRequest(FriendRequestEvent event) {
    _onFriendRequest?.call(event);
  }

  void emitFriendResponse(FriendResponseEvent event) {
    _onFriendResponse?.call(event);
  }

  @override
  Future<void> sendFriendRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
  }) async {
    lastFriendRequestId = requestId;
  }

  @override
  Future<void> sendFriendResponse({
    required String targetIp,
    required String requestId,
    required String responderName,
    required String responderMacAddress,
    required bool accepted,
  }) async {
    friendResponseCalls += 1;
  }

  @override
  Future<void> sendClipboardQuery({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int maxEntries,
  }) async {
    clipboardQueryCalls += 1;
    _onClipboardCatalog?.call(
      ClipboardCatalogEvent(
        requestId: requestId,
        ownerIp: targetIp,
        ownerName: 'Clipboard peer',
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        observedAt: DateTime(2026, 1, 1, 10, 2),
        entries: const <ClipboardCatalogItem>[
          ClipboardCatalogItem(
            id: 'entry-1',
            entryType: 'text',
            textValue: 'Remote clipboard value',
            createdAtMs: 100,
          ),
        ],
      ),
    );
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

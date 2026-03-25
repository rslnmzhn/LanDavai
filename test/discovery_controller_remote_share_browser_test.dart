import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
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
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  DiscoveryController? controller;
  late TrackingRemoteShareBrowser remoteShareBrowser;
  late CapturingLanDiscoveryService lanDiscoveryService;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_remote_share_browser_',
    );
    lanDiscoveryService = CapturingLanDiscoveryService();
    final sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: harness.database,
    );
    final sharedCacheIndexStore = SharedCacheIndexStore(
      database: harness.database,
    );
    final sharedCacheCatalog = SharedCacheCatalog(
      sharedFolderCacheRepository: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    remoteShareBrowser = TrackingRemoteShareBrowser(
      sharedCacheCatalog: sharedCacheCatalog,
    );
    controller = _buildController(
      database: harness.database,
      lanDiscoveryService: lanDiscoveryService,
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      sharedFolderCacheRepository: sharedFolderCacheRepository,
    );
  });

  tearDown(() async {
    controller?.dispose();
    remoteShareBrowser.dispose();
    await harness.dispose();
  });

  test(
    'loadRemoteShareOptions delegates browse startup to RemoteShareBrowser',
    () async {
      await controller!.loadRemoteShareOptions();

      expect(remoteShareBrowser.startBrowseCalls, 1);
      expect(remoteShareBrowser.isLoading, isFalse);
      expect(controller!.errorMessage, isNull);
      expect(
        controller!.infoMessage,
        'No Landa devices available for shared content.',
      );
    },
  );

  test(
    'share catalog packets are applied through RemoteShareBrowser instead of controller-owned session state',
    () async {
      await controller!.start();
      expect(lanDiscoveryService.onShareCatalog, isNotNull);

      await remoteShareBrowser.startBrowse(
        targets: <DiscoveredDevice>[
          DiscoveredDevice(
            ip: '192.168.1.40',
            macAddress: '11:22:33:44:55:66',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
        ],
        receiverMacAddress: controller!.localDeviceMac,
        requesterName: controller!.localName,
        requestId: 'request-1',
        responseWindow: Duration.zero,
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) async {},
      );

      lanDiscoveryService.onShareCatalog!(
        ShareCatalogEvent(
          requestId: 'request-1',
          ownerIp: '192.168.1.40',
          ownerName: 'Remote device',
          ownerMacAddress: '11-22-33-44-55-66',
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026),
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Photos',
              itemCount: 1,
              totalBytes: 42,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(
                  relativePath: 'album/photo.jpg',
                  sizeBytes: 42,
                ),
              ],
            ),
          ],
        ),
      );
      await _pumpUntil(
        () => remoteShareBrowser.currentBrowseProjection.options.isNotEmpty,
      );

      expect(remoteShareBrowser.applyRemoteCatalogCalls, 1);
      final options = remoteShareBrowser.currentBrowseProjection.options;
      expect(options, hasLength(1));
      expect(options.single.ownerIp, '192.168.1.40');
      expect(options.single.ownerName, 'Remote device');
    },
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
  Duration step = const Duration(milliseconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      break;
    }
    await Future<void>.delayed(step);
  }
}

DiscoveryController _buildController({
  required AppDatabase database,
  required LanDiscoveryService lanDiscoveryService,
  required RemoteShareBrowser remoteShareBrowser,
  required SharedCacheCatalog sharedCacheCatalog,
  required SharedCacheIndexStore sharedCacheIndexStore,
  required SharedFolderCacheRepository sharedFolderCacheRepository,
}) {
  final deviceAliasRepository = DeviceAliasRepository(database: database);
  final deviceRegistry = DeviceRegistry(
    deviceAliasRepository: deviceAliasRepository,
  );
  final fileHashService = FileHashService();
  final previewCacheOwner = PreviewCacheOwner(
    sharedFolderCacheRepository: sharedFolderCacheRepository,
    sharedCacheIndexStore: sharedCacheIndexStore,
    fileHashService: fileHashService,
  );

  return DiscoveryController(
    lanDiscoveryService: lanDiscoveryService,
    networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
    deviceRegistry: deviceRegistry,
    internetPeerEndpointStore: InternetPeerEndpointStore(
      friendRepository: FriendRepository(database: database),
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

class TrackingRemoteShareBrowser extends RemoteShareBrowser {
  TrackingRemoteShareBrowser({required super.sharedCacheCatalog});

  int startBrowseCalls = 0;
  int applyRemoteCatalogCalls = 0;

  @override
  Future<RemoteBrowseStartResult> startBrowse({
    required List<DiscoveredDevice> targets,
    required String receiverMacAddress,
    required String requesterName,
    required String requestId,
    required Future<void> Function({
      required String targetIp,
      required String requestId,
      required String requesterName,
    })
    sendShareQuery,
    Duration responseWindow = const Duration(milliseconds: 900),
  }) async {
    startBrowseCalls += 1;
    return super.startBrowse(
      targets: targets,
      receiverMacAddress: receiverMacAddress,
      requesterName: requesterName,
      requestId: requestId,
      sendShareQuery: sendShareQuery,
      responseWindow: Duration.zero,
    );
  }

  @override
  Future<void> applyRemoteCatalog({
    required ShareCatalogEvent event,
    required String ownerDisplayName,
    required String ownerMacAddress,
  }) async {
    applyRemoteCatalogCalls += 1;
    await super.applyRemoteCatalog(
      event: event,
      ownerDisplayName: ownerDisplayName,
      ownerMacAddress: ownerMacAddress,
    );
  }
}

class CapturingLanDiscoveryService extends LanDiscoveryService {
  void Function(ShareCatalogEvent event)? onShareCatalog;

  @override
  Future<void> start({
    required String deviceName,
    required String localPeerId,
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
    String? preferredSourceIp,
  }) async {
    this.onShareCatalog = onShareCatalog;
  }

  @override
  Future<void> stop() async {}
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

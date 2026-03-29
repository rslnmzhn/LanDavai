import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/application/remote_clipboard_projection_store.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/internet_peer_endpoint_store.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
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

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'DiscoveryController routes remote clipboard protocol callbacks through RemoteClipboardProjectionStore',
    () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_remote_clipboard_controller_',
      );
      final database = harness.database;
      final deviceAliasRepository = DeviceAliasRepository(database: database);
      final deviceRegistry = DeviceRegistry(
        deviceAliasRepository: deviceAliasRepository,
      );
      final trustedLanPeerStore = TrustedLanPeerStore(
        deviceRegistry: deviceRegistry,
        deviceAliasRepository: deviceAliasRepository,
      );
      final lanDiscoveryService = RecordingRemoteClipboardLanDiscoveryService();
      final settingsStore = SettingsStore(
        appSettingsRepository: AppSettingsRepository(database: database),
      );
      final sharedFolderCacheRepository = SharedFolderCacheRepository(
        database: database,
      );
      final sharedCacheIndexStore = SharedCacheIndexStore(database: database);
      final sharedCacheCatalog = SharedCacheCatalog(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
      );
      final fileHashService = FileHashService();
      final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
      final remoteClipboardProjectionStore =
          TrackingRemoteClipboardProjectionStore(
            fileHashService: fileHashService,
          );
      final previewCacheOwner = PreviewCacheOwner(
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        sharedCacheIndexStore: sharedCacheIndexStore,
        fileHashService: fileHashService,
      );
      final controller = DiscoveryController(
        lanDiscoveryService: lanDiscoveryService,
        networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
        deviceRegistry: deviceRegistry,
        internetPeerEndpointStore: InternetPeerEndpointStore(
          friendRepository: FriendRepository(database: database),
        ),
        trustedLanPeerStore: trustedLanPeerStore,
        localPeerIdentityStore: localPeerIdentityStore,
        settingsStore: settingsStore,
        appNotificationService: AppNotificationService.instance,
        transferHistoryRepository: TransferHistoryRepository(
          database: database,
        ),
        clipboardHistoryRepository: ClipboardHistoryRepository(
          database: database,
        ),
        clipboardCaptureService: ClipboardCaptureService(),
        remoteClipboardProjectionStore: remoteClipboardProjectionStore,
        remoteShareBrowser: RemoteShareBrowser(
          sharedCacheCatalog: sharedCacheCatalog,
        ),
        sharedCacheCatalog: sharedCacheCatalog,
        sharedCacheIndexStore: sharedCacheIndexStore,
        sharedFolderCacheRepository: sharedFolderCacheRepository,
        fileHashService: fileHashService,
        fileTransferService: FileTransferService(),
        transferStorageService: TransferStorageService(),
        previewCacheOwner: previewCacheOwner,
        pathOpener: PathOpener(),
      );

      addTearDown(() async {
        controller.dispose();
        previewCacheOwner.dispose();
        deviceRegistry.dispose();
        trustedLanPeerStore.dispose();
        await harness.dispose();
      });

      await deviceRegistry.recordSeenDevices(const <String, String>{
        'AA-BB-CC-DD-EE-FF': '192.168.1.80',
      });
      await trustedLanPeerStore.trustDevice(macAddress: 'AA-BB-CC-DD-EE-FF');
      await controller.start();

      await controller.requestRemoteClipboardHistory(
        DiscoveredDevice(
          ip: '192.168.1.80',
          macAddress: 'AA-BB-CC-DD-EE-FF',
          isAppDetected: true,
          lastSeen: DateTime(2026),
        ),
      );

      expect(lanDiscoveryService.clipboardQueryCalls, 1);
      expect(remoteClipboardProjectionStore.beginRequestCalls, 1);
      expect(remoteClipboardProjectionStore.applyCatalogCalls, 1);
      expect(remoteClipboardProjectionStore.finishRequestCalls, 1);
      expect(
        remoteClipboardProjectionStore.entriesFor('192.168.1.80'),
        hasLength(1),
      );
      expect(
        remoteClipboardProjectionStore
            .entriesFor('192.168.1.80')
            .single
            .textValue,
        'Remote clipboard value',
      );
      expect(remoteClipboardProjectionStore.isLoading, isFalse);
    },
  );
}

class RecordingRemoteClipboardLanDiscoveryService extends LanDiscoveryService {
  int clipboardQueryCalls = 0;
  void Function(ClipboardCatalogEvent event)? onClipboardCatalog;

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
    this.onClipboardCatalog = onClipboardCatalog;
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
    onClipboardCatalog?.call(
      ClipboardCatalogEvent(
        requestId: requestId,
        ownerIp: targetIp,
        ownerName: 'Remote peer',
        ownerMacAddress: '11:22:33:44:55:66',
        observedAt: DateTime(2026),
        entries: const <ClipboardCatalogItem>[
          ClipboardCatalogItem(
            id: 'remote-entry-1',
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

class TrackingRemoteClipboardProjectionStore
    extends RemoteClipboardProjectionStore {
  TrackingRemoteClipboardProjectionStore({required super.fileHashService});

  int beginRequestCalls = 0;
  int applyCatalogCalls = 0;
  int finishRequestCalls = 0;

  @override
  String beginRequest({
    required String ownerIp,
    required String localDeviceMac,
  }) {
    beginRequestCalls += 1;
    return super.beginRequest(ownerIp: ownerIp, localDeviceMac: localDeviceMac);
  }

  @override
  bool applyCatalog(ClipboardCatalogEvent event) {
    applyCatalogCalls += 1;
    return super.applyCatalog(event);
  }

  @override
  void finishRequest({required String requestId}) {
    finishRequestCalls += 1;
    super.finishRequest(requestId: requestId);
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

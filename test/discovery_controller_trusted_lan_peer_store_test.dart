import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_support/test_app_database.dart';

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
  return DiscoveryController(
    lanDiscoveryService: lanDiscoveryService,
    networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
    deviceRegistry: deviceRegistry,
    trustedLanPeerStore: trustedLanPeerStore,
    friendRepository: FriendRepository(database: database),
    appSettingsRepository: AppSettingsRepository(database: database),
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
    String? preferredSourceIp,
  }) async {
    return result;
  }
}

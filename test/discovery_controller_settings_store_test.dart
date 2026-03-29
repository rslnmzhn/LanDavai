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
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_settings_store_',
    );
  });

  tearDown(() async {
    controller?.dispose();
    await harness.dispose();
  });

  test('settings getter reads canonical snapshot from SettingsStore', () async {
    final settingsStore = SettingsStore(
      appSettingsRepository: AppSettingsRepository(database: harness.database),
    );
    const expected = AppSettings(
      backgroundScanInterval: BackgroundScanIntervalOption.fifteenMinutes,
      downloadAttemptNotificationsEnabled: false,
      minimizeToTrayOnClose: false,
      isLeftHandedMode: true,
      videoLinkPassword: 'watch-pass',
      previewCacheMaxSizeGb: 5,
      previewCacheMaxAgeDays: 12,
      clipboardHistoryMaxEntries: 18,
      recacheParallelWorkers: 3,
    );
    await settingsStore.save(expected);

    controller = _buildController(
      database: harness.database,
      settingsStore: settingsStore,
    );

    expect(
      controller!.settings.backgroundScanInterval,
      expected.backgroundScanInterval,
    );
    expect(
      controller!.settings.downloadAttemptNotificationsEnabled,
      expected.downloadAttemptNotificationsEnabled,
    );
    expect(
      controller!.settings.minimizeToTrayOnClose,
      expected.minimizeToTrayOnClose,
    );
    expect(controller!.settings.isLeftHandedMode, expected.isLeftHandedMode);
    expect(controller!.settings.videoLinkPassword, expected.videoLinkPassword);
    expect(
      controller!.settings.previewCacheMaxSizeGb,
      expected.previewCacheMaxSizeGb,
    );
    expect(
      controller!.settings.previewCacheMaxAgeDays,
      expected.previewCacheMaxAgeDays,
    );
    expect(
      controller!.settings.clipboardHistoryMaxEntries,
      expected.clipboardHistoryMaxEntries,
    );
    expect(
      controller!.settings.recacheParallelWorkers,
      expected.recacheParallelWorkers,
    );
  });

  test(
    'settings mutation routes through SettingsStore and leaves local_peer_id untouched',
    () async {
      final localPeerIdentityStore = LocalPeerIdentityStore(
        database: harness.database,
      );
      final localPeerId = await localPeerIdentityStore
          .loadOrCreateLocalPeerId();
      final trackingSettingsStore = TrackingSettingsStore(
        appSettingsRepository: AppSettingsRepository(
          database: harness.database,
        ),
      );
      controller = _buildController(
        database: harness.database,
        settingsStore: trackingSettingsStore,
      );

      await controller!.setVideoLinkPassword('  secret-code  ');

      final persistedSettings = await AppSettingsRepository(
        database: harness.database,
      ).load();
      final localPeerRows = await (await harness.database.database).query(
        AppDatabase.appSettingsTable,
        columns: <String>['setting_value'],
        where: 'setting_key = ?',
        whereArgs: <Object>['local_peer_id'],
        limit: 1,
      );

      expect(trackingSettingsStore.saveCalls, 1);
      expect(controller!.settings.videoLinkPassword, 'secret-code');
      expect(persistedSettings.videoLinkPassword, 'secret-code');
      expect(localPeerRows, hasLength(1));
      expect(localPeerRows.single['setting_value'], localPeerId);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required SettingsStore settingsStore,
}) {
  final deviceAliasRepository = DeviceAliasRepository(database: database);
  final deviceRegistry = DeviceRegistry(
    deviceAliasRepository: deviceAliasRepository,
  );
  final endpointRepository = FriendRepository(database: database);
  final localPeerIdentityStore = LocalPeerIdentityStore(database: database);
  final sharedFolderCacheRepository = SharedFolderCacheRepository(
    database: database,
  );
  final sharedCacheIndexStore = SharedCacheIndexStore(database: database);
  final sharedCacheCatalog = SharedCacheCatalog(
    sharedFolderCacheRepository: sharedFolderCacheRepository,
    sharedCacheIndexStore: sharedCacheIndexStore,
  );
  final fileHashService = FileHashService();
  final previewCacheOwner = PreviewCacheOwner(
    sharedFolderCacheRepository: sharedFolderCacheRepository,
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
    sharedFolderCacheRepository: sharedFolderCacheRepository,
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
    trustedLanPeerStore: TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: deviceAliasRepository,
    ),
    localPeerIdentityStore: localPeerIdentityStore,
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

class TrackingSettingsStore extends SettingsStore {
  TrackingSettingsStore({required super.appSettingsRepository});

  int saveCalls = 0;

  @override
  Future<void> save(AppSettings settings) async {
    saveCalls += 1;
    await super.save(settings);
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

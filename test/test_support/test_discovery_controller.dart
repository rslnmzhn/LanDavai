import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/desktop_window_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/network_host_scanner.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:landa/features/transfer/data/video_link_share_service.dart';

import 'test_app_database.dart';

class TestDiscoveryControllerHarness {
  TestDiscoveryControllerHarness._({
    required this.databaseHarness,
    required this.controller,
  });

  final TestAppDatabaseHarness databaseHarness;
  final TrackingDiscoveryController controller;

  static Future<TestDiscoveryControllerHarness> create() async {
    final databaseHarness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_ui_',
    );
    final database = databaseHarness.database;
    final deviceAliasRepository = DeviceAliasRepository(database: database);
    final controller = TrackingDiscoveryController(
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(allowTcpFallback: false),
      deviceAliasRepository: deviceAliasRepository,
      deviceRegistry: DeviceRegistry(
        deviceAliasRepository: deviceAliasRepository,
      ),
      friendRepository: FriendRepository(database: database),
      appSettingsRepository: AppSettingsRepository(database: database),
      appNotificationService: AppNotificationService.instance,
      transferHistoryRepository: TransferHistoryRepository(database: database),
      clipboardHistoryRepository: ClipboardHistoryRepository(
        database: database,
      ),
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

    return TestDiscoveryControllerHarness._(
      databaseHarness: databaseHarness,
      controller: controller,
    );
  }

  Future<void> dispose() async {
    if (!controller.wasDisposed) {
      controller.dispose();
    }
    await databaseHarness.dispose();
  }
}

class TrackingDiscoveryController extends DiscoveryController {
  TrackingDiscoveryController({
    required super.lanDiscoveryService,
    required super.networkHostScanner,
    required super.deviceAliasRepository,
    required super.deviceRegistry,
    required super.friendRepository,
    required super.appSettingsRepository,
    required super.appNotificationService,
    required super.transferHistoryRepository,
    required super.clipboardHistoryRepository,
    required super.clipboardCaptureService,
    required super.sharedFolderCacheRepository,
    required super.fileHashService,
    required super.fileTransferService,
    required super.transferStorageService,
    required super.videoLinkShareService,
    required super.pathOpener,
  });

  int startCalls = 0;
  int disposeCalls = 0;
  int shareableVideoListCalls = 0;
  bool wasDisposed = false;

  @override
  Future<void> start() async {
    startCalls += 1;
    notifyListeners();
  }

  @override
  Future<List<ShareableVideoFile>> listShareableVideoFiles({
    String? cacheId,
  }) async {
    shareableVideoListCalls += 1;
    return const <ShareableVideoFile>[];
  }

  @override
  void dispose() {
    if (wasDisposed) {
      return;
    }
    disposeCalls += 1;
    wasDisposed = true;
    super.dispose();
  }
}

class TrackingDesktopWindowService extends DesktopWindowService {
  int setMinimizeCalls = 0;
  bool? lastEnabled;

  @override
  Future<void> setMinimizeToTrayEnabled(bool enabled) async {
    setMinimizeCalls += 1;
    lastEnabled = enabled;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/core/utils/path_opener.dart';
import 'package:landa/features/clipboard/data/clipboard_capture_service.dart';
import 'package:landa/features/clipboard/data/clipboard_history_repository.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/discovery_controller.dart';
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
  late DeviceAliasRepository registryRepository;
  late ThrowingIdentityWriteDeviceAliasRepository controllerRepository;
  TrackingDeviceRegistry? registry;
  DiscoveryController? controller;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_discovery_registry_',
    );
    registryRepository = DeviceAliasRepository(database: harness.database);
    controllerRepository = ThrowingIdentityWriteDeviceAliasRepository(
      database: harness.database,
    );
  });

  tearDown(() async {
    controller?.dispose();
    registry?.dispose();
    await harness.dispose();
  });

  test(
    'renameDeviceAlias resolves stable identity through DeviceRegistry and not controller repository writes',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.55';
      registry = TrackingDeviceRegistry(database: harness.database);
      await registry!.recordSeenDevices(<String, String>{mac: ip});
      controller = _buildController(
        database: harness.database,
        deviceRegistry: registry!,
        deviceAliasRepository: controllerRepository,
        networkHostScanner: StubNetworkHostScanner(const <String, String?>{}),
      );

      await controller!.renameDeviceAlias(
        device: DiscoveredDevice(ip: ip, lastSeen: DateTime(2026)),
        alias: 'Office laptop',
      );

      final aliasMap = await registryRepository.loadAliasMap();

      expect(registry!.setAliasCalls, 1);
      expect(aliasMap['aa:bb:cc:dd:ee:ff'], 'Office laptop');
      expect(controller!.errorMessage, isNull);
    },
  );

  test(
    'refresh records seen devices through DeviceRegistry and projects aliases without direct repository identity writes',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      const ip = '192.168.1.77';
      await registryRepository.setAlias(
        macAddress: mac,
        alias: 'Office laptop',
      );
      registry = TrackingDeviceRegistry(database: harness.database);
      await registry!.load();
      controller = _buildController(
        database: harness.database,
        deviceRegistry: registry!,
        deviceAliasRepository: controllerRepository,
        networkHostScanner: StubNetworkHostScanner(<String, String?>{ip: mac}),
      );

      await controller!.refresh();

      final device = controller!.devices.single;
      final lastKnownIpMap = await registryRepository.loadLastKnownIpMap();

      expect(registry!.recordSeenDevicesCalls, 1);
      expect(device.ip, ip);
      expect(device.macAddress, 'aa:bb:cc:dd:ee:ff');
      expect(device.aliasName, 'Office laptop');
      expect(lastKnownIpMap['aa:bb:cc:dd:ee:ff'], ip);
      expect(controller!.errorMessage, isNull);
    },
  );
}

DiscoveryController _buildController({
  required AppDatabase database,
  required DeviceRegistry deviceRegistry,
  required DeviceAliasRepository deviceAliasRepository,
  required NetworkHostScanner networkHostScanner,
}) {
  return DiscoveryController(
    lanDiscoveryService: LanDiscoveryService(),
    networkHostScanner: networkHostScanner,
    deviceAliasRepository: deviceAliasRepository,
    deviceRegistry: deviceRegistry,
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

class TrackingDeviceRegistry extends DeviceRegistry {
  TrackingDeviceRegistry({required this.database})
    : super(deviceAliasRepository: DeviceAliasRepository(database: database));

  final AppDatabase database;
  int recordSeenDevicesCalls = 0;
  int setAliasCalls = 0;

  @override
  Future<void> recordSeenDevices(Map<String, String> macToIp) async {
    recordSeenDevicesCalls += 1;
    await super.recordSeenDevices(macToIp);
  }

  @override
  Future<void> setAlias({
    required String macAddress,
    required String alias,
  }) async {
    setAliasCalls += 1;
    await super.setAlias(macAddress: macAddress, alias: alias);
  }
}

class ThrowingIdentityWriteDeviceAliasRepository extends DeviceAliasRepository {
  ThrowingIdentityWriteDeviceAliasRepository({required super.database});

  @override
  Future<Map<String, String>> loadAliasMap() {
    throw StateError('DiscoveryController must not load aliases directly');
  }

  @override
  Future<void> recordSeenDevices(Map<String, String> macToIp) {
    throw StateError(
      'DiscoveryController must not record seen devices directly',
    );
  }

  @override
  Future<void> setAlias({required String macAddress, required String alias}) {
    throw StateError('DiscoveryController must not write aliases directly');
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

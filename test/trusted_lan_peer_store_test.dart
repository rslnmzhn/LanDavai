import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/application/trusted_lan_peer_store.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late AppDatabase database;
  late Database sqliteDatabase;
  late DeviceAliasRepository repository;
  late DeviceRegistry deviceRegistry;
  late TrustedLanPeerStore trustedLanPeerStore;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_trusted_lan_peer_store_',
    );
    database = harness.database;
    sqliteDatabase = await database.database;
    repository = DeviceAliasRepository(database: database);
    deviceRegistry = DeviceRegistry(deviceAliasRepository: repository);
    trustedLanPeerStore = TrustedLanPeerStore(
      deviceRegistry: deviceRegistry,
      deviceAliasRepository: repository,
    );
  });

  tearDown(() async {
    trustedLanPeerStore.dispose();
    deviceRegistry.dispose();
    await harness.dispose();
  });

  test('trust remains keyed to normalized mac when ip changes', () async {
    const mac = 'AA-BB-CC-DD-EE-FF';
    await deviceRegistry.recordSeenDevices(<String, String>{
      mac: '192.168.1.10',
    });
    await trustedLanPeerStore.trustDevice(macAddress: mac);

    expect(trustedLanPeerStore.isTrustedMac(mac), isTrue);
    expect(trustedLanPeerStore.isTrustedIp('192.168.1.10'), isTrue);

    await deviceRegistry.recordSeenDevices(<String, String>{
      'aa:bb:cc:dd:ee:ff': '192.168.1.55',
    });

    expect(trustedLanPeerStore.isTrustedMac('aa:bb:cc:dd:ee:ff'), isTrue);
    expect(trustedLanPeerStore.isTrustedIp('192.168.1.55'), isTrue);
    expect(trustedLanPeerStore.isTrustedIp('192.168.1.10'), isFalse);
  });

  test(
    'trust writes stay in known_devices and do not create or update friends rows',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';

      await trustedLanPeerStore.trustDevice(macAddress: mac);

      final trustedRows = await sqliteDatabase.query(
        AppDatabase.knownDevicesTable,
        where: 'mac_address = ?',
        whereArgs: <Object>['aa:bb:cc:dd:ee:ff'],
      );
      final friendRows = await sqliteDatabase.query(AppDatabase.friendsTable);

      expect(trustedRows, hasLength(1));
      expect(trustedRows.single['is_trusted'], 1);
      expect(friendRows, isEmpty);

      await trustedLanPeerStore.revokeTrust(macAddress: mac);

      final updatedRows = await sqliteDatabase.query(
        AppDatabase.knownDevicesTable,
        where: 'mac_address = ?',
        whereArgs: <Object>['aa:bb:cc:dd:ee:ff'],
      );

      expect(updatedRows, hasLength(1));
      expect(updatedRows.single['is_trusted'], 0);
      expect(await sqliteDatabase.query(AppDatabase.friendsTable), isEmpty);
    },
  );
}

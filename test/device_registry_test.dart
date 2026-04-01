import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/application/device_registry.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late DeviceAliasRepository repository;
  late DeviceRegistry registry;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_registry_');
    repository = DeviceAliasRepository(database: harness.database);
    registry = DeviceRegistry(deviceAliasRepository: repository);
    database = await harness.database.database;
  });

  tearDown(() async {
    registry.dispose();
    await harness.dispose();
  });

  test(
    'load hydrates alias and last-known-ip mappings from known_devices',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      await repository.recordSeenDevices(<String, String>{mac: '192.168.1.10'});
      await repository.setAlias(macAddress: mac, alias: 'Office laptop');

      await registry.load();

      expect(registry.aliasForMac(mac), 'Office laptop');
      expect(registry.macForIp('192.168.1.10'), 'aa:bb:cc:dd:ee:ff');
    },
  );

  test(
    'recordSeenDevices updates registry mapping and persistence together',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';

      await registry.load();
      await registry.recordSeenDevices(<String, String>{mac: '192.168.1.10'});
      await registry.recordSeenDevices(<String, String>{
        'aa:bb:cc:dd:ee:ff': '192.168.1.77',
      });

      final rows = await database.query(
        AppDatabase.knownDevicesTable,
        where: 'mac_address = ?',
        whereArgs: <Object>['aa:bb:cc:dd:ee:ff'],
      );

      expect(registry.macForIp('192.168.1.10'), isNull);
      expect(registry.macForIp('192.168.1.77'), 'aa:bb:cc:dd:ee:ff');
      expect(rows.single['last_known_ip'], '192.168.1.77');
    },
  );

  test('setAlias updates registry alias view and persistence', () async {
    const mac = 'AA-BB-CC-DD-EE-FF';
    await repository.recordSeenDevices(<String, String>{mac: '192.168.1.10'});
    await registry.load();

    await registry.setAlias(macAddress: mac, alias: 'Office laptop');

    final aliasMap = await repository.loadAliasMap();

    expect(registry.aliasForMac('aa:bb:cc:dd:ee:ff'), 'Office laptop');
    expect(aliasMap['aa:bb:cc:dd:ee:ff'], 'Office laptop');
  });
}

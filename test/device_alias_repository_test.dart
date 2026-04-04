import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/data/device_alias_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late DeviceAliasRepository repository;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_device_alias_',
    );
    repository = DeviceAliasRepository(database: harness.database);
    database = await harness.database.database;
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'normalizeMac keeps canonical lowercase form and rejects invalid values',
    () {
      expect(
        DeviceAliasRepository.normalizeMac('AA-BB-CC-DD-EE-FF'),
        'aa:bb:cc:dd:ee:ff',
      );
      expect(
        DeviceAliasRepository.normalizeMac('aa:bb:cc:dd:ee:ff'),
        'aa:bb:cc:dd:ee:ff',
      );
      expect(DeviceAliasRepository.normalizeMac('00:00:00:00:00:00'), isNull);
      expect(DeviceAliasRepository.normalizeMac('invalid-mac'), isNull);
    },
  );

  test(
    'preserves alias and trust when the same normalized mac is seen on a new ip',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';
      await repository.recordSeenDevices(<String, String>{mac: '192.168.1.10'});
      await repository.setAlias(macAddress: mac, alias: 'Office laptop');
      await repository.setTrusted(macAddress: mac, isTrusted: true);

      await repository.recordSeenDevices(<String, String>{
        'aa:bb:cc:dd:ee:ff': '192.168.1.55',
      });

      final aliasMap = await repository.loadAliasMap();
      final trustedMacs = await repository.loadTrustedMacs();
      final rows = await database.query(
        AppDatabase.knownDevicesTable,
        where: 'mac_address = ?',
        whereArgs: <Object>['aa:bb:cc:dd:ee:ff'],
      );

      expect(aliasMap['aa:bb:cc:dd:ee:ff'], 'Office laptop');
      expect(trustedMacs, contains('aa:bb:cc:dd:ee:ff'));
      expect(rows, hasLength(1));
      expect(rows.single['last_known_ip'], '192.168.1.55');
      expect(rows.single['is_trusted'], 1);
    },
  );

  test(
    'ignores invalid mac addresses and blank ip values when recording seen devices',
    () async {
      await repository.recordSeenDevices(<String, String>{
        'invalid-mac': '192.168.1.10',
        'AA-BB-CC-DD-EE-FF': '   ',
      });

      final rows = await database.query(AppDatabase.knownDevicesTable);

      expect(rows, isEmpty);
    },
  );

  test(
    'persists peer identity binding alongside normalized known-device metadata',
    () async {
      const mac = 'AA-BB-CC-DD-EE-FF';

      await repository.setPeerIdentity(
        macAddress: mac,
        peerId: 'LN-PEER-ALICE',
        lastKnownIp: '192.168.1.80',
      );

      final peerIdMap = await repository.loadPeerIdMap();
      final lastKnownIps = await repository.loadLastKnownIpMap();
      final rows = await database.query(
        AppDatabase.knownDevicesTable,
        where: 'mac_address = ?',
        whereArgs: <Object>['aa:bb:cc:dd:ee:ff'],
      );

      expect(peerIdMap['aa:bb:cc:dd:ee:ff'], 'LN-PEER-ALICE');
      expect(lastKnownIps['aa:bb:cc:dd:ee:ff'], '192.168.1.80');
      expect(rows.single['peer_id'], 'LN-PEER-ALICE');
    },
  );
}

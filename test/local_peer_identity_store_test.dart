import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/application/local_peer_identity_store.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late LocalPeerIdentityStore store;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_local_peer_identity_',
    );
    store = LocalPeerIdentityStore(database: harness.database);
    database = await harness.database.database;
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'loadOrCreateLocalPeerId persists current app_settings key semantics',
    () async {
      final generated = await store.loadOrCreateLocalPeerId();
      expect(generated, startsWith('LN-'));

      final storedRows = await database.query(
        AppDatabase.appSettingsTable,
        where: 'setting_key = ?',
        whereArgs: const <Object>[LocalPeerIdentityStore.localPeerIdKey],
      );
      expect(storedRows, hasLength(1));
      expect(storedRows.single['setting_value'], generated);

      await database.insert(AppDatabase.appSettingsTable, <String, Object>{
        'setting_key': LocalPeerIdentityStore.localPeerIdKey,
        'setting_value': '  LN-fixed-peer  ',
        'updated_at': 123,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final reused = await store.loadOrCreateLocalPeerId();
      expect(reused, 'LN-fixed-peer');
    },
  );

  test(
    'getLocalPeerId trims stored values and treats blank rows as absent',
    () async {
      expect(await store.getLocalPeerId(), isNull);

      await database.insert(AppDatabase.appSettingsTable, <String, Object>{
        'setting_key': LocalPeerIdentityStore.localPeerIdKey,
        'setting_value': '   ',
        'updated_at': 123,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      expect(await store.getLocalPeerId(), isNull);

      await database.insert(AppDatabase.appSettingsTable, <String, Object>{
        'setting_key': LocalPeerIdentityStore.localPeerIdKey,
        'setting_value': '  LN-trimmed  ',
        'updated_at': 456,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      expect(await store.getLocalPeerId(), 'LN-trimmed');
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late FriendRepository repository;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_friends_');
    repository = FriendRepository(database: harness.database);
    database = await harness.database.database;
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'loadOrCreateLocalPeerId persists current app_settings key semantics',
    () async {
      final generated = await repository.loadOrCreateLocalPeerId();
      expect(generated, startsWith('LN-'));

      final storedRows = await database.query(
        AppDatabase.appSettingsTable,
        where: 'setting_key = ?',
        whereArgs: <Object>['local_peer_id'],
      );
      expect(storedRows, hasLength(1));
      expect(storedRows.single['setting_value'], generated);

      await database.insert(AppDatabase.appSettingsTable, <String, Object>{
        'setting_key': 'local_peer_id',
        'setting_value': '  LN-fixed-peer  ',
        'updated_at': 123,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final reused = await repository.loadOrCreateLocalPeerId();
      expect(reused, 'LN-fixed-peer');
    },
  );

  test(
    'stores, orders, toggles, and removes friend endpoint records',
    () async {
      await repository.upsertFriend(
        friendId: 'older',
        displayName: 'Older peer',
        endpointHost: '10.0.0.10',
        endpointPort: 40404,
        isEnabled: true,
      );
      await repository.upsertFriend(
        friendId: 'newer',
        displayName: 'Newer peer',
        endpointHost: '10.0.0.11',
        endpointPort: 50505,
        isEnabled: true,
      );

      await repository.setFriendEnabled(friendId: 'older', isEnabled: false);
      final listed = await repository.listFriends();

      expect(listed.map((peer) => peer.friendId), <String>['newer', 'older']);
      final older = listed.last;
      expect(older.isEnabled, isFalse);
      expect(older.endpointHost, '10.0.0.10');
      expect(older.endpointPort, 40404);

      await repository.removeFriend('newer');
      final afterRemoval = await repository.listFriends();
      expect(afterRemoval.map((peer) => peer.friendId), <String>['older']);
    },
  );
}

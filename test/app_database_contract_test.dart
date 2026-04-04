import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:sqflite/sqflite.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late Database database;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_app_db_');
    database = await harness.database.database;
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'creates all persistence anchor tables with current key columns',
    () async {
      expect(AppDatabase.schemaVersion, 7);

      final tables = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
    ''');
      final tableNames = tables
          .map((row) => row['name'] as String)
          .where((name) => !name.startsWith('sqlite_'))
          .toSet();

      expect(
        tableNames,
        containsAll(<String>{
          AppDatabase.knownDevicesTable,
          AppDatabase.sharedFolderCachesTable,
          AppDatabase.transferHistoryTable,
          AppDatabase.appSettingsTable,
          AppDatabase.friendsTable,
          AppDatabase.clipboardHistoryTable,
        }),
      );

      expect(
        await _columnNames(database, AppDatabase.knownDevicesTable),
        containsAll(<String>[
          'mac_address',
          'peer_id',
          'alias_name',
          'is_trusted',
          'last_known_ip',
          'last_seen_at',
          'updated_at',
        ]),
      );
      expect(
        await _columnNames(database, AppDatabase.sharedFolderCachesTable),
        containsAll(<String>[
          'cache_id',
          'role',
          'owner_mac_address',
          'peer_mac_address',
          'root_path',
          'display_name',
          'index_file_path',
          'item_count',
          'total_bytes',
          'updated_at',
        ]),
      );
      expect(
        await _columnNames(database, AppDatabase.transferHistoryTable),
        containsAll(<String>[
          'id',
          'request_id',
          'direction',
          'peer_name',
          'peer_ip',
          'root_path',
          'saved_paths_json',
          'file_count',
          'total_bytes',
          'status',
          'created_at',
        ]),
      );
      expect(
        await _columnNames(database, AppDatabase.appSettingsTable),
        containsAll(<String>['setting_key', 'setting_value', 'updated_at']),
      );
      expect(
        await _columnNames(database, AppDatabase.friendsTable),
        containsAll(<String>[
          'friend_id',
          'display_name',
          'endpoint_host',
          'endpoint_port',
          'is_enabled',
          'updated_at',
        ]),
      );
      expect(
        await _columnNames(database, AppDatabase.clipboardHistoryTable),
        containsAll(<String>[
          'id',
          'entry_type',
          'content_hash',
          'text_value',
          'image_path',
          'created_at',
        ]),
      );
    },
  );

  test(
    'creates current contract indexes for discovery, cache, history, and clipboard tables',
    () async {
      final indexes = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'index'
    ''');
      final indexNames = indexes
          .map((row) => row['name'] as String)
          .where((name) => !name.startsWith('sqlite_'))
          .toSet();

      expect(
        indexNames,
        containsAll(<String>{
          'idx_known_devices_last_seen',
          'idx_shared_folder_caches_owner',
          'idx_transfer_history_created',
          'idx_friends_enabled',
          'idx_clipboard_history_created',
          'idx_clipboard_history_hash',
        }),
      );
    },
  );
}

Future<List<String>> _columnNames(Database database, String tableName) async {
  final rows = await database.rawQuery('PRAGMA table_info($tableName)');
  return rows.map((row) => row['name'] as String).toList(growable: false);
}

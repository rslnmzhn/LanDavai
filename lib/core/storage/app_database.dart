import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String knownDevicesTable = 'known_devices';
  static const String sharedFolderCachesTable = 'shared_folder_caches';
  static const String transferHistoryTable = 'transfer_history';
  static const String appSettingsTable = 'app_settings';
  static const String friendsTable = 'friends';
  static const String clipboardHistoryTable = 'clipboard_history';
  static const int schemaVersion = 7;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final dbFactory = _resolveFactory();
    final dbPath = await _resolveDatabasePath();
    _database = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _runMigrations(db, oldVersion, newVersion);
        },
      ),
    );
    return _database!;
  }

  Future<Directory> resolveSharedCacheDirectory() async {
    final baseDir = await _resolveBaseDirectory();
    final cacheDir = Directory(p.join(baseDir.path, 'shared_folder_caches'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  Future<Directory> resolveSharedThumbnailDirectory() async {
    final cacheDir = await resolveSharedCacheDirectory();
    final thumbnailDir = Directory(p.join(cacheDir.path, 'thumbnails'));
    if (!await thumbnailDir.exists()) {
      await thumbnailDir.create(recursive: true);
    }
    return thumbnailDir;
  }

  Future<void> close() async {
    if (_database == null) {
      return;
    }

    await _database!.close();
    _database = null;
  }

  DatabaseFactory _resolveFactory() {
    if (Platform.isLinux || Platform.isWindows) {
      sqfliteFfiInit();
      return databaseFactoryFfi;
    }
    return sqflite.databaseFactory;
  }

  Future<String> _resolveDatabasePath() async {
    final baseDir = await _resolveBaseDirectory();
    return p.join(baseDir.path, 'landa.sqlite');
  }

  Future<Directory> _resolveBaseDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final appDir = Directory(p.join(supportDir.path, 'Landa'));
    if (!await appDir.exists()) {
      await appDir.create(recursive: true);
    }
    return appDir;
  }

  Future<void> _createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $knownDevicesTable (
        mac_address TEXT PRIMARY KEY,
        peer_id TEXT,
        alias_name TEXT,
        is_trusted INTEGER NOT NULL DEFAULT 0,
        last_known_ip TEXT,
        last_seen_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE $sharedFolderCachesTable (
        cache_id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        owner_mac_address TEXT NOT NULL,
        peer_mac_address TEXT,
        root_path TEXT NOT NULL,
        display_name TEXT NOT NULL,
        index_file_path TEXT NOT NULL,
        item_count INTEGER NOT NULL,
        total_bytes INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_known_devices_last_seen
      ON $knownDevicesTable(last_seen_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX idx_shared_folder_caches_owner
      ON $sharedFolderCachesTable(owner_mac_address, peer_mac_address)
    ''');
    await _createTransferHistoryTable(db);
    await _createAppSettingsTable(db);
    await _createFriendsTable(db);
    await _createClipboardHistoryTable(db);
  }

  Future<void> _runMigrations(
    DatabaseExecutor db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2 && newVersion >= 2) {
      await db.execute(
        'ALTER TABLE $knownDevicesTable '
        'ADD COLUMN is_trusted INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (oldVersion < 3 && newVersion >= 3) {
      await _createTransferHistoryTable(db);
    }

    if (oldVersion < 4 && newVersion >= 4) {
      await _createAppSettingsTable(db);
    }

    if (oldVersion < 5 && newVersion >= 5) {
      await _createFriendsTable(db);
    }

    if (oldVersion < 6 && newVersion >= 6) {
      await _createClipboardHistoryTable(db);
    }

    if (oldVersion < 7 && newVersion >= 7) {
      await db.execute(
        'ALTER TABLE $knownDevicesTable '
        'ADD COLUMN peer_id TEXT',
      );
    }
  }

  Future<void> _createTransferHistoryTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $transferHistoryTable (
        id TEXT PRIMARY KEY,
        request_id TEXT,
        direction TEXT NOT NULL,
        peer_name TEXT NOT NULL,
        peer_ip TEXT,
        root_path TEXT NOT NULL,
        saved_paths_json TEXT NOT NULL,
        file_count INTEGER NOT NULL,
        total_bytes INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transfer_history_created
      ON $transferHistoryTable(created_at DESC)
    ''');
  }

  Future<void> _createAppSettingsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $appSettingsTable (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _createClipboardHistoryTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $clipboardHistoryTable (
        id TEXT PRIMARY KEY,
        entry_type TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        text_value TEXT,
        image_path TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clipboard_history_created
      ON $clipboardHistoryTable(created_at DESC)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_clipboard_history_hash
      ON $clipboardHistoryTable(content_hash)
    ''');
  }

  Future<void> _createFriendsTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $friendsTable (
        friend_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        endpoint_host TEXT NOT NULL,
        endpoint_port INTEGER NOT NULL,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_friends_enabled
      ON $friendsTable(is_enabled, updated_at DESC)
    ''');
  }
}

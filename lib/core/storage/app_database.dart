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
  static const int schemaVersion = 3;

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
}



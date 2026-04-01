import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../../core/storage/app_database.dart';
import '../../discovery/data/device_alias_repository.dart';
import '../domain/shared_folder_cache.dart';
import 'shared_cache_record_store.dart';

class SharedFolderCacheRepository implements SharedCacheRecordStore {
  SharedFolderCacheRepository({required AppDatabase database})
    : _database = database;

  final AppDatabase _database;

  @override
  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) async {
    final db = await _database.database;
    final filters = <String>[];
    final args = <Object?>[];

    if (role != null) {
      filters.add('role = ?');
      args.add(role.name);
    }
    if (ownerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(ownerMacAddress);
      if (normalized != null) {
        filters.add('owner_mac_address = ?');
        args.add(normalized);
      }
    }
    if (peerMacAddress != null) {
      final normalized = DeviceAliasRepository.normalizeMac(peerMacAddress);
      if (normalized != null) {
        filters.add('peer_mac_address = ?');
        args.add(normalized);
      }
    }

    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(SharedFolderCacheRecord.fromDbMap).toList(growable: false);
  }

  @override
  Future<SharedFolderCacheRecord?> findCacheById(String cacheId) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return SharedFolderCacheRecord.fromDbMap(rows.first);
  }

  @override
  Future<SharedFolderCacheRecord?> findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) {
    return _findOwnerCacheByRootPath(
      ownerMacAddress: ownerMacAddress,
      rootPath: rootPath,
    );
  }

  @override
  Future<void> upsertCacheRecord(SharedFolderCacheRecord record) {
    return _upsertRecord(record);
  }

  @override
  Future<void> deleteCacheRecord(String cacheId) async {
    final db = await _database.database;
    await db.delete(
      AppDatabase.sharedFolderCachesTable,
      where: 'cache_id = ?',
      whereArgs: <Object?>[cacheId],
    );
  }

  @override
  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress}) async {
    final ownerMac = _normalizeOrThrow(
      ownerMacAddress,
      field: 'ownerMacAddress',
    );
    final db = await _database.database;
    return db.update(
      AppDatabase.sharedFolderCachesTable,
      <String, Object?>{'owner_mac_address': ownerMac},
      where: 'role = ? AND owner_mac_address != ?',
      whereArgs: <Object?>[SharedFolderCacheRole.owner.name, ownerMac],
    );
  }

  Future<SharedFolderCacheRecord?> _findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.sharedFolderCachesTable,
      where: 'role = ? AND owner_mac_address = ?',
      whereArgs: <Object?>[SharedFolderCacheRole.owner.name, ownerMacAddress],
    );
    if (rows.isEmpty) {
      return null;
    }

    final target = _normalizeComparablePath(rootPath);
    for (final row in rows) {
      final record = SharedFolderCacheRecord.fromDbMap(row);
      if (record.rootPath.startsWith('selection://')) {
        continue;
      }
      if (_normalizeComparablePath(record.rootPath) == target) {
        return record;
      }
    }
    return null;
  }

  Future<void> _upsertRecord(SharedFolderCacheRecord record) async {
    final db = await _database.database;
    await db.insert(
      AppDatabase.sharedFolderCachesTable,
      record.toDbMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  String _normalizeComparablePath(String rawPath) {
    final normalized = p.normalize(rawPath).replaceAll('\\', '/');
    if (Platform.isWindows) {
      return normalized.toLowerCase();
    }
    return normalized;
  }

  String _normalizeOrThrow(String macAddress, {required String field}) {
    final normalized = DeviceAliasRepository.normalizeMac(macAddress);
    if (normalized == null) {
      throw ArgumentError('Invalid $field: $macAddress');
    }
    return normalized;
  }
}
 
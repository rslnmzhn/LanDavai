import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../domain/friend_peer.dart';

class FriendRepository {
  FriendRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  Future<List<FriendPeer>> listFriends() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.friendsTable,
      orderBy: 'display_name COLLATE NOCASE ASC, friend_id COLLATE NOCASE ASC',
    );

    return rows.map(_mapRow).toList(growable: false);
  }

  Future<void> upsertFriend({
    required String friendId,
    required String displayName,
    required String endpointHost,
    required int endpointPort,
    required bool isEnabled,
  }) async {
    final normalizedId = friendId.trim();
    final normalizedName = displayName.trim();
    final normalizedHost = endpointHost.trim();
    if (normalizedId.isEmpty) {
      throw ArgumentError('friendId is required');
    }
    if (normalizedHost.isEmpty) {
      throw ArgumentError('endpointHost is required');
    }
    if (endpointPort <= 0 || endpointPort > 65535) {
      throw ArgumentError('endpointPort must be in 1..65535');
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(AppDatabase.friendsTable, <String, Object>{
      'friend_id': normalizedId,
      'display_name': normalizedName.isEmpty ? normalizedId : normalizedName,
      'endpoint_host': normalizedHost,
      'endpoint_port': endpointPort,
      'is_enabled': isEnabled ? 1 : 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeFriend(String friendId) async {
    final normalizedId = friendId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final db = await _database.database;
    await db.delete(
      AppDatabase.friendsTable,
      where: 'friend_id = ?',
      whereArgs: <Object>[normalizedId],
    );
  }

  Future<void> setFriendEnabled({
    required String friendId,
    required bool isEnabled,
  }) async {
    final normalizedId = friendId.trim();
    if (normalizedId.isEmpty) {
      return;
    }
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      AppDatabase.friendsTable,
      <String, Object>{'is_enabled': isEnabled ? 1 : 0, 'updated_at': now},
      where: 'friend_id = ?',
      whereArgs: <Object>[normalizedId],
    );
  }

  FriendPeer _mapRow(Map<String, Object?> row) {
    return FriendPeer(
      friendId: (row['friend_id'] as String?) ?? '',
      displayName: (row['display_name'] as String?) ?? '',
      endpointHost: (row['endpoint_host'] as String?) ?? '',
      endpointPort: (row['endpoint_port'] as int?) ?? 40404,
      isEnabled: ((row['is_enabled'] as int?) ?? 0) == 1,
      updatedAtMs: (row['updated_at'] as int?) ?? 0,
    );
  }
}

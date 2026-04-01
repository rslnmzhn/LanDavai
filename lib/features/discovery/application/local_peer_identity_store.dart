import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';

class LocalPeerIdentityStore {
  LocalPeerIdentityStore({required AppDatabase database})
    : _database = database;

  static const String localPeerIdKey = 'local_peer_id';

  final AppDatabase _database;

  Future<String?> getLocalPeerId() async {
    final db = await _database.database;
    final row = await db.query(
      AppDatabase.appSettingsTable,
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: const <Object>[localPeerIdKey],
      limit: 1,
    );
    if (row.isEmpty) {
      return null;
    }
    final existing = row.first['setting_value'] as String?;
    final value = existing?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<String> loadOrCreateLocalPeerId() async {
    final existing = await getLocalPeerId();
    if (existing != null) {
      return existing;
    }

    final peerId = _generatePeerId();
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = await _database.database;
    await db.insert(AppDatabase.appSettingsTable, <String, Object>{
      'setting_key': localPeerIdKey,
      'setting_value': peerId,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return peerId;
  }

  String _generatePeerId() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final buffer = StringBuffer('LN-');
    for (var i = 0; i < 10; i += 1) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }
}

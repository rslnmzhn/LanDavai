import '../../../core/storage/app_database.dart';

class DeviceAliasRepository {
  DeviceAliasRepository({required AppDatabase database}) : _database = database;

  final AppDatabase _database;

  Future<void> recordSeenDevices(Map<String, String> macToIp) async {
    if (macToIp.isEmpty) {
      return;
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in macToIp.entries) {
        final mac = normalizeMac(entry.key);
        final ip = entry.value.trim();
        if (mac == null || ip.isEmpty) {
          continue;
        }

        batch.rawInsert(
          '''
            INSERT OR IGNORE INTO ${AppDatabase.knownDevicesTable}
              (mac_address, alias_name, last_known_ip, last_seen_at, updated_at)
            VALUES (?, NULL, ?, ?, ?)
          ''',
          <Object?>[mac, ip, now, now],
        );
        batch.rawUpdate(
          '''
            UPDATE ${AppDatabase.knownDevicesTable}
            SET last_known_ip = ?, last_seen_at = ?, updated_at = ?
            WHERE mac_address = ?
          ''',
          <Object?>[ip, now, now, mac],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<Map<String, String>> loadAliasMap() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.knownDevicesTable,
      columns: <String>['mac_address', 'alias_name'],
      where: 'alias_name IS NOT NULL AND LENGTH(TRIM(alias_name)) > 0',
    );

    final aliases = <String, String>{};
    for (final row in rows) {
      final mac = row['mac_address'] as String?;
      final alias = row['alias_name'] as String?;
      if (mac == null || alias == null) {
        continue;
      }
      aliases[mac] = alias.trim();
    }
    return aliases;
  }

  Future<Map<String, String>> loadLastKnownIpMap() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.knownDevicesTable,
      columns: <String>['mac_address', 'last_known_ip'],
      where: 'last_known_ip IS NOT NULL AND LENGTH(TRIM(last_known_ip)) > 0',
    );

    final lastKnownIps = <String, String>{};
    for (final row in rows) {
      final mac = row['mac_address'] as String?;
      final ip = row['last_known_ip'] as String?;
      if (mac == null || ip == null) {
        continue;
      }
      final normalizedIp = ip.trim();
      if (normalizedIp.isEmpty) {
        continue;
      }
      lastKnownIps[mac] = normalizedIp;
    }
    return lastKnownIps;
  }

  Future<Map<String, String>> loadPeerIdMap() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.knownDevicesTable,
      columns: <String>['mac_address', 'peer_id'],
      where: 'peer_id IS NOT NULL AND LENGTH(TRIM(peer_id)) > 0',
    );

    final peerIds = <String, String>{};
    for (final row in rows) {
      final mac = row['mac_address'] as String?;
      final peerId = row['peer_id'] as String?;
      if (mac == null || peerId == null) {
        continue;
      }
      final normalizedPeerId = peerId.trim();
      if (normalizedPeerId.isEmpty) {
        continue;
      }
      peerIds[mac] = normalizedPeerId;
    }
    return peerIds;
  }

  Future<Set<String>> loadTrustedMacs() async {
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.knownDevicesTable,
      columns: <String>['mac_address', 'is_trusted'],
      where: 'is_trusted = 1',
    );

    final trusted = <String>{};
    for (final row in rows) {
      final mac = row['mac_address'] as String?;
      if (mac == null) {
        continue;
      }
      trusted.add(mac);
    }
    return trusted;
  }

  Future<void> setAlias({
    required String macAddress,
    required String alias,
  }) async {
    final mac = normalizeMac(macAddress);
    if (mac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final normalizedAlias = alias.trim();
    final aliasValue = normalizedAlias.isEmpty ? null : normalizedAlias;

    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
          INSERT OR IGNORE INTO ${AppDatabase.knownDevicesTable}
            (mac_address, alias_name, last_known_ip, last_seen_at, updated_at)
          VALUES (?, NULL, NULL, ?, ?)
        ''',
        <Object?>[mac, now, now],
      );
      await txn.rawUpdate(
        '''
          UPDATE ${AppDatabase.knownDevicesTable}
          SET alias_name = ?, updated_at = ?
          WHERE mac_address = ?
        ''',
        <Object?>[aliasValue, now, mac],
      );
    });
  }

  Future<void> setTrusted({
    required String macAddress,
    required bool isTrusted,
  }) async {
    final mac = normalizeMac(macAddress);
    if (mac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final trustedValue = isTrusted ? 1 : 0;

    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
          INSERT OR IGNORE INTO ${AppDatabase.knownDevicesTable}
            (mac_address, alias_name, is_trusted, last_known_ip, last_seen_at, updated_at)
          VALUES (?, NULL, ?, NULL, ?, ?)
        ''',
        <Object?>[mac, trustedValue, now, now],
      );
      await txn.rawUpdate(
        '''
          UPDATE ${AppDatabase.knownDevicesTable}
          SET is_trusted = ?, updated_at = ?
          WHERE mac_address = ?
        ''',
        <Object?>[trustedValue, now, mac],
      );
    });
  }

  Future<void> setPeerIdentity({
    required String macAddress,
    required String peerId,
    String? lastKnownIp,
  }) async {
    final mac = normalizeMac(macAddress);
    final normalizedPeerId = peerId.trim();
    final normalizedIp = lastKnownIp?.trim();
    if (mac == null) {
      throw ArgumentError('Invalid MAC address: $macAddress');
    }
    if (normalizedPeerId.isEmpty) {
      throw ArgumentError('peerId is required');
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.rawInsert(
        '''
          INSERT OR IGNORE INTO ${AppDatabase.knownDevicesTable}
            (mac_address, peer_id, alias_name, is_trusted, last_known_ip, last_seen_at, updated_at)
          VALUES (?, ?, NULL, 0, ?, ?, ?)
        ''',
        <Object?>[mac, normalizedPeerId, normalizedIp, now, now],
      );
      if (normalizedIp != null && normalizedIp.isNotEmpty) {
        await txn.rawUpdate(
          '''
            UPDATE ${AppDatabase.knownDevicesTable}
            SET peer_id = ?, last_known_ip = ?, last_seen_at = ?, updated_at = ?
            WHERE mac_address = ?
          ''',
          <Object?>[normalizedPeerId, normalizedIp, now, now, mac],
        );
      } else {
        await txn.rawUpdate(
          '''
            UPDATE ${AppDatabase.knownDevicesTable}
            SET peer_id = ?, updated_at = ?
            WHERE mac_address = ?
          ''',
          <Object?>[normalizedPeerId, now, mac],
        );
      }
    });
  }

  static String? normalizeMac(String? macAddress) {
    if (macAddress == null) {
      return null;
    }

    final normalized = macAddress.trim().toLowerCase().replaceAll('-', ':');
    final valid = RegExp(
      r'^[0-9a-f]{2}(:[0-9a-f]{2}){5}$',
    ).hasMatch(normalized);
    if (!valid || normalized == '00:00:00:00:00:00') {
      return null;
    }
    return normalized;
  }
}

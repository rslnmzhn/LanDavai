import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';

class ConfiguredDiscoveryTargetsRepository {
  ConfiguredDiscoveryTargetsRepository({required AppDatabase database})
    : _databaseProvider = (() async => database.database);

  ConfiguredDiscoveryTargetsRepository.withDatabaseProvider({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;

  static const String _settingKey = 'configured_discovery_targets_json';

  final Future<Database> Function() _databaseProvider;

  Future<List<String>> load() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      AppDatabase.appSettingsTable,
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: <Object>[_settingKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const <String>[];
    }

    final rawValue = rows.single['setting_value'] as String?;
    if (rawValue == null || rawValue.trim().isEmpty) {
      return const <String>[];
    }

    final decoded = jsonDecode(rawValue);
    if (decoded is! List) {
      return const <String>[];
    }

    final normalized = <String>{};
    for (final value in decoded) {
      if (value is! String) {
        continue;
      }
      final ip = normalizeIpv4(value);
      if (ip != null) {
        normalized.add(ip);
      }
    }
    final result = normalized.toList(growable: false)..sort(_compareIp);
    return result;
  }

  Future<void> save(List<String> targets) async {
    final db = await _databaseProvider();
    final normalized = <String>{};
    for (final target in targets) {
      final ip = normalizeIpv4(target);
      if (ip != null) {
        normalized.add(ip);
      }
    }
    final sortedTargets = normalized.toList(growable: false)..sort(_compareIp);
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(AppDatabase.appSettingsTable, <String, Object>{
      'setting_key': _settingKey,
      'setting_value': jsonEncode(sortedTargets),
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static String? normalizeIpv4(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return null;
    }
    final parsed = InternetAddress.tryParse(value);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return null;
    }
    if (parsed.address == '0.0.0.0' ||
        parsed.address == '255.255.255.255' ||
        parsed.isLoopback ||
        parsed.isMulticast) {
      return null;
    }
    return parsed.address;
  }

  static int _compareIp(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList(growable: false);
    final bParts = b.split('.').map(int.parse).toList(growable: false);
    for (var index = 0; index < 4; index += 1) {
      final compare = aParts[index].compareTo(bParts[index]);
      if (compare != 0) {
        return compare;
      }
    }
    return 0;
  }
}

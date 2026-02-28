import 'package:sqflite/sqflite.dart';

import '../../../core/storage/app_database.dart';
import '../domain/app_settings.dart';

class AppSettingsRepository {
  AppSettingsRepository({required AppDatabase database})
    : _databaseProvider = (() async => database.database);

  AppSettingsRepository.withDatabaseProvider({
    required Future<Database> Function() databaseProvider,
  }) : _databaseProvider = databaseProvider;

  final Future<Database> Function() _databaseProvider;

  static const String _backgroundScanIntervalKey = 'background_scan_seconds';
  static const String _downloadNotificationsKey =
      'download_attempt_notifications_enabled';
  static const String _minimizeToTrayKey = 'minimize_to_tray_on_close';

  Future<AppSettings> load() async {
    final db = await _databaseProvider();
    final rows = await db.query(
      AppDatabase.appSettingsTable,
      columns: <String>['setting_key', 'setting_value'],
    );

    final values = <String, String>{};
    for (final row in rows) {
      final key = row['setting_key'] as String?;
      final value = row['setting_value'] as String?;
      if (key == null || value == null) {
        continue;
      }
      values[key] = value;
    }

    final defaults = AppSettings.defaults;
    final scanSeconds =
        int.tryParse(values[_backgroundScanIntervalKey] ?? '') ??
        defaults.backgroundScanInterval.duration.inSeconds;

    return AppSettings(
      backgroundScanInterval: BackgroundScanIntervalOptionX.fromSeconds(
        scanSeconds,
      ),
      downloadAttemptNotificationsEnabled: _parseBool(
        values[_downloadNotificationsKey],
        fallback: defaults.downloadAttemptNotificationsEnabled,
      ),
      minimizeToTrayOnClose: _parseBool(
        values[_minimizeToTrayKey],
        fallback: defaults.minimizeToTrayOnClose,
      ),
    );
  }

  Future<void> save(AppSettings settings) async {
    final db = await _databaseProvider();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await _upsertSetting(
        txn: txn,
        key: _backgroundScanIntervalKey,
        value: settings.backgroundScanInterval.duration.inSeconds.toString(),
        updatedAtMs: now,
      );
      await _upsertSetting(
        txn: txn,
        key: _downloadNotificationsKey,
        value: settings.downloadAttemptNotificationsEnabled ? '1' : '0',
        updatedAtMs: now,
      );
      await _upsertSetting(
        txn: txn,
        key: _minimizeToTrayKey,
        value: settings.minimizeToTrayOnClose ? '1' : '0',
        updatedAtMs: now,
      );
    });
  }

  Future<void> _upsertSetting({
    required DatabaseExecutor txn,
    required String key,
    required String value,
    required int updatedAtMs,
  }) async {
    await txn.insert(AppDatabase.appSettingsTable, <String, Object>{
      'setting_key': key,
      'setting_value': value,
      'updated_at': updatedAtMs,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool _parseBool(String? raw, {required bool fallback}) {
    if (raw == null) {
      return fallback;
    }
    return raw == '1';
  }
}

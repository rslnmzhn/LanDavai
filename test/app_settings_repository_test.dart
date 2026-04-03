import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database database;
  late AppSettingsRepository repository;

  setUp(() async {
    sqfliteFfiInit();
    final factory = databaseFactoryFfi;
    database = await factory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE app_settings (
              setting_key TEXT PRIMARY KEY,
              setting_value TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
        },
      ),
    );
    repository = AppSettingsRepository.withDatabaseProvider(
      databaseProvider: () async => database,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('returns defaults when table is empty', () async {
    final settings = await repository.load();

    expect(
      settings.backgroundScanInterval,
      AppSettings.defaults.backgroundScanInterval,
    );
    expect(
      settings.downloadAttemptNotificationsEnabled,
      AppSettings.defaults.downloadAttemptNotificationsEnabled,
    );
    expect(
      settings.useStandardAppDownloadFolder,
      AppSettings.defaults.useStandardAppDownloadFolder,
    );
    expect(
      settings.minimizeToTrayOnClose,
      AppSettings.defaults.minimizeToTrayOnClose,
    );
    expect(settings.isLeftHandedMode, AppSettings.defaults.isLeftHandedMode);
    expect(settings.videoLinkPassword, AppSettings.defaults.videoLinkPassword);
    expect(
      settings.previewCacheMaxSizeGb,
      AppSettings.defaults.previewCacheMaxSizeGb,
    );
    expect(
      settings.previewCacheMaxAgeDays,
      AppSettings.defaults.previewCacheMaxAgeDays,
    );
    expect(
      settings.clipboardHistoryMaxEntries,
      AppSettings.defaults.clipboardHistoryMaxEntries,
    );
    expect(
      settings.recacheParallelWorkers,
      AppSettings.defaults.recacheParallelWorkers,
    );
  });

  test('persists and restores all app settings', () async {
    const expected = AppSettings(
      backgroundScanInterval: BackgroundScanIntervalOption.fifteenMinutes,
      downloadAttemptNotificationsEnabled: false,
      useStandardAppDownloadFolder: false,
      minimizeToTrayOnClose: false,
      isLeftHandedMode: true,
      videoLinkPassword: 'secret123',
      previewCacheMaxSizeGb: 4,
      previewCacheMaxAgeDays: 10,
      clipboardHistoryMaxEntries: 42,
      recacheParallelWorkers: 6,
    );

    await repository.save(expected);
    final restored = await repository.load();

    expect(restored.backgroundScanInterval, expected.backgroundScanInterval);
    expect(
      restored.downloadAttemptNotificationsEnabled,
      expected.downloadAttemptNotificationsEnabled,
    );
    expect(
      restored.useStandardAppDownloadFolder,
      expected.useStandardAppDownloadFolder,
    );
    expect(restored.minimizeToTrayOnClose, expected.minimizeToTrayOnClose);
    expect(restored.isLeftHandedMode, expected.isLeftHandedMode);
    expect(restored.videoLinkPassword, expected.videoLinkPassword);
    expect(restored.previewCacheMaxSizeGb, expected.previewCacheMaxSizeGb);
    expect(restored.previewCacheMaxAgeDays, expected.previewCacheMaxAgeDays);
    expect(
      restored.clipboardHistoryMaxEntries,
      expected.clipboardHistoryMaxEntries,
    );
    expect(restored.recacheParallelWorkers, expected.recacheParallelWorkers);
  });
}

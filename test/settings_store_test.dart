import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/storage/app_database.dart';
import 'package:landa/features/discovery/data/friend_repository.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/settings/domain/app_settings.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late AppSettingsRepository repository;
  late SettingsStore store;
  late FriendRepository friendRepository;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_settings_store_',
    );
    repository = AppSettingsRepository(database: harness.database);
    store = SettingsStore(appSettingsRepository: repository);
    friendRepository = FriendRepository(database: harness.database);
  });

  tearDown(() async {
    store.dispose();
    await harness.dispose();
  });

  test(
    'load ignores local_peer_id contamination when no app settings exist',
    () async {
      await friendRepository.loadOrCreateLocalPeerId();

      await store.load();

      expect(
        store.settings.backgroundScanInterval,
        AppSettings.defaults.backgroundScanInterval,
      );
      expect(
        store.settings.downloadAttemptNotificationsEnabled,
        AppSettings.defaults.downloadAttemptNotificationsEnabled,
      );
      expect(
        store.settings.minimizeToTrayOnClose,
        AppSettings.defaults.minimizeToTrayOnClose,
      );
      expect(
        store.settings.isLeftHandedMode,
        AppSettings.defaults.isLeftHandedMode,
      );
      expect(
        store.settings.videoLinkPassword,
        AppSettings.defaults.videoLinkPassword,
      );
      expect(
        store.settings.previewCacheMaxSizeGb,
        AppSettings.defaults.previewCacheMaxSizeGb,
      );
      expect(
        store.settings.previewCacheMaxAgeDays,
        AppSettings.defaults.previewCacheMaxAgeDays,
      );
      expect(
        store.settings.clipboardHistoryMaxEntries,
        AppSettings.defaults.clipboardHistoryMaxEntries,
      );
      expect(
        store.settings.recacheParallelWorkers,
        AppSettings.defaults.recacheParallelWorkers,
      );
    },
  );

  test(
    'save preserves existing local_peer_id row while keeping app_settings semantics unchanged',
    () async {
      final localPeerId = await friendRepository.loadOrCreateLocalPeerId();
      const expected = AppSettings(
        backgroundScanInterval: BackgroundScanIntervalOption.fifteenMinutes,
        downloadAttemptNotificationsEnabled: false,
        minimizeToTrayOnClose: false,
        isLeftHandedMode: true,
        videoLinkPassword: 'shared-secret',
        previewCacheMaxSizeGb: 4,
        previewCacheMaxAgeDays: 10,
        clipboardHistoryMaxEntries: 42,
        recacheParallelWorkers: 6,
      );

      await store.save(expected);
      await store.load();

      final localPeerRows = await (await harness.database.database).query(
        AppDatabase.appSettingsTable,
        columns: <String>['setting_value'],
        where: 'setting_key = ?',
        whereArgs: <Object>['local_peer_id'],
        limit: 1,
      );

      expect(
        store.settings.backgroundScanInterval,
        expected.backgroundScanInterval,
      );
      expect(
        store.settings.downloadAttemptNotificationsEnabled,
        expected.downloadAttemptNotificationsEnabled,
      );
      expect(
        store.settings.minimizeToTrayOnClose,
        expected.minimizeToTrayOnClose,
      );
      expect(store.settings.isLeftHandedMode, expected.isLeftHandedMode);
      expect(store.settings.videoLinkPassword, expected.videoLinkPassword);
      expect(
        store.settings.previewCacheMaxSizeGb,
        expected.previewCacheMaxSizeGb,
      );
      expect(
        store.settings.previewCacheMaxAgeDays,
        expected.previewCacheMaxAgeDays,
      );
      expect(
        store.settings.clipboardHistoryMaxEntries,
        expected.clipboardHistoryMaxEntries,
      );
      expect(
        store.settings.recacheParallelWorkers,
        expected.recacheParallelWorkers,
      );
      expect(localPeerRows, hasLength(1));
      expect(localPeerRows.single['setting_value'], localPeerId);
    },
  );
}

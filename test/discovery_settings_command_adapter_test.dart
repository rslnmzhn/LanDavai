import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/discovery_settings_command_adapter.dart';
import 'package:landa/features/settings/application/settings_store.dart';
import 'package:landa/features/settings/data/app_settings_repository.dart';
import 'package:landa/features/settings/domain/app_settings.dart';

void main() {
  group('DiscoverySettingsCommandAdapter', () {
    test(
      'saves changed background scan interval and reports success',
      () async {
        final store = SettingsStore(
          appSettingsRepository: _MemoryAppSettingsRepository(),
        );
        await store.load();

        final changedSettings = <AppSettings>[];
        final adapter = DiscoverySettingsCommandAdapter(
          settingsStore: store,
          onSettingsChanged: changedSettings.add,
          onError: (_) => fail('unexpected settings save error'),
        );

        await adapter.updateBackgroundScanInterval(
          BackgroundScanIntervalOption.tenSeconds,
        );

        expect(
          store.settings.backgroundScanInterval,
          BackgroundScanIntervalOption.tenSeconds,
        );
        expect(changedSettings, hasLength(1));
        expect(
          changedSettings.single.backgroundScanInterval,
          BackgroundScanIntervalOption.tenSeconds,
        );
      },
    );

    test('does not save unchanged values', () async {
      final repository = _MemoryAppSettingsRepository();
      final store = SettingsStore(appSettingsRepository: repository);
      await store.load();

      var changes = 0;
      final adapter = DiscoverySettingsCommandAdapter(
        settingsStore: store,
        onSettingsChanged: (_) => changes += 1,
        onError: (_) => fail('unexpected settings save error'),
      );

      await adapter.updateBackgroundScanInterval(
        AppSettings.defaults.backgroundScanInterval,
      );

      expect(repository.saveCount, 0);
      expect(changes, 0);
    });

    test('normalizes numeric and string setting values before save', () async {
      final store = SettingsStore(
        appSettingsRepository: _MemoryAppSettingsRepository(),
      );
      await store.load();

      final adapter = DiscoverySettingsCommandAdapter(
        settingsStore: store,
        onSettingsChanged: (_) {},
        onError: (_) => fail('unexpected settings save error'),
      );

      await adapter.setVideoLinkPassword('  secret  ');
      await adapter.setPreviewCacheMaxSizeGb(-10);
      await adapter.setPreviewCacheMaxAgeDays(-5);
      await adapter.setClipboardHistoryMaxEntries(-1);
      await adapter.setRecacheParallelWorkers(-3);
      await adapter.setDebugLogRetainedLines(0);

      expect(store.settings.videoLinkPassword, 'secret');
      expect(store.settings.previewCacheMaxSizeGb, 0);
      expect(store.settings.previewCacheMaxAgeDays, 0);
      expect(store.settings.clipboardHistoryMaxEntries, 0);
      expect(store.settings.recacheParallelWorkers, 0);
      expect(
        store.settings.debugLogRetainedLines,
        AppSettings.defaults.debugLogRetainedLines,
      );
    });

    test('reports save errors without claiming success', () async {
      final store = SettingsStore(
        appSettingsRepository: _MemoryAppSettingsRepository(throwOnSave: true),
      );
      await store.load();

      Object? reportedError;
      var changes = 0;
      final adapter = DiscoverySettingsCommandAdapter(
        settingsStore: store,
        onSettingsChanged: (_) => changes += 1,
        onError: (error) => reportedError = error,
      );

      await adapter.setMinimizeToTrayOnClose(
        !AppSettings.defaults.minimizeToTrayOnClose,
      );

      expect(reportedError, isA<StateError>());
      expect(changes, 0);
      expect(
        store.settings.minimizeToTrayOnClose,
        AppSettings.defaults.minimizeToTrayOnClose,
      );
    });
  });
}

class _MemoryAppSettingsRepository extends AppSettingsRepository {
  _MemoryAppSettingsRepository({this.throwOnSave = false})
    : super.withDatabaseProvider(
        databaseProvider: () => throw UnsupportedError('database not used'),
      );

  final bool throwOnSave;
  AppSettings _settings = AppSettings.defaults;
  int saveCount = 0;

  @override
  Future<AppSettings> load() async => _settings;

  @override
  Future<void> save(AppSettings settings) async {
    if (throwOnSave) {
      throw StateError('save failed');
    }
    saveCount += 1;
    _settings = settings;
  }
}

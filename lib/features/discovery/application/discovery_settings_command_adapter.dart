import 'dart:async';

import '../../settings/application/settings_store.dart';
import '../../settings/domain/app_settings.dart';

typedef DiscoverySettingsChanged = void Function(AppSettings settings);
typedef DiscoverySettingsErrorHandler = void Function(Object error);

class DiscoverySettingsCommandAdapter {
  DiscoverySettingsCommandAdapter({
    required SettingsStore settingsStore,
    required DiscoverySettingsChanged onSettingsChanged,
    required DiscoverySettingsErrorHandler onError,
  }) : _settingsStore = settingsStore,
       _onSettingsChanged = onSettingsChanged,
       _onError = onError;

  final SettingsStore _settingsStore;
  final DiscoverySettingsChanged _onSettingsChanged;
  final DiscoverySettingsErrorHandler _onError;

  AppSettings get settings => _settingsStore.settings;

  Future<void> updateBackgroundScanInterval(
    BackgroundScanIntervalOption interval,
  ) {
    return _saveIfChanged(
      (settings) => settings.backgroundScanInterval == interval,
      (settings) => settings.copyWith(backgroundScanInterval: interval),
    );
  }

  Future<void> setDownloadAttemptNotificationsEnabled(bool enabled) {
    return _saveIfChanged(
      (settings) => settings.downloadAttemptNotificationsEnabled == enabled,
      (settings) =>
          settings.copyWith(downloadAttemptNotificationsEnabled: enabled),
    );
  }

  Future<void> setUseStandardAppDownloadFolder(bool enabled) {
    return _saveIfChanged(
      (settings) => settings.useStandardAppDownloadFolder == enabled,
      (settings) => settings.copyWith(useStandardAppDownloadFolder: enabled),
    );
  }

  Future<void> setMinimizeToTrayOnClose(bool enabled) {
    return _saveIfChanged(
      (settings) => settings.minimizeToTrayOnClose == enabled,
      (settings) => settings.copyWith(minimizeToTrayOnClose: enabled),
    );
  }

  Future<void> setLeftHandedMode(bool enabled) {
    return _saveIfChanged(
      (settings) => settings.isLeftHandedMode == enabled,
      (settings) => settings.copyWith(isLeftHandedMode: enabled),
    );
  }

  Future<void> setVideoLinkPassword(String value) {
    final normalized = value.trim();
    return _saveIfChanged(
      (settings) => settings.videoLinkPassword == normalized,
      (settings) => settings.copyWith(videoLinkPassword: normalized),
    );
  }

  Future<void> setPreviewCacheMaxSizeGb(int value) {
    final normalized = value < 0 ? 0 : value;
    return _saveIfChanged(
      (settings) => settings.previewCacheMaxSizeGb == normalized,
      (settings) => settings.copyWith(previewCacheMaxSizeGb: normalized),
    );
  }

  Future<void> setPreviewCacheMaxAgeDays(int value) {
    final normalized = value < 0 ? 0 : value;
    return _saveIfChanged(
      (settings) => settings.previewCacheMaxAgeDays == normalized,
      (settings) => settings.copyWith(previewCacheMaxAgeDays: normalized),
    );
  }

  Future<void> setClipboardHistoryMaxEntries(int value) {
    final normalized = value < 0 ? 0 : value;
    return _saveIfChanged(
      (settings) => settings.clipboardHistoryMaxEntries == normalized,
      (settings) => settings.copyWith(clipboardHistoryMaxEntries: normalized),
    );
  }

  Future<void> setRecacheParallelWorkers(int value) {
    final normalized = value < 0 ? 0 : value;
    return _saveIfChanged(
      (settings) => settings.recacheParallelWorkers == normalized,
      (settings) => settings.copyWith(recacheParallelWorkers: normalized),
    );
  }

  Future<void> setDebugLogRetainedLines(int value) {
    final normalized = value <= 0
        ? AppSettings.defaults.debugLogRetainedLines
        : value;
    return _saveIfChanged(
      (settings) => settings.debugLogRetainedLines == normalized,
      (settings) => settings.copyWith(debugLogRetainedLines: normalized),
    );
  }

  Future<void> _saveIfChanged(
    bool Function(AppSettings settings) isUnchanged,
    AppSettings Function(AppSettings settings) buildNextSettings,
  ) async {
    final current = settings;
    if (isUnchanged(current)) {
      return;
    }

    try {
      await _settingsStore.save(buildNextSettings(current));
      _onSettingsChanged(_settingsStore.settings);
    } catch (error) {
      _onError(error);
    }
  }
}

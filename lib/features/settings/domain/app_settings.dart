import 'dart:core';

enum BackgroundScanIntervalOption {
  tenSeconds,
  thirtySeconds,
  fiveMinutes,
  fifteenMinutes,
  oneHour,
}

extension BackgroundScanIntervalOptionX on BackgroundScanIntervalOption {
  Duration get duration {
    switch (this) {
      case BackgroundScanIntervalOption.tenSeconds:
        return const Duration(seconds: 10);
      case BackgroundScanIntervalOption.thirtySeconds:
        return const Duration(seconds: 30);
      case BackgroundScanIntervalOption.fiveMinutes:
        return const Duration(minutes: 5);
      case BackgroundScanIntervalOption.fifteenMinutes:
        return const Duration(minutes: 15);
      case BackgroundScanIntervalOption.oneHour:
        return const Duration(hours: 1);
    }
  }

  String get label {
    switch (this) {
      case BackgroundScanIntervalOption.tenSeconds:
        return '10 секунд';
      case BackgroundScanIntervalOption.thirtySeconds:
        return '30 секунд';
      case BackgroundScanIntervalOption.fiveMinutes:
        return '5 минут';
      case BackgroundScanIntervalOption.fifteenMinutes:
        return '15 минут';
      case BackgroundScanIntervalOption.oneHour:
        return '1 час';
    }
  }

  static BackgroundScanIntervalOption fromSeconds(int seconds) {
    switch (seconds) {
      case 10:
        return BackgroundScanIntervalOption.tenSeconds;
      case 30:
        return BackgroundScanIntervalOption.thirtySeconds;
      case 300:
        return BackgroundScanIntervalOption.fiveMinutes;
      case 900:
        return BackgroundScanIntervalOption.fifteenMinutes;
      case 3600:
        return BackgroundScanIntervalOption.oneHour;
      default:
        return AppSettings.defaults.backgroundScanInterval;
    }
  }
}

class AppSettings {
  const AppSettings({
    required this.backgroundScanInterval,
    required this.downloadAttemptNotificationsEnabled,
    required this.minimizeToTrayOnClose,
    required this.isLeftHandedMode,
    required this.videoLinkPassword,
    required this.previewCacheMaxSizeGb,
    required this.previewCacheMaxAgeDays,
    required this.clipboardHistoryMaxEntries,
    required this.recacheParallelWorkers,
  });

  final BackgroundScanIntervalOption backgroundScanInterval;
  final bool downloadAttemptNotificationsEnabled;
  final bool minimizeToTrayOnClose;
  final bool isLeftHandedMode;
  final String videoLinkPassword;
  final int previewCacheMaxSizeGb;
  final int previewCacheMaxAgeDays;
  final int clipboardHistoryMaxEntries;
  final int recacheParallelWorkers;

  static const AppSettings defaults = AppSettings(
    backgroundScanInterval: BackgroundScanIntervalOption.fiveMinutes,
    downloadAttemptNotificationsEnabled: true,
    minimizeToTrayOnClose: true,
    isLeftHandedMode: false,
    videoLinkPassword: '',
    previewCacheMaxSizeGb: 2,
    previewCacheMaxAgeDays: 30,
    clipboardHistoryMaxEntries: 120,
    recacheParallelWorkers: 0,
  );

  AppSettings copyWith({
    BackgroundScanIntervalOption? backgroundScanInterval,
    bool? downloadAttemptNotificationsEnabled,
    bool? minimizeToTrayOnClose,
    bool? isLeftHandedMode,
    String? videoLinkPassword,
    int? previewCacheMaxSizeGb,
    int? previewCacheMaxAgeDays,
    int? clipboardHistoryMaxEntries,
    int? recacheParallelWorkers,
  }) {
    return AppSettings(
      backgroundScanInterval:
          backgroundScanInterval ?? this.backgroundScanInterval,
      downloadAttemptNotificationsEnabled:
          downloadAttemptNotificationsEnabled ??
          this.downloadAttemptNotificationsEnabled,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      isLeftHandedMode: isLeftHandedMode ?? this.isLeftHandedMode,
      videoLinkPassword: videoLinkPassword ?? this.videoLinkPassword,
      previewCacheMaxSizeGb:
          previewCacheMaxSizeGb ?? this.previewCacheMaxSizeGb,
      previewCacheMaxAgeDays:
          previewCacheMaxAgeDays ?? this.previewCacheMaxAgeDays,
      clipboardHistoryMaxEntries:
          clipboardHistoryMaxEntries ?? this.clipboardHistoryMaxEntries,
      recacheParallelWorkers:
          recacheParallelWorkers ?? this.recacheParallelWorkers,
    );
  }
}

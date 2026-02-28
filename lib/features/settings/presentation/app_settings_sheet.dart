import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/app_settings.dart';

class AppSettingsSheet extends StatelessWidget {
  const AppSettingsSheet({
    required this.settings,
    required this.onBackgroundIntervalChanged,
    required this.onDownloadAttemptNotificationsChanged,
    required this.onMinimizeToTrayChanged,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<BackgroundScanIntervalOption> onBackgroundIntervalChanged;
  final ValueChanged<bool> onDownloadAttemptNotificationsChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Настройки', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Фоновое сканирование сети',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.mutedBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<BackgroundScanIntervalOption>(
                  isExpanded: true,
                  value: settings.backgroundScanInterval,
                  items: BackgroundScanIntervalOption.values
                      .map(
                        (option) => DropdownMenuItem(
                          value: option,
                          child: Text(option.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (next) {
                    if (next == null) {
                      return;
                    }
                    onBackgroundIntervalChanged(next);
                  },
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Интервал управляет авто-сканированием. Для немедленного обновления используйте кнопку Refresh.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            SwitchListTile.adaptive(
              value: settings.downloadAttemptNotificationsEnabled,
              title: const Text('Уведомлять о попытках скачивания'),
              subtitle: const Text(
                'Показывать системное уведомление, когда устройство просит ваши файлы.',
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: onDownloadAttemptNotificationsChanged,
            ),
            if (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.linux)
              SwitchListTile.adaptive(
                value: settings.minimizeToTrayOnClose,
                title: const Text('Сворачивать в трей при закрытии'),
                subtitle: const Text(
                  'Окно скрывается в трей, приложение продолжает работу в фоне.',
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: onMinimizeToTrayChanged,
              ),
          ],
        ),
      ),
    );
  }
}

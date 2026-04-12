import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/app_settings.dart';

class AppSettingsSectionCard extends StatelessWidget {
  const AppSettingsSectionCard({
    required this.title,
    required this.children,
    this.description,
    super.key,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.mutedBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (description != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              description!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class AppSettingsNetworkTab extends StatelessWidget {
  const AppSettingsNetworkTab({
    required this.settings,
    required this.configuredDiscoveryTargets,
    required this.configuredTargetController,
    required this.onAddConfiguredTarget,
    required this.onRemoveConfiguredTarget,
    required this.onBackgroundIntervalChanged,
    required this.onDownloadAttemptNotificationsChanged,
    super.key,
  });

  final AppSettings settings;
  final List<String> configuredDiscoveryTargets;
  final TextEditingController configuredTargetController;
  final Future<void> Function() onAddConfiguredTarget;
  final Future<void> Function(String value) onRemoveConfiguredTarget;
  final ValueChanged<BackgroundScanIntervalOption> onBackgroundIntervalChanged;
  final ValueChanged<bool> onDownloadAttemptNotificationsChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        const AppSettingsSectionCard(
          title: 'Сеть и обнаружение',
          description:
              'Настройте фоновое обнаружение и fallback-поведение для routed/virtual сетей.',
          children: [],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Фоновое сканирование сети',
          description:
              'Интервал управляет авто-сканированием. Для немедленного обновления используйте кнопку Refresh.',
          children: [
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
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Явные discovery targets',
          description:
              'Fallback для virtual/routed сетей, где автообнаружение может не сработать. Landa будет отправлять discovery-пакеты только на указанные IPv4-адреса.',
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: configuredTargetController,
                    keyboardType: TextInputType.text,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'IPv4-адрес устройства',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => unawaited(onAddConfiguredTarget()),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => unawaited(onAddConfiguredTarget()),
                    child: const Text('Добавить'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (configuredDiscoveryTargets.isEmpty)
              Text(
                'Список пуст. Добавьте IP-адреса устройств виртуальной сети, если они не находятся автоматически.',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Column(
                children: configuredDiscoveryTargets
                    .map(
                      (target) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(target),
                        trailing: IconButton(
                          tooltip: 'Удалить',
                          onPressed: () =>
                              unawaited(onRemoveConfiguredTarget(target)),
                          icon: const Icon(Icons.delete_outline_rounded),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Уведомления',
          children: [
            SwitchListTile.adaptive(
              value: settings.downloadAttemptNotificationsEnabled,
              title: const Text('Уведомлять о попытках скачивания'),
              subtitle: const Text(
                'Показывать системное уведомление, когда устройство просит ваши файлы.',
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: onDownloadAttemptNotificationsChanged,
            ),
          ],
        ),
      ],
    );
  }
}

class AppSettingsDesktopTab extends StatelessWidget {
  const AppSettingsDesktopTab({
    required this.settings,
    required this.onUseStandardAppDownloadFolderChanged,
    required this.onMinimizeToTrayChanged,
    required this.onLeftHandedModeChanged,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<bool> onUseStandardAppDownloadFolderChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onLeftHandedModeChanged;

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        const AppSettingsSectionCard(
          title: 'Окно и поведение',
          description:
              'Настройки интерфейса и поведения Landa на текущем устройстве.',
          children: [],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Интерфейс',
          children: [
            SwitchListTile.adaptive(
              value: settings.isLeftHandedMode,
              title: const Text('Режим для левшей'),
              subtitle: const Text(
                'Меню с тремя полосками и боковая панель переедут на левую сторону.',
              ),
              contentPadding: EdgeInsets.zero,
              onChanged: onLeftHandedModeChanged,
            ),
          ],
        ),
        if (isDesktop) ...[
          const SizedBox(height: AppSpacing.md),
          AppSettingsSectionCard(
            title: 'Desktop',
            children: [
              SwitchListTile.adaptive(
                value: settings.useStandardAppDownloadFolder,
                title: const Text('Скачивать в стандартную папку Landa'),
                subtitle: const Text(
                  'Если выключено, Windows/Linux будут спрашивать папку назначения перед скачиванием из общих папок.',
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: onUseStandardAppDownloadFolderChanged,
              ),
              const SizedBox(height: AppSpacing.xs),
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
        ],
      ],
    );
  }
}

class AppSettingsStorageTab extends StatelessWidget {
  const AppSettingsStorageTab({
    required this.cacheSizeController,
    required this.cacheAgeController,
    required this.clipboardLimitController,
    required this.recacheWorkersController,
    required this.onSaveCacheSize,
    required this.onSaveCacheAge,
    required this.onSaveClipboardLimit,
    required this.onSaveRecacheParallelWorkers,
    required this.onShowLogs,
    required this.onOpenLogsFolder,
    this.isShowingLogs = false,
    this.isOpeningLogsFolder = false,
    super.key,
  });

  final TextEditingController cacheSizeController;
  final TextEditingController cacheAgeController;
  final TextEditingController clipboardLimitController;
  final TextEditingController recacheWorkersController;
  final VoidCallback onSaveCacheSize;
  final VoidCallback onSaveCacheAge;
  final VoidCallback onSaveClipboardLimit;
  final VoidCallback onSaveRecacheParallelWorkers;
  final Future<void> Function() onShowLogs;
  final Future<void> Function() onOpenLogsFolder;
  final bool isShowingLogs;
  final bool isOpeningLogsFolder;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        AppSettingsSectionCard(
          title: 'Preview-кэш',
          description:
              '0 = без ограничений. Если срок = 0, файлы живут бессрочно и удаляются только по лимиту размера.',
          children: [
            IntegerSettingField(
              controller: cacheSizeController,
              label: 'Максимальный размер кэша (ГБ)',
              onSave: onSaveCacheSize,
            ),
            const SizedBox(height: AppSpacing.sm),
            IntegerSettingField(
              controller: cacheAgeController,
              label: 'Максимальный срок хранения (дни)',
              onSave: onSaveCacheAge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'История буфера обмена',
          description:
              'Максимум записей в локальной истории. 0 = без ограничений.',
          children: [
            IntegerSettingField(
              controller: clipboardLimitController,
              label: 'Максимум записей истории',
              onSave: onSaveClipboardLimit,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Ускорение re-cache',
          description: 'Число воркеров для пересборки кэша. 0 = авто (по CPU).',
          children: [
            IntegerSettingField(
              controller: recacheWorkersController,
              label: 'Параллельные воркеры re-cache',
              onSave: onSaveRecacheParallelWorkers,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'Диагностика',
          description:
              'debug.log помогает разбирать проблемы shared-download и runtime-сбоев.',
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  key: const Key('settings-show-logs-action'),
                  onPressed: isShowingLogs
                      ? null
                      : () => unawaited(onShowLogs()),
                  icon: isShowingLogs
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.description_outlined),
                  label: const Text('Показать логи'),
                ),
                OutlinedButton.icon(
                  key: const Key('settings-open-logs-folder-action'),
                  onPressed: isOpeningLogsFolder
                      ? null
                      : () => unawaited(onOpenLogsFolder()),
                  icon: isOpeningLogsFolder
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: const Text('Открыть папку с логами'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class AppSettingsAccessTab extends StatelessWidget {
  const AppSettingsAccessTab({
    required this.videoLinkPasswordController,
    required this.onSaveVideoLinkPassword,
    super.key,
  });

  final TextEditingController videoLinkPasswordController;
  final VoidCallback onSaveVideoLinkPassword;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      children: [
        AppSettingsSectionCard(
          title: 'Веб-ссылка',
          description: 'Используется для доступа к видео по ссылке из меню.',
          children: [
            TextSettingField(
              controller: videoLinkPasswordController,
              label: 'Пароль для веб-сервера',
              obscureText: true,
              onSave: onSaveVideoLinkPassword,
            ),
          ],
        ),
      ],
    );
  }
}

class IntegerSettingField extends StatelessWidget {
  const IntegerSettingField({
    required this.controller,
    required this.label,
    required this.onSave,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onSave,
            child: const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}

class TextSettingField extends StatelessWidget {
  const TextSettingField({
    required this.controller,
    required this.label,
    required this.onSave,
    this.obscureText = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSave;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => onSave(),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: onSave,
            child: const Text('Сохранить'),
          ),
        ),
      ],
    );
  }
}

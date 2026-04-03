import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/app_settings.dart';

class AppSettingsSheet extends StatefulWidget {
  const AppSettingsSheet({
    required this.settings,
    required this.onBackgroundIntervalChanged,
    required this.onDownloadAttemptNotificationsChanged,
    required this.onUseStandardAppDownloadFolderChanged,
    required this.onMinimizeToTrayChanged,
    required this.onLeftHandedModeChanged,
    required this.onVideoLinkPasswordChanged,
    required this.onPreviewCacheMaxSizeGbChanged,
    required this.onPreviewCacheMaxAgeDaysChanged,
    required this.onClipboardHistoryMaxEntriesChanged,
    required this.onRecacheParallelWorkersChanged,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<BackgroundScanIntervalOption> onBackgroundIntervalChanged;
  final ValueChanged<bool> onDownloadAttemptNotificationsChanged;
  final ValueChanged<bool> onUseStandardAppDownloadFolderChanged;
  final ValueChanged<bool> onMinimizeToTrayChanged;
  final ValueChanged<bool> onLeftHandedModeChanged;
  final ValueChanged<String> onVideoLinkPasswordChanged;
  final ValueChanged<int> onPreviewCacheMaxSizeGbChanged;
  final ValueChanged<int> onPreviewCacheMaxAgeDaysChanged;
  final ValueChanged<int> onClipboardHistoryMaxEntriesChanged;
  final ValueChanged<int> onRecacheParallelWorkersChanged;

  @override
  State<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<AppSettingsSheet> {
  late final TextEditingController _cacheSizeController;
  late final TextEditingController _cacheAgeController;
  late final TextEditingController _clipboardLimitController;
  late final TextEditingController _recacheWorkersController;
  late final TextEditingController _videoLinkPasswordController;

  @override
  void initState() {
    super.initState();
    _cacheSizeController = TextEditingController(
      text: widget.settings.previewCacheMaxSizeGb.toString(),
    );
    _cacheAgeController = TextEditingController(
      text: widget.settings.previewCacheMaxAgeDays.toString(),
    );
    _clipboardLimitController = TextEditingController(
      text: widget.settings.clipboardHistoryMaxEntries.toString(),
    );
    _recacheWorkersController = TextEditingController(
      text: widget.settings.recacheParallelWorkers.toString(),
    );
    _videoLinkPasswordController = TextEditingController(
      text: widget.settings.videoLinkPassword,
    );
  }

  @override
  void didUpdateWidget(covariant AppSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.previewCacheMaxSizeGb !=
        widget.settings.previewCacheMaxSizeGb) {
      _cacheSizeController.text = widget.settings.previewCacheMaxSizeGb
          .toString();
    }
    if (oldWidget.settings.previewCacheMaxAgeDays !=
        widget.settings.previewCacheMaxAgeDays) {
      _cacheAgeController.text = widget.settings.previewCacheMaxAgeDays
          .toString();
    }
    if (oldWidget.settings.clipboardHistoryMaxEntries !=
        widget.settings.clipboardHistoryMaxEntries) {
      _clipboardLimitController.text = widget
          .settings
          .clipboardHistoryMaxEntries
          .toString();
    }
    if (oldWidget.settings.recacheParallelWorkers !=
        widget.settings.recacheParallelWorkers) {
      _recacheWorkersController.text = widget.settings.recacheParallelWorkers
          .toString();
    }
    if (oldWidget.settings.videoLinkPassword !=
        widget.settings.videoLinkPassword) {
      _videoLinkPasswordController.text = widget.settings.videoLinkPassword;
    }
  }

  @override
  void dispose() {
    _cacheSizeController.dispose();
    _cacheAgeController.dispose();
    _clipboardLimitController.dispose();
    _recacheWorkersController.dispose();
    _videoLinkPasswordController.dispose();
    super.dispose();
  }

  void _showValidationMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _saveCacheSize() {
    final parsed = int.tryParse(_cacheSizeController.text.trim());
    if (parsed == null || parsed < 0) {
      _showValidationMessage('Введите неотрицательное число (ГБ).');
      return;
    }
    widget.onPreviewCacheMaxSizeGbChanged(parsed);
  }

  void _saveCacheAge() {
    final parsed = int.tryParse(_cacheAgeController.text.trim());
    if (parsed == null || parsed < 0) {
      _showValidationMessage('Введите неотрицательное число (дни).');
      return;
    }
    widget.onPreviewCacheMaxAgeDaysChanged(parsed);
  }

  void _saveClipboardLimit() {
    final parsed = int.tryParse(_clipboardLimitController.text.trim());
    if (parsed == null || parsed < 0) {
      _showValidationMessage('Введите неотрицательное число записей.');
      return;
    }
    widget.onClipboardHistoryMaxEntriesChanged(parsed);
  }

  void _saveRecacheParallelWorkers() {
    final parsed = int.tryParse(_recacheWorkersController.text.trim());
    if (parsed == null || parsed < 0) {
      _showValidationMessage('Введите неотрицательное число потоков.');
      return;
    }
    widget.onRecacheParallelWorkersChanged(parsed);
  }

  void _saveVideoLinkPassword() {
    widget.onVideoLinkPasswordChanged(_videoLinkPasswordController.text.trim());
  }

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
        child: SingleChildScrollView(
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
                    value: widget.settings.backgroundScanInterval,
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
                      widget.onBackgroundIntervalChanged(next);
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
                value: widget.settings.downloadAttemptNotificationsEnabled,
                title: const Text('Уведомлять о попытках скачивания'),
                subtitle: const Text(
                  'Показывать системное уведомление, когда устройство просит ваши файлы.',
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: widget.onDownloadAttemptNotificationsChanged,
              ),
              if (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux)
                SwitchListTile.adaptive(
                  value: widget.settings.useStandardAppDownloadFolder,
                  title: const Text('Скачивать в стандартную папку Landa'),
                  subtitle: const Text(
                    'Если выключено, Windows/Linux будут спрашивать папку назначения перед скачиванием из общих папок.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  onChanged: widget.onUseStandardAppDownloadFolderChanged,
                ),
              if (defaultTargetPlatform == TargetPlatform.windows ||
                  defaultTargetPlatform == TargetPlatform.linux)
                SwitchListTile.adaptive(
                  value: widget.settings.minimizeToTrayOnClose,
                  title: const Text('Сворачивать в трей при закрытии'),
                  subtitle: const Text(
                    'Окно скрывается в трей, приложение продолжает работу в фоне.',
                  ),
                  contentPadding: EdgeInsets.zero,
                  onChanged: widget.onMinimizeToTrayChanged,
                ),
              SwitchListTile.adaptive(
                value: widget.settings.isLeftHandedMode,
                title: const Text('Режим для левшей'),
                subtitle: const Text(
                  'Меню с тремя полосками и боковая панель переедут на левую сторону.',
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: widget.onLeftHandedModeChanged,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Ограничения preview-кэша',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '0 = без ограничений. Если срок = 0, файлы живут бессрочно и удаляются только по лимиту размера.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _IntegerSettingField(
                controller: _cacheSizeController,
                label: 'Максимальный размер кэша (ГБ)',
                onSave: _saveCacheSize,
              ),
              const SizedBox(height: AppSpacing.sm),
              _IntegerSettingField(
                controller: _cacheAgeController,
                label: 'Максимальный срок хранения (дни)',
                onSave: _saveCacheAge,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'История буфера обмена',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Максимум записей в локальной истории. 0 = без ограничений.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _IntegerSettingField(
                controller: _clipboardLimitController,
                label: 'Максимум записей истории',
                onSave: _saveClipboardLimit,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Ускорение re-cache',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Число воркеров для пересборки кэша. 0 = авто (по CPU).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _IntegerSettingField(
                controller: _recacheWorkersController,
                label: 'Параллельные воркеры re-cache',
                onSave: _saveRecacheParallelWorkers,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Пароль веб-ссылки',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Используется для доступа к видео по ссылке из меню.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              _TextSettingField(
                controller: _videoLinkPasswordController,
                label: 'Пароль для веб-сервера',
                obscureText: true,
                onSave: _saveVideoLinkPassword,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntegerSettingField extends StatelessWidget {
  const _IntegerSettingField({
    required this.controller,
    required this.label,
    required this.onSave,
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

class _TextSettingField extends StatelessWidget {
  const _TextSettingField({
    required this.controller,
    required this.label,
    required this.onSave,
    this.obscureText = false,
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

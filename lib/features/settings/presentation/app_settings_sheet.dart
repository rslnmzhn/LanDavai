import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/app_settings.dart';
import 'app_settings_tab_sections.dart';

class AppSettingsSheet extends StatefulWidget {
  const AppSettingsSheet({
    required this.settings,
    required this.configuredDiscoveryTargets,
    required this.configuredTargetValidator,
    required this.onAddConfiguredDiscoveryTarget,
    required this.onRemoveConfiguredDiscoveryTarget,
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
    required this.onShowLogs,
    required this.onOpenLogsFolder,
    super.key,
  });

  final AppSettings settings;
  final List<String> configuredDiscoveryTargets;
  final String? Function(String raw) configuredTargetValidator;
  final Future<bool> Function(String raw) onAddConfiguredDiscoveryTarget;
  final Future<void> Function(String value) onRemoveConfiguredDiscoveryTarget;
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
  final Future<String?> Function() onShowLogs;
  final Future<String?> Function() onOpenLogsFolder;

  @override
  State<AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<AppSettingsSheet> {
  late final TextEditingController _cacheSizeController;
  late final TextEditingController _cacheAgeController;
  late final TextEditingController _clipboardLimitController;
  late final TextEditingController _recacheWorkersController;
  late final TextEditingController _videoLinkPasswordController;
  late final TextEditingController _configuredTargetController;
  bool _isShowingLogs = false;
  bool _isOpeningLogsFolder = false;

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
    _configuredTargetController = TextEditingController();
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
    _configuredTargetController.dispose();
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

  Future<void> _runLogAction({
    required Future<String?> Function() action,
    required void Function(bool value) setBusy,
  }) async {
    setState(() {
      setBusy(true);
    });
    try {
      final message = await action();
      if (message != null && mounted) {
        _showValidationMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          setBusy(false);
        });
      }
    }
  }

  Future<void> _addConfiguredTarget() async {
    final raw = _configuredTargetController.text;
    final error = widget.configuredTargetValidator(raw);
    if (error != null) {
      _showValidationMessage(error);
      return;
    }
    final added = await widget.onAddConfiguredDiscoveryTarget(raw);
    if (!added) {
      _showValidationMessage('Не удалось добавить IP-адрес.');
      return;
    }
    _configuredTargetController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Text(
              'Настройки',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: AppColors.mutedBorder),
              ),
              child: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                labelColor: AppColors.brandPrimaryDark,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
                ),
                padding: EdgeInsets.all(AppSpacing.xs),
                tabs: [
                  Tab(text: 'Сеть'),
                  Tab(text: 'Интерфейс'),
                  Tab(text: 'Хранилище'),
                  Tab(text: 'Доступ'),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: TabBarView(
              children: [
                AppSettingsNetworkTab(
                  settings: widget.settings,
                  configuredDiscoveryTargets: widget.configuredDiscoveryTargets,
                  configuredTargetController: _configuredTargetController,
                  onAddConfiguredTarget: _addConfiguredTarget,
                  onRemoveConfiguredTarget:
                      widget.onRemoveConfiguredDiscoveryTarget,
                  onBackgroundIntervalChanged:
                      widget.onBackgroundIntervalChanged,
                  onDownloadAttemptNotificationsChanged:
                      widget.onDownloadAttemptNotificationsChanged,
                ),
                AppSettingsDesktopTab(
                  settings: widget.settings,
                  onUseStandardAppDownloadFolderChanged:
                      widget.onUseStandardAppDownloadFolderChanged,
                  onMinimizeToTrayChanged: widget.onMinimizeToTrayChanged,
                  onLeftHandedModeChanged: widget.onLeftHandedModeChanged,
                ),
                AppSettingsStorageTab(
                  cacheSizeController: _cacheSizeController,
                  cacheAgeController: _cacheAgeController,
                  clipboardLimitController: _clipboardLimitController,
                  recacheWorkersController: _recacheWorkersController,
                  onSaveCacheSize: _saveCacheSize,
                  onSaveCacheAge: _saveCacheAge,
                  onSaveClipboardLimit: _saveClipboardLimit,
                  onSaveRecacheParallelWorkers: _saveRecacheParallelWorkers,
                  onShowLogs: () => _runLogAction(
                    action: widget.onShowLogs,
                    setBusy: (value) => _isShowingLogs = value,
                  ),
                  onOpenLogsFolder: () => _runLogAction(
                    action: widget.onOpenLogsFolder,
                    setBusy: (value) => _isOpeningLogsFolder = value,
                  ),
                  isShowingLogs: _isShowingLogs,
                  isOpeningLogsFolder: _isOpeningLogsFolder,
                ),
                AppSettingsAccessTab(
                  videoLinkPasswordController: _videoLinkPasswordController,
                  onSaveVideoLinkPassword: _saveVideoLinkPassword,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

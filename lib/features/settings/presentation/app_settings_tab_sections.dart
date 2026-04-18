import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';

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
        AppSettingsSectionCard(
          title: 'settings.network_section_title'.tr(),
          description: 'settings.network_section_description'.tr(),
          children: const [],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'settings.background_scan_title'.tr(),
          description: 'settings.background_scan_description'.tr(),
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
                          child: Text(
                            _backgroundScanIntervalLabel(option).tr(),
                          ),
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
          title: 'settings.discovery_targets_title'.tr(),
          description: 'settings.discovery_targets_description'.tr(),
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
                    decoration: InputDecoration(
                      labelText: 'settings.discovery_target_field'.tr(),
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
                    child: Text('common.add'.tr()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (configuredDiscoveryTargets.isEmpty)
              Text(
                'settings.discovery_targets_empty'.tr(),
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
                          tooltip: 'common.delete'.tr(),
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
          title: 'settings.notifications_title'.tr(),
          children: [
            SwitchListTile.adaptive(
              value: settings.downloadAttemptNotificationsEnabled,
              title: Text('settings.download_attempt_notifications'.tr()),
              subtitle: Text(
                'settings.download_attempt_notifications_description'.tr(),
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
        AppSettingsSectionCard(
          title: 'settings.window_section_title'.tr(),
          description: 'settings.window_section_description'.tr(),
          children: const [],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'settings.interface_title'.tr(),
          children: [
            SwitchListTile.adaptive(
              value: settings.isLeftHandedMode,
              title: Text('settings.left_handed_mode'.tr()),
              subtitle: Text('settings.left_handed_mode_description'.tr()),
              contentPadding: EdgeInsets.zero,
              onChanged: onLeftHandedModeChanged,
            ),
          ],
        ),
        if (isDesktop) ...[
          const SizedBox(height: AppSpacing.md),
          AppSettingsSectionCard(
            title: 'settings.desktop_title'.tr(),
            children: [
              SwitchListTile.adaptive(
                value: settings.useStandardAppDownloadFolder,
                title: Text('settings.use_standard_download_folder'.tr()),
                subtitle: Text(
                  'settings.use_standard_download_folder_description'.tr(),
                ),
                contentPadding: EdgeInsets.zero,
                onChanged: onUseStandardAppDownloadFolderChanged,
              ),
              const SizedBox(height: AppSpacing.xs),
              SwitchListTile.adaptive(
                value: settings.minimizeToTrayOnClose,
                title: Text('settings.minimize_to_tray'.tr()),
                subtitle: Text('settings.minimize_to_tray_description'.tr()),
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
    required this.debugLogRetainedLinesController,
    required this.onSaveCacheSize,
    required this.onSaveCacheAge,
    required this.onSaveClipboardLimit,
    required this.onSaveRecacheParallelWorkers,
    required this.onSaveDebugLogRetainedLines,
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
  final TextEditingController debugLogRetainedLinesController;
  final VoidCallback onSaveCacheSize;
  final VoidCallback onSaveCacheAge;
  final VoidCallback onSaveClipboardLimit;
  final VoidCallback onSaveRecacheParallelWorkers;
  final VoidCallback onSaveDebugLogRetainedLines;
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
          title: 'settings.preview_cache_title'.tr(),
          description: 'settings.preview_cache_description'.tr(),
          children: [
            IntegerSettingField(
              controller: cacheSizeController,
              label: 'settings.preview_cache_max_size'.tr(),
              onSave: onSaveCacheSize,
            ),
            const SizedBox(height: AppSpacing.sm),
            IntegerSettingField(
              controller: cacheAgeController,
              label: 'settings.preview_cache_max_age'.tr(),
              onSave: onSaveCacheAge,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'settings.clipboard_history_title'.tr(),
          description: 'settings.clipboard_history_description'.tr(),
          children: [
            IntegerSettingField(
              controller: clipboardLimitController,
              label: 'settings.clipboard_history_max_entries'.tr(),
              onSave: onSaveClipboardLimit,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'settings.recache_title'.tr(),
          description: 'settings.recache_description'.tr(),
          children: [
            IntegerSettingField(
              controller: recacheWorkersController,
              label: 'settings.recache_parallel_workers'.tr(),
              onSave: onSaveRecacheParallelWorkers,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        AppSettingsSectionCard(
          title: 'settings.diagnostics_title'.tr(),
          description: 'settings.diagnostics_description'.tr(),
          children: [
            IntegerSettingField(
              controller: debugLogRetainedLinesController,
              label: 'settings.debug_log_retained_lines'.tr(),
              onSave: onSaveDebugLogRetainedLines,
              fieldKey: const Key('settings-debug-log-line-cap-field'),
              buttonKey: const Key('settings-debug-log-line-cap-save'),
            ),
            const SizedBox(height: AppSpacing.sm),
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
                  label: Text('settings.show_logs'.tr()),
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
                  label: Text('settings.open_logs_folder'.tr()),
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
          title: 'settings.access_title'.tr(),
          description: 'settings.access_description'.tr(),
          children: [
            TextSettingField(
              controller: videoLinkPasswordController,
              label: 'settings.video_link_password'.tr(),
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
    this.fieldKey,
    this.buttonKey,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSave;
  final Key? fieldKey;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            key: fieldKey,
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
            key: buttonKey,
            onPressed: onSave,
            child: Text('common.save'.tr()),
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
            child: Text('common.save'.tr()),
          ),
        ),
      ],
    );
  }
}

String _backgroundScanIntervalLabel(BackgroundScanIntervalOption option) {
  switch (option) {
    case BackgroundScanIntervalOption.tenSeconds:
      return 'settings.background_interval_ten_seconds';
    case BackgroundScanIntervalOption.thirtySeconds:
      return 'settings.background_interval_thirty_seconds';
    case BackgroundScanIntervalOption.fiveMinutes:
      return 'settings.background_interval_five_minutes';
    case BackgroundScanIntervalOption.fifteenMinutes:
      return 'settings.background_interval_fifteen_minutes';
    case BackgroundScanIntervalOption.oneHour:
      return 'settings.background_interval_one_hour';
  }
}

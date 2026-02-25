import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/storage/app_database.dart';
import '../../../core/utils/path_opener.dart';
import '../../history/data/transfer_history_repository.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/file_transfer_service.dart';
import '../../transfer/data/shared_folder_cache_repository.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../application/discovery_controller.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/network_host_scanner.dart';
import '../domain/discovered_device.dart';

class DiscoveryPage extends StatefulWidget {
  const DiscoveryPage({super.key});

  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  late final DiscoveryController _controller;
  String? _lastInfoMessage;

  @override
  void initState() {
    super.initState();
    _controller = DiscoveryController(
      deviceAliasRepository: DeviceAliasRepository(
        database: AppDatabase.instance,
      ),
      transferHistoryRepository: TransferHistoryRepository(
        database: AppDatabase.instance,
      ),
      sharedFolderCacheRepository: SharedFolderCacheRepository(
        database: AppDatabase.instance,
      ),
      fileHashService: FileHashService(),
      fileTransferService: FileTransferService(),
      transferStorageService: TransferStorageService(),
      pathOpener: PathOpener(),
      lanDiscoveryService: LanDiscoveryService(),
      networkHostScanner: NetworkHostScanner(),
    )..start();
    _controller.addListener(_handleInfoMessages);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleInfoMessages);
    _controller.dispose();
    super.dispose();
  }

  void _handleInfoMessages() {
    final info = _controller.infoMessage;
    if (!mounted || info == null || info == _lastInfoMessage) {
      return;
    }
    _lastInfoMessage = info;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(info)));
    _controller.clearInfoMessage();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final devices = _controller.devices;
        return Scaffold(
          appBar: AppBar(
            title: const Text('LanDa devices'),
            actions: [
              IconButton(
                tooltip: 'Download history',
                onPressed: _openHistorySheet,
                icon: const Icon(Icons.history),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _controller.isManualRefreshInProgress
                    ? null
                    : _controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                _NetworkSummaryCard(
                  controller: _controller,
                  total: devices.length,
                ),
                const SizedBox(height: AppSpacing.md),
                if (_controller.errorMessage != null) ...[
                  _ErrorBanner(message: _controller.errorMessage!),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_controller.isUploading || _controller.isDownloading) ...[
                  _TransferProgressCard(controller: _controller),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (_controller.isManualRefreshInProgress) ...[
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.brandPrimary,
                    backgroundColor: AppColors.mutedBorder,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Expanded(
                  child: devices.isEmpty
                      ? _EmptyState(onRefresh: _controller.refresh)
                      : ListView.separated(
                          itemCount: devices.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (_, index) => _DeviceTile(
                            device: devices[index],
                            selected:
                                _controller.selectedDevice?.ip ==
                                devices[index].ip,
                            onSelect: _controller.selectDeviceByIp,
                            onRename: _showRenameDialog,
                            onToggleFavorite: _controller.toggleTrustedDevice,
                          ),
                        ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: _ActionBar(
            controller: _controller,
            onReceive: _openReceivePanel,
            onAdd: _openAddShareMenu,
            onSend: _controller.sendFilesToSelectedDevice,
          ),
        );
      },
    );
  }

  Future<void> _showRenameDialog(DiscoveredDevice device) async {
    final initialValue = device.aliasName ?? device.deviceName ?? '';
    final controller = TextEditingController(text: initialValue);
    final newAlias = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Custom name',
              helperText: 'Name is bound to device MAC address.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Reset'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (newAlias == null) {
      return;
    }

    await _controller.renameDeviceAlias(device: device, alias: newAlias);
    if (!mounted || _controller.errorMessage == null) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_controller.errorMessage!)));
  }

  Future<void> _openAddShareMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('Add shared folder'),
                subtitle: const Text(
                  'Create lightweight cache index for folder',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _controller.addSharedFolder();
                },
              ),
              ListTile(
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('Add shared files'),
                subtitle: const Text(
                  'Create lightweight cache index for files',
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _controller.addSharedFiles();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final history = _controller.downloadHistory;
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'История загрузок',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: history.isEmpty
                            ? const Center(
                                child: Text('История загрузок пока пустая'),
                              )
                            : ListView.separated(
                                itemCount: history.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.sm),
                                itemBuilder: (_, index) {
                                  final item = history[index];
                                  return Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.peerName,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                ),
                                              ),
                                              Text(
                                                _formatTime(item.createdAt),
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(
                                            height: AppSpacing.xxs,
                                          ),
                                          Text(
                                            '${item.fileCount} files • ${_formatBytes(item.totalBytes)}',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                          const SizedBox(height: AppSpacing.xs),
                                          Wrap(
                                            spacing: AppSpacing.xs,
                                            runSpacing: AppSpacing.xs,
                                            children: item.savedPaths
                                                .take(6)
                                                .map(
                                                  (path) => ActionChip(
                                                    label: Text(
                                                      p.basename(path),
                                                    ),
                                                    onPressed: () async {
                                                      await _controller
                                                          .openHistoryPath(
                                                            path,
                                                          );
                                                    },
                                                  ),
                                                )
                                                .toList(growable: false),
                                          ),
                                          if (item.savedPaths.length > 6) ...[
                                            const SizedBox(
                                              height: AppSpacing.xxs,
                                            ),
                                            Text(
                                              '+${item.savedPaths.length - 6} more files',
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                            ),
                                          ],
                                          const SizedBox(height: AppSpacing.sm),
                                          OutlinedButton.icon(
                                            onPressed: () async {
                                              await _controller.openHistoryPath(
                                                item.rootPath,
                                              );
                                            },
                                            icon: const Icon(Icons.folder_open),
                                            label: const Text('Открыть папку'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openReceivePanel() async {
    unawaited(_controller.loadRemoteShareOptions());
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.88,
          child: _ReceivePanelSheet(controller: _controller),
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  String _formatTime(DateTime time) {
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }
}

class _NetworkSummaryCard extends StatelessWidget {
  const _NetworkSummaryCard({required this.controller, required this.total});

  final DiscoveryController controller;
  final int total;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: AppColors.brandPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(Icons.lan, color: AppColors.brandPrimary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controller.localName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Local IP: ${controller.localIp ?? "Detecting..."}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Devices: $total • App detected: ${controller.appDetectedCount}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    selected == null
                        ? 'Target: not selected'
                        : 'Target: ${selected.displayName} (${selected.ip})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.error),
      ),
    );
  }
}

class _TransferProgressCard extends StatelessWidget {
  const _TransferProgressCard({required this.controller});

  final DiscoveryController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfer Progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (controller.isUploading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Upload: ${(controller.uploadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: controller.uploadProgress,
                minHeight: 6,
                color: AppColors.brandPrimary,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
            if (controller.isDownloading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Download: ${(controller.downloadProgress * 100).toStringAsFixed(0)}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              LinearProgressIndicator(
                value: controller.downloadProgress,
                minHeight: 6,
                color: AppColors.success,
                backgroundColor: AppColors.mutedBorder,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onToggleFavorite,
  });

  final DiscoveredDevice device;
  final bool selected;
  final void Function(String ip) onSelect;
  final Future<void> Function(DiscoveredDevice device) onRename;
  final Future<void> Function(DiscoveredDevice device) onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = device.isAppDetected;
    final tileBackground = selected
        ? AppColors.brandAccent.withValues(alpha: 0.22)
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.09)
        : AppColors.surface;
    final borderColor = selected
        ? AppColors.brandPrimary
        : isHighlighted
        ? AppColors.brandPrimary.withValues(alpha: 0.45)
        : AppColors.mutedBorder;
    final iconColor = isHighlighted
        ? AppColors.brandPrimary
        : AppColors.mutedIcon;
    final subtitle = [
      device.ip,
      if (device.macAddress != null) 'MAC ${device.macAddress}',
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: tileBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: borderColor),
      ),
      child: ListTile(
        minTileHeight: 56,
        onTap: () => onSelect(device.ip),
        onLongPress: () => onRename(device),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Icon(Icons.devices, color: iconColor),
        title: Text(
          device.displayName,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: device.isTrusted
                  ? 'Убрать из избранного'
                  : 'Добавить в избранное',
              onPressed: () => onToggleFavorite(device),
              icon: Icon(
                device.isTrusted ? Icons.star : Icons.star_border,
                color: device.isTrusted
                    ? AppColors.warning
                    : AppColors.textSecondary,
              ),
            ),
            _StatusChip(device: device, selected: selected),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.device, required this.selected});

  final DiscoveredDevice device;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (selected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandPrimary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'Target',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.brandPrimaryDark),
        ),
      );
    }
    if (device.isAppDetected) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Text(
          'App found',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.success),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.mutedIcon.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        device.isReachable ? 'LAN host' : 'Stale',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_find, size: 48, color: AppColors.mutedIcon),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'No devices found yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Make sure you are on the same Wi-Fi / LAN and refresh.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onRefresh,
                child: const Text('Refresh scan'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceivePanelSheet extends StatefulWidget {
  const _ReceivePanelSheet({required this.controller});

  final DiscoveryController controller;

  @override
  State<_ReceivePanelSheet> createState() => _ReceivePanelSheetState();
}

class _ReceivePanelSheetState extends State<_ReceivePanelSheet> {
  String? _selectedOwnerIp;
  final Set<String> _selectedFileIds = <String>{};

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final remoteOptions = widget.controller.remoteShareOptions;
        final owners = _buildOwnerChoices(remoteOptions);
        final selectedOwner = _selectedOwnerIp == null
            ? null
            : _findOwnerByIp(owners, _selectedOwnerIp!);
        if (selectedOwner == null && _selectedOwnerIp != null) {
          _selectedOwnerIp = null;
          _selectedFileIds.clear();
        }

        final fileChoices = _selectedOwnerIp == null
            ? const <_RemoteFileChoice>[]
            : _buildFileChoices(
                remoteOptions: remoteOptions,
                ownerIp: _selectedOwnerIp!,
              );
        final validIds = fileChoices.map((file) => file.id).toSet();
        _selectedFileIds.removeWhere((id) => !validIds.contains(id));

        final selectedCount = fileChoices
            .where((file) => _selectedFileIds.contains(file.id))
            .length;
        final requests = widget.controller.incomingRequests;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Выбор файлов из LAN',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Обновить список',
                      onPressed: widget.controller.isLoadingRemoteShares
                          ? null
                          : widget.controller.loadRemoteShareOptions,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.controller.isLoadingRemoteShares) ...[
                  const LinearProgressIndicator(
                    minHeight: 3,
                    color: AppColors.brandPrimary,
                    backgroundColor: AppColors.mutedBorder,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                OutlinedButton.icon(
                  onPressed: owners.isEmpty ? null : () => _pickOwner(owners),
                  icon: const Icon(Icons.devices_rounded),
                  label: Text(
                    selectedOwner == null
                        ? 'Выбрать устройство'
                        : 'Устройство: ${selectedOwner.name}',
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: owners.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет доступных общих папок/файлов на устройствах LAN',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : selectedOwner == null
                      ? const Center(
                          child: Text(
                            'Нажмите "Выбрать устройство", чтобы увидеть файлы.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${selectedOwner.name} • ${selectedOwner.ip}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Доступно: ${selectedOwner.fileCount} файлов',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedFileIds
                                        ..clear()
                                        ..addAll(
                                          fileChoices.map((file) => file.id),
                                        );
                                    });
                                  },
                                  child: const Text('Выбрать все'),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                TextButton(
                                  onPressed: () {
                                    setState(_selectedFileIds.clear);
                                  },
                                  child: const Text('Очистить'),
                                ),
                                const Spacer(),
                                Text(
                                  'Выбрано: $selectedCount',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Expanded(
                              child: ListView.separated(
                                itemCount: fileChoices.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.xs),
                                itemBuilder: (_, index) {
                                  final file = fileChoices[index];
                                  final checked = _selectedFileIds.contains(
                                    file.id,
                                  );
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedFileIds.add(file.id);
                                        } else {
                                          _selectedFileIds.remove(file.id);
                                        }
                                      });
                                    },
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                    ),
                                    title: Text(
                                      file.relativePath,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${file.cacheDisplayName} • ${_formatBytes(file.sizeBytes)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: selectedCount == 0
                                    ? null
                                    : () => _requestSelectedFiles(
                                        owner: selectedOwner,
                                        files: fileChoices,
                                      ),
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  'Скачать выбранные ($selectedCount)',
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
                const Divider(height: AppSpacing.lg),
                Text(
                  'Входящие запросы на передачу',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (requests.isEmpty)
                  Text(
                    'Нет ожидающих запросов.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  SizedBox(
                    height: 150,
                    child: ListView.separated(
                      itemCount: requests.length,
                      separatorBuilder: (_, index) =>
                          const SizedBox(height: AppSpacing.xs),
                      itemBuilder: (_, index) {
                        final request = requests[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${request.senderName} • ${request.sharedLabel}\n'
                                '${request.items.length} files • ${_formatBytes(request.totalBytes)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: () async {
                                await widget.controller
                                    .respondToTransferRequest(
                                      requestId: request.requestId,
                                      approved: false,
                                    );
                              },
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                await widget.controller
                                    .respondToTransferRequest(
                                      requestId: request.requestId,
                                      approved: true,
                                    );
                              },
                              child: const Text('Accept'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickOwner(List<_RemoteOwnerChoice> owners) async {
    final selectedIp = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: owners.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final owner = owners[index];
              return ListTile(
                title: Text(owner.name),
                subtitle: Text(
                  '${owner.ip} • ${owner.fileCount} файлов • ${owner.shareCount} шар',
                ),
                onTap: () => Navigator.of(context).pop(owner.ip),
              );
            },
          ),
        );
      },
    );

    if (selectedIp == null || !mounted) {
      return;
    }
    setState(() {
      _selectedOwnerIp = selectedIp;
      _selectedFileIds.clear();
    });
  }

  Future<void> _requestSelectedFiles({
    required _RemoteOwnerChoice owner,
    required List<_RemoteFileChoice> files,
  }) async {
    final selectedByCache = <String, Set<String>>{};
    for (final file in files) {
      if (!_selectedFileIds.contains(file.id)) {
        continue;
      }
      selectedByCache
          .putIfAbsent(file.cacheId, () => <String>{})
          .add(file.relativePath);
    }

    await widget.controller.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
    );

    if (!mounted) {
      return;
    }
    setState(_selectedFileIds.clear);
  }

  _RemoteOwnerChoice? _findOwnerByIp(
    List<_RemoteOwnerChoice> owners,
    String ip,
  ) {
    for (final owner in owners) {
      if (owner.ip == ip) {
        return owner;
      }
    }
    return null;
  }

  List<_RemoteOwnerChoice> _buildOwnerChoices(List<RemoteShareOption> options) {
    final ownersByIp = <String, _RemoteOwnerDraft>{};
    for (final option in options) {
      final draft = ownersByIp.putIfAbsent(
        option.ownerIp,
        () => _RemoteOwnerDraft(
          ip: option.ownerIp,
          name: option.ownerName,
          macAddress: option.ownerMacAddress,
        ),
      );
      draft.shareCount += 1;
      for (final file in option.entry.files) {
        draft.uniqueFiles.add('${option.entry.cacheId}|${file.relativePath}');
      }
    }

    final list = ownersByIp.values
        .map(
          (draft) => _RemoteOwnerChoice(
            ip: draft.ip,
            name: draft.name,
            macAddress: draft.macAddress,
            shareCount: draft.shareCount,
            fileCount: draft.uniqueFiles.length,
          ),
        )
        .toList(growable: false);
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<_RemoteFileChoice> _buildFileChoices({
    required List<RemoteShareOption> remoteOptions,
    required String ownerIp,
  }) {
    final files = <_RemoteFileChoice>[];
    for (final option in remoteOptions) {
      if (option.ownerIp != ownerIp) {
        continue;
      }
      for (final file in option.entry.files) {
        files.add(
          _RemoteFileChoice(
            ownerIp: option.ownerIp,
            cacheId: option.entry.cacheId,
            cacheDisplayName: option.entry.displayName,
            relativePath: file.relativePath,
            sizeBytes: file.sizeBytes,
          ),
        );
      }
    }
    files.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

class _RemoteOwnerChoice {
  const _RemoteOwnerChoice({
    required this.ip,
    required this.name,
    required this.macAddress,
    required this.shareCount,
    required this.fileCount,
  });

  final String ip;
  final String name;
  final String macAddress;
  final int shareCount;
  final int fileCount;
}

class _RemoteOwnerDraft {
  _RemoteOwnerDraft({
    required this.ip,
    required this.name,
    required this.macAddress,
  });

  final String ip;
  final String name;
  final String macAddress;
  int shareCount = 0;
  final Set<String> uniqueFiles = <String>{};
}

class _RemoteFileChoice {
  const _RemoteFileChoice({
    required this.ownerIp,
    required this.cacheId,
    required this.cacheDisplayName,
    required this.relativePath,
    required this.sizeBytes,
  });

  final String ownerIp;
  final String cacheId;
  final String cacheDisplayName;
  final String relativePath;
  final int sizeBytes;

  String get id => '$ownerIp|$cacheId|$relativePath';
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.onReceive,
    required this.onAdd,
    required this.onSend,
  });

  final DiscoveryController controller;
  final Future<void> Function() onReceive;
  final Future<void> Function() onAdd;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onReceive,
                icon: const Icon(Icons.arrow_downward),
                label: const Text('Принять'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: controller.isAddingShare ? null : onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Общий доступ'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.isSendingTransfer ? null : onSend,
                icon: const Icon(Icons.arrow_upward),
                label: const Text('Отправить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

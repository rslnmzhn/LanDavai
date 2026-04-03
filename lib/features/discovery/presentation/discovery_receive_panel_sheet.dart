import 'dart:io';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../files/application/preview_cache_owner.dart';
import '../../files/presentation/file_explorer/local_file_viewer.dart';
import '../../transfer/application/transfer_session_coordinator.dart';
import '../application/remote_share_browser.dart';

Future<void> showDiscoveryReceivePanel({
  required BuildContext context,
  required Future<void> Function() onRefreshRemoteShares,
  required RemoteShareBrowser remoteShareBrowser,
  required PreviewCacheOwner previewCacheOwner,
  required TransferSessionCoordinator transferSessionCoordinator,
  required bool useStandardAppDownloadFolder,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.88,
        child: DiscoveryReceivePanelSheet(
          onRefreshRemoteShares: onRefreshRemoteShares,
          remoteShareBrowser: remoteShareBrowser,
          previewCacheOwner: previewCacheOwner,
          transferSessionCoordinator: transferSessionCoordinator,
          useStandardAppDownloadFolder: useStandardAppDownloadFolder,
        ),
      );
    },
  );
}

class DiscoveryReceivePanelSheet extends StatefulWidget {
  const DiscoveryReceivePanelSheet({
    required this.onRefreshRemoteShares,
    required this.remoteShareBrowser,
    required this.previewCacheOwner,
    required this.transferSessionCoordinator,
    required this.useStandardAppDownloadFolder,
    super.key,
  });

  final Future<void> Function() onRefreshRemoteShares;
  final RemoteShareBrowser remoteShareBrowser;
  final PreviewCacheOwner previewCacheOwner;
  final TransferSessionCoordinator transferSessionCoordinator;
  final bool useStandardAppDownloadFolder;

  @override
  State<DiscoveryReceivePanelSheet> createState() =>
      _DiscoveryReceivePanelSheetState();
}

class _DiscoveryReceivePanelSheetState
    extends State<DiscoveryReceivePanelSheet> {
  String? _previewingFileId;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.transferSessionCoordinator,
        widget.remoteShareBrowser,
      ]),
      builder: (context, _) {
        final browse = widget.remoteShareBrowser.currentBrowseProjection;
        final owners = browse.owners;
        final selectedOwner = browse.selectedOwner;
        final fileChoices = browse.files;
        final folderChoices = browse.folders;
        final selectedCount = browse.selectedCount;
        final isFileListCapped = browse.isFileListCapped;
        final hiddenFilesCount = browse.hiddenFilesCount;
        final requests = widget.transferSessionCoordinator.incomingRequests;

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
                      onPressed: widget.remoteShareBrowser.isLoading
                          ? null
                          : widget.onRefreshRemoteShares,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.remoteShareBrowser.isLoading) ...[
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
                            if (isFileListCapped) ...[
                              const SizedBox(height: AppSpacing.xxs),
                              Text(
                                'Показаны первые ${fileChoices.length} файлов '
                                '(скрыто: $hiddenFilesCount) для стабильной работы.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.xs),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    widget.remoteShareBrowser
                                        .selectVisibleFiles(
                                          fileChoices.map((file) => file.id),
                                        );
                                  },
                                  child: Text(
                                    browse.isFileListCapped
                                        ? 'Выбрать все видимые'
                                        : 'Выбрать все файлы',
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () => _requestAllSharesFromOwner(
                                    owner: selectedOwner,
                                  ),
                                  icon: const Icon(Icons.download_for_offline),
                                  label: const Text('Скачать всё с устройства'),
                                ),
                                TextButton(
                                  onPressed:
                                      widget.remoteShareBrowser.clearSelections,
                                  child: const Text('Очистить'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      folderChoices.isEmpty ||
                                          browse.isFileListCapped
                                      ? null
                                      : () => _pickFolders(folderChoices),
                                  icon: const Icon(Icons.folder_copy_outlined),
                                  label: Text(
                                    'Папки целиком (${browse.selectedFolderIds.length})',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Выбрано файлов: $selectedCount',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Expanded(
                              child: ListView.separated(
                                itemCount: fileChoices.length,
                                separatorBuilder: (_, index) =>
                                    const SizedBox(height: AppSpacing.xs),
                                itemBuilder: (_, index) {
                                  final file = fileChoices[index];
                                  final coveredByFolder = browse
                                      .folderCoveredFileIds
                                      .contains(file.id);
                                  final checked = browse
                                      .effectiveSelectedFileIds
                                      .contains(file.id);
                                  final subtitle =
                                      '${file.cacheDisplayName} • ${_formatBytes(file.sizeBytes)}'
                                      '${coveredByFolder ? ' • из выбранной папки' : ''}';
                                  return CheckboxListTile(
                                    value: checked,
                                    onChanged: coveredByFolder
                                        ? null
                                        : (value) {
                                            widget.remoteShareBrowser
                                                .setFileSelected(
                                                  fileId: file.id,
                                                  isSelected: value == true,
                                                );
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
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    secondary: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Preview before download',
                                          onPressed: _previewingFileId == null
                                              ? () => _previewRemoteFile(file)
                                              : null,
                                          icon: _previewingFileId == file.id
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(
                                                  Icons.visibility_outlined,
                                                ),
                                        ),
                                        _RemoteFilePreview(file: file),
                                      ],
                                    ),
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
                                await widget.transferSessionCoordinator
                                    .respondToTransferRequest(
                                      requestId: request.requestId,
                                      approved: false,
                                    );
                              },
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: () async {
                                await widget.transferSessionCoordinator
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

  Future<void> _pickOwner(List<RemoteBrowseOwnerChoice> owners) async {
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
    widget.remoteShareBrowser.selectOwner(selectedIp);
  }

  Future<void> _pickFolders(List<RemoteBrowseFolderChoice> folders) async {
    final validIds = folders.map((folder) => folder.id).toSet();
    final initialSelection = widget
        .remoteShareBrowser
        .currentBrowseProjection
        .selectedFolderIds
        .where(validIds.contains)
        .toSet();

    final selectedIds = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final draftSelection = <String>{...initialSelection};
        return FractionallySizedBox(
          heightFactor: 0.8,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Скачать папки целиком',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Отметьте папки. Их содержимое будет скачано с сохранением структуры.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: ListView.separated(
                          itemCount: folders.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(height: AppSpacing.xs),
                          itemBuilder: (_, index) {
                            final folder = folders[index];
                            final checked = draftSelection.contains(folder.id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (value) {
                                setModalState(() {
                                  if (value == true) {
                                    draftSelection.add(folder.id);
                                  } else {
                                    draftSelection.remove(folder.id);
                                  }
                                });
                              },
                              title: Text(folder.displayLabel),
                              subtitle: Text(
                                '${folder.fileCount} файлов • ${_formatBytes(folder.totalBytes)}',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Отмена'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(context).pop(draftSelection),
                            child: const Text('Применить'),
                          ),
                        ],
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

    if (selectedIds == null || !mounted) {
      return;
    }

    widget.remoteShareBrowser.setSelectedFolderIds(selectedIds);
  }

  Future<void> _previewRemoteFile(RemoteBrowseFileChoice file) async {
    setState(() {
      _previewingFileId = file.id;
    });

    try {
      final previewPath = await widget.transferSessionCoordinator
          .requestRemoteFilePreview(
            ownerIp: file.ownerIp,
            ownerName: file.ownerName,
            cacheId: file.cacheId,
            relativePath: file.relativePath,
          );
      if (!mounted || previewPath == null || previewPath.trim().isEmpty) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => LocalFileViewerPage(
            filePath: previewPath,
            previewCacheOwner: widget.previewCacheOwner,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _previewingFileId = null;
        });
      }
    }
  }

  Future<void> _requestSelectedFiles({
    required RemoteBrowseOwnerChoice owner,
  }) async {
    final selectedByCache = widget.remoteShareBrowser
        .buildSelectedRelativePathsByCache();
    await widget.transferSessionCoordinator.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
      useStandardAppDownloadFolder: widget.useStandardAppDownloadFolder,
    );

    if (!mounted) {
      return;
    }
    widget.remoteShareBrowser.clearSelections();
  }

  Future<void> _requestAllSharesFromOwner({
    required RemoteBrowseOwnerChoice owner,
  }) async {
    final selectedByCache = widget.remoteShareBrowser
        .buildDownloadAllRequestForOwner(owner.ip);
    if (selectedByCache.isEmpty) {
      return;
    }

    await widget.transferSessionCoordinator.requestDownloadFromRemoteFiles(
      ownerIp: owner.ip,
      ownerName: owner.name,
      selectedRelativePathsByCache: selectedByCache,
      useStandardAppDownloadFolder: widget.useStandardAppDownloadFolder,
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
}

class _RemoteFilePreview extends StatelessWidget {
  const _RemoteFilePreview({required this.file});

  final RemoteBrowseFileChoice file;

  @override
  Widget build(BuildContext context) {
    final scheme = _resolveScheme(file.mediaKind);
    final hasPreview = file.previewPath != null && file.previewPath!.isNotEmpty;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: scheme.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: scheme.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPreview)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.file(
                File(file.previewPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) {
                  return Center(
                    child: Icon(scheme.icon, color: scheme.iconColor, size: 26),
                  );
                },
              ),
            )
          else
            Center(child: Icon(scheme.icon, color: scheme.iconColor, size: 26)),
          if (file.mediaKind == RemoteBrowseMediaKind.video)
            const Center(
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          Positioned(
            left: AppSpacing.xxs,
            right: AppSpacing.xxs,
            bottom: AppSpacing.xxs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxs,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                file.previewLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  _PreviewScheme _resolveScheme(RemoteBrowseMediaKind kind) {
    switch (kind) {
      case RemoteBrowseMediaKind.image:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.brandAccent,
          iconColor: AppColors.brandPrimaryDark,
          icon: Icons.image_rounded,
        );
      case RemoteBrowseMediaKind.video:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.warning,
          iconColor: AppColors.warning,
          icon: Icons.play_circle_fill_rounded,
        );
      case RemoteBrowseMediaKind.other:
        return const _PreviewScheme(
          background: AppColors.surfaceSoft,
          border: AppColors.mutedBorder,
          iconColor: AppColors.mutedIcon,
          icon: Icons.insert_drive_file_rounded,
        );
    }
  }
}

class _PreviewScheme {
  const _PreviewScheme({
    required this.background,
    required this.border,
    required this.iconColor,
    required this.icon,
  });

  final Color background;
  final Color border;
  final Color iconColor;
  final IconData icon;
}

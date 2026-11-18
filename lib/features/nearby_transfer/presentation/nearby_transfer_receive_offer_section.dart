import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';
import 'nearby_transfer_remote_preview_dialog.dart';

class NearbyTransferReceiveOfferSection extends StatelessWidget {
  const NearbyTransferReceiveOfferSection({required this.store, super.key});

  final NearbyTransferSessionStore store;
  static const int _virtualizationThreshold = 24;

  @override
  Widget build(BuildContext context) {
    final incomingOffer = store.incomingOffer;
    final progress = store.transferProgress;
    final isTransferring = store.phase == NearbyTransferSessionPhase.transferring;

    if (incomingOffer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (store.lastReceivedPaths.isNotEmpty) ...[
            _ReceivedFilesSuccessCard(savedPaths: store.lastReceivedPaths),
            const SizedBox(height: AppSpacing.md),
          ],
          Text(
            isTransferring
                ? 'nearby_transfer.offer_receiving'.tr()
                : 'nearby_transfer.offer_waiting'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: progress),
          ],
        ],
      );
    }

    final rawOfferLabel = incomingOffer.label;
    final resolvedOfferLabel =
        rawOfferLabel == 'Файлы' && incomingOffer.files.length > 1
        ? 'nearby_transfer.selected_default_label'.tr()
        : rawOfferLabel;
    final visibleNodes = store.visibleIncomingNodes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (store.lastReceivedPaths.isNotEmpty) ...[
          _ReceivedFilesSuccessCard(savedPaths: store.lastReceivedPaths),
          const SizedBox(height: AppSpacing.md),
        ],
        Text(
          resolvedOfferLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (store.currentIncomingDirectory != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: store.navigateIncomingUp,
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text('nearby_transfer.offer_back'.tr()),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  store.currentIncomingDirectory!.relativePath,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'nearby_transfer.offer_description'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'nearby_transfer.offer_selected_summary'.tr(
                namedArgs: <String, String>{
                  'count': '${store.selectedIncomingFileCount}',
                  'size': _formatBytes(context, store.selectedIncomingTotalBytes),
                },
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            TextButton(
              onPressed: isTransferring ? null : store.selectAllIncomingFiles,
              child: Text('nearby_transfer.offer_select_all'.tr()),
            ),
            if (store.hasIncomingSelection)
              TextButton(
                onPressed: isTransferring ? null : store.clearIncomingSelection,
                child: Text('nearby_transfer.offer_clear_selection'.tr()),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visibleNodes.length > _virtualizationThreshold)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: visibleNodes.length,
              separatorBuilder: (_, index) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) => _IncomingOfferTile(
                store: store,
                node: visibleNodes[index],
              ),
            ),
          )
        else
          for (var i = 0; i < visibleNodes.length; i += 1) ...[
            _IncomingOfferTile(store: store, node: visibleNodes[i]),
            if (i != visibleNodes.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        if (progress != null) ...[
          const SizedBox(height: AppSpacing.md),
          LinearProgressIndicator(value: progress),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'nearby_transfer.offer_progress_detail'.tr(
              namedArgs: <String, String>{
                'completed': _formatBytes(context, store.transferCompletedBytes),
                'total': _formatBytes(context, store.transferTotalBytes),
                'percent': '${(progress * 100).round()}',
              },
            ),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: store.hasIncomingSelection && !isTransferring
                ? store.downloadSelectedIncomingFiles
                : null,
            icon: isTransferring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            label: Text('nearby_transfer.download_selected'.tr()),
          ),
        ),
      ],
    );
  }
}

class _ReceivedFilesSuccessCard extends StatelessWidget {
  const _ReceivedFilesSuccessCard({required this.savedPaths});

  final List<String> savedPaths;

  @override
  Widget build(BuildContext context) {
    final folderPath = p.dirname(savedPaths.first);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.success),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  'nearby_transfer.received_card_title'.tr(
                    namedArgs: <String, String>{
                      'count': '${savedPaths.length}',
                    },
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            folderPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () => unawaited(OpenFilex.open(folderPath)),
            icon: const Icon(Icons.folder_open_rounded),
            label: Text('nearby_transfer.received_open_folder'.tr()),
          ),
        ],
      ),
    );
  }
}

class _IncomingOfferTile extends StatelessWidget {
  const _IncomingOfferTile({required this.store, required this.node});

  final NearbyTransferSessionStore store;
  final NearbyTransferRemoteOfferNode node;

  @override
  Widget build(BuildContext context) {
    final file = node.asFileDescriptor;
    final canPreview =
        file != null &&
        file.previewKind != NearbyTransferRemotePreviewKind.none;
    final checkboxValue = store.isIncomingNodePartiallySelected(node.id)
        ? null
        : store.isIncomingNodeSelected(node.id);

    return Material(
      color: AppColors.surfaceSoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(
          color: AppColors.brandAccent.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (node.isDirectory) {
            store.openIncomingDirectory(node.id);
          } else {
            store.toggleIncomingNodeSelection(
              node.id,
              !(checkboxValue ?? false),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              _IncomingOfferPreviewBadge(node: node),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _buildSecondaryLabel(context, node),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canPreview)
                IconButton(
                  key: ValueKey<String>(
                    'nearby-transfer-preview-button-${node.id}',
                  ),
                  tooltip: 'common.preview'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: store.isPreviewLoading(file.id)
                      ? null
                      : () async {
                          final preview = await store.loadIncomingPreview(file);
                          if (!context.mounted || preview == null) {
                            return;
                          }
                          await showDialog<void>(
                            context: context,
                            builder: (context) {
                              return NearbyTransferRemotePreviewDialog(
                                filePathLabel: file.relativePath,
                                preview: preview,
                              );
                            },
                          );
                        },
                  icon: store.isPreviewLoading(file.id)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_rounded),
                ),
              if (node.isDirectory)
                IconButton(
                  key: ValueKey<String>(
                    'nearby-transfer-open-folder-button-${node.id}',
                  ),
                  tooltip: 'common.open_folder'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => store.openIncomingDirectory(node.id),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              Checkbox(
                key: ValueKey<String>('nearby-transfer-checkbox-${node.id}'),
                tristate: true,
                visualDensity: VisualDensity.compact,
                value: checkboxValue,
                onChanged: (value) {
                  store.toggleIncomingNodeSelection(node.id, value ?? false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingOfferPreviewBadge extends StatelessWidget {
  const _IncomingOfferPreviewBadge({required this.node});

  final NearbyTransferRemoteOfferNode node;

  @override
  Widget build(BuildContext context) {
    final icon = switch (node.kind) {
      NearbyTransferRemoteOfferNodeKind.directory => Icons.folder_outlined,
      NearbyTransferRemoteOfferNodeKind.file => switch (node.previewKind) {
        NearbyTransferRemotePreviewKind.image => Icons.image_outlined,
        NearbyTransferRemotePreviewKind.text => Icons.description_outlined,
        NearbyTransferRemotePreviewKind.none =>
          Icons.insert_drive_file_outlined,
      },
    };
    return Container(
      key: ValueKey<String>('nearby-transfer-preview-badge-${node.id}'),
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Icon(icon, color: AppColors.brandPrimary),
    );
  }
}

String _buildSecondaryLabel(
  BuildContext context,
  NearbyTransferRemoteOfferNode node,
) {
  final sizeLabel = _formatBytes(context, node.sizeBytes);
  if (node.isFile) {
    return sizeLabel;
  }
  return 'nearby_transfer.offer_folder_summary'.tr(
    namedArgs: <String, String>{
      'count': '${node.fileCount}',
      'size': sizeLabel,
    },
  );
}

String _formatBytes(BuildContext context, int bytes) {
  if (bytes < 1024) {
    return 'common.format_size_b'.tr(
      namedArgs: <String, String>{'value': '$bytes'},
    );
  }
  if (bytes < 1024 * 1024) {
    return 'common.format_size_kb'.tr(
      namedArgs: <String, String>{'value': (bytes / 1024).toStringAsFixed(1)},
    );
  }
  if (bytes < 1024 * 1024 * 1024) {
    return 'common.format_size_mb'.tr(
      namedArgs: <String, String>{
        'value': (bytes / (1024 * 1024)).toStringAsFixed(1),
      },
    );
  }
  return 'common.format_size_gb'.tr(
    namedArgs: <String, String>{
      'value': (bytes / (1024 * 1024 * 1024)).toStringAsFixed(1),
    },
  );
}

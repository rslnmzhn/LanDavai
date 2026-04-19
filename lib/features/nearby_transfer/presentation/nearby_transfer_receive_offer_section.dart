import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import '../data/nearby_transfer_transport_adapter.dart';
import 'nearby_transfer_remote_preview_dialog.dart';

class NearbyTransferReceiveOfferSection extends StatelessWidget {
  const NearbyTransferReceiveOfferSection({required this.store, super.key});

  final NearbyTransferSessionStore store;

  @override
  Widget build(BuildContext context) {
    final incomingOffer = store.incomingOffer;
    if (incomingOffer == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.phase == NearbyTransferSessionPhase.transferring
                ? 'nearby_transfer.offer_receiving'.tr()
                : 'nearby_transfer.offer_waiting'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (store.transferProgress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: store.transferProgress),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          incomingOffer.label,
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
        const SizedBox(height: AppSpacing.md),
        ...store.visibleIncomingNodes.map((node) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _IncomingOfferTile(store: store, node: node),
          );
        }),
        if (store.transferProgress != null) ...[
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: store.transferProgress),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: store.hasIncomingSelection
              ? store.downloadSelectedIncomingFiles
              : null,
          icon: const Icon(Icons.download_rounded),
          label: Text('nearby_transfer.download_selected'.tr()),
        ),
      ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.35),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              60,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IncomingOfferPreviewBadge(node: node),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.name),
                      const SizedBox(height: AppSpacing.xs),
                      Text(_buildSecondaryLabel(context, node)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (canPreview)
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: IconButton(
                key: ValueKey<String>(
                  'nearby-transfer-preview-button-${node.id}',
                ),
                tooltip: 'common.preview'.tr(),
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
            ),
          if (node.isDirectory)
            Positioned(
              top: AppSpacing.xs,
              right: canPreview ? 44 : AppSpacing.xs,
              child: IconButton(
                key: ValueKey<String>(
                  'nearby-transfer-open-folder-button-${node.id}',
                ),
                tooltip: 'common.open_folder'.tr(),
                onPressed: () => store.openIncomingDirectory(node.id),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          Positioned(
            right: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Checkbox(
              key: ValueKey<String>('nearby-transfer-checkbox-${node.id}'),
              tristate: true,
              value: checkboxValue,
              onChanged: (value) {
                store.toggleIncomingNodeSelection(node.id, value ?? false);
              },
            ),
          ),
        ],
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
      width: 52,
      height: 52,
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

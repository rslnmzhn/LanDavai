import 'package:flutter/material.dart';

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
                ? 'Получение файлов...'
                : 'Соединение установлено. Ожидаем список файлов от подключённого устройства.',
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
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Выберите файлы для загрузки. Предпросмотр доступен для поддерживаемых форматов.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        ...incomingOffer.files.map((file) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _IncomingFileTile(store: store, file: file),
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
          label: const Text('Скачать выбранные'),
        ),
      ],
    );
  }
}

class _IncomingFileTile extends StatelessWidget {
  const _IncomingFileTile({required this.store, required this.file});

  final NearbyTransferSessionStore store;
  final NearbyTransferRemoteFileDescriptor file;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.brandAccent.withValues(alpha: 0.35),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        leading: Checkbox(
          value: store.isIncomingFileSelected(file.id),
          onChanged: (value) {
            store.toggleIncomingFileSelection(file.id, value ?? false);
          },
        ),
        title: Text(file.relativePath),
        subtitle: Text(_formatBytes(file.sizeBytes)),
        trailing: file.previewKind == NearbyTransferRemotePreviewKind.none
            ? null
            : TextButton.icon(
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
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.visibility_rounded),
                label: const Text('Preview'),
              ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

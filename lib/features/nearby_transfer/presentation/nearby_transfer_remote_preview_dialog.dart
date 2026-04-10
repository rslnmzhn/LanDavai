import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../data/nearby_transfer_transport_adapter.dart';

class NearbyTransferRemotePreviewDialog extends StatelessWidget {
  const NearbyTransferRemotePreviewDialog({
    required this.filePathLabel,
    required this.preview,
    super.key,
  });

  final String filePathLabel;
  final NearbyTransferRemoteFilePreview preview;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(filePathLabel),
      content: SizedBox(width: 520, child: _PreviewBody(preview: preview)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.preview});

  final NearbyTransferRemoteFilePreview preview;

  @override
  Widget build(BuildContext context) {
    switch (preview.kind) {
      case NearbyTransferRemotePreviewKind.text:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.isTruncated)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Text(
                  'Предпросмотр ограничен первыми 64 KB.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (preview.isTruncated) const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview.textContent ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'JetBrainsMono',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        );
      case NearbyTransferRemotePreviewKind.image:
        final bytes = preview.imageBytes;
        if (bytes == null || bytes.isEmpty) {
          return const Text('Предпросмотр недоступен.');
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Text('Не удалось открыть изображение.');
            },
          ),
        );
      case NearbyTransferRemotePreviewKind.none:
        return const Text('Предпросмотр недоступен для этого файла.');
    }
  }
}

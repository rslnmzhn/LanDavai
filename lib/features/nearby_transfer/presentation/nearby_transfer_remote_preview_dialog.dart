import 'dart:math' as math;
import 'dart:typed_data';

import 'package:easy_localization/easy_localization.dart';
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final dialogWidth = math.min(520.0, math.max(240.0, screenWidth - 48.0));
    return AlertDialog(
      title: Text(
        filePathLabel,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      content: SizedBox(
        width: dialogWidth,
        child: _PreviewBody(preview: preview),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('nearby_transfer.close'.tr()),
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
                child: Text(
                  'nearby_transfer.preview_truncated'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
            if (preview.isTruncated) const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview.textContent ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'JetBrains Mono',
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
          return Text('nearby_transfer.preview_unavailable'.tr());
        }
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Image.memory(
              Uint8List.fromList(bytes),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Text('nearby_transfer.preview_image_failed'.tr());
              },
            ),
          ),
        );
      case NearbyTransferRemotePreviewKind.none:
        return Text('nearby_transfer.preview_unsupported'.tr());
    }
  }
}

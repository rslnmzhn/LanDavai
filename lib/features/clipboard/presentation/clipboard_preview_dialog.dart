import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';

Future<void> showClipboardTextPreviewDialog({
  required BuildContext context,
  required String title,
  required String text,
  String? note,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(text),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    note,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('clipboard.close'.tr()),
          ),
        ],
      );
    },
  );
}

Future<void> showClipboardImagePreviewDialog({
  required BuildContext context,
  required String title,
  required ImageProvider<Object> imageProvider,
  String? note,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(dialogContext).textTheme.titleLarge,
                ),
                if (note != null && note.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    note,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      child: Center(
                        child: Image(
                          image: imageProvider,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stackTrace) => Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Text(
                              'clipboard.image_preview_unavailable'.tr(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text('clipboard.close'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

ImageProvider<Object>? buildClipboardFullImageProviderFromPath(
  String? imagePath,
) {
  final path = imagePath?.trim();
  if (path == null || path.isEmpty) {
    return null;
  }
  return FileImage(File(path));
}

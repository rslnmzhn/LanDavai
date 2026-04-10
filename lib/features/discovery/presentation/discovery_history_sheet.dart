import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_spacing.dart';
import '../../history/application/download_history_boundary.dart';

class DiscoveryHistorySheet extends StatelessWidget {
  const DiscoveryHistorySheet({
    required this.downloadHistoryBoundary,
    required this.onOpenPath,
    super.key,
  });

  final DownloadHistoryBoundary downloadHistoryBoundary;
  final Future<void> Function(String path) onOpenPath;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: downloadHistoryBoundary,
      builder: (context, _) {
        final history = downloadHistoryBoundary.records;
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
                                padding: const EdgeInsets.all(AppSpacing.md),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                    const SizedBox(height: AppSpacing.xxs),
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
                                              label: Text(p.basename(path)),
                                              onPressed: () => onOpenPath(path),
                                            ),
                                          )
                                          .toList(growable: false),
                                    ),
                                    if (item.savedPaths.length > 6) ...[
                                      const SizedBox(height: AppSpacing.xxs),
                                      Text(
                                        '+${item.savedPaths.length - 6} more files',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.sm),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          onOpenPath(item.rootPath),
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

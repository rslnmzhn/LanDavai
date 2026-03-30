import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../application/files_feature_state_owner.dart';
import '../../application/preview_cache_owner.dart';
import 'file_explorer_models.dart';

class ExplorerPathHeader extends StatelessWidget {
  const ExplorerPathHeader({
    required this.rootLabel,
    required this.relativePath,
    required this.canGoUp,
    required this.onGoUp,
    required this.canSelectRoot,
    required this.onSelectRoot,
    super.key,
  });

  final String rootLabel;
  final String relativePath;
  final bool canGoUp;
  final VoidCallback? onGoUp;
  final bool canSelectRoot;
  final VoidCallback? onSelectRoot;

  @override
  Widget build(BuildContext context) {
    final full = relativePath.isEmpty
        ? rootLabel
        : '$rootLabel / $relativePath';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Up',
              onPressed: canGoUp ? onGoUp : null,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(full, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Select root',
              onPressed: canSelectRoot ? onSelectRoot : null,
              icon: const Icon(Icons.source_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class ExplorerEntityTile extends StatelessWidget {
  const ExplorerEntityTile({
    required this.entry,
    required this.previewCacheOwner,
    required this.onTap,
    this.onDelete,
    super.key,
  });

  final FilesFeatureEntry entry;
  final PreviewCacheOwner previewCacheOwner;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      tileColor: AppColors.surface,
      leading: ExplorerEntityLeading(
        isDirectory: entry.isDirectory,
        filePath: entry.filePath,
        previewCacheOwner: previewCacheOwner,
      ),
      title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        entry.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: 'Remove from sharing',
              onPressed: () async {
                await onDelete!();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
      onTap: onTap,
    );
  }
}

class ExplorerEntityLeading extends StatelessWidget {
  const ExplorerEntityLeading({
    required this.isDirectory,
    required this.filePath,
    required this.previewCacheOwner,
    this.size = 44,
    super.key,
  });

  final bool isDirectory;
  final String? filePath;
  final PreviewCacheOwner previewCacheOwner;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isDirectory) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.brandPrimary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(Icons.folder_rounded, color: AppColors.brandPrimary),
      );
    }
    final path = filePath;
    if (path == null || path.trim().isEmpty) {
      return _ExplorerFilePreview(
        filePath: '',
        previewCacheOwner: previewCacheOwner,
        size: size,
      );
    }
    return _ExplorerFilePreview(
      filePath: path,
      previewCacheOwner: previewCacheOwner,
      size: size,
    );
  }
}

class _ExplorerFilePreview extends StatelessWidget {
  const _ExplorerFilePreview({
    required this.filePath,
    required this.previewCacheOwner,
    this.size = 44,
  });

  final String filePath;
  final PreviewCacheOwner previewCacheOwner;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ext = p.extension(filePath).toLowerCase();
    if (explorerImageExtensions.contains(ext)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.file(
          File(filePath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackIcon(Icons.image_rounded),
        ),
      );
    }
    if (explorerVideoExtensions.contains(ext)) {
      return _ExplorerVideoPreview(
        filePath: filePath,
        previewCacheOwner: previewCacheOwner,
        size: size,
      );
    }
    if (explorerAudioExtensions.contains(ext)) {
      return _ExplorerAudioPreview(
        filePath: filePath,
        previewCacheOwner: previewCacheOwner,
        size: size,
      );
    }
    return _fallbackIcon(Icons.insert_drive_file_rounded);
  }

  Widget _fallbackIcon(IconData icon) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: AppColors.mutedIcon),
    );
  }
}

class _ExplorerVideoPreview extends StatefulWidget {
  const _ExplorerVideoPreview({
    required this.filePath,
    required this.previewCacheOwner,
    this.size = 44,
  });

  final String filePath;
  final PreviewCacheOwner previewCacheOwner;
  final double size;

  @override
  State<_ExplorerVideoPreview> createState() => _ExplorerVideoPreviewState();
}

class _ExplorerVideoPreviewState extends State<_ExplorerVideoPreview> {
  late final Future<Uint8List?> _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _thumbnailFuture = _loadThumbnail();
  }

  Future<Uint8List?> _loadThumbnail() async {
    return widget.previewCacheOwner.loadVideoPreview(
      filePath: widget.filePath,
      maxExtent: math.max(180, (widget.size * 2).round()),
      quality: 72,
      timeMs: 700,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _thumbnailFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildFallback();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Image.memory(
                bytes,
                width: widget.size,
                height: widget.size,
                fit: BoxFit.cover,
              ),
              Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white,
                size: widget.size * 0.42,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(Icons.videocam_rounded, color: AppColors.mutedIcon),
    );
  }
}

class _ExplorerAudioPreview extends StatefulWidget {
  const _ExplorerAudioPreview({
    required this.filePath,
    required this.previewCacheOwner,
    this.size = 44,
  });

  final String filePath;
  final PreviewCacheOwner previewCacheOwner;
  final double size;

  @override
  State<_ExplorerAudioPreview> createState() => _ExplorerAudioPreviewState();
}

class _ExplorerAudioPreviewState extends State<_ExplorerAudioPreview> {
  late final Future<Uint8List?> _coverFuture;

  @override
  void initState() {
    super.initState();
    _coverFuture = widget.previewCacheOwner.loadAudioCover(
      filePath: widget.filePath,
      maxExtent: math.max(180, (widget.size * 2).round()),
      quality: 78,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _coverFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return _buildFallback();
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.memory(
            bytes,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
          ),
        );
      },
    );
  }

  Widget _buildFallback() {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: const Icon(Icons.audiotrack_rounded, color: AppColors.mutedIcon),
    );
  }
}

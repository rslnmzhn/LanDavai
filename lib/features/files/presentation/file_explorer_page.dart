import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:video_player/video_player.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';

class FileExplorerRoot {
  const FileExplorerRoot({required this.label, required this.path});

  final String label;
  final String path;
}

class FileExplorerPage extends StatefulWidget {
  const FileExplorerPage({required this.roots, super.key});

  final List<FileExplorerRoot> roots;

  @override
  State<FileExplorerPage> createState() => _FileExplorerPageState();
}

class _FileExplorerPageState extends State<FileExplorerPage> {
  late final List<FileExplorerRoot> _roots;
  var _selectedRootIndex = 0;
  late String _currentPath;

  bool _isLoading = false;
  String? _errorMessage;
  List<FileSystemEntity> _entities = const <FileSystemEntity>[];

  FileExplorerRoot get _selectedRoot => _roots[_selectedRootIndex];

  @override
  void initState() {
    super.initState();
    _roots = widget.roots.where((root) => root.path.trim().isNotEmpty).toList();
    if (_roots.isEmpty) {
      _errorMessage = 'No local folders available.';
      _currentPath = Directory.current.path;
      return;
    }

    _selectedRootIndex = 0;
    _currentPath = _roots.first.path;
    _loadDirectory(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            tooltip: 'Select root',
            onPressed: _roots.isEmpty ? null : _pickRoot,
            icon: const Icon(Icons.source_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => _loadDirectory(_currentPath),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ExplorerPathHeader(
                rootLabel: _selectedRoot.label,
                relativePath: _relativePathLabel(),
                canGoUp: _canGoUp,
                onGoUp: _canGoUp ? _goUp : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_isLoading)
                const LinearProgressIndicator(
                  minHeight: 3,
                  color: AppColors.brandPrimary,
                  backgroundColor: AppColors.mutedBorder,
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                _ExplorerErrorBanner(
                  message: _errorMessage!,
                  onRetry: () => _loadDirectory(_currentPath),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _entities.isEmpty
                    ? const Center(child: Text('Folder is empty'))
                    : ListView.separated(
                        itemCount: _entities.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: AppSpacing.xs),
                        itemBuilder: (_, index) {
                          final entity = _entities[index];
                          return _ExplorerEntityTile(
                            entity: entity,
                            onTap: () => _openEntity(entity),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canGoUp {
    final root = _normalizePath(_selectedRoot.path);
    final current = _normalizePath(_currentPath);
    if (root == current) {
      return false;
    }
    return _isWithinRoot(current, root);
  }

  Future<void> _pickRoot() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _roots.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (_, index) {
              final root = _roots[index];
              return ListTile(
                leading: const Icon(Icons.folder_special_rounded),
                title: Text(root.label),
                subtitle: Text(root.path),
                trailing: index == _selectedRootIndex
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(index),
              );
            },
          ),
        );
      },
    );

    if (selected == null || selected == _selectedRootIndex || !mounted) {
      return;
    }

    setState(() {
      _selectedRootIndex = selected;
      _currentPath = _roots[selected].path;
      _errorMessage = null;
    });
    await _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final directory = Directory(path);
      if (!await directory.exists()) {
        throw FileSystemException('Directory not found', path);
      }

      final items = await directory.list(followLinks: false).toList();
      items.sort((a, b) {
        final aDir = a is Directory;
        final bDir = b is Directory;
        if (aDir != bDir) {
          return aDir ? -1 : 1;
        }
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _currentPath = path;
        _entities = items;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entities = const <FileSystemEntity>[];
        _isLoading = false;
        _errorMessage = 'Cannot open folder: $error';
      });
    }
  }

  Future<void> _goUp() async {
    final parentPath = Directory(_currentPath).parent.path;
    final rootPath = _selectedRoot.path;
    final normalizedParent = _normalizePath(parentPath);
    final normalizedRoot = _normalizePath(rootPath);

    final targetPath = _isWithinRoot(normalizedParent, normalizedRoot)
        ? parentPath
        : rootPath;
    await _loadDirectory(targetPath);
  }

  Future<void> _openEntity(FileSystemEntity entity) async {
    if (entity is Directory) {
      await _loadDirectory(entity.path);
      return;
    }

    if (!mounted) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalFileViewerPage(filePath: entity.path),
      ),
    );
  }

  String _relativePathLabel() {
    final rootPath = _selectedRoot.path;
    final currentPath = _currentPath;
    var relative = p.relative(currentPath, from: rootPath);
    if (relative == '.') {
      relative = '';
    }
    return relative.replaceAll('\\', '/');
  }

  String _normalizePath(String value) {
    var normalized = p.normalize(value).replaceAll('\\', '/').trim();
    if (Platform.isWindows) {
      normalized = normalized.toLowerCase();
    }
    return normalized;
  }

  bool _isWithinRoot(String candidate, String root) {
    if (candidate == root) {
      return true;
    }
    return candidate.startsWith('$root/');
  }
}

class LocalFileViewerPage extends StatelessWidget {
  const LocalFileViewerPage({required this.filePath, super.key});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(filePath);
    final fileKind = _resolveFileKind(filePath);

    Widget body;
    switch (fileKind) {
      case _LocalFileKind.image:
        body = _ImageFileViewer(filePath: filePath);
      case _LocalFileKind.video:
        body = _VideoFileViewer(filePath: filePath);
      case _LocalFileKind.text:
        body = _TextFileViewer(filePath: filePath);
      case _LocalFileKind.pdf:
        body = _PdfFileViewer(filePath: filePath);
      case _LocalFileKind.other:
        body = _UnsupportedFileViewer(filePath: filePath);
    }

    return Scaffold(
      appBar: AppBar(title: Text(fileName)),
      body: SafeArea(child: body),
    );
  }

  _LocalFileKind _resolveFileKind(String path) {
    final ext = p.extension(path).toLowerCase();
    if (_imageExtensions.contains(ext)) {
      return _LocalFileKind.image;
    }
    if (_videoExtensions.contains(ext)) {
      return _LocalFileKind.video;
    }
    if (_textExtensions.contains(ext)) {
      return _LocalFileKind.text;
    }
    if (ext == '.pdf') {
      return _LocalFileKind.pdf;
    }
    return _LocalFileKind.other;
  }

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.tif',
    '.tiff',
  };

  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.mkv',
    '.avi',
    '.webm',
    '.m4v',
    '.3gp',
    '.mpeg',
    '.mpg',
  };

  static const Set<String> _textExtensions = <String>{
    '.txt',
    '.md',
    '.log',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
  };
}

class _ImageFileViewer extends StatelessWidget {
  const _ImageFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.2,
      maxScale: 4,
      child: Center(
        child: Image.file(
          File(filePath),
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const _ViewerError(message: 'Cannot open image file.');
          },
        ),
      ),
    );
  }
}

class _VideoFileViewer extends StatefulWidget {
  const _VideoFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_VideoFileViewer> createState() => _VideoFileViewerState();
}

class _VideoFileViewerState extends State<_VideoFileViewer> {
  VideoPlayerController? _controller;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.filePath));
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage =
            'Cannot open video in built-in player on this platform.\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _UnsupportedFileViewer(
        filePath: widget.filePath,
        hintMessage: _errorMessage,
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final isPlaying = controller.value.isPlaying;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          colors: const VideoProgressColors(
            playedColor: AppColors.brandPrimary,
            bufferedColor: AppColors.brandAccent,
            backgroundColor: AppColors.mutedBorder,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: isPlaying ? 'Pause' : 'Play',
              onPressed: () async {
                if (isPlaying) {
                  await controller.pause();
                } else {
                  await controller.play();
                }
                if (mounted) {
                  setState(() {});
                }
              },
              icon: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                size: 34,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }
}

class _TextFileViewer extends StatefulWidget {
  const _TextFileViewer({required this.filePath});

  final String filePath;

  @override
  State<_TextFileViewer> createState() => _TextFileViewerState();
}

class _TextFileViewerState extends State<_TextFileViewer> {
  static const int _previewLimitBytes = 2 * 1024 * 1024;

  bool _isLoading = true;
  String? _errorMessage;
  String _content = '';
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      final previewBytes = bytes.length > _previewLimitBytes
          ? bytes.sublist(0, _previewLimitBytes)
          : bytes;

      if (!mounted) {
        return;
      }
      setState(() {
        _content = utf8.decode(previewBytes, allowMalformed: true);
        _truncated = bytes.length > _previewLimitBytes;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = 'Cannot read text file: $error';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ViewerError(message: _errorMessage!);
    }

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_truncated)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                'Preview is truncated to 2 MB.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (_truncated) const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                _content,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontFamily: 'JetBrainsMono',
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdfFileViewer extends StatelessWidget {
  const _PdfFileViewer({required this.filePath});

  final String filePath;

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    return SfPdfViewer.file(
      file,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (details) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF load failed: ${details.error}')),
        );
      },
    );
  }
}

class _UnsupportedFileViewer extends StatelessWidget {
  const _UnsupportedFileViewer({required this.filePath, this.hintMessage});

  final String filePath;
  final String? hintMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file_rounded, size: 42),
            const SizedBox(height: AppSpacing.sm),
            Text(
              hintMessage ??
                  'This file type is not supported by the built-in viewer yet.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: () async {
                await OpenFilex.open(filePath);
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open externally'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
        ),
      ),
    );
  }
}

class _ExplorerPathHeader extends StatelessWidget {
  const _ExplorerPathHeader({
    required this.rootLabel,
    required this.relativePath,
    required this.canGoUp,
    required this.onGoUp,
  });

  final String rootLabel;
  final String relativePath;
  final bool canGoUp;
  final VoidCallback? onGoUp;

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
          ],
        ),
      ),
    );
  }
}

class _ExplorerEntityTile extends StatelessWidget {
  const _ExplorerEntityTile({required this.entity, required this.onTap});

  final FileSystemEntity entity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDirectory = entity is Directory;
    final name = p.basename(entity.path);

    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      tileColor: AppColors.surface,
      leading: Icon(
        isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
        color: isDirectory ? AppColors.brandPrimary : AppColors.mutedIcon,
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(entity.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

class _ExplorerErrorBanner extends StatelessWidget {
  const _ExplorerErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

enum _LocalFileKind { image, video, text, pdf, other }

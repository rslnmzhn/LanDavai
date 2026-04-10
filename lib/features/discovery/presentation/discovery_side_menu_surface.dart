import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../settings/domain/app_settings.dart';
import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/data/thumbnail_cache_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../application/discovery_controller.dart';
import '../application/video_link_session_boundary.dart';

class DiscoverySideMenuSurface extends StatefulWidget {
  const DiscoverySideMenuSurface({
    required this.onOpenFriends,
    required this.onOpenSettings,
    required this.onOpenClipboard,
    required this.onOpenHistory,
    required this.onOpenFiles,
    required this.videoLinkSessionBoundary,
    required this.sharedCacheCatalog,
    required this.sharedCacheIndexStore,
    required this.settings,
    required this.ownerMacAddress,
    required this.isBoundaryReady,
    required this.reloadVersion,
    required this.closeOnTap,
    this.onRefresh,
    super.key,
  });

  final Future<void> Function() onOpenFriends;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onOpenClipboard;
  final Future<void> Function() onOpenHistory;
  final Future<void> Function() onOpenFiles;
  final Future<void> Function()? onRefresh;
  final VideoLinkSessionBoundary videoLinkSessionBoundary;
  final SharedCacheCatalog sharedCacheCatalog;
  final SharedCacheIndexStore sharedCacheIndexStore;
  final AppSettings settings;
  final String ownerMacAddress;
  final bool isBoundaryReady;
  final int reloadVersion;
  final bool closeOnTap;

  @override
  State<DiscoverySideMenuSurface> createState() =>
      _DiscoverySideMenuSurfaceState();
}

class _DiscoverySideMenuSurfaceState extends State<DiscoverySideMenuSurface> {
  List<ShareableVideoFile> _shareableVideoFiles = const <ShareableVideoFile>[];
  String? _selectedShareableVideoId;
  bool _isLoadingShareableVideoFiles = false;

  @override
  void initState() {
    super.initState();
    if (widget.isBoundaryReady) {
      unawaited(_reloadShareableVideoFiles());
    }
  }

  @override
  void didUpdateWidget(covariant DiscoverySideMenuSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldReload =
        oldWidget.sharedCacheCatalog != widget.sharedCacheCatalog ||
        oldWidget.sharedCacheIndexStore != widget.sharedCacheIndexStore ||
        oldWidget.ownerMacAddress != widget.ownerMacAddress ||
        oldWidget.reloadVersion != widget.reloadVersion ||
        (!oldWidget.isBoundaryReady && widget.isBoundaryReady);
    if (shouldReload && widget.isBoundaryReady) {
      unawaited(_reloadShareableVideoFiles());
    }
  }

  ShareableVideoFile? get _selectedShareableVideoFile {
    final selectedId = _selectedShareableVideoId;
    if (selectedId == null) {
      return null;
    }
    for (final file in _shareableVideoFiles) {
      if (file.id == selectedId) {
        return file;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.videoLinkSessionBoundary,
      builder: (context, _) {
        return SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Text(
                  'Menu',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _buildItem(
                context: context,
                icon: Icons.group_rounded,
                title: 'Friends',
                onTap: widget.onOpenFriends,
              ),
              _buildItem(
                context: context,
                icon: Icons.tune_rounded,
                title: 'Settings',
                onTap: widget.onOpenSettings,
              ),
              _buildItem(
                context: context,
                icon: Icons.content_paste_rounded,
                title: 'Clipboard',
                onTap: widget.onOpenClipboard,
              ),
              _buildItem(
                context: context,
                icon: Icons.history,
                title: 'Download history',
                onTap: widget.onOpenHistory,
              ),
              _buildItem(
                context: context,
                icon: Icons.folder_open_rounded,
                title: 'Files',
                onTap: widget.onOpenFiles,
              ),
              _buildItem(
                context: context,
                icon: Icons.refresh_rounded,
                title: 'Refresh',
                onTap: widget.onRefresh,
              ),
              _VideoLinkServerCard(
                videoLinkSessionBoundary: widget.videoLinkSessionBoundary,
                videos: _shareableVideoFiles,
                selectedVideoId: _selectedShareableVideoId,
                isLoadingVideos: _isLoadingShareableVideoFiles,
                onSelectedVideoChanged: (next) {
                  setState(() {
                    _selectedShareableVideoId = next;
                  });
                },
                onOpenVideoList: () => unawaited(_reloadShareableVideoFiles()),
                onToggle: _toggleVideoLinkServer,
                onCopyLink: widget.videoLinkSessionBoundary.watchUrl == null
                    ? null
                    : () => unawaited(
                        _copyToClipboard(
                          widget.videoLinkSessionBoundary.watchUrl!,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Future<void> Function()? onTap,
  }) {
    final isEnabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Material(
        color: isEnabled ? AppColors.surfaceSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          key: Key(
            'discovery-menu-action-${title.toLowerCase().replaceAll(' ', '-')}',
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: !isEnabled
              ? null
              : () {
                  if (widget.closeOnTap) {
                    Navigator.of(context).pop();
                  }
                  unawaited(onTap());
                },
          child: Ink(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isEnabled
                    ? AppColors.mutedBorder
                    : AppColors.mutedBorder.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? AppColors.brandAccent.withValues(alpha: 0.24)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    color: isEnabled
                        ? AppColors.brandPrimaryDark
                        : AppColors.textMuted,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: isEnabled
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isEnabled
                      ? AppColors.textSecondary
                      : AppColors.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _copyToClipboard(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _showVideoLinkMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
  }

  Future<void> _reloadShareableVideoFiles({bool notifyIfEmpty = false}) async {
    if (!widget.isBoundaryReady || _isLoadingShareableVideoFiles) {
      return;
    }
    setState(() {
      _isLoadingShareableVideoFiles = true;
    });
    try {
      final files = await _listShareableVideoFiles();
      if (!mounted) {
        return;
      }
      var selectedId = _selectedShareableVideoId;
      if (selectedId == null || files.every((file) => file.id != selectedId)) {
        selectedId = files.isEmpty ? null : files.first.id;
      }
      setState(() {
        _shareableVideoFiles = files;
        _selectedShareableVideoId = selectedId;
      });
      if (notifyIfEmpty && files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No shared video files available. Add shared files first.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingShareableVideoFiles = false;
        });
      }
    }
  }

  Future<void> _publishSelectedVideoLink() async {
    final selected = _selectedShareableVideoFile;
    if (selected == null) {
      _showVideoLinkMessage('Select a video file first.', isError: true);
      return;
    }
    final password = widget.settings.videoLinkPassword.trim();
    if (password.isEmpty) {
      _showVideoLinkMessage(
        'Set a web-link password in Settings.',
        isError: true,
      );
      return;
    }

    try {
      final link = await widget.videoLinkSessionBoundary.publishVideoLinkShare(
        filePath: selected.absolutePath,
        displayName: selected.fileName,
        password: password,
      );
      if (!mounted) {
        return;
      }
      _showVideoLinkMessage(
        link == null
            ? 'Video link updated for ${selected.fileName}.'
            : 'Video link updated: $link',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showVideoLinkMessage(
        'Failed to publish video link: $error',
        isError: true,
      );
    }
  }

  Future<void> _toggleVideoLinkServer(bool enabled) async {
    if (enabled) {
      if (_shareableVideoFiles.isEmpty) {
        await _reloadShareableVideoFiles(notifyIfEmpty: true);
      }
      if (_shareableVideoFiles.isEmpty) {
        return;
      }
      await _publishSelectedVideoLink();
      return;
    }

    final activeSession = widget.videoLinkSessionBoundary.activeSession;
    if (activeSession == null) {
      return;
    }
    final shouldStop = await _confirmStopVideoLinkShare();
    if (!shouldStop) {
      return;
    }
    try {
      await widget.videoLinkSessionBoundary.stopVideoLinkShare();
      if (!mounted) {
        return;
      }
      _showVideoLinkMessage('Video link sharing stopped.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showVideoLinkMessage(
        'Failed to stop video link sharing: $error',
        isError: true,
      );
    }
  }

  Future<bool> _confirmStopVideoLinkShare() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Stop video link sharing?'),
          content: const Text(
            'The active video link will stop working until you publish a file again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<List<SharedFolderCacheRecord>> _loadOwnerCachesForVideos() async {
    final ownerMacAddress = widget.ownerMacAddress.trim();
    if (ownerMacAddress.isNotEmpty) {
      try {
        await widget.sharedCacheCatalog.loadOwnerCaches(
          ownerMacAddress: ownerMacAddress,
        );
      } catch (_) {
        // Keep using the last loaded owner snapshot in the current session.
      }
    }
    return widget.sharedCacheCatalog.ownerCaches;
  }

  Future<List<ShareableVideoFile>> _listShareableVideoFiles() async {
    final caches = await _loadOwnerCachesForVideos();
    final files = <ShareableVideoFile>[];
    for (final cache in caches) {
      final entries = await widget.sharedCacheIndexStore.readIndexEntries(
        cache,
      );
      for (final entry in entries) {
        if (!_isVideoPath(entry.relativePath)) {
          continue;
        }
        final absolutePath = _resolveCacheFilePath(cache: cache, entry: entry);
        if (absolutePath == null || absolutePath.trim().isEmpty) {
          continue;
        }
        final file = File(absolutePath);
        if (!await file.exists()) {
          continue;
        }
        final stat = await file.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        files.add(
          ShareableVideoFile(
            id: '${cache.cacheId}|${entry.relativePath}',
            cacheId: cache.cacheId,
            cacheDisplayName: cache.displayName,
            relativePath: entry.relativePath,
            absolutePath: absolutePath,
            sizeBytes: stat.size,
          ),
        );
      }
    }
    files.sort((a, b) {
      final cacheCmp = a.cacheDisplayName.toLowerCase().compareTo(
        b.cacheDisplayName.toLowerCase(),
      );
      if (cacheCmp != 0) {
        return cacheCmp;
      }
      return a.relativePath.toLowerCase().compareTo(
        b.relativePath.toLowerCase(),
      );
    });
    return files;
  }

  bool _isVideoPath(String relativePath) {
    return ThumbnailCacheService.videoExtensions.contains(
      p.extension(relativePath).toLowerCase(),
    );
  }

  String? _resolveCacheFilePath({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
  }) {
    if (cache.rootPath.startsWith('selection://')) {
      return entry.absolutePath;
    }
    final localRelative = entry.relativePath.replaceAll('/', p.separator);
    return p.join(cache.rootPath, localRelative);
  }
}

class _VideoLinkServerCard extends StatelessWidget {
  const _VideoLinkServerCard({
    required this.videoLinkSessionBoundary,
    required this.videos,
    required this.selectedVideoId,
    required this.isLoadingVideos,
    required this.onSelectedVideoChanged,
    required this.onOpenVideoList,
    required this.onToggle,
    this.onCopyLink,
  });

  final VideoLinkSessionBoundary videoLinkSessionBoundary;
  final List<ShareableVideoFile> videos;
  final String? selectedVideoId;
  final bool isLoadingVideos;
  final ValueChanged<String?> onSelectedVideoChanged;
  final VoidCallback onOpenVideoList;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onCopyLink;

  @override
  Widget build(BuildContext context) {
    final activeSession = videoLinkSessionBoundary.activeSession;
    final activeUrl = videoLinkSessionBoundary.watchUrl;
    final enabled = activeSession != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile.adaptive(
          secondary: Icon(
            enabled ? Icons.language_rounded : Icons.link_off_rounded,
            color: enabled ? AppColors.success : AppColors.textMuted,
          ),
          value: enabled,
          onChanged: onToggle,
          title: const Text('Web server for video'),
        ),
        ListTile(
          title: DropdownButtonFormField<String>(
            initialValue: selectedVideoId,
            isExpanded: true,
            onTap: onOpenVideoList,
            items: videos
                .map(
                  (file) => DropdownMenuItem<String>(
                    value: file.id,
                    child: Text(
                      '${file.cacheDisplayName} • ${file.relativePath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                )
                .toList(growable: false),
            selectedItemBuilder: (context) {
              return videos
                  .map(
                    (file) => Text(
                      '${file.cacheDisplayName} • ${file.relativePath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  )
                  .toList(growable: false);
            },
            onChanged: videos.isEmpty ? null : onSelectedVideoChanged,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Video from shared files',
            ),
          ),
        ),
        if (isLoadingVideos)
          const ListTile(title: LinearProgressIndicator(minHeight: 2)),
        if (activeSession != null)
          ListTile(dense: true, title: Text('File: ${activeSession.fileName}')),
        if (activeUrl != null)
          ListTile(
            dense: true,
            title: SelectableText(
              activeUrl,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'JetBrainsMono'),
            ),
            trailing: OutlinedButton.icon(
              onPressed: onCopyLink,
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
          ),
      ],
    );
  }
}

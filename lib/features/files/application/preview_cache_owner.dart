import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;

import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/shared_cache_thumbnail_store.dart';
import '../../transfer/data/transfer_storage_service.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import 'audio_artwork_reader.dart';

class PreparedPreviewFile {
  const PreparedPreviewFile({
    required this.sourcePath,
    required this.fileName,
    required this.sizeBytes,
    required this.sha256,
    this.deleteAfterTransfer = false,
  });

  final String sourcePath;
  final String fileName;
  final int sizeBytes;
  final String sha256;
  final bool deleteAfterTransfer;
}

class PreviewCacheOwner {
  PreviewCacheOwner({
    required SharedCacheThumbnailStore sharedCacheThumbnailStore,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required FileHashService fileHashService,
    Future<Directory> Function()? mediaPreviewDirectoryProvider,
    Future<Directory> Function()? previewArtifactDirectoryProvider,
    AudioArtworkReader audioArtworkReader = const AudioArtworkReader(),
  }) : _sharedCacheThumbnailStore = sharedCacheThumbnailStore,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _fileHashService = fileHashService,
       _audioArtworkReader = audioArtworkReader,
       _mediaPreviewDirectoryProvider =
           mediaPreviewDirectoryProvider ?? _defaultMediaPreviewDirectory,
       _previewArtifactDirectoryProvider =
           previewArtifactDirectoryProvider ?? _defaultPreviewArtifactDirectory;

  static const int _maxInMemoryItems = 320;

  static const Set<String> _previewImageExtensions = <String>{
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

  static const Set<String> _previewVideoExtensions = <String>{
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

  static const Set<String> _previewTextExtensions = <String>{
    '.txt',
    '.md',
    '.log',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
  };

  final SharedCacheThumbnailStore _sharedCacheThumbnailStore;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final FileHashService _fileHashService;
  final AudioArtworkReader _audioArtworkReader;
  final Future<Directory> Function() _mediaPreviewDirectoryProvider;
  final Future<Directory> Function() _previewArtifactDirectoryProvider;

  final Map<String, Uint8List?> _memoryByKey = <String, Uint8List?>{};
  final Map<String, Future<Uint8List?>> _pendingByKey =
      <String, Future<Uint8List?>>{};

  Directory? _mediaPreviewDirectory;
  Directory? _previewArtifactDirectory;

  Future<Uint8List?> loadVideoPreview({
    required String filePath,
    required int maxExtent,
    required int quality,
    required int timeMs,
  }) {
    return _loadOrCreate(
      kind: 'video',
      filePath: filePath,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: 't$timeMs',
      builder: () async {
        if (_useMediaKitForPlayback) {
          final bytes = await _buildVideoPreviewWithMediaKit(
            filePath: filePath,
            timeMs: timeMs,
          );
          if (bytes == null || bytes.isEmpty) {
            return null;
          }
          return _normalizeArtworkBytes(
            bytes,
            maxExtent: maxExtent,
            quality: quality,
          );
        }

        final bytes = await video_thumbnail.VideoThumbnail.thumbnailData(
          video: filePath,
          imageFormat: video_thumbnail.ImageFormat.JPEG,
          maxWidth: maxExtent,
          quality: quality,
          timeMs: timeMs,
        );
        if (bytes == null || bytes.isEmpty) {
          return null;
        }
        return Uint8List.fromList(bytes);
      },
    );
  }

  Future<Uint8List?> loadAudioCover({
    required String filePath,
    required int maxExtent,
    required int quality,
  }) {
    return _loadOrCreate(
      kind: 'audio',
      filePath: filePath,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: 'cover',
      builder: () async {
        final rawCover = await _audioArtworkReader.loadRawAudioCoverBytes(
          filePath,
        );
        if (rawCover == null || rawCover.isEmpty) {
          return null;
        }
        return _normalizeArtworkBytes(
          rawCover,
          maxExtent: maxExtent,
          quality: quality,
        );
      },
    );
  }

  Future<Directory> resolvePreviewArtifactDirectory() async {
    final existing = _previewArtifactDirectory;
    if (existing != null) {
      return existing;
    }
    final directory = await _previewArtifactDirectoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _previewArtifactDirectory = directory;
    return directory;
  }

  Future<List<PreparedPreviewFile>> buildCompressedPreviewFilesForCache(
    SharedFolderCacheRecord cache, {
    Set<String>? relativePathFilter,
  }) async {
    final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
    final normalizedFilter = relativePathFilter
        ?.map(_normalizeTransferPathForMatch)
        .where((value) => value.isNotEmpty)
        .toSet();

    final result = <PreparedPreviewFile>[];
    for (final entry in entries) {
      if (normalizedFilter != null &&
          !normalizedFilter.contains(
            _normalizeTransferPathForMatch(entry.relativePath),
          )) {
        continue;
      }
      final sourcePath = _resolveCacheFilePath(cache: cache, entry: entry);
      if (sourcePath == null) {
        continue;
      }
      final preview = await _buildCompressedPreviewForEntry(
        cache: cache,
        entry: entry,
        sourcePath: sourcePath,
      );
      if (preview != null) {
        result.add(preview);
      }
    }
    return result;
  }

  Future<PreparedPreviewFile?> materializePreviewArtifact({
    required String originalRelativePath,
    required String outputExtension,
    required List<int> contentBytes,
    String suffix = 'preview',
  }) async {
    if (contentBytes.isEmpty) {
      return null;
    }

    final directory = await resolvePreviewArtifactDirectory();
    final relativeName = _buildPreviewRelativeName(
      originalRelativePath,
      outputExtension: outputExtension,
      suffix: suffix,
    );
    final token = _fileHashService.buildStableId(
      'preview-artifact|$relativeName|$suffix|'
      '${DateTime.now().microsecondsSinceEpoch}',
    );
    final outputPath = p.join(directory.path, '$token$outputExtension');
    final outputFile = File(outputPath);
    await outputFile.create(recursive: true);
    await outputFile.writeAsBytes(contentBytes, flush: true);

    final stat = await outputFile.stat();
    final sha = await _fileHashService.computeSha256ForPath(outputPath);
    return PreparedPreviewFile(
      sourcePath: outputPath,
      fileName: relativeName,
      sizeBytes: stat.size,
      sha256: sha,
      deleteAfterTransfer: true,
    );
  }

  Future<PreviewCacheCleanupResult> cleanupPreviewArtifacts({
    required int maxSizeGb,
    required int maxAgeDays,
  }) async {
    final directory = await resolvePreviewArtifactDirectory();
    if (!await directory.exists()) {
      return const PreviewCacheCleanupResult(
        filesDeleted: 0,
        bytesFreed: 0,
        filesRemaining: 0,
        remainingBytes: 0,
      );
    }

    final entries = <_PreviewCacheArtifactEntry>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) {
          continue;
        }
        entries.add(
          _PreviewCacheArtifactEntry(
            path: entity.path,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } catch (_) {
        // Skip unreadable entries.
      }
    }

    var filesDeleted = 0;
    var bytesFreed = 0;
    final survivors = <_PreviewCacheArtifactEntry>[];

    final expiryCutoff = maxAgeDays > 0
        ? DateTime.now().subtract(Duration(days: maxAgeDays))
        : null;
    for (final entry in entries) {
      if (expiryCutoff != null && entry.modifiedAt.isBefore(expiryCutoff)) {
        final deleted = await _tryDeleteFile(entry.path);
        if (deleted) {
          filesDeleted += 1;
          bytesFreed += entry.sizeBytes;
          continue;
        }
      }
      survivors.add(entry);
    }

    final maxSizeBytes = maxSizeGb > 0 ? maxSizeGb * 1024 * 1024 * 1024 : null;
    var remainingBytes = survivors.fold<int>(
      0,
      (sum, entry) => sum + entry.sizeBytes,
    );

    if (maxSizeBytes != null && remainingBytes > maxSizeBytes) {
      survivors.sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt));
      for (final entry in survivors) {
        if (remainingBytes <= maxSizeBytes) {
          break;
        }
        final deleted = await _tryDeleteFile(entry.path);
        if (!deleted) {
          continue;
        }
        filesDeleted += 1;
        bytesFreed += entry.sizeBytes;
        remainingBytes -= entry.sizeBytes;
        entry.deleted = true;
      }
    }

    final filesRemaining = survivors.where((entry) => !entry.deleted).length;
    if (remainingBytes < 0) {
      remainingBytes = 0;
    }

    return PreviewCacheCleanupResult(
      filesDeleted: filesDeleted,
      bytesFreed: bytesFreed,
      filesRemaining: filesRemaining,
      remainingBytes: remainingBytes,
    );
  }

  Future<PreparedPreviewFile?> _buildCompressedPreviewForEntry({
    required SharedFolderCacheRecord cache,
    required SharedFolderIndexEntry entry,
    required String sourcePath,
  }) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      return null;
    }

    final ext = p.extension(entry.relativePath).toLowerCase();
    if (_previewImageExtensions.contains(ext)) {
      try {
        final bytes = await file.readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final longest = math.max(decoded.width, decoded.height);
          final resized = longest > 960
              ? img.copyResize(
                  decoded,
                  width: decoded.width >= decoded.height ? 960 : null,
                  height: decoded.height > decoded.width ? 960 : null,
                )
              : decoded;
          final compressed = Uint8List.fromList(
            img.encodeJpg(resized, quality: 52),
          );
          return materializePreviewArtifact(
            originalRelativePath: entry.relativePath,
            outputExtension: '.jpg',
            contentBytes: compressed,
          );
        }
      } catch (_) {
        return null;
      }
    }

    if (_previewVideoExtensions.contains(ext)) {
      try {
        Uint8List? bytes;
        final thumbnailId = entry.thumbnailId;
        if (thumbnailId != null && thumbnailId.trim().isNotEmpty) {
          bytes = await _sharedCacheThumbnailStore.readOwnerThumbnailBytes(
            cacheId: cache.cacheId,
            thumbnailId: thumbnailId,
          );
        }
        if (bytes != null && bytes.isNotEmpty) {
          final decoded = img.decodeImage(bytes);
          final compressed = decoded == null
              ? bytes
              : Uint8List.fromList(img.encodeJpg(decoded, quality: 50));
          return materializePreviewArtifact(
            originalRelativePath: entry.relativePath,
            outputExtension: '.jpg',
            contentBytes: compressed,
            suffix: 'video-preview',
          );
        }
      } catch (_) {
        // Fall through to the text fallback below.
      }
      return materializePreviewArtifact(
        originalRelativePath: entry.relativePath,
        outputExtension: '.txt',
        contentBytes: utf8.encode(
          'Video preview is unavailable on sender side for this file.',
        ),
        suffix: 'video-preview',
      );
    }

    if (_previewTextExtensions.contains(ext)) {
      try {
        final bytes = await file.readAsBytes();
        final maxBytes = math.min(bytes.length, 64 * 1024);
        final snippet = utf8.decode(
          bytes.sublist(0, maxBytes),
          allowMalformed: true,
        );
        final previewText = bytes.length > maxBytes
            ? '$snippet\n\n--- Preview truncated ---'
            : snippet;
        return materializePreviewArtifact(
          originalRelativePath: entry.relativePath,
          outputExtension: '.txt',
          contentBytes: utf8.encode(previewText),
          suffix: 'text-preview',
        );
      } catch (_) {
        return null;
      }
    }

    if (ext == '.pdf') {
      return materializePreviewArtifact(
        originalRelativePath: entry.relativePath,
        outputExtension: '.txt',
        contentBytes: utf8.encode(
          'PDF preview/viewing is temporarily unavailable. '
          'Download the file and open it externally.',
        ),
        suffix: 'pdf-preview',
      );
    }

    return materializePreviewArtifact(
      originalRelativePath: entry.relativePath,
      outputExtension: '.txt',
      contentBytes: utf8.encode(
        'Preview is not available for this file type yet.',
      ),
      suffix: 'preview-note',
    );
  }

  Future<Uint8List?> _loadOrCreate({
    required String kind,
    required String filePath,
    required int maxExtent,
    required int quality,
    required String extraKey,
    required Future<Uint8List?> Function() builder,
  }) async {
    if (filePath.trim().isEmpty) {
      return null;
    }

    final source = File(filePath);
    if (!await source.exists()) {
      return null;
    }

    final stat = await source.stat();
    if (stat.type != FileSystemEntityType.file) {
      return null;
    }

    final key = _buildCacheKey(
      kind: kind,
      filePath: filePath,
      stat: stat,
      maxExtent: maxExtent,
      quality: quality,
      extraKey: extraKey,
    );
    if (_memoryByKey.containsKey(key)) {
      final cached = _memoryByKey[key];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
      _memoryByKey.remove(key);
    }

    final pending = _pendingByKey[key];
    if (pending != null) {
      return pending;
    }

    final future = () async {
      try {
        final cacheDir = await resolveMediaPreviewDirectory();
        final cacheFile = File(p.join(cacheDir.path, '$kind-$key.jpg'));
        if (await cacheFile.exists()) {
          final cachedBytes = await cacheFile.readAsBytes();
          if (cachedBytes.isEmpty) {
            await cacheFile.delete();
          } else {
            _rememberInMemory(key, cachedBytes);
            return cachedBytes;
          }
        }

        final generated = await builder();
        if (generated == null || generated.isEmpty) {
          return null;
        }

        if (!await cacheFile.parent.exists()) {
          await cacheFile.parent.create(recursive: true);
        }
        await cacheFile.writeAsBytes(generated, flush: true);
        _rememberInMemory(key, generated);
        return generated;
      } catch (_) {
        return null;
      } finally {
        _pendingByKey.remove(key);
      }
    }();

    _pendingByKey[key] = future;
    return future;
  }

  String _buildCacheKey({
    required String kind,
    required String filePath,
    required FileStat stat,
    required int maxExtent,
    required int quality,
    required String extraKey,
  }) {
    var normalizedPath = p.normalize(filePath).replaceAll('\\', '/');
    if (Platform.isWindows) {
      normalizedPath = normalizedPath.toLowerCase();
    }
    final input =
        '$kind|$normalizedPath|${stat.size}|'
        '${stat.modified.millisecondsSinceEpoch}|$maxExtent|$quality|$extraKey';
    return sha256.convert(utf8.encode(input)).toString();
  }

  void _rememberInMemory(String key, Uint8List? value) {
    _memoryByKey[key] = value;
    if (_memoryByKey.length <= _maxInMemoryItems) {
      return;
    }
    final firstKey = _memoryByKey.keys.first;
    _memoryByKey.remove(firstKey);
  }

  Future<Uint8List?> _normalizeArtworkBytes(
    Uint8List bytes, {
    required int maxExtent,
    required int quality,
  }) async {
    try {
      return await Isolate.run(
        () => _normalizeArtworkBytesSync(
          bytes: bytes,
          maxExtent: maxExtent,
          quality: quality,
        ),
      );
    } catch (_) {
      return bytes;
    }
  }

  Future<Uint8List?> _buildVideoPreviewWithMediaKit({
    required String filePath,
    required int timeMs,
  }) async {
    final player = Player();
    final videoController = VideoController(player);
    try {
      try {
        await player.open(Media(_mediaUriFromFilePath(filePath)), play: true);
      } catch (_) {
        await player.open(Media(filePath), play: true);
      }
      await player.setVolume(0);
      try {
        await videoController.waitUntilFirstFrameRendered.timeout(
          const Duration(seconds: 2),
        );
      } catch (_) {
        // Continue with the best-effort capture fallback below.
      }
      await _waitForVideoFrame(player);

      final targetMs = timeMs <= 0 ? 700 : timeMs;
      final candidateMs = <int>[targetMs, 0, 1200];
      for (final ms in candidateMs) {
        if (ms > 0) {
          await player.seek(Duration(milliseconds: ms));
          await Future<void>.delayed(const Duration(milliseconds: 240));
        } else {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        for (var attempt = 0; attempt < 3; attempt += 1) {
          final bytes = await player.screenshot(format: 'image/jpeg');
          if (bytes != null && bytes.isNotEmpty) {
            return bytes;
          }
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  Future<void> _waitForVideoFrame(Player player) async {
    if (_hasVideoFrame(player.state)) {
      return;
    }
    final completer = Completer<void>();
    late final StreamSubscription<VideoParams> subscription;
    subscription = player.stream.videoParams.listen((params) {
      final width = params.dw ?? params.w ?? 0;
      final height = params.dh ?? params.h ?? 0;
      if (width > 0 && height > 0 && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      // Best-effort only.
    } finally {
      await subscription.cancel();
    }
  }

  bool _hasVideoFrame(PlayerState state) {
    final width =
        state.width ?? state.videoParams.dw ?? state.videoParams.w ?? 0;
    final height =
        state.height ?? state.videoParams.dh ?? state.videoParams.h ?? 0;
    return width > 0 && height > 0;
  }

  Uint8List? _normalizeArtworkBytesSync({
    required Uint8List bytes,
    required int maxExtent,
    required int quality,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }
    final resized = _resizeToLongestEdge(decoded, maxExtent: maxExtent);
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  img.Image _resizeToLongestEdge(img.Image source, {required int maxExtent}) {
    if (source.width <= maxExtent && source.height <= maxExtent) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxExtent);
    }
    return img.copyResize(source, height: maxExtent);
  }

  String _buildPreviewRelativeName(
    String originalRelativePath, {
    required String outputExtension,
    required String suffix,
  }) {
    final normalized = originalRelativePath.replaceAll('\\', '/');
    final dir = p.dirname(normalized);
    final base = p.basenameWithoutExtension(normalized);
    final safeBase = _safePreviewSegment(base);
    final fileName = '$safeBase.$suffix$outputExtension';
    if (dir == '.' || dir.isEmpty) {
      return fileName;
    }
    final safeDir = dir
        .split('/')
        .where((segment) => segment.isNotEmpty && segment != '.')
        .map(_safePreviewSegment)
        .toList(growable: false);
    if (safeDir.isEmpty) {
      return fileName;
    }
    return [...safeDir, fileName].join('/');
  }

  String _safePreviewSegment(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'file';
    }
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  String _normalizeTransferPathForMatch(String value) {
    return value.replaceAll('\\', '/').trim().toLowerCase();
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

  Future<bool> _tryDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Directory> _defaultMediaPreviewDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Landa', 'media_previews'));
  }

  static Future<Directory> _defaultPreviewArtifactDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'Landa', 'preview_cache'));
  }

  static String _mediaUriFromFilePath(String filePath) {
    return Uri.file(filePath).toString();
  }

  static bool get _useMediaKitForPlayback =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  @visibleForTesting
  Future<Directory> resolveMediaPreviewDirectory() async {
    final existing = _mediaPreviewDirectory;
    if (existing != null) {
      return existing;
    }
    final directory = await _mediaPreviewDirectoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _mediaPreviewDirectory = directory;
    return directory;
  }

  @visibleForTesting
  void clearInMemoryPreviewCache() {
    _memoryByKey.clear();
  }

  void dispose() {
    _memoryByKey.clear();
    _pendingByKey.clear();
  }
}

class _PreviewCacheArtifactEntry {
  _PreviewCacheArtifactEntry({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
  bool deleted = false;
}

part of '../file_explorer_page.dart';

class _MediaPreviewCache {
  static final Map<String, Uint8List?> _memoryByKey = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _pendingByKey =
      <String, Future<Uint8List?>>{};
  static Directory? _cacheDirectory;
  static const int _maxInMemoryItems = 320;

  static Future<Uint8List?> loadVideoPreview({
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
        } else {
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
        }
      },
    );
  }

  static Future<Uint8List?> loadAudioCover({
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
        final metadata = await MetadataRetriever.fromFile(File(filePath));
        final rawCover = metadata.albumArt;
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

  static Future<Uint8List?> _loadOrCreate({
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
      return _memoryByKey[key];
    }
    final pending = _pendingByKey[key];
    if (pending != null) {
      return pending;
    }

    final future = () async {
      try {
        final cacheDir = await _resolveCacheDirectory();
        final cacheFile = File(p.join(cacheDir.path, '$kind-$key.jpg'));
        if (await cacheFile.exists()) {
          final cachedBytes = await cacheFile.readAsBytes();
          _rememberInMemory(key, cachedBytes);
          return cachedBytes;
        }

        final generated = await builder();
        if (generated == null || generated.isEmpty) {
          _rememberInMemory(key, null);
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

  static String _buildCacheKey({
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
        '$kind|$normalizedPath|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$maxExtent|$quality|$extraKey';
    return sha256.convert(utf8.encode(input)).toString();
  }

  static void _rememberInMemory(String key, Uint8List? value) {
    _memoryByKey[key] = value;
    if (_memoryByKey.length <= _maxInMemoryItems) {
      return;
    }
    final firstKey = _memoryByKey.keys.first;
    _memoryByKey.remove(firstKey);
  }

  static Future<Directory> _resolveCacheDirectory() async {
    final existing = _cacheDirectory;
    if (existing != null) {
      return existing;
    }
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'Landa', 'media_previews'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cacheDirectory = dir;
    return dir;
  }

  static Future<Uint8List?> _normalizeArtworkBytes(
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

  static Future<Uint8List?> _buildVideoPreviewWithMediaKit({
    required String filePath,
    required int timeMs,
  }) async {
    final player = Player();
    try {
      await player.open(Media(_mediaUriFromFilePath(filePath)), play: false);
      if (timeMs > 0) {
        await player.seek(Duration(milliseconds: timeMs));
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return player.screenshot(format: 'image/jpeg');
    } catch (_) {
      return null;
    } finally {
      await player.dispose();
    }
  }

  static Uint8List? _normalizeArtworkBytesSync({
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

  static img.Image _resizeToLongestEdge(
    img.Image source, {
    required int maxExtent,
  }) {
    if (source.width <= maxExtent && source.height <= maxExtent) {
      return source;
    }
    if (source.width >= source.height) {
      return img.copyResize(source, width: maxExtent);
    }
    return img.copyResize(source, height: maxExtent);
  }
}

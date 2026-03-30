import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../../core/storage/app_database.dart';
import 'shared_cache_thumbnail_store.dart';

class ThumbnailDescriptor {
  const ThumbnailDescriptor({
    required this.thumbnailId,
    required this.filePath,
  });

  final String thumbnailId;
  final String filePath;
}

class ThumbnailRequestItem {
  const ThumbnailRequestItem({
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
  });

  final String cacheId;
  final String relativePath;
  final String thumbnailId;
}

class ThumbnailCacheService implements SharedCacheThumbnailStore {
  ThumbnailCacheService({required AppDatabase database}) : _database = database;

  static const int _thumbnailMaxExtent = 180;
  static const int _thumbnailQuality = 68;
  static const int _maxPacketSafeBytes = 36 * 1024;

  static const Set<String> imageExtensions = <String>{
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

  static const Set<String> videoExtensions = <String>{
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

  final AppDatabase _database;

  bool supportsThumbnailForPath(String relativePath) {
    return isImagePath(relativePath) || isVideoPath(relativePath);
  }

  bool isImagePath(String relativePath) {
    return imageExtensions.contains(p.extension(relativePath).toLowerCase());
  }

  bool isVideoPath(String relativePath) {
    return videoExtensions.contains(p.extension(relativePath).toLowerCase());
  }

  String buildThumbnailId({
    required String cacheId,
    required String relativePath,
    required int sizeBytes,
    required int modifiedAtMs,
  }) {
    final payload =
        '$cacheId|${relativePath.replaceAll('\\', '/').toLowerCase()}|'
        '$sizeBytes|$modifiedAtMs';
    return sha256.convert(payload.codeUnits).toString();
  }

  Future<ThumbnailDescriptor?> ensureOwnerThumbnail({
    required String cacheId,
    required String relativePath,
    required String sourcePath,
    required int sizeBytes,
    required int modifiedAtMs,
  }) async {
    if (!supportsThumbnailForPath(relativePath)) {
      return null;
    }

    final thumbnailId = buildThumbnailId(
      cacheId: cacheId,
      relativePath: relativePath,
      sizeBytes: sizeBytes,
      modifiedAtMs: modifiedAtMs,
    );
    final target = await _resolveOwnerThumbnailFile(
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );

    if (await target.exists()) {
      return ThumbnailDescriptor(
        thumbnailId: thumbnailId,
        filePath: target.path,
      );
    }

    Uint8List? bytes;
    if (isImagePath(relativePath)) {
      bytes = await _buildImageThumbnail(sourcePath);
    } else if (isVideoPath(relativePath)) {
      bytes = await _buildVideoThumbnail(sourcePath);
    }

    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    bytes = await _ensurePacketSafeThumbnailBytes(bytes);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return ThumbnailDescriptor(thumbnailId: thumbnailId, filePath: target.path);
  }

  @override
  Future<Uint8List?> readOwnerThumbnailBytes({
    required String cacheId,
    required String thumbnailId,
  }) async {
    final target = await _resolveOwnerThumbnailFile(
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
    if (!await target.exists()) {
      return null;
    }
    return target.readAsBytes();
  }

  @override
  Future<String?> resolveReceiverThumbnailPath({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
  }) async {
    final target = await _resolveReceiverThumbnailFile(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
    if (await target.exists()) {
      return target.path;
    }
    return null;
  }

  @override
  Future<String> saveReceiverThumbnailBytes({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
    required Uint8List bytes,
  }) async {
    final target = await _resolveReceiverThumbnailFile(
      ownerMacAddress: ownerMacAddress,
      cacheId: cacheId,
      thumbnailId: thumbnailId,
    );
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  Future<void> deleteOwnerCacheThumbnails(String cacheId) async {
    final root = await _resolveThumbnailRootDirectory();
    final directory = Directory(p.join(root.path, 'owner', cacheId));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<void> deleteReceiverCacheThumbnails({
    required String ownerMacAddress,
    required String cacheId,
  }) async {
    final root = await _resolveThumbnailRootDirectory();
    final normalizedOwner = _normalizeOwnerMacForPath(ownerMacAddress);
    final directory = Directory(
      p.join(root.path, 'receiver', normalizedOwner, cacheId),
    );
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<File> _resolveOwnerThumbnailFile({
    required String cacheId,
    required String thumbnailId,
  }) async {
    final root = await _resolveThumbnailRootDirectory();
    return File(p.join(root.path, 'owner', cacheId, '$thumbnailId.jpg'));
  }

  Future<File> _resolveReceiverThumbnailFile({
    required String ownerMacAddress,
    required String cacheId,
    required String thumbnailId,
  }) async {
    final root = await _resolveThumbnailRootDirectory();
    final normalizedOwner = ownerMacAddress.toLowerCase().replaceAll(':', '-');
    return File(
      p.join(
        root.path,
        'receiver',
        normalizedOwner,
        cacheId,
        '$thumbnailId.jpg',
      ),
    );
  }

  String _normalizeOwnerMacForPath(String ownerMacAddress) {
    return ownerMacAddress.toLowerCase().replaceAll(':', '-');
  }

  Future<Directory> _resolveThumbnailRootDirectory() async {
    return _database.resolveSharedThumbnailDirectory();
  }

  Future<Uint8List?> _buildImageThumbnail(String sourcePath) async {
    try {
      final source = File(sourcePath);
      if (!await source.exists()) {
        return null;
      }
      final bytes = await source.readAsBytes();
      return await Isolate.run(
        () => _buildImageThumbnailSync(
          bytes: bytes,
          maxExtent: _thumbnailMaxExtent,
          quality: _thumbnailQuality,
        ),
      );
    } catch (error) {
      _log('Image thumbnail build failed: $error');
      return null;
    }
  }

  Future<Uint8List?> _buildVideoThumbnail(String sourcePath) async {
    try {
      final data = await VideoThumbnail.thumbnailData(
        video: sourcePath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: _thumbnailMaxExtent,
        quality: _thumbnailQuality,
        timeMs: 0,
      );
      if (data == null || data.isEmpty) {
        return null;
      }
      return Uint8List.fromList(data);
    } catch (error) {
      _log('Video thumbnail build failed: $error');
      return null;
    }
  }

  Future<Uint8List?> _ensurePacketSafeThumbnailBytes(Uint8List bytes) async {
    if (bytes.lengthInBytes <= _maxPacketSafeBytes) {
      return bytes;
    }
    try {
      final reduced = await Isolate.run(
        () => _ensurePacketSafeThumbnailBytesSync(
          bytes: bytes,
          maxPacketSafeBytes: _maxPacketSafeBytes,
          maxExtent: _thumbnailMaxExtent,
          quality: _thumbnailQuality,
        ),
      );
      if (reduced == null || reduced.isEmpty) {
        return null;
      }
      if (reduced.lengthInBytes > _maxPacketSafeBytes) {
        return null;
      }
      return reduced;
    } catch (error) {
      _log('Thumbnail packet-safe resize failed: $error');
      return null;
    }
  }

  static Uint8List? _buildImageThumbnailSync({
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

  static Uint8List? _ensurePacketSafeThumbnailBytesSync({
    required Uint8List bytes,
    required int maxPacketSafeBytes,
    required int maxExtent,
    required int quality,
  }) {
    if (bytes.lengthInBytes <= maxPacketSafeBytes) {
      return bytes;
    }
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return null;
    }

    var targetExtent = math.max(64, maxExtent);
    var targetQuality = quality;
    var attempts = 0;
    Uint8List? encoded;
    while (attempts < 8) {
      final resized = _resizeToLongestEdge(decoded, maxExtent: targetExtent);
      encoded = Uint8List.fromList(
        img.encodeJpg(resized, quality: targetQuality),
      );
      if (encoded.lengthInBytes <= maxPacketSafeBytes) {
        return encoded;
      }
      attempts += 1;
      targetExtent = math.max(48, (targetExtent * 0.82).round());
      targetQuality = math.max(34, targetQuality - 6);
    }
    return encoded;
  }

  static img.Image _resizeToLongestEdge(
    img.Image decoded, {
    required int maxExtent,
  }) {
    return img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? maxExtent : null,
      height: decoded.height >= decoded.width ? maxExtent : null,
      interpolation: img.Interpolation.average,
    );
  }

  void _log(String message) {
    developer.log(message, name: 'ThumbnailCacheService');
  }
}

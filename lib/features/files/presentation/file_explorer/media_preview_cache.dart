part of '../file_explorer_page.dart';

class _MediaPreviewCache {
  static final Map<String, Uint8List?> _memoryByKey = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _pendingByKey =
      <String, Future<Uint8List?>>{};
  static Directory? _cacheDirectory;
  static const int _maxInMemoryItems = 320;
  static const int _maxId3TagBytes = 16 * 1024 * 1024;
  static const int _maxArtworkPayloadBytes = 8 * 1024 * 1024;

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
        final rawCover = await _loadRawAudioCoverBytes(filePath);
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

  static Future<Uint8List?> _loadRawAudioCoverBytes(String filePath) async {
    final extension = p.extension(filePath).toLowerCase();
    if (extension == '.flac') {
      return _readFlacArtwork(filePath);
    }
    if (extension == '.mp3') {
      return _readMp3Artwork(filePath);
    }
    final fromMp3 = await _readMp3Artwork(filePath);
    if (fromMp3 != null && fromMp3.isNotEmpty) {
      return fromMp3;
    }
    if (extension == '.fla') {
      return _readFlacArtwork(filePath);
    }
    return null;
  }

  static Future<Uint8List?> _readMp3Artwork(String filePath) async {
    RandomAccessFile? handle;
    try {
      handle = await File(filePath).open();
      final header = await handle.read(10);
      if (header.length < 10 ||
          header[0] != 0x49 ||
          header[1] != 0x44 ||
          header[2] != 0x33) {
        return null;
      }
      final version = header[3];
      if (version < 2 || version > 4) {
        return null;
      }
      final flags = header[5];
      final tagSize = _decodeSyncSafeInt(header, 6);
      if (tagSize <= 0) {
        return null;
      }
      final boundedTagSize = math.min(tagSize, _maxId3TagBytes);
      if (boundedTagSize <= 0) {
        return null;
      }
      final bytes = await handle.read(boundedTagSize);
      if (bytes.isEmpty) {
        return null;
      }
      var tagBytes = Uint8List.fromList(bytes);
      if ((flags & 0x80) != 0) {
        tagBytes = _removeId3UnsyncBytes(tagBytes);
      }
      if (version == 2) {
        return _extractPictureFromId3v22(tagBytes);
      }
      return _extractPictureFromId3v23OrV24(tagBytes, isV24: version == 4);
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  static Uint8List? _extractPictureFromId3v23OrV24(
    Uint8List tagBytes, {
    required bool isV24,
  }) {
    var offset = 0;
    while (offset + 10 <= tagBytes.length) {
      if (_isZeroFilled(tagBytes, offset, 4)) {
        break;
      }
      final frameId = ascii.decode(
        tagBytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final frameSize = isV24
          ? _decodeSyncSafeInt(tagBytes, offset + 4)
          : _decodeUInt32(tagBytes, offset + 4);
      final frameStart = offset + 10;
      final frameEnd = frameStart + frameSize;
      if (frameSize <= 0 || frameEnd > tagBytes.length) {
        break;
      }
      if (frameId == 'APIC') {
        return _extractImageDataFromApic(
          Uint8List.sublistView(tagBytes, frameStart, frameEnd),
        );
      }
      offset = frameEnd;
    }
    return null;
  }

  static Uint8List? _extractPictureFromId3v22(Uint8List tagBytes) {
    var offset = 0;
    while (offset + 6 <= tagBytes.length) {
      if (_isZeroFilled(tagBytes, offset, 3)) {
        break;
      }
      final frameId = ascii.decode(
        tagBytes.sublist(offset, offset + 3),
        allowInvalid: true,
      );
      final frameSize = _decodeUInt24(tagBytes, offset + 3);
      final frameStart = offset + 6;
      final frameEnd = frameStart + frameSize;
      if (frameSize <= 0 || frameEnd > tagBytes.length) {
        break;
      }
      if (frameId == 'PIC') {
        return _extractImageDataFromPic(
          Uint8List.sublistView(tagBytes, frameStart, frameEnd),
        );
      }
      offset = frameEnd;
    }
    return null;
  }

  static Uint8List? _extractImageDataFromApic(Uint8List payload) {
    if (payload.length < 4) {
      return null;
    }
    final textEncoding = payload[0];
    var cursor = 1;
    final mimeEnd = _findTextTerminator(payload, cursor, 0);
    if (mimeEnd < 0) {
      return null;
    }
    cursor = mimeEnd + 1;
    if (cursor >= payload.length) {
      return null;
    }
    cursor += 1; // picture type
    if (cursor >= payload.length) {
      return null;
    }
    final descriptionEnd = _findTextTerminator(payload, cursor, textEncoding);
    if (descriptionEnd < 0) {
      return null;
    }
    final terminatorSize = _terminatorSize(textEncoding);
    cursor = descriptionEnd + terminatorSize;
    if (cursor >= payload.length) {
      return null;
    }
    final imageBytes = payload.sublist(cursor);
    if (imageBytes.isEmpty || imageBytes.length > _maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(imageBytes);
  }

  static Uint8List? _extractImageDataFromPic(Uint8List payload) {
    if (payload.length < 6) {
      return null;
    }
    final textEncoding = payload[0];
    var cursor = 1;
    cursor += 3; // image format
    if (cursor >= payload.length) {
      return null;
    }
    cursor += 1; // picture type
    if (cursor >= payload.length) {
      return null;
    }
    final descriptionEnd = _findTextTerminator(payload, cursor, textEncoding);
    if (descriptionEnd < 0) {
      return null;
    }
    final terminatorSize = _terminatorSize(textEncoding);
    cursor = descriptionEnd + terminatorSize;
    if (cursor >= payload.length) {
      return null;
    }
    final imageBytes = payload.sublist(cursor);
    if (imageBytes.isEmpty || imageBytes.length > _maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(imageBytes);
  }

  static Future<Uint8List?> _readFlacArtwork(String filePath) async {
    RandomAccessFile? handle;
    try {
      handle = await File(filePath).open();
      final signature = await handle.read(4);
      if (signature.length < 4 ||
          signature[0] != 0x66 ||
          signature[1] != 0x4c ||
          signature[2] != 0x61 ||
          signature[3] != 0x43) {
        return null;
      }
      while (true) {
        final blockHeader = await handle.read(4);
        if (blockHeader.length < 4) {
          return null;
        }
        final isLastBlock = (blockHeader[0] & 0x80) != 0;
        final blockType = blockHeader[0] & 0x7f;
        final blockSize = _decodeUInt24(blockHeader, 1);
        if (blockSize < 0) {
          return null;
        }
        if (blockType == 6) {
          if (blockSize <= 0 || blockSize > _maxId3TagBytes) {
            return null;
          }
          final pictureBlock = await handle.read(blockSize);
          if (pictureBlock.length < blockSize) {
            return null;
          }
          return _extractImageDataFromFlacPictureBlock(pictureBlock);
        }
        final position = await handle.position();
        await handle.setPosition(position + blockSize);
        if (isLastBlock) {
          return null;
        }
      }
    } catch (_) {
      return null;
    } finally {
      await handle?.close();
    }
  }

  static Uint8List? _extractImageDataFromFlacPictureBlock(Uint8List payload) {
    var offset = 0;
    if (offset + 4 > payload.length) {
      return null;
    }
    offset += 4; // picture type
    if (offset + 4 > payload.length) {
      return null;
    }
    final mimeLength = _decodeUInt32(payload, offset);
    offset += 4;
    if (mimeLength < 0 || offset + mimeLength > payload.length) {
      return null;
    }
    offset += mimeLength;
    if (offset + 4 > payload.length) {
      return null;
    }
    final descriptionLength = _decodeUInt32(payload, offset);
    offset += 4;
    if (descriptionLength < 0 || offset + descriptionLength > payload.length) {
      return null;
    }
    offset += descriptionLength;
    const fixedPictureMetaLength = 16;
    if (offset + fixedPictureMetaLength + 4 > payload.length) {
      return null;
    }
    offset += fixedPictureMetaLength;
    final imageLength = _decodeUInt32(payload, offset);
    offset += 4;
    if (imageLength <= 0 || offset + imageLength > payload.length) {
      return null;
    }
    if (imageLength > _maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(payload.sublist(offset, offset + imageLength));
  }

  static Uint8List _removeId3UnsyncBytes(Uint8List input) {
    if (input.isEmpty) {
      return input;
    }
    final output = BytesBuilder(copy: false);
    var index = 0;
    while (index < input.length) {
      final value = input[index];
      if (value == 0xff &&
          index + 1 < input.length &&
          input[index + 1] == 0x00) {
        output.addByte(0xff);
        index += 2;
        continue;
      }
      output.addByte(value);
      index += 1;
    }
    return output.toBytes();
  }

  static int _decodeSyncSafeInt(List<int> bytes, int offset) {
    if (offset + 3 >= bytes.length) {
      return 0;
    }
    return ((bytes[offset] & 0x7f) << 21) |
        ((bytes[offset + 1] & 0x7f) << 14) |
        ((bytes[offset + 2] & 0x7f) << 7) |
        (bytes[offset + 3] & 0x7f);
  }

  static int _decodeUInt24(List<int> bytes, int offset) {
    if (offset + 2 >= bytes.length) {
      return -1;
    }
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  static int _decodeUInt32(List<int> bytes, int offset) {
    if (offset + 3 >= bytes.length) {
      return -1;
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  static bool _isZeroFilled(List<int> bytes, int offset, int length) {
    if (offset + length > bytes.length) {
      return true;
    }
    for (var i = 0; i < length; i += 1) {
      if (bytes[offset + i] != 0) {
        return false;
      }
    }
    return true;
  }

  static int _findTextTerminator(Uint8List bytes, int start, int textEncoding) {
    if (start < 0 || start >= bytes.length) {
      return -1;
    }
    final isUtf16 = textEncoding == 1 || textEncoding == 2;
    if (!isUtf16) {
      for (var i = start; i < bytes.length; i += 1) {
        if (bytes[i] == 0x00) {
          return i;
        }
      }
      return -1;
    }
    for (var i = start; i + 1 < bytes.length; i += 1) {
      if (bytes[i] == 0x00 && bytes[i + 1] == 0x00) {
        return i;
      }
    }
    return -1;
  }

  static int _terminatorSize(int textEncoding) {
    return (textEncoding == 1 || textEncoding == 2) ? 2 : 1;
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
        final cacheDir = await _resolveCacheDirectory();
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
        // Continue with best-effort capture fallback below.
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
        for (var attempt = 0; attempt < 3; attempt++) {
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

  static Future<void> _waitForVideoFrame(Player player) async {
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
      // timeout; continue and let screenshot retry logic handle it
    } finally {
      await subscription.cancel();
    }
  }

  static bool _hasVideoFrame(PlayerState state) {
    final width =
        state.width ?? state.videoParams.dw ?? state.videoParams.w ?? 0;
    final height =
        state.height ?? state.videoParams.dh ?? state.videoParams.h ?? 0;
    return width > 0 && height > 0;
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

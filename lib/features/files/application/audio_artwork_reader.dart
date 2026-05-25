import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class AudioArtworkReader {
  const AudioArtworkReader();

  static const int maxId3TagBytes = 16 * 1024 * 1024;
  static const int maxArtworkPayloadBytes = 8 * 1024 * 1024;

  Future<Uint8List?> loadRawAudioCoverBytes(String filePath) async {
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

  Future<Uint8List?> _readMp3Artwork(String filePath) async {
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
      final boundedTagSize = math.min(tagSize, maxId3TagBytes);
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

  Uint8List? _extractPictureFromId3v23OrV24(
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

  Uint8List? _extractPictureFromId3v22(Uint8List tagBytes) {
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

  Uint8List? _extractImageDataFromApic(Uint8List payload) {
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
    cursor += 1;
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
    if (imageBytes.isEmpty || imageBytes.length > maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(imageBytes);
  }

  Uint8List? _extractImageDataFromPic(Uint8List payload) {
    if (payload.length < 6) {
      return null;
    }
    final textEncoding = payload[0];
    var cursor = 1;
    cursor += 3;
    if (cursor >= payload.length) {
      return null;
    }
    cursor += 1;
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
    if (imageBytes.isEmpty || imageBytes.length > maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(imageBytes);
  }

  Future<Uint8List?> _readFlacArtwork(String filePath) async {
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
          if (blockSize <= 0 || blockSize > maxId3TagBytes) {
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

  Uint8List? _extractImageDataFromFlacPictureBlock(Uint8List payload) {
    var offset = 0;
    if (offset + 4 > payload.length) {
      return null;
    }
    offset += 4;
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
    if (imageLength > maxArtworkPayloadBytes) {
      return null;
    }
    return Uint8List.fromList(payload.sublist(offset, offset + imageLength));
  }

  Uint8List _removeId3UnsyncBytes(Uint8List input) {
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

  int _decodeSyncSafeInt(List<int> bytes, int offset) {
    if (offset + 3 >= bytes.length) {
      return 0;
    }
    return ((bytes[offset] & 0x7f) << 21) |
        ((bytes[offset + 1] & 0x7f) << 14) |
        ((bytes[offset + 2] & 0x7f) << 7) |
        (bytes[offset + 3] & 0x7f);
  }

  int _decodeUInt24(List<int> bytes, int offset) {
    if (offset + 2 >= bytes.length) {
      return -1;
    }
    return (bytes[offset] << 16) | (bytes[offset + 1] << 8) | bytes[offset + 2];
  }

  int _decodeUInt32(List<int> bytes, int offset) {
    if (offset + 3 >= bytes.length) {
      return -1;
    }
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  bool _isZeroFilled(List<int> bytes, int offset, int length) {
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

  int _findTextTerminator(Uint8List bytes, int start, int textEncoding) {
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

  int _terminatorSize(int textEncoding) {
    return (textEncoding == 1 || textEncoding == 2) ? 2 : 1;
  }
}

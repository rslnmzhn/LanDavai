import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/transfer_request.dart';

class TransferHeaderCodec {
  const TransferHeaderCodec({
    this.compressionThresholdBytes = 128 * 1024,
    this.maxDecompressedBytes = 8 * 1024 * 1024,
  });

  final int compressionThresholdBytes;
  final int maxDecompressedBytes;

  EncodedTransferHeader encode(TransferHeader header) {
    final jsonBytes = utf8.encode(jsonEncode(header.toJson()));
    if (jsonBytes.length < compressionThresholdBytes) {
      return EncodedTransferHeader(
        bytes: Uint8List.fromList(jsonBytes),
        rawBytesLength: jsonBytes.length,
        compressed: false,
      );
    }

    final compressed = gzip.encode(jsonBytes);
    if (compressed.length >= jsonBytes.length) {
      return EncodedTransferHeader(
        bytes: Uint8List.fromList(jsonBytes),
        rawBytesLength: jsonBytes.length,
        compressed: false,
      );
    }

    return EncodedTransferHeader(
      bytes: Uint8List.fromList(compressed),
      rawBytesLength: jsonBytes.length,
      compressed: true,
    );
  }

  TransferHeader decode(Uint8List headerBytes) {
    Uint8List decodedBytes;
    if (_looksLikeGzip(headerBytes)) {
      final sink = _BoundedByteSink(maxDecompressedBytes);
      final conversion = gzip.decoder.startChunkedConversion(sink);
      try {
        conversion.add(headerBytes);
        conversion.close();
      } catch (e) {
        if (e is FormatException) {
          rethrow;
        }
        throw TransferHeaderFormatException(
          'Failed to decompress transfer header: $e',
        );
      }
      decodedBytes = sink.toBytes();
    } else {
      if (headerBytes.length > maxDecompressedBytes) {
        throw const FormatException(
          'Transfer header exceeded maximum decompression limit.',
        );
      }
      decodedBytes = headerBytes;
    }

    final decoded = jsonDecode(utf8.decode(decodedBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const TransferHeaderFormatException(
        'Invalid transfer header payload.',
      );
    }
    return TransferHeader.fromJson(decoded);
  }

  bool _looksLikeGzip(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
  }
}

class _BoundedByteSink implements Sink<List<int>> {
  _BoundedByteSink(this.maxBytes);

  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (_builder.length + chunk.length > maxBytes) {
      throw const FormatException(
        'Transfer header exceeded maximum decompression limit.',
      );
    }
    _builder.add(chunk);
  }

  @override
  void close() {}

  Uint8List toBytes() => _builder.toBytes();
}

class TransferHeader {
  const TransferHeader({required this.requestId, required this.files});

  final String requestId;
  final List<TransferFileManifestItem> files;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'files': files
          .map(
            (file) => <String, Object>{
              'name': file.fileName,
              'size': file.sizeBytes,
              'sha256': file.sha256,
            },
          )
          .toList(growable: false),
    };
  }

  factory TransferHeader.fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'];
    final files = json['files'];
    if (requestId is! String || files is! List<dynamic>) {
      throw const TransferHeaderFormatException(
        'Transfer header is missing required fields.',
      );
    }

    return TransferHeader(
      requestId: requestId,
      files: files.map(_manifestItemFromJson).toList(growable: false),
    );
  }

  static TransferFileManifestItem _manifestItemFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const TransferHeaderFormatException(
        'Transfer header file entry is invalid.',
      );
    }
    final name = value['name'];
    final size = value['size'];
    final sha256 = value['sha256'];
    if (name is! String || size is! num || sha256 is! String) {
      throw const TransferHeaderFormatException(
        'Transfer header file entry is missing required fields.',
      );
    }
    return TransferFileManifestItem(
      fileName: name,
      sizeBytes: size.toInt(),
      sha256: sha256,
    );
  }
}

class EncodedTransferHeader {
  const EncodedTransferHeader({
    required this.bytes,
    required this.rawBytesLength,
    required this.compressed,
  });

  final Uint8List bytes;
  final int rawBytesLength;
  final bool compressed;
}

class TransferHeaderFormatException implements Exception {
  const TransferHeaderFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

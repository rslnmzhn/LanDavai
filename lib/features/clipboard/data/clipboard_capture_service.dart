import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../domain/clipboard_entry.dart';

class ClipboardCaptureData {
  const ClipboardCaptureData({
    required this.type,
    required this.contentHash,
    this.textValue,
    this.imageBytes,
  });

  final ClipboardEntryType type;
  final String contentHash;
  final String? textValue;
  final Uint8List? imageBytes;
}

class ClipboardCaptureService {
  Future<ClipboardCaptureData?> readCurrentClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      return null;
    }

    final reader = await clipboard.read();
    final imageBytes = await _tryReadPngBytes(reader);
    if (imageBytes != null && imageBytes.isNotEmpty) {
      final hash = sha256.convert(imageBytes).toString();
      return ClipboardCaptureData(
        type: ClipboardEntryType.image,
        contentHash: 'image:$hash',
        imageBytes: imageBytes,
      );
    }

    final text = await reader.readValue(Formats.plainText);
    if (text == null) {
      return null;
    }
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final hash = sha256.convert(utf8.encode(normalized)).toString();
    return ClipboardCaptureData(
      type: ClipboardEntryType.text,
      contentHash: 'text:$hash',
      textValue: text,
    );
  }

  Future<Uint8List?> _tryReadPngBytes(ClipboardReader reader) async {
    if (!reader.canProvide(Formats.png)) {
      return null;
    }

    final completer = Completer<Uint8List?>();
    final progress = reader.getFile(
      Formats.png,
      (file) async {
        final bytes = await file.readAll();
        if (!completer.isCompleted) {
          completer.complete(bytes);
        }
      },
      onError: (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );

    if (progress == null) {
      return null;
    }

    try {
      return await completer.future.timeout(
        const Duration(milliseconds: 800),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }
}

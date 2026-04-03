import 'dart:typed_data';

enum ClipboardEntryType { text, image }

extension ClipboardEntryTypeX on ClipboardEntryType {
  String get value {
    switch (this) {
      case ClipboardEntryType.text:
        return 'text';
      case ClipboardEntryType.image:
        return 'image';
    }
  }

  static ClipboardEntryType fromValue(String raw) {
    switch (raw) {
      case 'image':
        return ClipboardEntryType.image;
      case 'text':
      default:
        return ClipboardEntryType.text;
    }
  }
}

class ClipboardHistoryEntry {
  const ClipboardHistoryEntry({
    required this.id,
    required this.type,
    required this.contentHash,
    required this.createdAt,
    this.textValue,
    this.imagePath,
  });

  final String id;
  final ClipboardEntryType type;
  final String contentHash;
  final String? textValue;
  final String? imagePath;
  final DateTime createdAt;
}

class RemoteClipboardEntry {
  const RemoteClipboardEntry({
    required this.id,
    required this.type,
    required this.createdAt,
    this.textValue,
    this.imageBytes,
  });

  final String id;
  final ClipboardEntryType type;
  final DateTime createdAt;
  final String? textValue;
  final Uint8List? imageBytes;
}

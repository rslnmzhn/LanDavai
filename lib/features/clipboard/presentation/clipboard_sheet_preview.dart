import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/clipboard_entry.dart';

const int _clipboardListPreviewTextLimit = 180;
const int _clipboardPreviewCacheSize = 72;

class LocalClipboardListEntryPreview {
  const LocalClipboardListEntryPreview({
    required this.source,
    required this.createdLabel,
    this.previewText,
    this.imageProvider,
  });

  final ClipboardHistoryEntry source;
  final String createdLabel;
  final String? previewText;
  final ImageProvider<Object>? imageProvider;
}

class RemoteClipboardListEntryPreview {
  const RemoteClipboardListEntryPreview({
    required this.source,
    required this.createdLabel,
    this.previewText,
    this.imageProvider,
  });

  final RemoteClipboardEntry source;
  final String createdLabel;
  final String? previewText;
  final ImageProvider<Object>? imageProvider;
}

List<LocalClipboardListEntryPreview> buildLocalClipboardListPreviews(
  List<ClipboardHistoryEntry> entries,
) {
  return entries
      .map(_buildLocalClipboardListEntryPreview)
      .toList(growable: false);
}

List<RemoteClipboardListEntryPreview> buildRemoteClipboardListPreviews(
  List<RemoteClipboardEntry> entries,
) {
  return entries
      .map(_buildRemoteClipboardListEntryPreview)
      .toList(growable: false);
}

String buildClipboardPreviewText(String? rawText) {
  final text = rawText?.trim() ?? '';
  if (text.isEmpty) {
    return '';
  }

  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.length <= _clipboardListPreviewTextLimit) {
    return collapsed;
  }
  final clipped = collapsed.substring(0, _clipboardListPreviewTextLimit - 1);
  return '${clipped.trimRight()}…';
}

String formatClipboardCreatedAt(DateTime createdAt) {
  final local = createdAt.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

LocalClipboardListEntryPreview _buildLocalClipboardListEntryPreview(
  ClipboardHistoryEntry entry,
) {
  return LocalClipboardListEntryPreview(
    source: entry,
    createdLabel: formatClipboardCreatedAt(entry.createdAt),
    previewText: entry.type == ClipboardEntryType.text
        ? buildClipboardPreviewText(entry.textValue)
        : null,
    imageProvider: entry.type == ClipboardEntryType.image
        ? _buildFilePreviewProvider(entry.imagePath)
        : null,
  );
}

RemoteClipboardListEntryPreview _buildRemoteClipboardListEntryPreview(
  RemoteClipboardEntry entry,
) {
  return RemoteClipboardListEntryPreview(
    source: entry,
    createdLabel: formatClipboardCreatedAt(entry.createdAt),
    previewText: entry.type == ClipboardEntryType.text
        ? buildClipboardPreviewText(entry.textValue)
        : null,
    imageProvider: entry.type == ClipboardEntryType.image
        ? _buildMemoryPreviewProvider(entry.imageBytes)
        : null,
  );
}

ImageProvider<Object>? _buildFilePreviewProvider(String? imagePath) {
  final path = imagePath?.trim();
  if (path == null || path.isEmpty) {
    return null;
  }
  return ResizeImage.resizeIfNeeded(
    _clipboardPreviewCacheSize,
    _clipboardPreviewCacheSize,
    FileImage(File(path)),
  );
}

ImageProvider<Object>? _buildMemoryPreviewProvider(Uint8List? imageBytes) {
  if (imageBytes == null || imageBytes.isEmpty) {
    return null;
  }
  return ResizeImage.resizeIfNeeded(
    _clipboardPreviewCacheSize,
    _clipboardPreviewCacheSize,
    MemoryImage(imageBytes),
  );
}

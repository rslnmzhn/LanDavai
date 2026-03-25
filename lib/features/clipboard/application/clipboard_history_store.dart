import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../transfer/data/transfer_storage_service.dart';
import '../data/clipboard_capture_service.dart';
import '../data/clipboard_history_repository.dart';
import '../domain/clipboard_entry.dart';

class ClipboardHistoryStore extends ChangeNotifier {
  ClipboardHistoryStore({
    required ClipboardHistoryRepository clipboardHistoryRepository,
    required ClipboardCaptureService clipboardCaptureService,
    required TransferStorageService transferStorageService,
    this.loadLimit = 300,
    this.appFolderName = 'Landa',
  }) : _clipboardHistoryRepository = clipboardHistoryRepository,
       _clipboardCaptureService = clipboardCaptureService,
       _transferStorageService = transferStorageService;

  final ClipboardHistoryRepository _clipboardHistoryRepository;
  final ClipboardCaptureService _clipboardCaptureService;
  final TransferStorageService _transferStorageService;
  final int loadLimit;
  final String appFolderName;

  final List<ClipboardHistoryEntry> _entries = <ClipboardHistoryEntry>[];
  String? _lastCapturedClipboardHash;

  List<ClipboardHistoryEntry> get entries =>
      List<ClipboardHistoryEntry>.unmodifiable(_entries);

  ClipboardHistoryEntry? findLatest() {
    if (_entries.isEmpty) {
      return null;
    }
    return _entries.first;
  }

  List<ClipboardHistoryEntry> listRecent({int? limit}) {
    final safeLimit = limit;
    if (safeLimit == null || safeLimit >= _entries.length) {
      return entries;
    }
    return List<ClipboardHistoryEntry>.unmodifiable(
      _entries.take(safeLimit).toList(growable: false),
    );
  }

  Future<void> load({
    bool notify = true,
    bool updateLastCapturedHash = true,
  }) async {
    try {
      final rows = await _clipboardHistoryRepository.listRecent(
        limit: loadLimit,
      );
      _entries
        ..clear()
        ..addAll(rows);
      if (updateLastCapturedHash) {
        _lastCapturedClipboardHash = rows.isEmpty
            ? null
            : rows.first.contentHash;
      }
      if (notify) {
        notifyListeners();
      }
    } catch (error) {
      _log('Failed to load clipboard history: $error');
    }
  }

  Future<void> captureSnapshot({required int maxEntries}) async {
    final captured = await _clipboardCaptureService.readCurrentClipboard();
    if (captured == null) {
      return;
    }
    if (_lastCapturedClipboardHash == captured.contentHash) {
      return;
    }
    if (await _clipboardHistoryRepository.hasHash(captured.contentHash)) {
      _lastCapturedClipboardHash = captured.contentHash;
      return;
    }

    final entry = await _buildEntryFromCapture(captured);
    await appendEntry(entry: entry, maxEntries: maxEntries);
  }

  Future<void> appendEntry({
    required ClipboardHistoryEntry entry,
    int? maxEntries,
  }) async {
    await _clipboardHistoryRepository.insert(entry);
    _lastCapturedClipboardHash = entry.contentHash;
    if (maxEntries != null) {
      await _trimRemovedEntries(maxEntries);
    }
    await load(updateLastCapturedHash: false);
  }

  Future<ClipboardHistoryEntry?> deleteEntry(String entryId) async {
    final normalizedId = entryId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }

    final removed = await _clipboardHistoryRepository.deleteById(normalizedId);
    if (removed == null) {
      return null;
    }
    await _deleteClipboardImageFileIfExists(removed.imagePath);
    await load(updateLastCapturedHash: false);
    return removed;
  }

  Future<void> trimHistory(int maxEntries) async {
    await _trimRemovedEntries(maxEntries);
    await load(updateLastCapturedHash: false);
  }

  Future<ClipboardHistoryEntry> _buildEntryFromCapture(
    ClipboardCaptureData captured,
  ) async {
    final createdAt = DateTime.now();
    final entryId = _buildEntryId(
      contentHash: captured.contentHash,
      createdAt: createdAt,
    );
    String? imagePath;
    if (captured.type == ClipboardEntryType.image &&
        captured.imageBytes != null &&
        captured.imageBytes!.isNotEmpty) {
      final directory = await _transferStorageService.resolveClipboardDirectory(
        appFolderName: appFolderName,
      );
      imagePath = p.join(directory.path, '$entryId.png');
      await File(imagePath).writeAsBytes(captured.imageBytes!, flush: true);
    }

    return ClipboardHistoryEntry(
      id: entryId,
      type: captured.type,
      contentHash: captured.contentHash,
      textValue: captured.textValue,
      imagePath: imagePath,
      createdAt: createdAt,
    );
  }

  Future<void> _trimRemovedEntries(int maxEntries) async {
    final removed = await _clipboardHistoryRepository.trimToMaxEntries(
      maxEntries,
    );
    for (final entry in removed) {
      await _deleteClipboardImageFileIfExists(entry.imagePath);
    }
  }

  Future<void> _deleteClipboardImageFileIfExists(String? imagePath) async {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) {
      return;
    }

    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      _log('Failed to delete clipboard image file $path: $error');
    }
  }

  String _buildEntryId({
    required String contentHash,
    required DateTime createdAt,
  }) {
    final raw = 'clipboard|$contentHash|${createdAt.microsecondsSinceEpoch}';
    final digest = sha256.convert(utf8.encode(raw)).toString();
    return 'clipboard_$digest';
  }

  void _log(String message) {
    developer.log(message, name: 'ClipboardHistoryStore');
  }
}

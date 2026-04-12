import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanSharePacketCodec {
  const LanSharePacketCodec();

  static const int _shareCatalogChunkSizingIndex = 9999;
  static const int _shareCatalogChunkSizingCount = 9999;

  EncodedLanPacket? encodeShareQuery({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanShareQueryPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeShareAccessRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required int transferPort,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'transferPort': transferPort,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanShareAccessRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeShareAccessResponse({
    required String instanceId,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'responderName': responderName,
      'approved': approved,
      'message': message,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanShareAccessResponsePrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeShareCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
    int chunkIndex = 0,
    int chunkCount = 1,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'chunkIndex': chunkIndex,
      'chunkCount': chunkCount,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'removedCacheIds': removedCacheIds,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanShareCatalogPrefix,
      payload: payload,
    );
  }

  List<EncodedLanPacket> encodeShareCatalogChunks({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    final chunkEntries = _chunkShareCatalogEntries(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      createdAtMs: createdAtMs,
    );
    if (chunkEntries.isEmpty) {
      return const <EncodedLanPacket>[];
    }

    final chunkCount = chunkEntries.length;
    final packets = <EncodedLanPacket>[];
    for (var index = 0; index < chunkEntries.length; index += 1) {
      final packet = encodeShareCatalog(
        instanceId: instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: chunkEntries[index],
        removedCacheIds: index == 0 ? removedCacheIds : const <String>[],
        createdAtMs: createdAtMs,
        chunkIndex: index,
        chunkCount: chunkCount,
      );
      if (packet == null) {
        return const <EncodedLanPacket>[];
      }
      packets.add(packet);
    }
    return packets;
  }

  EncodedLanPacket? encodeDownloadRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
    int? transferPort,
    required bool previewMode,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'requesterMacAddress': requesterMacAddress,
      'cacheId': cacheId,
      'selectedRelativePaths': selectedRelativePaths,
      'selectedFolderPrefixes': selectedFolderPrefixes,
      'transferPort': transferPort,
      'previewMode': previewMode,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanDownloadRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeDownloadResponse({
    required String instanceId,
    required String requestId,
    required String responderName,
    required bool approved,
    String? message,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'responderName': responderName,
      'approved': approved,
      'message': message,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanDownloadResponsePrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeThumbnailSyncRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'requesterName': requesterName,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanThumbnailSyncRequestPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeThumbnailPacket({
    required String instanceId,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerMacAddress': ownerMacAddress,
      'cacheId': cacheId,
      'relativePath': relativePath,
      'thumbnailId': thumbnailId,
      'bytesBase64': base64Encode(bytes),
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanThumbnailPacketPrefix,
      payload: payload,
    );
  }

  List<SharedCatalogEntryItem> fitShareCatalogEntries(
    List<SharedCatalogEntryItem> entries,
  ) {
    if (entries.isEmpty) {
      return const <SharedCatalogEntryItem>[];
    }

    final limited = <SharedCatalogEntryItem>[];
    var remainingFilesBudget = lanMaxShareCatalogFilesPerPacket;
    final entryLimit = min(entries.length, lanMaxShareCatalogEntriesPerPacket);

    for (var i = 0; i < entryLimit; i += 1) {
      final entry = entries[i];
      final perEntryBudget = min(
        lanMaxShareCatalogFilesPerEntry,
        max(0, remainingFilesBudget),
      );
      final keepFilesCount = min(entry.files.length, perEntryBudget);
      final keptFiles = keepFilesCount == entry.files.length
          ? entry.files
          : entry.files.take(keepFilesCount).toList(growable: false);
      remainingFilesBudget -= keepFilesCount;
      limited.add(
        SharedCatalogEntryItem(
          cacheId: entry.cacheId,
          displayName: entry.displayName,
          itemCount: entry.itemCount,
          totalBytes: entry.totalBytes,
          files: keptFiles,
        ),
      );
    }

    return limited;
  }

  List<List<SharedCatalogEntryItem>> _chunkShareCatalogEntries({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    if (entries.isEmpty) {
      return const <List<SharedCatalogEntryItem>>[<SharedCatalogEntryItem>[]];
    }

    final remainingEntries = entries
        .map(_PendingShareCatalogEntry.new)
        .toList(growable: false);
    final chunks = <List<SharedCatalogEntryItem>>[];
    var entryIndex = 0;

    while (entryIndex < remainingEntries.length) {
      final chunk = <SharedCatalogEntryItem>[];
      var madeProgress = false;

      while (entryIndex < remainingEntries.length) {
        final pendingEntry = remainingEntries[entryIndex];
        final candidate = _largestEntrySliceThatFits(
          instanceId: instanceId,
          requestId: requestId,
          ownerName: ownerName,
          ownerMacAddress: ownerMacAddress,
          existingEntries: chunk,
          pendingEntry: pendingEntry,
          removedCacheIds: chunks.isEmpty ? removedCacheIds : const <String>[],
          createdAtMs: createdAtMs,
        );
        if (candidate == null) {
          break;
        }

        chunk.add(candidate);
        pendingEntry.consume(candidate.files.length);
        if (pendingEntry.isComplete) {
          entryIndex += 1;
        }
        madeProgress = true;
      }

      if (!madeProgress) {
        final fallbackEntry = remainingEntries[entryIndex];
        final forcedCandidate = fallbackEntry.remainingFileCount == 0
            ? fallbackEntry.slice(0)
            : fallbackEntry.slice(1);
        chunk.add(forcedCandidate);
        fallbackEntry.consume(forcedCandidate.files.length);
        if (fallbackEntry.isComplete) {
          entryIndex += 1;
        }
      }

      chunks.add(List<SharedCatalogEntryItem>.unmodifiable(chunk));
    }

    return List<List<SharedCatalogEntryItem>>.unmodifiable(chunks);
  }

  SharedCatalogEntryItem? _largestEntrySliceThatFits({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> existingEntries,
    required _PendingShareCatalogEntry pendingEntry,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    if (pendingEntry.remainingFileCount == 0) {
      final candidate = pendingEntry.slice(0);
      return _canEncodeShareCatalogChunk(
            instanceId: instanceId,
            requestId: requestId,
            ownerName: ownerName,
            ownerMacAddress: ownerMacAddress,
            entries: <SharedCatalogEntryItem>[...existingEntries, candidate],
            removedCacheIds: removedCacheIds,
            createdAtMs: createdAtMs,
          )
          ? candidate
          : null;
    }

    var low = 1;
    var high = pendingEntry.remainingFileCount;
    SharedCatalogEntryItem? best;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = pendingEntry.slice(mid);
      final fits = _canEncodeShareCatalogChunk(
        instanceId: instanceId,
        requestId: requestId,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: <SharedCatalogEntryItem>[...existingEntries, candidate],
        removedCacheIds: removedCacheIds,
        createdAtMs: createdAtMs,
      );
      if (fits) {
        best = candidate;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return best;
  }

  bool _canEncodeShareCatalogChunk({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    return encodeShareCatalog(
          instanceId: instanceId,
          requestId: requestId,
          ownerName: ownerName,
          ownerMacAddress: ownerMacAddress,
          entries: entries,
          removedCacheIds: removedCacheIds,
          createdAtMs: createdAtMs,
          chunkIndex: _shareCatalogChunkSizingIndex,
          chunkCount: _shareCatalogChunkSizingCount,
        ) !=
        null;
  }

  LanShareQueryPacket? parseShareQueryPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanShareQueryPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    if (instanceId == null || requestId == null || requesterName == null) {
      return null;
    }

    return LanShareQueryPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
    );
  }

  LanShareAccessRequestPacket? parseShareAccessRequestPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanShareAccessRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    final transferPortRaw = decoded['transferPort'];
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null ||
        transferPortRaw is! num) {
      return null;
    }

    final transferPort = transferPortRaw.toInt();
    if (transferPort <= 0 || transferPort > 65535) {
      return null;
    }

    return LanShareAccessRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      transferPort: transferPort,
    );
  }

  LanShareAccessResponsePacket? parseShareAccessResponsePacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanShareAccessResponsePrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final responderName = decoded['responderName'] as String?;
    final approved = decoded['approved'];
    if (instanceId == null ||
        requestId == null ||
        responderName == null ||
        approved is! bool) {
      return null;
    }

    return LanShareAccessResponsePacket(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      approved: approved,
      message: decoded['message'] as String?,
    );
  }

  LanShareCatalogPacket? parseShareCatalogPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanShareCatalogPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerName = decoded['ownerName'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final entriesRaw = decoded['entries'];
    if (instanceId == null ||
        requestId == null ||
        ownerName == null ||
        ownerMacAddress == null ||
        entriesRaw is! List<dynamic>) {
      return null;
    }

    final entries = <SharedCatalogEntryItem>[];
    for (final rawEntry in entriesRaw) {
      if (rawEntry is! Map<String, dynamic>) {
        continue;
      }
      final parsed = SharedCatalogEntryItem.fromJson(rawEntry);
      if (parsed != null) {
        entries.add(parsed);
      }
    }

    final removedRaw = decoded['removedCacheIds'];
    final removedCacheIds = <String>[];
    if (removedRaw is List<dynamic>) {
      for (final raw in removedRaw) {
        if (raw is! String) {
          continue;
        }
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        removedCacheIds.add(normalized);
      }
    }

    return LanShareCatalogPacket(
      instanceId: instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: entries,
      removedCacheIds: removedCacheIds,
      chunkIndex: decoded['chunkIndex'] is num
          ? (decoded['chunkIndex'] as num).toInt()
          : 0,
      chunkCount: decoded['chunkCount'] is num
          ? (decoded['chunkCount'] as num).toInt()
          : 1,
    );
  }

  LanDownloadRequestPacket? parseDownloadRequestPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanDownloadRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final requesterMacAddress = decoded['requesterMacAddress'] as String?;
    final cacheId = decoded['cacheId'] as String?;
    final selectedRelativePathsRaw = decoded['selectedRelativePaths'];
    final selectedFolderPrefixesRaw = decoded['selectedFolderPrefixes'];
    final transferPortRaw = decoded['transferPort'];
    final previewMode = decoded['previewMode'] as bool? ?? false;
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        requesterMacAddress == null ||
        cacheId == null) {
      return null;
    }

    final selectedRelativePaths = <String>[];
    if (selectedRelativePathsRaw is List<dynamic>) {
      for (final raw in selectedRelativePathsRaw) {
        if (raw is! String) {
          continue;
        }
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        selectedRelativePaths.add(normalized);
      }
    }

    final selectedFolderPrefixes = <String>[];
    if (selectedFolderPrefixesRaw is List<dynamic>) {
      for (final raw in selectedFolderPrefixesRaw) {
        if (raw is! String) {
          continue;
        }
        final normalized = raw.trim();
        if (normalized.isEmpty) {
          continue;
        }
        selectedFolderPrefixes.add(normalized);
      }
    }

    return LanDownloadRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      requesterMacAddress: requesterMacAddress,
      cacheId: cacheId,
      selectedRelativePaths: selectedRelativePaths,
      selectedFolderPrefixes: selectedFolderPrefixes,
      transferPort: transferPortRaw is num ? transferPortRaw.toInt() : null,
      previewMode: previewMode,
    );
  }

  LanDownloadResponsePacket? parseDownloadResponsePacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanDownloadResponsePrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final responderName = decoded['responderName'] as String?;
    final approved = decoded['approved'] as bool?;
    if (instanceId == null ||
        requestId == null ||
        responderName == null ||
        approved == null) {
      return null;
    }

    return LanDownloadResponsePacket(
      instanceId: instanceId,
      requestId: requestId,
      responderName: responderName,
      approved: approved,
      message: decoded['message'] as String?,
    );
  }

  LanThumbnailSyncRequestPacket? parseThumbnailSyncRequestPacket(
    String message,
  ) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanThumbnailSyncRequestPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final requesterName = decoded['requesterName'] as String?;
    final itemsRaw = decoded['items'];
    if (instanceId == null ||
        requestId == null ||
        requesterName == null ||
        itemsRaw is! List<dynamic>) {
      return null;
    }

    final items = <ThumbnailSyncItem>[];
    for (final raw in itemsRaw) {
      if (raw is! Map<String, dynamic>) {
        continue;
      }
      final parsed = ThumbnailSyncItem.fromJson(raw);
      if (parsed != null) {
        items.add(parsed);
      }
    }
    if (items.isEmpty) {
      return null;
    }

    return LanThumbnailSyncRequestPacket(
      instanceId: instanceId,
      requestId: requestId,
      requesterName: requesterName,
      items: items,
    );
  }

  LanThumbnailPacket? parseThumbnailPacket(String message) {
    final decoded = decodeLanEnvelope(
      message: message,
      expectedPrefix: lanThumbnailPacketPrefix,
    );
    if (decoded == null) {
      return null;
    }

    final instanceId = decoded['instanceId'] as String?;
    final requestId = decoded['requestId'] as String?;
    final ownerMacAddress = decoded['ownerMacAddress'] as String?;
    final cacheId = decoded['cacheId'] as String?;
    final relativePath = decoded['relativePath'] as String?;
    final thumbnailId = decoded['thumbnailId'] as String?;
    final bytesBase64 = decoded['bytesBase64'] as String?;
    if (instanceId == null ||
        requestId == null ||
        ownerMacAddress == null ||
        cacheId == null ||
        relativePath == null ||
        thumbnailId == null ||
        bytesBase64 == null) {
      return null;
    }

    try {
      final bytes = base64Decode(bytesBase64);
      if (bytes.isEmpty) {
        return null;
      }
      return LanThumbnailPacket(
        instanceId: instanceId,
        requestId: requestId,
        ownerMacAddress: ownerMacAddress,
        cacheId: cacheId,
        relativePath: relativePath,
        thumbnailId: thumbnailId,
        bytes: Uint8List.fromList(bytes),
      );
    } catch (_) {
      return null;
    }
  }
}

class _PendingShareCatalogEntry {
  _PendingShareCatalogEntry(this.entry);

  final SharedCatalogEntryItem entry;
  int consumedFiles = 0;

  int get remainingFileCount => entry.files.length - consumedFiles;
  bool get isComplete => remainingFileCount <= 0;

  void consume(int fileCount) {
    consumedFiles += fileCount;
  }

  SharedCatalogEntryItem slice(int fileCount) {
    final endIndex = fileCount <= 0 ? consumedFiles : consumedFiles + fileCount;
    return SharedCatalogEntryItem(
      cacheId: entry.cacheId,
      displayName: entry.displayName,
      itemCount: entry.itemCount,
      totalBytes: entry.totalBytes,
      files: entry.files.sublist(consumedFiles, endIndex),
    );
  }
}

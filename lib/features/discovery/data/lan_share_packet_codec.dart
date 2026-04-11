import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'lan_packet_codec_common.dart';
import 'lan_packet_codec_models.dart';

class LanSharePacketCodec {
  const LanSharePacketCodec();

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

  EncodedLanPacket? encodeShareCatalog({
    required String instanceId,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    required List<String> removedCacheIds,
    required int createdAtMs,
  }) {
    final payload = <String, Object?>{
      'instanceId': instanceId,
      'requestId': requestId,
      'ownerName': ownerName,
      'ownerMacAddress': ownerMacAddress,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'removedCacheIds': removedCacheIds,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanShareCatalogPrefix,
      payload: payload,
    );
  }

  EncodedLanPacket? encodeDownloadRequest({
    required String instanceId,
    required String requestId,
    required String requesterName,
    required String requesterMacAddress,
    required String cacheId,
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
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
      'previewMode': previewMode,
      'createdAtMs': createdAtMs,
    };
    return encodeLanEnvelopePacket(
      prefix: lanDownloadRequestPrefix,
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
      previewMode: previewMode,
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

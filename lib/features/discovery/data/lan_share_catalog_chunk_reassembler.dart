import 'lan_packet_codec_models.dart';

class LanShareCatalogChunkReassembler {
  LanShareCatalogChunkReassembler({
    this.chunkTtl = const Duration(seconds: 15),
  });

  final Duration chunkTtl;
  final Map<String, _PendingShareCatalogChunks> _pendingShareCatalogChunks =
      <String, _PendingShareCatalogChunks>{};

  LanShareCatalogPacket? consume({
    required LanShareCatalogPacket packet,
    required String senderIp,
    DateTime? now,
    void Function(String message)? log,
  }) {
    prune(now);
    if (packet.chunkCount <= 1) {
      return packet;
    }
    if (packet.chunkIndex < 0 || packet.chunkIndex >= packet.chunkCount) {
      log?.call(
        'Ignoring malformed share catalog chunk from $senderIp '
        '(requestId=${packet.requestId}, chunk=${packet.chunkIndex}/${packet.chunkCount})',
      );
      return null;
    }
    final key =
        '$senderIp|${packet.instanceId}|${packet.requestId}|${packet.ownerMacAddress}';
    final pending = _pendingShareCatalogChunks.putIfAbsent(
      key,
      () => _PendingShareCatalogChunks(
        requestId: packet.requestId,
        ownerName: packet.ownerName,
        ownerMacAddress: packet.ownerMacAddress,
        chunkCount: packet.chunkCount,
        createdAt: now ?? DateTime.now(),
      ),
    );
    final reassembled = pending.add(packet);
    if (reassembled != null) {
      _pendingShareCatalogChunks.remove(key);
      return reassembled;
    }
    return null;
  }

  void prune([DateTime? now]) {
    final observedNow = now ?? DateTime.now();
    _pendingShareCatalogChunks.removeWhere(
      (_, pending) => observedNow.difference(pending.createdAt) > chunkTtl,
    );
  }

  void clear() {
    _pendingShareCatalogChunks.clear();
  }
}

class _PendingShareCatalogChunks {
  _PendingShareCatalogChunks({
    required this.requestId,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.chunkCount,
    required this.createdAt,
  });

  final String requestId;
  final String ownerName;
  final String ownerMacAddress;
  final int chunkCount;
  final DateTime createdAt;
  final Map<int, LanShareCatalogPacket> _chunksByIndex =
      <int, LanShareCatalogPacket>{};

  LanShareCatalogPacket? add(LanShareCatalogPacket packet) {
    _chunksByIndex[packet.chunkIndex] = packet;
    if (_chunksByIndex.length < chunkCount) {
      return null;
    }

    final mergedEntriesByCacheId = <String, _MergedShareCatalogEntry>{};
    final orderedCacheIds = <String>[];
    final removedCacheIds = <String>{};
    for (var chunkIndex = 0; chunkIndex < chunkCount; chunkIndex += 1) {
      final chunk = _chunksByIndex[chunkIndex];
      if (chunk == null) {
        return null;
      }
      removedCacheIds.addAll(chunk.removedCacheIds);
      for (final entry in chunk.entries) {
        final merged = mergedEntriesByCacheId.putIfAbsent(entry.cacheId, () {
          orderedCacheIds.add(entry.cacheId);
          return _MergedShareCatalogEntry(
            cacheId: entry.cacheId,
            displayName: entry.displayName,
            itemCount: entry.itemCount,
            totalBytes: entry.totalBytes,
          );
        });
        merged.files.addAll(entry.files);
      }
    }

    return LanShareCatalogPacket(
      instanceId: _chunksByIndex[0]!.instanceId,
      requestId: requestId,
      ownerName: ownerName,
      ownerMacAddress: ownerMacAddress,
      entries: orderedCacheIds
          .map((cacheId) => mergedEntriesByCacheId[cacheId]!.build())
          .toList(growable: false),
      removedCacheIds: removedCacheIds.toList(growable: false),
    );
  }
}

class _MergedShareCatalogEntry {
  _MergedShareCatalogEntry({
    required this.cacheId,
    required this.displayName,
    required this.itemCount,
    required this.totalBytes,
  });

  final String cacheId;
  final String displayName;
  final int itemCount;
  final int totalBytes;
  final List<SharedCatalogFileItem> files = <SharedCatalogFileItem>[];

  SharedCatalogEntryItem build() {
    return SharedCatalogEntryItem(
      cacheId: cacheId,
      displayName: displayName,
      itemCount: itemCount,
      totalBytes: totalBytes,
      files: List<SharedCatalogFileItem>.unmodifiable(files),
    );
  }
}

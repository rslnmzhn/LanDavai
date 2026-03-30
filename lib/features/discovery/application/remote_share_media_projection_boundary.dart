import 'dart:io';

import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/data/file_hash_service.dart';
import '../../transfer/data/shared_cache_thumbnail_store.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_packet_codec.dart';
import '../data/lan_protocol_events.dart';
import 'remote_share_browser.dart';

class RemoteShareMediaProjectionBoundary {
  RemoteShareMediaProjectionBoundary({
    required RemoteShareBrowser remoteShareBrowser,
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required SharedCacheThumbnailStore sharedFolderCacheRepository,
    required FileHashService fileHashService,
    required LanDiscoveryService lanDiscoveryService,
  }) : _remoteShareBrowser = remoteShareBrowser,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _sharedFolderCacheRepository = sharedFolderCacheRepository,
       _fileHashService = fileHashService,
       _lanDiscoveryService = lanDiscoveryService;

  static const int _maxThumbnailSyncItemsPerCatalog = 240;

  final RemoteShareBrowser _remoteShareBrowser;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final SharedCacheThumbnailStore _sharedFolderCacheRepository;
  final FileHashService _fileHashService;
  final LanDiscoveryService _lanDiscoveryService;

  Future<void> syncRemoteThumbnails({
    required ShareCatalogEvent event,
    required String requesterName,
  }) async {
    final ownerMac = DeviceAliasRepository.normalizeMac(event.ownerMacAddress);
    if (ownerMac == null) {
      return;
    }

    final requested = <ThumbnailSyncItem>[];
    final localUpdates = <RemoteBrowsePreviewPathUpdate>[];
    var syncLimitReached = false;
    for (final entry in event.entries) {
      for (final file in entry.files) {
        final thumbId = file.thumbnailId;
        if (thumbId == null || thumbId.isEmpty) {
          continue;
        }

        final existing = _remoteShareBrowser.previewPathFor(
          ownerIp: event.ownerIp,
          cacheId: entry.cacheId,
          relativePath: file.relativePath,
        );
        if (existing != null && await File(existing).exists()) {
          continue;
        }

        final localPath = await _sharedFolderCacheRepository
            .resolveReceiverThumbnailPath(
              ownerMacAddress: ownerMac,
              cacheId: entry.cacheId,
              thumbnailId: thumbId,
            );
        if (localPath != null) {
          localUpdates.add(
            RemoteBrowsePreviewPathUpdate(
              ownerIp: event.ownerIp,
              cacheId: entry.cacheId,
              relativePath: file.relativePath,
              previewPath: localPath,
            ),
          );
          continue;
        }

        requested.add(
          ThumbnailSyncItem(
            cacheId: entry.cacheId,
            relativePath: file.relativePath,
            thumbnailId: thumbId,
          ),
        );
        if (requested.length >= _maxThumbnailSyncItemsPerCatalog) {
          syncLimitReached = true;
          break;
        }
      }
      if (syncLimitReached) {
        break;
      }
    }

    if (localUpdates.isNotEmpty) {
      _remoteShareBrowser.recordPreviewPaths(localUpdates);
    }
    if (requested.isEmpty) {
      return;
    }

    final requestId = _fileHashService.buildStableId(
      'thumb-sync|${event.ownerIp}|${DateTime.now().microsecondsSinceEpoch}',
    );
    await _lanDiscoveryService.sendThumbnailSyncRequest(
      targetIp: event.ownerIp,
      requestId: requestId,
      requesterName: requesterName,
      items: requested,
    );
  }

  Future<void> handleThumbnailSyncRequest({
    required ThumbnailSyncRequestEvent event,
    required String ownerMacAddress,
  }) async {
    final ownerMac = DeviceAliasRepository.normalizeMac(ownerMacAddress);
    if (ownerMac == null) {
      return;
    }

    await _sharedCacheCatalog.loadOwnerCaches(ownerMacAddress: ownerMac);
    final cachesById = <String, SharedFolderCacheRecord>{
      for (final cache in _sharedCacheCatalog.ownerCaches) cache.cacheId: cache,
    };
    final entriesByCache = <String, Map<String, SharedFolderIndexEntry>>{};
    for (final item in event.items) {
      final cache = cachesById[item.cacheId];
      if (cache == null) {
        continue;
      }
      final byRelative = entriesByCache.putIfAbsent(
        item.cacheId,
        () => <String, SharedFolderIndexEntry>{},
      );
      if (!byRelative.containsKey(item.relativePath)) {
        final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
        for (final entry in entries) {
          byRelative[entry.relativePath] = entry;
        }
      }

      final entry = byRelative[item.relativePath];
      if (entry == null ||
          entry.thumbnailId == null ||
          entry.thumbnailId != item.thumbnailId) {
        continue;
      }

      final bytes = await _sharedFolderCacheRepository.readOwnerThumbnailBytes(
        cacheId: item.cacheId,
        thumbnailId: item.thumbnailId,
      );
      if (bytes == null || bytes.isEmpty) {
        continue;
      }

      await _lanDiscoveryService.sendThumbnailPacket(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerMacAddress: ownerMac,
        cacheId: item.cacheId,
        relativePath: item.relativePath,
        thumbnailId: item.thumbnailId,
        bytes: bytes,
      );
    }
  }

  Future<void> handleThumbnailPacket({
    required ThumbnailPacketEvent event,
  }) async {
    if (event.bytes.isEmpty) {
      return;
    }
    final ownerMac = DeviceAliasRepository.normalizeMac(event.ownerMacAddress);
    if (ownerMac == null) {
      return;
    }
    final savedPath = await _sharedFolderCacheRepository
        .saveReceiverThumbnailBytes(
          ownerMacAddress: ownerMac,
          cacheId: event.cacheId,
          thumbnailId: event.thumbnailId,
          bytes: event.bytes,
        );
    _remoteShareBrowser.recordPreviewPath(
      ownerIp: event.ownerIp,
      cacheId: event.cacheId,
      relativePath: event.relativePath,
      previewPath: savedPath,
    );
  }
}

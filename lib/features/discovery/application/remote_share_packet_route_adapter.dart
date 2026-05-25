import 'dart:io';

import '../../transfer/application/shared_cache_catalog.dart';
import '../../transfer/application/shared_cache_index_store.dart';
import '../../transfer/domain/shared_folder_cache.dart';
import '../data/device_alias_repository.dart';
import '../data/lan_discovery_service.dart';
import '../data/lan_packet_codec.dart';
import '../data/lan_protocol_events.dart';
import 'remote_share_browser.dart';
import 'remote_share_media_projection_boundary.dart';

class RemoteShareCatalogRouteResult {
  const RemoteShareCatalogRouteResult({
    required this.ownerIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.observedAt,
    required this.removedLocalCacheCount,
    required this.ownerReportedRemovedCacheCount,
  });

  final String ownerIp;
  final String ownerName;
  final String? ownerMacAddress;
  final DateTime observedAt;
  final int removedLocalCacheCount;
  final int ownerReportedRemovedCacheCount;
}

class RemoteSharePacketRouteAdapter {
  RemoteSharePacketRouteAdapter({
    required LanDiscoveryService lanDiscoveryService,
    required SharedCacheCatalog sharedCacheCatalog,
    required SharedCacheIndexStore sharedCacheIndexStore,
    required RemoteShareBrowser remoteShareBrowser,
    required RemoteShareMediaProjectionBoundary
    remoteShareMediaProjectionBoundary,
    required String Function() localNameProvider,
    required String Function() localDeviceMacProvider,
    required List<SharedFolderCacheRecord> Function() ownerCachesProvider,
    required Future<void> Function() loadOwnerCaches,
    required Future<bool> Function() hasSharedStorageAccess,
    void Function(String message)? log,
  }) : _lanDiscoveryService = lanDiscoveryService,
       _sharedCacheCatalog = sharedCacheCatalog,
       _sharedCacheIndexStore = sharedCacheIndexStore,
       _remoteShareBrowser = remoteShareBrowser,
       _remoteShareMediaProjectionBoundary = remoteShareMediaProjectionBoundary,
       _localNameProvider = localNameProvider,
       _localDeviceMacProvider = localDeviceMacProvider,
       _ownerCachesProvider = ownerCachesProvider,
       _loadOwnerCaches = loadOwnerCaches,
       _hasSharedStorageAccess = hasSharedStorageAccess,
       _log = log;

  final LanDiscoveryService _lanDiscoveryService;
  final SharedCacheCatalog _sharedCacheCatalog;
  final SharedCacheIndexStore _sharedCacheIndexStore;
  final RemoteShareBrowser _remoteShareBrowser;
  final RemoteShareMediaProjectionBoundary _remoteShareMediaProjectionBoundary;
  final String Function() _localNameProvider;
  final String Function() _localDeviceMacProvider;
  final List<SharedFolderCacheRecord> Function() _ownerCachesProvider;
  final Future<void> Function() _loadOwnerCaches;
  final Future<bool> Function() _hasSharedStorageAccess;
  final void Function(String message)? _log;

  Future<void> handleShareQuery(ShareQueryEvent event) async {
    try {
      final requesterAddress = InternetAddress.tryParse(event.requesterIp);
      if (requesterAddress == null ||
          requesterAddress.type != InternetAddressType.IPv4 ||
          requesterAddress.address == '0.0.0.0') {
        _log?.call(
          'Ignoring share query with invalid requester IP: ${event.requesterIp}',
        );
        return;
      }

      final removedCacheIds = <String>[];
      if (await _canPruneUnavailableOwnerCaches()) {
        removedCacheIds.addAll(
          await _sharedCacheCatalog.pruneUnavailableOwnerCaches(
            ownerMacAddress: _localDeviceMacProvider(),
          ),
        );
      } else {
        _log?.call(
          'Skipping owner cache pruning: Android shared storage access is not granted.',
        );
      }
      await _loadOwnerCaches();

      final catalog = await _buildShareCatalog();
      await _lanDiscoveryService.sendShareCatalog(
        targetIp: event.requesterIp,
        requestId: event.requestId,
        ownerName: _localNameProvider(),
        ownerMacAddress: _localDeviceMacProvider(),
        entries: catalog,
        removedCacheIds: removedCacheIds,
      );
      _log?.call(
        'Share catalog sent to ${event.requesterIp}. '
        'entries=${catalog.length} removed=${removedCacheIds.length}',
      );
    } catch (error) {
      _log?.call(
        'Failed to answer share query from ${event.requesterIp}: $error',
      );
    }
  }

  Future<RemoteShareCatalogRouteResult> handleShareCatalog({
    required ShareCatalogEvent event,
    required String ownerDisplayName,
    required String? ownerMacAddress,
  }) async {
    final removedLocalCacheCount = await _pruneStaleReceiverCaches(
      event: event,
      ownerMacAddress: ownerMacAddress,
    );

    await _remoteShareBrowser.applyRemoteCatalog(
      event: event,
      ownerDisplayName: ownerDisplayName,
      ownerMacAddress: ownerMacAddress ?? event.ownerMacAddress,
    );
    _syncRemoteThumbnails(event);

    return RemoteShareCatalogRouteResult(
      ownerIp: event.ownerIp,
      ownerName: event.ownerName,
      ownerMacAddress: ownerMacAddress,
      observedAt: event.observedAt,
      removedLocalCacheCount: removedLocalCacheCount,
      ownerReportedRemovedCacheCount: event.removedCacheIds.length,
    );
  }

  Future<List<SharedCatalogEntryItem>> _buildShareCatalog() async {
    final catalog = <SharedCatalogEntryItem>[];
    for (final cache in _ownerCachesProvider()) {
      final entries = await _sharedCacheIndexStore.readIndexEntries(cache);
      final files = entries
          .map(
            (entry) => SharedCatalogFileItem(
              relativePath: entry.relativePath,
              sizeBytes: entry.sizeBytes,
              thumbnailId: entry.thumbnailId,
            ),
          )
          .toList(growable: false);
      catalog.add(
        SharedCatalogEntryItem(
          cacheId: cache.cacheId,
          displayName: cache.displayName,
          itemCount: entries.length,
          totalBytes: entries.fold<int>(
            0,
            (sum, entry) => sum + entry.sizeBytes,
          ),
          files: files,
        ),
      );
    }
    return catalog;
  }

  Future<bool> _canPruneUnavailableOwnerCaches() async {
    if (!Platform.isAndroid) {
      return true;
    }
    return _hasSharedStorageAccess();
  }

  Future<int> _pruneStaleReceiverCaches({
    required ShareCatalogEvent event,
    required String? ownerMacAddress,
  }) async {
    final ownerMac = DeviceAliasRepository.normalizeMac(ownerMacAddress);
    if (ownerMac == null) {
      return 0;
    }

    final activeCacheIds = event.entries
        .map((entry) => entry.cacheId)
        .where((id) => id.trim().isNotEmpty)
        .toSet();
    final removedLocal = await _sharedCacheCatalog.pruneReceiverCachesForOwner(
      ownerMacAddress: ownerMac,
      receiverMacAddress: _localDeviceMacProvider(),
      activeCacheIds: activeCacheIds,
    );
    if (removedLocal.isNotEmpty) {
      _log?.call(
        'Pruned ${removedLocal.length} stale receiver cache(s) '
        'for owner ${event.ownerIp}',
      );
    } else if (event.removedCacheIds.isNotEmpty) {
      _log?.call(
        'Owner ${event.ownerIp} reported ${event.removedCacheIds.length} removed cache(s).',
      );
    }
    return removedLocal.length;
  }

  void _syncRemoteThumbnails(ShareCatalogEvent event) {
    _remoteShareMediaProjectionBoundary
        .syncRemoteThumbnails(event: event, requesterName: _localNameProvider())
        .catchError((Object error, StackTrace stack) {
          _log?.call(
            'Unhandled remote share media projection error '
            'from ${event.ownerIp}: $error',
          );
          _log?.call(stack.toString());
        });
  }
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/application/remote_share_packet_route_adapter.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteSharePacketRouteAdapter', () {
    test('answers share queries with owner cache catalog', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_remote_share_route_query_',
      );
      addTearDown(harness.dispose);

      final bundle = _SharedCacheBundle(harness);
      final fixtureDirectory = Directory(
        p.join(harness.rootDirectory.path, 'shared_docs'),
      );
      await fixtureDirectory.create(recursive: true);
      await File(
        p.join(fixtureDirectory.path, 'readme.txt'),
      ).writeAsString('hello', flush: true);
      final upsertResult = await bundle.catalog.upsertOwnerFolderCache(
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        folderPath: fixtureDirectory.path,
        displayName: 'Docs',
      );
      final cache = upsertResult.record;

      var loadOwnerCachesCalls = 0;
      final lanDiscoveryService = _RecordingLanDiscoveryService();
      final adapter = _buildAdapter(
        lanDiscoveryService: lanDiscoveryService,
        bundle: bundle,
        ownerCachesProvider: () => <SharedFolderCacheRecord>[cache],
        loadOwnerCaches: () async {
          loadOwnerCachesCalls += 1;
        },
      );

      await adapter.handleShareQuery(
        ShareQueryEvent(
          requestId: 'share-request-1',
          requesterIp: '192.168.1.44',
          requesterName: 'Remote',
          observedAt: DateTime(2026),
        ),
      );

      expect(loadOwnerCachesCalls, 1);
      expect(lanDiscoveryService.shareCatalogs, hasLength(1));
      final sent = lanDiscoveryService.shareCatalogs.single;
      expect(sent.targetIp, '192.168.1.44');
      expect(sent.ownerName, 'Local');
      expect(sent.ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
      expect(sent.entries.single.cacheId, cache.cacheId);
      expect(sent.entries.single.displayName, 'Docs');
      expect(sent.entries.single.files.single.relativePath, 'readme.txt');
    });

    test('ignores share queries with invalid requester IP', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_remote_share_route_invalid_',
      );
      addTearDown(harness.dispose);

      var loadOwnerCachesCalls = 0;
      final lanDiscoveryService = _RecordingLanDiscoveryService();
      final adapter = _buildAdapter(
        lanDiscoveryService: lanDiscoveryService,
        bundle: _SharedCacheBundle(harness),
        ownerCachesProvider: () => const <SharedFolderCacheRecord>[],
        loadOwnerCaches: () async {
          loadOwnerCachesCalls += 1;
        },
      );

      await adapter.handleShareQuery(
        ShareQueryEvent(
          requestId: 'share-request-1',
          requesterIp: '0.0.0.0',
          requesterName: 'Remote',
          observedAt: DateTime(2026),
        ),
      );

      expect(loadOwnerCachesCalls, 0);
      expect(lanDiscoveryService.shareCatalogs, isEmpty);
    });

    test('applies share catalogs through RemoteShareBrowser', () async {
      final harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_remote_share_route_catalog_',
      );
      addTearDown(harness.dispose);

      final bundle = _SharedCacheBundle(harness);
      final adapter = _buildAdapter(
        lanDiscoveryService: _RecordingLanDiscoveryService(),
        bundle: bundle,
        ownerCachesProvider: () => const <SharedFolderCacheRecord>[],
      );
      await bundle.browser.startBrowse(
        targets: const [],
        receiverMacAddress: 'aa:bb:cc:dd:ee:ff',
        requesterName: 'Local',
        requestId: 'share-request-1',
        responseWindow: Duration.zero,
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) async {},
      );

      final result = await adapter.handleShareCatalog(
        event: ShareCatalogEvent(
          requestId: 'share-request-1',
          ownerIp: '192.168.1.45',
          ownerName: 'Remote',
          ownerMacAddress: '11:22:33:44:55:66',
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026),
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Photos',
              itemCount: 1,
              totalBytes: 42,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(
                  relativePath: 'album/photo.jpg',
                  sizeBytes: 42,
                ),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Remote',
        ownerMacAddress: '11:22:33:44:55:66',
      );

      expect(result.ownerIp, '192.168.1.45');
      expect(bundle.browser.applyRemoteCatalogCalls, 1);
      final options = bundle.browser.currentBrowseProjection.options;
      expect(options, hasLength(1));
      expect(options.single.ownerIp, '192.168.1.45');
      expect(options.single.entry.displayName, 'Photos');
    });
  });
}

RemoteSharePacketRouteAdapter _buildAdapter({
  required _RecordingLanDiscoveryService lanDiscoveryService,
  required _SharedCacheBundle bundle,
  required List<SharedFolderCacheRecord> Function() ownerCachesProvider,
  Future<void> Function()? loadOwnerCaches,
}) {
  return RemoteSharePacketRouteAdapter(
    lanDiscoveryService: lanDiscoveryService,
    sharedCacheCatalog: bundle.catalog,
    sharedCacheIndexStore: bundle.indexStore,
    remoteShareBrowser: bundle.browser,
    remoteShareMediaProjectionBoundary: bundle.mediaProjectionBoundary,
    localNameProvider: () => 'Local',
    localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
    ownerCachesProvider: ownerCachesProvider,
    loadOwnerCaches: loadOwnerCaches ?? () async {},
    hasSharedStorageAccess: () async => true,
  );
}

class _SharedCacheBundle {
  _SharedCacheBundle(TestAppDatabaseHarness harness)
    : indexStore = SharedCacheIndexStore(
        database: harness.database,
        thumbnailCacheService: ThumbnailCacheService(
          database: harness.database,
        ),
      ),
      recordStore = SharedFolderCacheRepository(database: harness.database) {
    catalog = SharedCacheCatalog(
      sharedCacheRecordStore: recordStore,
      sharedCacheIndexStore: indexStore,
    );
    browser = _TrackingRemoteShareBrowser(sharedCacheCatalog: catalog);
    mediaProjectionBoundary = RemoteShareMediaProjectionBoundary(
      remoteShareBrowser: browser,
      sharedCacheCatalog: catalog,
      sharedCacheIndexStore: indexStore,
      sharedCacheThumbnailStore: ThumbnailCacheService(
        database: harness.database,
      ),
      fileHashService: FileHashService(),
      lanDiscoveryService: _RecordingLanDiscoveryService(),
    );
  }

  final SharedCacheIndexStore indexStore;
  final SharedFolderCacheRepository recordStore;
  late final SharedCacheCatalog catalog;
  late final _TrackingRemoteShareBrowser browser;
  late final RemoteShareMediaProjectionBoundary mediaProjectionBoundary;
}

class _TrackingRemoteShareBrowser extends RemoteShareBrowser {
  _TrackingRemoteShareBrowser({required super.sharedCacheCatalog});

  int applyRemoteCatalogCalls = 0;

  @override
  Future<void> applyRemoteCatalog({
    required ShareCatalogEvent event,
    required String ownerDisplayName,
    required String ownerMacAddress,
  }) async {
    applyRemoteCatalogCalls += 1;
    await super.applyRemoteCatalog(
      event: event,
      ownerDisplayName: ownerDisplayName,
      ownerMacAddress: ownerMacAddress,
    );
  }
}

class _RecordedShareCatalog {
  const _RecordedShareCatalog({
    required this.targetIp,
    required this.ownerName,
    required this.ownerMacAddress,
    required this.entries,
  });

  final String targetIp;
  final String ownerName;
  final String ownerMacAddress;
  final List<SharedCatalogEntryItem> entries;
}

class _RecordingLanDiscoveryService extends LanDiscoveryService {
  final List<_RecordedShareCatalog> shareCatalogs = <_RecordedShareCatalog>[];

  @override
  Future<void> sendShareCatalog({
    required String targetIp,
    required String requestId,
    required String ownerName,
    required String ownerMacAddress,
    required List<SharedCatalogEntryItem> entries,
    List<String> removedCacheIds = const <String>[],
  }) async {
    shareCatalogs.add(
      _RecordedShareCatalog(
        targetIp: targetIp,
        ownerName: ownerName,
        ownerMacAddress: ownerMacAddress,
        entries: entries,
      ),
    );
  }
}

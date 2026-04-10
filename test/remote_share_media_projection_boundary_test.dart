import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/application/remote_share_media_projection_boundary.dart';
import 'package:landa/features/discovery/data/lan_discovery_service.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late SharedFolderCacheRepository sharedFolderCacheRepository;
  late ThumbnailCacheService thumbnailCacheService;
  late SharedCacheIndexStore sharedCacheIndexStore;
  late SharedCacheCatalog sharedCacheCatalog;
  late RemoteShareBrowser remoteShareBrowser;
  late CapturingLanDiscoveryService lanDiscoveryService;
  late RemoteShareMediaProjectionBoundary boundary;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_remote_share_media_projection_boundary_',
    );
    thumbnailCacheService = ThumbnailCacheService(database: harness.database);
    sharedFolderCacheRepository = SharedFolderCacheRepository(
      database: harness.database,
    );
    sharedCacheIndexStore = SharedCacheIndexStore(
      database: harness.database,
      thumbnailCacheService: thumbnailCacheService,
    );
    sharedCacheCatalog = SharedCacheCatalog(
      sharedCacheRecordStore: sharedFolderCacheRepository,
      sharedCacheIndexStore: sharedCacheIndexStore,
    );
    remoteShareBrowser = RemoteShareBrowser(
      sharedCacheCatalog: sharedCacheCatalog,
    );
    lanDiscoveryService = CapturingLanDiscoveryService();
    boundary = RemoteShareMediaProjectionBoundary(
      remoteShareBrowser: remoteShareBrowser,
      sharedCacheCatalog: sharedCacheCatalog,
      sharedCacheIndexStore: sharedCacheIndexStore,
      sharedCacheThumbnailStore: thumbnailCacheService,
      fileHashService: FileHashService(),
      lanDiscoveryService: lanDiscoveryService,
    );
  });

  tearDown(() async {
    remoteShareBrowser.dispose();
    sharedCacheCatalog.dispose();
    await harness.dispose();
  });

  test(
    'syncRemoteThumbnails reuses cached receiver thumbnail paths through RemoteShareBrowser projection ownership',
    () async {
      await _seedRemoteCatalog(
        browser: remoteShareBrowser,
        receiverMacAddress: 'aa:bb:cc:dd:ee:ff',
      );
      final savedPath = await thumbnailCacheService.saveReceiverThumbnailBytes(
        ownerMacAddress: '11:22:33:44:55:66',
        cacheId: 'remote-cache-1',
        thumbnailId: 'thumb-1',
        bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
      );

      await boundary.syncRemoteThumbnails(
        event: _remoteCatalogEvent(),
        requesterName: 'Landa desktop',
      );

      final previewPath = remoteShareBrowser.previewPathFor(
        ownerIp: '192.168.1.40',
        cacheId: 'remote-cache-1',
        relativePath: 'album/photo.jpg',
      );
      expect(previewPath, savedPath);
      expect(lanDiscoveryService.thumbnailSyncRequests, isEmpty);
    },
  );

  test(
    'handleThumbnailPacket writes receiver thumbnail bytes and records preview path through RemoteShareBrowser',
    () async {
      await _seedRemoteCatalog(
        browser: remoteShareBrowser,
        receiverMacAddress: 'aa:bb:cc:dd:ee:ff',
      );

      await boundary.handleThumbnailPacket(
        event: ThumbnailPacketEvent(
          requestId: 'thumb-packet-1',
          ownerIp: '192.168.1.40',
          ownerMacAddress: '11-22-33-44-55-66',
          cacheId: 'remote-cache-1',
          relativePath: 'album/photo.jpg',
          thumbnailId: 'thumb-1',
          bytes: Uint8List.fromList(<int>[9, 8, 7]),
          observedAt: DateTime(2026),
        ),
      );

      final previewPath = remoteShareBrowser.previewPathFor(
        ownerIp: '192.168.1.40',
        cacheId: 'remote-cache-1',
        relativePath: 'album/photo.jpg',
      );
      expect(previewPath, isNotNull);
      expect(await File(previewPath!).exists(), isTrue);
    },
  );

  test(
    'handleThumbnailSyncRequest reads owner thumbnail bytes and replies through existing media protocol flow',
    () async {
      final imageFile = File(
        p.join(harness.rootDirectory.path, 'owner-thumb-source.png'),
      );
      await imageFile.writeAsBytes(_tinyPngBytes);
      final ownerCache = SharedFolderCacheRecord(
        cacheId: 'owner-cache-1',
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: 'selection://owner-cache-1',
        displayName: 'Owner files',
        indexFilePath: await sharedCacheIndexStore.resolveIndexFilePath(
          role: SharedFolderCacheRole.owner,
          displayName: 'Owner files',
          cacheId: 'owner-cache-1',
        ),
        itemCount: 1,
        totalBytes: _tinyPngBytes.length,
        updatedAtMs: DateTime(2026).millisecondsSinceEpoch,
      );
      await sharedFolderCacheRepository.upsertCacheRecord(ownerCache);
      const thumbnailId = 'manual-thumb-1';
      await sharedCacheIndexStore.materializeReceiverIndex(
        record: ownerCache,
        entries: <SharedFolderIndexEntry>[
          SharedFolderIndexEntry(
            relativePath: 'owner-thumb-source.png',
            sizeBytes: _tinyPngBytes.length,
            modifiedAtMs: DateTime(2026).millisecondsSinceEpoch,
            absolutePath: imageFile.path,
            thumbnailId: thumbnailId,
          ),
        ],
      );
      final thumbnailRoot = await harness.database
          .resolveSharedThumbnailDirectory();
      final ownerThumbnailFile = File(
        p.join(
          thumbnailRoot.path,
          'owner',
          ownerCache.cacheId,
          '$thumbnailId.jpg',
        ),
      );
      await ownerThumbnailFile.parent.create(recursive: true);
      await ownerThumbnailFile.writeAsBytes(
        Uint8List.fromList(<int>[5, 4, 3, 2]),
        flush: true,
      );

      await boundary.handleThumbnailSyncRequest(
        event: ThumbnailSyncRequestEvent(
          requestId: 'thumb-sync-1',
          requesterIp: '192.168.1.40',
          requesterName: 'Remote device',
          items: <ThumbnailSyncItem>[
            ThumbnailSyncItem(
              cacheId: ownerCache.cacheId,
              relativePath: 'owner-thumb-source.png',
              thumbnailId: thumbnailId,
            ),
          ],
          observedAt: DateTime(2026),
        ),
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      );

      expect(lanDiscoveryService.thumbnailPackets, hasLength(1));
      final packet = lanDiscoveryService.thumbnailPackets.single;
      expect(packet.targetIp, '192.168.1.40');
      expect(packet.cacheId, ownerCache.cacheId);
      expect(packet.relativePath, 'owner-thumb-source.png');
      expect(packet.thumbnailId, thumbnailId);
      expect(packet.ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
      expect(packet.bytes, isNotEmpty);
    },
  );
}

Future<void> _seedRemoteCatalog({
  required RemoteShareBrowser browser,
  required String receiverMacAddress,
}) async {
  await browser.startBrowse(
    targets: <DiscoveredDevice>[
      DiscoveredDevice(
        ip: '192.168.1.40',
        macAddress: '11:22:33:44:55:66',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
    ],
    receiverMacAddress: receiverMacAddress,
    requesterName: 'Landa desktop',
    requestId: 'request-1',
    responseWindow: Duration.zero,
    sendShareQuery:
        ({
          required String targetIp,
          required String requestId,
          required String requesterName,
        }) async {},
  );
  await browser.applyRemoteCatalog(
    event: _remoteCatalogEvent(),
    ownerDisplayName: 'Remote device',
    ownerMacAddress: '11-22-33-44-55-66',
  );
}

ShareCatalogEvent _remoteCatalogEvent() {
  return ShareCatalogEvent(
    requestId: 'request-1',
    ownerIp: '192.168.1.40',
    ownerName: 'Remote device',
    ownerMacAddress: '11-22-33-44-55-66',
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
            thumbnailId: 'thumb-1',
          ),
        ],
      ),
    ],
  );
}

class CapturingLanDiscoveryService extends LanDiscoveryService {
  final List<CapturedThumbnailSyncRequest> thumbnailSyncRequests =
      <CapturedThumbnailSyncRequest>[];
  final List<CapturedThumbnailPacket> thumbnailPackets =
      <CapturedThumbnailPacket>[];

  @override
  Future<void> sendThumbnailSyncRequest({
    required String targetIp,
    required String requestId,
    required String requesterName,
    required List<ThumbnailSyncItem> items,
  }) async {
    thumbnailSyncRequests.add(
      CapturedThumbnailSyncRequest(
        targetIp: targetIp,
        requestId: requestId,
        requesterName: requesterName,
        items: List<ThumbnailSyncItem>.from(items),
      ),
    );
  }

  @override
  Future<void> sendThumbnailPacket({
    required String targetIp,
    required String requestId,
    required String ownerMacAddress,
    required String cacheId,
    required String relativePath,
    required String thumbnailId,
    required Uint8List bytes,
  }) async {
    thumbnailPackets.add(
      CapturedThumbnailPacket(
        targetIp: targetIp,
        requestId: requestId,
        ownerMacAddress: ownerMacAddress,
        cacheId: cacheId,
        relativePath: relativePath,
        thumbnailId: thumbnailId,
        bytes: bytes,
      ),
    );
  }
}

class CapturedThumbnailSyncRequest {
  const CapturedThumbnailSyncRequest({
    required this.targetIp,
    required this.requestId,
    required this.requesterName,
    required this.items,
  });

  final String targetIp;
  final String requestId;
  final String requesterName;
  final List<ThumbnailSyncItem> items;
}

class CapturedThumbnailPacket {
  const CapturedThumbnailPacket({
    required this.targetIp,
    required this.requestId,
    required this.ownerMacAddress,
    required this.cacheId,
    required this.relativePath,
    required this.thumbnailId,
    required this.bytes,
  });

  final String targetIp;
  final String requestId;
  final String ownerMacAddress;
  final String cacheId;
  final String relativePath;
  final String thumbnailId;
  final Uint8List bytes;
}

final Uint8List _tinyPngBytes = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

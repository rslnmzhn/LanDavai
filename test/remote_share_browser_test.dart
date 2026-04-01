import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/remote_share_browser.dart';
import 'package:landa/features/discovery/data/lan_packet_codec.dart';
import 'package:landa/features/discovery/data/lan_protocol_events.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late RecordingSharedCacheCatalog sharedCacheCatalog;
  late RemoteShareBrowser browser;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_remote_share_browser_',
    );
    sharedCacheCatalog = RecordingSharedCacheCatalog(
      sharedCacheRecordStore: SharedFolderCacheRepository(
        database: harness.database,
      ),
      sharedCacheIndexStore: SharedCacheIndexStore(database: harness.database),
      receiverCachesByOwnerMac: <String, List<SharedFolderCacheRecord>>{
        '11:22:33:44:55:66': <SharedFolderCacheRecord>[
          SharedFolderCacheRecord(
            cacheId: 'receiver-cache-1',
            role: SharedFolderCacheRole.receiver,
            ownerMacAddress: '11:22:33:44:55:66',
            peerMacAddress: 'aa:bb:cc:dd:ee:ff',
            rootPath: 'remote-cache-1',
            displayName: 'Snapshot',
            indexFilePath: 'receiver-cache-1.json',
            itemCount: 2,
            totalBytes: 1234,
            updatedAtMs: 1000,
          ),
        ],
      },
    );
    browser = RemoteShareBrowser(sharedCacheCatalog: sharedCacheCatalog);
  });

  tearDown(() async {
    browser.dispose();
    sharedCacheCatalog.dispose();
    await harness.dispose();
  });

  test(
    'owns current browse projection and integrates receiver cache snapshots without durable writes',
    () async {
      var shareQueryCalls = 0;
      final startResult = await browser.startBrowse(
        targets: <DiscoveredDevice>[
          DiscoveredDevice(
            ip: '192.168.1.20',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
        ],
        receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
        requesterName: 'Landa desktop',
        requestId: 'request-1',
        responseWindow: Duration.zero,
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) async {
              shareQueryCalls += 1;
              expect(targetIp, '192.168.1.20');
              expect(requestId, 'request-1');
              expect(requesterName, 'Landa desktop');
            },
      );

      expect(startResult.hadTargets, isTrue);
      expect(shareQueryCalls, 1);
      expect(sharedCacheCatalog.listReceiverCachesCalls, 1);

      await browser.applyRemoteCatalog(
        event: ShareCatalogEvent(
          requestId: 'request-1',
          ownerIp: '192.168.1.20',
          ownerName: 'Remote Mac',
          ownerMacAddress: '11-22-33-44-55-66',
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026),
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Remote cache',
              itemCount: 2,
              totalBytes: 1234,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(
                  relativePath: 'videos/demo.mp4',
                  sizeBytes: 1000,
                  thumbnailId: 'thumb-1',
                ),
                SharedCatalogFileItem(
                  relativePath: 'docs/readme.txt',
                  sizeBytes: 234,
                ),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Alias device',
        ownerMacAddress: '11-22-33-44-55-66',
      );

      browser.selectOwner('192.168.1.20');
      final initialProjection = browser.currentBrowseProjection;

      expect(initialProjection.options, hasLength(1));
      expect(initialProjection.owners, hasLength(1));
      expect(initialProjection.selectedOwner?.name, 'Alias device');
      expect(initialProjection.selectedOwner?.cachedShareCount, 1);
      expect(initialProjection.files, hasLength(2));
      expect(initialProjection.files.first.hasReceiverCacheSnapshot, isTrue);
      expect(
        initialProjection.folders.map((folder) => folder.folderPath),
        containsAll(<String>['', 'videos', 'docs']),
      );

      final selectedVideosFolderId = initialProjection.folders
          .firstWhere((folder) => folder.folderPath == 'videos')
          .id;
      browser.setSelectedFolderIds(<String>{selectedVideosFolderId});
      final selectedProjection = browser.currentBrowseProjection;

      expect(selectedProjection.selectedFolderIds, <String>{
        selectedVideosFolderId,
      });
      expect(selectedProjection.selectedCount, 1);
      expect(selectedProjection.folderCoveredFileIds, <String>{
        '192.168.1.20|remote-cache-1|videos/demo.mp4',
      });
      expect(browser.buildSelectedRelativePathsByCache(), <String, Set<String>>{
        'remote-cache-1': <String>{'videos/demo.mp4'},
      });
      expect(
        browser.buildDownloadAllRequestForOwner('192.168.1.20'),
        <String, Set<String>>{'remote-cache-1': <String>{}},
      );
      expect(
        browser.ownerMacForCache(
          ownerIp: '192.168.1.20',
          cacheId: 'remote-cache-1',
        ),
        '11:22:33:44:55:66',
      );
      expect(sharedCacheCatalog.receiverCacheWriteCalls, 0);
    },
  );

  test(
    'ignores stale share catalog packets from an older browse request',
    () async {
      await browser.startBrowse(
        targets: <DiscoveredDevice>[
          DiscoveredDevice(
            ip: '192.168.1.20',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
        ],
        receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
        requesterName: 'Landa desktop',
        requestId: 'request-2',
        responseWindow: Duration.zero,
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) async {},
      );

      await browser.applyRemoteCatalog(
        event: ShareCatalogEvent(
          requestId: 'stale-request',
          ownerIp: '192.168.1.20',
          ownerName: 'Remote Mac',
          ownerMacAddress: '11-22-33-44-55-66',
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026),
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Remote cache',
              itemCount: 1,
              totalBytes: 1,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(relativePath: 'alpha.txt', sizeBytes: 1),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Alias device',
        ownerMacAddress: '11-22-33-44-55-66',
      );

      expect(browser.currentBrowseProjection.options, isEmpty);
    },
  );

  test(
    'records preview-path projection updates through owner-backed batch writes',
    () async {
      await browser.startBrowse(
        targets: <DiscoveredDevice>[
          DiscoveredDevice(
            ip: '192.168.1.20',
            isAppDetected: true,
            lastSeen: DateTime(2026),
          ),
        ],
        receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
        requesterName: 'Landa desktop',
        requestId: 'request-3',
        responseWindow: Duration.zero,
        sendShareQuery:
            ({
              required String targetIp,
              required String requestId,
              required String requesterName,
            }) async {},
      );

      await browser.applyRemoteCatalog(
        event: ShareCatalogEvent(
          requestId: 'request-3',
          ownerIp: '192.168.1.20',
          ownerName: 'Remote Mac',
          ownerMacAddress: '11-22-33-44-55-66',
          removedCacheIds: const <String>[],
          observedAt: DateTime(2026),
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Remote cache',
              itemCount: 1,
              totalBytes: 1000,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(
                  relativePath: 'videos/demo.mp4',
                  sizeBytes: 1000,
                  thumbnailId: 'thumb-1',
                ),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Alias device',
        ownerMacAddress: '11-22-33-44-55-66',
      );

      browser.recordPreviewPaths(const <RemoteBrowsePreviewPathUpdate>[
        RemoteBrowsePreviewPathUpdate(
          ownerIp: '192.168.1.20',
          cacheId: 'remote-cache-1',
          relativePath: 'videos/demo.mp4',
          previewPath: 'C:/tmp/thumb-1.jpg',
        ),
      ]);
      browser.selectOwner('192.168.1.20');

      expect(
        browser.currentBrowseProjection.files.single.previewPath,
        'C:/tmp/thumb-1.jpg',
      );
    },
  );
}

class RecordingSharedCacheCatalog extends SharedCacheCatalog {
  RecordingSharedCacheCatalog({
    required super.sharedCacheRecordStore,
    required super.sharedCacheIndexStore,
    required Map<String, List<SharedFolderCacheRecord>>
    receiverCachesByOwnerMac,
  }) : _receiverCachesByOwnerMac = receiverCachesByOwnerMac;

  final Map<String, List<SharedFolderCacheRecord>> _receiverCachesByOwnerMac;
  int listReceiverCachesCalls = 0;
  int receiverCacheWriteCalls = 0;

  @override
  Future<List<SharedFolderCacheRecord>> listReceiverCaches({
    required String receiverMacAddress,
    String? ownerMacAddress,
  }) async {
    listReceiverCachesCalls += 1;
    if (ownerMacAddress == null) {
      return _receiverCachesByOwnerMac.values
          .expand((records) => records)
          .toList(growable: false);
    }
    final key = ownerMacAddress.toLowerCase().replaceAll('-', ':');
    return List<SharedFolderCacheRecord>.from(
      _receiverCachesByOwnerMac[key] ?? const <SharedFolderCacheRecord>[],
    );
  }

  @override
  Future<SharedFolderCacheRecord> saveReceiverCache({
    required String ownerMacAddress,
    required String receiverMacAddress,
    required String remoteFolderIdentity,
    required String remoteDisplayName,
    required List<SharedFolderIndexEntry> entries,
  }) {
    receiverCacheWriteCalls += 1;
    return super.saveReceiverCache(
      ownerMacAddress: ownerMacAddress,
      receiverMacAddress: receiverMacAddress,
      remoteFolderIdentity: remoteFolderIdentity,
      remoteDisplayName: remoteDisplayName,
      entries: entries,
    );
  }
}

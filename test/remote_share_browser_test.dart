import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

      final projection = browser.currentBrowseProjection;
      expect(projection.options, hasLength(1));
      expect(projection.owners, hasLength(1));
      expect(projection.owners.single.name, 'Alias device');
      expect(projection.owners.single.cachedShareCount, 1);
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
    'aggregated explorer directory keeps stable identity across owners and shares',
    () async {
      await _seedCatalogs(browser);

      final directory = browser.buildExplorerDirectory(
        filterKey: RemoteShareBrowser.allDevicesFilterKey,
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.flat,
      );

      expect(directory.entries.folders, isEmpty);
      expect(directory.entries.files, hasLength(2));
      expect(
        directory.entries.files.map((file) => file.sourceToken).toSet(),
        hasLength(2),
      );
      expect(
        directory.entries.files.map((file) => file.subtitle),
        containsAll(<String>['Device A • Docs • 4 B', 'Device B • Docs • 8 B']),
      );
    },
  );

  test(
    'owner explorer directory resolves opaque tokens back to remote file identity',
    () async {
      await _seedCatalogs(browser);

      final directory = browser.buildExplorerDirectory(
        filterKey: '192.168.1.20',
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      expect(directory.entries.folders, isNotEmpty);

      final docsFolder = directory.entries.folders.firstWhere(
        (folder) => folder.name.startsWith('Docs'),
      );
      final docsDirectory = browser.buildExplorerDirectory(
        filterKey: '192.168.1.20',
        folderPath: docsFolder.folderPath,
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      final file = docsDirectory.entries.files.single;
      final resolved = browser.resolveFileToken(file.sourceToken!);

      expect(resolved, isNotNull);
      expect(resolved!.ownerIp, '192.168.1.20');
      expect(resolved.cacheId, 'remote-cache-1');
      expect(resolved.relativePath, 'report.txt');
      expect(browser.containsFileToken(file.sourceToken!), isTrue);
    },
  );

  test(
    'structured folder tokens resolve to whole-share and nested-folder download targets',
    () async {
      await browser.startBrowse(
        targets: const <DiscoveredDevice>[],
        receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
        requesterName: 'Receiver',
        requestId: 'request-folders',
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
          requestId: 'request-folders',
          ownerIp: '192.168.1.20',
          ownerName: 'Device A',
          ownerMacAddress: '11:22:33:44:55:66',
          observedAt: DateTime(2026),
          removedCacheIds: const <String>[],
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Docs',
              itemCount: 3,
              totalBytes: 12,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(relativePath: 'docs/a.txt', sizeBytes: 2),
                SharedCatalogFileItem(
                  relativePath: 'docs/sub/b.txt',
                  sizeBytes: 3,
                ),
                SharedCatalogFileItem(relativePath: 'other.txt', sizeBytes: 7),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Device A',
        ownerMacAddress: '11:22:33:44:55:66',
      );

      final root = browser.buildExplorerDirectory(
        filterKey: '192.168.1.20',
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      final shareFolder = root.entries.folders.firstWhere(
        (folder) => folder.name.startsWith('Docs'),
      );
      final wholeShareTarget = browser.resolveDownloadToken(
        shareFolder.sourceToken!,
      );

      expect(wholeShareTarget, isNotNull);
      expect(
        wholeShareTarget!.selectedRelativePathsByCache,
        <String, Set<String>>{'remote-cache-1': <String>{}},
      );

      final shareDirectory = browser.buildExplorerDirectory(
        filterKey: '192.168.1.20',
        folderPath: shareFolder.folderPath,
        viewMode: RemoteBrowseExplorerViewMode.structured,
      );
      final nestedFolder = shareDirectory.entries.folders.firstWhere(
        (folder) => folder.name == 'docs',
      );
      final nestedTarget = browser.resolveDownloadToken(
        nestedFolder.sourceToken!,
      );

      expect(nestedTarget, isNotNull);
      expect(nestedTarget!.selectedRelativePathsByCache, <String, Set<String>>{
        'remote-cache-1': <String>{'docs/a.txt', 'docs/sub/b.txt'},
      });
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

      final token = browser.currentFileTokens().single;
      final resolved = browser.resolveFileToken(token);
      expect(resolved?.previewPath, 'C:/tmp/thumb-1.jpg');
    },
  );

  test('structured aggregated mode keeps honest nested paths', () async {
    await _seedCatalogs(browser);

    final root = browser.buildExplorerDirectory(
      filterKey: RemoteShareBrowser.allDevicesFilterKey,
      folderPath: '',
      viewMode: RemoteBrowseExplorerViewMode.structured,
    );

    expect(
      root.entries.folders.map((folder) => folder.name),
      contains('Device A (192.168.1.20)'),
    );

    final deviceDirectory = browser.buildExplorerDirectory(
      filterKey: RemoteShareBrowser.allDevicesFilterKey,
      folderPath: 'Device A (192.168.1.20)',
      viewMode: RemoteBrowseExplorerViewMode.structured,
    );
    expect(
      deviceDirectory.entries.folders.map((folder) => folder.name).first,
      startsWith('Docs'),
    );
  });

  test(
    'flat mode orders media before documents and documents before other files',
    () async {
      await browser.startBrowse(
        targets: const <DiscoveredDevice>[],
        receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
        requesterName: 'Receiver',
        requestId: 'request-media',
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
          requestId: 'request-media',
          ownerIp: '192.168.1.20',
          ownerName: 'Device A',
          ownerMacAddress: '11:22:33:44:55:66',
          observedAt: DateTime(2026),
          removedCacheIds: const <String>[],
          entries: <SharedCatalogEntryItem>[
            SharedCatalogEntryItem(
              cacheId: 'remote-cache-1',
              displayName: 'Mixed',
              itemCount: 3,
              totalBytes: 12,
              files: <SharedCatalogFileItem>[
                SharedCatalogFileItem(relativePath: 'readme.pdf', sizeBytes: 2),
                SharedCatalogFileItem(relativePath: 'song.mp3', sizeBytes: 3),
                SharedCatalogFileItem(
                  relativePath: 'archive.zip',
                  sizeBytes: 7,
                ),
              ],
            ),
          ],
        ),
        ownerDisplayName: 'Device A',
        ownerMacAddress: '11:22:33:44:55:66',
      );

      final directory = browser.buildExplorerDirectory(
        filterKey: RemoteShareBrowser.allDevicesFilterKey,
        folderPath: '',
        viewMode: RemoteBrowseExplorerViewMode.flat,
      );

      expect(
        directory.entries.files
            .map((file) => p.basename(file.virtualPath))
            .toList(),
        <String>['song.mp3', 'readme.pdf', 'archive.zip'],
      );
    },
  );

  test('flat mode category filtering keeps only selected categories', () async {
    await browser.startBrowse(
      targets: const <DiscoveredDevice>[],
      receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
      requesterName: 'Receiver',
      requestId: 'request-filter',
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
        requestId: 'request-filter',
        ownerIp: '192.168.1.20',
        ownerName: 'Device A',
        ownerMacAddress: '11:22:33:44:55:66',
        observedAt: DateTime(2026),
        removedCacheIds: const <String>[],
        entries: <SharedCatalogEntryItem>[
          SharedCatalogEntryItem(
            cacheId: 'remote-cache-1',
            displayName: 'Mixed',
            itemCount: 3,
            totalBytes: 12,
            files: <SharedCatalogFileItem>[
              SharedCatalogFileItem(relativePath: 'photo.jpg', sizeBytes: 2),
              SharedCatalogFileItem(relativePath: 'readme.pdf', sizeBytes: 3),
              SharedCatalogFileItem(relativePath: 'script.dart', sizeBytes: 7),
            ],
          ),
        ],
      ),
      ownerDisplayName: 'Device A',
      ownerMacAddress: '11:22:33:44:55:66',
    );

    final directory = browser.buildExplorerDirectory(
      filterKey: RemoteShareBrowser.allDevicesFilterKey,
      folderPath: '',
      viewMode: RemoteBrowseExplorerViewMode.flat,
      showAllFlatCategories: false,
      visibleFlatCategories: const <RemoteBrowseFlatFileCategory>{
        RemoteBrowseFlatFileCategory.documents,
      },
    );

    expect(
      directory.entries.files
          .map((file) => p.basename(file.virtualPath))
          .toList(),
      <String>['readme.pdf'],
    );
  });
}

Future<void> _seedCatalogs(RemoteShareBrowser browser) async {
  await browser.startBrowse(
    targets: <DiscoveredDevice>[
      DiscoveredDevice(
        ip: '192.168.1.20',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
      DiscoveredDevice(
        ip: '192.168.1.30',
        isAppDetected: true,
        lastSeen: DateTime(2026),
      ),
    ],
    receiverMacAddress: 'AA-BB-CC-DD-EE-FF',
    requesterName: 'Receiver',
    requestId: 'seed-request',
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
      requestId: 'seed-request',
      ownerIp: '192.168.1.20',
      ownerName: 'Device A',
      ownerMacAddress: '11:22:33:44:55:66',
      observedAt: DateTime(2026),
      removedCacheIds: const <String>[],
      entries: <SharedCatalogEntryItem>[
        SharedCatalogEntryItem(
          cacheId: 'remote-cache-1',
          displayName: 'Docs',
          itemCount: 1,
          totalBytes: 4,
          files: <SharedCatalogFileItem>[
            SharedCatalogFileItem(relativePath: 'report.txt', sizeBytes: 4),
          ],
        ),
      ],
    ),
    ownerDisplayName: 'Device A',
    ownerMacAddress: '11:22:33:44:55:66',
  );
  await browser.applyRemoteCatalog(
    event: ShareCatalogEvent(
      requestId: 'seed-request',
      ownerIp: '192.168.1.30',
      ownerName: 'Device B',
      ownerMacAddress: '22:33:44:55:66:77',
      observedAt: DateTime(2026),
      removedCacheIds: const <String>[],
      entries: <SharedCatalogEntryItem>[
        SharedCatalogEntryItem(
          cacheId: 'remote-cache-2',
          displayName: 'Docs',
          itemCount: 1,
          totalBytes: 8,
          files: <SharedCatalogFileItem>[
            SharedCatalogFileItem(relativePath: 'report.txt', sizeBytes: 8),
          ],
        ),
      ],
    ),
    ownerDisplayName: 'Device B',
    ownerMacAddress: '22:33:44:55:66:77',
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

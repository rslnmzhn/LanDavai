import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/shared_cache_catalog_bridge.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late SharedFolderCacheRepository repository;
  late SharedCacheIndexStore indexStore;
  late SharedCacheCatalog catalog;
  late Directory fixtureDirectory;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_shared_cache_catalog_bridge_',
    );
    repository = SharedFolderCacheRepository(database: harness.database);
    indexStore = SharedCacheIndexStore(database: harness.database);
    catalog = SharedCacheCatalog(
      sharedFolderCacheRepository: repository,
      sharedCacheIndexStore: indexStore,
    );
    fixtureDirectory = Directory(
      p.join(harness.rootDirectory.path, 'shared_bridge_fixture'),
    );
    await fixtureDirectory.create(recursive: true);
  });

  tearDown(() async {
    catalog.dispose();
    await harness.dispose();
  });

  test(
    'bridge serves canonical shared-cache reads from catalog metadata and index store truth',
    () async {
      final rootDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
      final nestedDirectory = Directory(p.join(rootDirectory.path, 'nested'));
      await nestedDirectory.create(recursive: true);
      final notesFile = File(p.join(rootDirectory.path, 'notes.txt'));
      final videoFile = File(p.join(rootDirectory.path, 'clip.mp4'));
      final nestedFile = File(p.join(nestedDirectory.path, 'guide.txt'));
      await notesFile.writeAsString('notes', flush: true);
      await videoFile.writeAsString('video', flush: true);
      await nestedFile.writeAsString('guide', flush: true);

      await catalog.upsertOwnerFolderCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        folderPath: rootDirectory.path,
        displayName: 'Shared Docs',
      );

      final bridge = SharedCacheCatalogBridge(
        sharedCacheCatalog: catalog,
        sharedCacheIndexStore: indexStore,
        ownerMacAddressProvider: () => 'aa:bb:cc:dd:ee:ff',
      );

      final summary = await bridge.summarizeOwnerSharedContent();
      final nestedSummary = await bridge.summarizeOwnerSharedContent(
        virtualFolderPath: 'Shared Docs/nested',
      );
      final rootListing = await bridge.listShareableLocalDirectory(
        virtualFolderPath: '',
      );
      final docsListing = await bridge.listShareableLocalDirectory(
        virtualFolderPath: 'Shared Docs',
      );
      final videos = await bridge.listShareableVideoFiles();

      expect(summary.totalCaches, 1);
      expect(summary.folderCaches, 1);
      expect(summary.selectionCaches, 0);
      expect(summary.totalFiles, 3);
      expect(nestedSummary.totalCaches, 1);
      expect(nestedSummary.totalFiles, 1);
      expect(rootListing.folders, hasLength(1));
      expect(rootListing.folders.single.virtualPath, 'Shared Docs');
      expect(docsListing.folders.map((folder) => folder.virtualPath), <String>[
        'Shared Docs/nested',
      ]);
      expect(docsListing.files.map((file) => file.relativePath), <String>[
        'clip.mp4',
        'notes.txt',
      ]);
      expect(videos, hasLength(1));
      expect(videos.single.relativePath, 'clip.mp4');
      expect(videos.single.cacheDisplayName, 'Shared Docs');
    },
  );

  test(
    'bridge refreshes metadata through SharedCacheCatalog and index through SharedCacheIndexStore',
    () async {
      final indexedFile = File(p.join(fixtureDirectory.path, 'alpha.mp4'));
      await indexedFile.writeAsString('alpha', flush: true);

      final recordingIndexStore = RecordingSharedCacheIndexStore(
        database: harness.database,
        entriesByCacheId: <String, List<SharedFolderIndexEntry>>{
          'cache-1': <SharedFolderIndexEntry>[
            SharedFolderIndexEntry(
              relativePath: 'alpha.mp4',
              sizeBytes: 5,
              modifiedAtMs: 1000,
              absolutePath: indexedFile.path,
            ),
          ],
        },
      );
      final recordingCatalog = RecordingSharedCacheCatalog(
        sharedFolderCacheRepository: repository,
        sharedCacheIndexStore: recordingIndexStore,
        ownerCaches: <SharedFolderCacheRecord>[
          SharedFolderCacheRecord(
            cacheId: 'cache-1',
            role: SharedFolderCacheRole.owner,
            ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
            peerMacAddress: null,
            rootPath: 'selection://cache-1',
            displayName: 'Selected files',
            indexFilePath: indexedFile.path,
            itemCount: 1,
            totalBytes: 5,
            updatedAtMs: 1000,
          ),
        ],
      );
      final bridge = SharedCacheCatalogBridge(
        sharedCacheCatalog: recordingCatalog,
        sharedCacheIndexStore: recordingIndexStore,
        ownerMacAddressProvider: () => 'aa:bb:cc:dd:ee:ff',
      );

      final videos = await bridge.listShareableVideoFiles();

      expect(recordingCatalog.loadOwnerCachesCalls, 1);
      expect(recordingIndexStore.readCacheIds, <String>['cache-1']);
      expect(videos, hasLength(1));
      expect(videos.single.cacheId, 'cache-1');
    },
  );
}

class RecordingSharedCacheCatalog extends SharedCacheCatalog {
  RecordingSharedCacheCatalog({
    required super.sharedFolderCacheRepository,
    required super.sharedCacheIndexStore,
    required List<SharedFolderCacheRecord> ownerCaches,
  }) : _ownerCachesSnapshot = List<SharedFolderCacheRecord>.from(ownerCaches);

  int loadOwnerCachesCalls = 0;
  final List<SharedFolderCacheRecord> _ownerCachesSnapshot;

  @override
  List<SharedFolderCacheRecord> get ownerCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerCachesSnapshot);

  @override
  Future<OwnerCacheCatalogLoadResult> loadOwnerCaches({
    required String ownerMacAddress,
    bool rebindOwnerCachesToMac = false,
  }) async {
    loadOwnerCachesCalls += 1;
    return OwnerCacheCatalogLoadResult(
      ownerCaches: ownerCaches,
      reboundCount: 0,
    );
  }
}

class RecordingSharedCacheIndexStore extends SharedCacheIndexStore {
  RecordingSharedCacheIndexStore({
    required super.database,
    required Map<String, List<SharedFolderIndexEntry>> entriesByCacheId,
  }) : _entriesByCacheId = entriesByCacheId;

  final Map<String, List<SharedFolderIndexEntry>> _entriesByCacheId;
  final List<String> readCacheIds = <String>[];

  @override
  Future<List<SharedFolderIndexEntry>> readIndexEntries(
    SharedFolderCacheRecord record,
  ) async {
    readCacheIds.add(record.cacheId);
    return List<SharedFolderIndexEntry>.from(
      _entriesByCacheId[record.cacheId] ?? const <SharedFolderIndexEntry>[],
    );
  }
}

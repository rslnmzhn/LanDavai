import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/features/discovery/application/shared_cache_maintenance_boundary.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/application/shared_cache_owner_contracts.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  group('SharedCacheMaintenanceBoundary', () {
    late TestAppDatabaseHarness harness;
    late SharedFolderCacheRepository repository;
    late SharedCacheIndexStore indexStore;
    late SharedCacheCatalog catalog;
    late Directory fixtureDirectory;

    setUp(() async {
      harness = await TestAppDatabaseHarness.create(
        prefix: 'landa_shared_cache_maintenance_boundary_',
      );
      repository = SharedFolderCacheRepository(database: harness.database);
      indexStore = SharedCacheIndexStore(database: harness.database);
      catalog = SharedCacheCatalog(
        sharedFolderCacheRepository: repository,
        sharedCacheIndexStore: indexStore,
      );
      fixtureDirectory = Directory(
        p.join(harness.rootDirectory.path, 'shared_cache_maintenance_fixture'),
      );
      await fixtureDirectory.create(recursive: true);
    });

    tearDown(() async {
      catalog.dispose();
      await harness.dispose();
    });

    test(
      'summarizeOwnerSharedContent reads scoped totals from SharedCacheCatalog and SharedCacheIndexStore',
      () async {
        final rootDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
        final nestedDirectory = Directory(p.join(rootDirectory.path, 'nested'));
        await nestedDirectory.create(recursive: true);
        final notesFile = File(p.join(rootDirectory.path, 'notes.txt'));
        final nestedFile = File(p.join(nestedDirectory.path, 'guide.txt'));
        await notesFile.writeAsString('notes', flush: true);
        await nestedFile.writeAsString('guide', flush: true);

        await catalog.upsertOwnerFolderCache(
          ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
          folderPath: rootDirectory.path,
          displayName: 'Shared Docs',
        );

        final boundary = SharedCacheMaintenanceBoundary(
          sharedCacheCatalog: catalog,
          sharedCacheIndexStore: indexStore,
          appNotificationService: AppNotificationService.instance,
          ownerMacAddressProvider: () => 'aa:bb:cc:dd:ee:ff',
        );

        final summary = await boundary.summarizeOwnerSharedContent();
        final nestedSummary = await boundary.summarizeOwnerSharedContent(
          virtualFolderPath: 'Shared Docs/nested',
        );

        expect(summary.totalCaches, 1);
        expect(summary.folderCaches, 1);
        expect(summary.selectionCaches, 0);
        expect(summary.totalFiles, 2);
        expect(nestedSummary.totalCaches, 1);
        expect(nestedSummary.totalFiles, 1);
      },
    );

    test(
      'removeCacheById resolves owner cache lookup and deletion through SharedCacheCatalog',
      () async {
        final recordingCatalog = RecordingSharedCacheCatalog(
          sharedFolderCacheRepository: repository,
          sharedCacheIndexStore: indexStore,
          ownerCaches: <SharedFolderCacheRecord>[
            _ownerCacheRecord(cacheId: 'cache-1', displayName: 'Shared docs'),
          ],
        );
        final boundary = SharedCacheMaintenanceBoundary(
          sharedCacheCatalog: recordingCatalog,
          sharedCacheIndexStore: indexStore,
          appNotificationService: AppNotificationService.instance,
          ownerMacAddressProvider: () => '02:00:00:00:00:01',
        );

        final removed = await boundary.removeCacheById('cache-1');
        final missing = await boundary.removeCacheById('missing-cache');

        expect(removed, isTrue);
        expect(missing, isFalse);
        expect(recordingCatalog.loadOwnerCachesCalls, 3);
        expect(recordingCatalog.lastOwnerMacAddress, '02:00:00:00:00:01');
        expect(recordingCatalog.deletedCacheIds, <String>['cache-1']);
      },
    );

    test(
      'recacheOwner routes maintenance progress and cache refresh through SharedCacheCatalog',
      () async {
        final recordingCatalog = RecordingSharedCacheCatalog(
          sharedFolderCacheRepository: repository,
          sharedCacheIndexStore: indexStore,
          ownerCaches: <SharedFolderCacheRecord>[
            _ownerCacheRecord(
              cacheId: 'cache-1',
              displayName: 'Selected files',
            ),
          ],
        );
        final boundary = SharedCacheMaintenanceBoundary(
          sharedCacheCatalog: recordingCatalog,
          sharedCacheIndexStore: indexStore,
          appNotificationService: AppNotificationService.instance,
          ownerMacAddressProvider: () => '02:00:00:00:00:01',
        );
        final progressSnapshots = <double?>[];
        boundary.addListener(() {
          progressSnapshots.add(boundary.recacheProgressValue);
        });

        final report = await boundary.recacheOwner();

        expect(report, isNotNull);
        expect(report!.updatedCaches, 1);
        expect(report.failedCaches, 0);
        expect(report.before.totalFiles, 2);
        expect(report.after.totalFiles, 3);
        expect(recordingCatalog.refreshOwnerSelectionCalls, 1);
        expect(boundary.isRecacheInProgress, isFalse);
        expect(progressSnapshots.whereType<double>(), isNotEmpty);
      },
    );
  });
}

class RecordingSharedCacheCatalog extends SharedCacheCatalog {
  RecordingSharedCacheCatalog({
    required super.sharedFolderCacheRepository,
    required super.sharedCacheIndexStore,
    required List<SharedFolderCacheRecord> ownerCaches,
  }) : _ownerCachesSnapshot = List<SharedFolderCacheRecord>.from(ownerCaches);

  int loadOwnerCachesCalls = 0;
  String? lastOwnerMacAddress;
  final List<String> deletedCacheIds = <String>[];
  int refreshOwnerSelectionCalls = 0;
  List<SharedFolderCacheRecord> _ownerCachesSnapshot;

  @override
  List<SharedFolderCacheRecord> get ownerCaches =>
      List<SharedFolderCacheRecord>.unmodifiable(_ownerCachesSnapshot);

  @override
  Future<OwnerCacheCatalogLoadResult> loadOwnerCaches({
    required String ownerMacAddress,
    bool rebindOwnerCachesToMac = false,
  }) async {
    loadOwnerCachesCalls += 1;
    lastOwnerMacAddress = ownerMacAddress;
    return OwnerCacheCatalogLoadResult(
      ownerCaches: ownerCaches,
      reboundCount: rebindOwnerCachesToMac ? 1 : 0,
    );
  }

  @override
  Future<void> deleteCache(String cacheId) async {
    deletedCacheIds.add(cacheId);
    _ownerCachesSnapshot = _ownerCachesSnapshot
        .where((cache) => cache.cacheId != cacheId)
        .toList(growable: false);
  }

  @override
  Future<SharedFolderCacheRecord> refreshOwnerSelectionCacheEntries(
    SharedFolderCacheRecord cache, {
    OwnerCacheProgressCallback? onProgress,
  }) async {
    refreshOwnerSelectionCalls += 1;
    onProgress?.call(
      processedFiles: 2,
      totalFiles: 3,
      relativePath: 'alpha.mp4',
      stage: OwnerCacheProgressStage.indexing,
    );
    final updated = SharedFolderCacheRecord(
      cacheId: cache.cacheId,
      role: cache.role,
      ownerMacAddress: cache.ownerMacAddress,
      peerMacAddress: cache.peerMacAddress,
      rootPath: cache.rootPath,
      displayName: cache.displayName,
      indexFilePath: cache.indexFilePath,
      itemCount: 3,
      totalBytes: cache.totalBytes + 100,
      updatedAtMs: cache.updatedAtMs + 1,
    );
    _ownerCachesSnapshot = <SharedFolderCacheRecord>[updated];
    return updated;
  }
}

SharedFolderCacheRecord _ownerCacheRecord({
  required String cacheId,
  required String displayName,
}) {
  return SharedFolderCacheRecord(
    cacheId: cacheId,
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: '02:00:00:00:00:01',
    peerMacAddress: null,
    rootPath: 'selection://$cacheId',
    displayName: displayName,
    indexFilePath: 'C:/tmp/$cacheId.landa-cache.json',
    itemCount: 2,
    totalBytes: 123,
    updatedAtMs: 1000,
  );
}

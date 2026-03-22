import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_catalog_');
    repository = SharedFolderCacheRepository(database: harness.database);
    indexStore = SharedCacheIndexStore(database: harness.database);
    catalog = SharedCacheCatalog(
      sharedFolderCacheRepository: repository,
      sharedCacheIndexStore: indexStore,
    );
    fixtureDirectory = Directory(
      p.join(harness.rootDirectory.path, 'selection_fixture'),
    );
    await fixtureDirectory.create(recursive: true);
  });

  tearDown(() async {
    catalog.dispose();
    await harness.dispose();
  });

  test(
    'owner metadata writes and owner metadata reads route through SharedCacheCatalog',
    () async {
      final fileA = File(p.join(fixtureDirectory.path, 'alpha.txt'));
      final fileB = File(p.join(fixtureDirectory.path, 'beta.txt'));
      await fileA.writeAsString('alpha', flush: true);
      await fileB.writeAsString('beta', flush: true);

      final record = await catalog.buildOwnerSelectionCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        filePaths: <String>[fileB.path, fileA.path],
        displayName: 'Selected files',
      );
      final loaded = await catalog.loadOwnerCaches(
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      );
      final persisted = await repository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      );

      expect(catalog.ownerCaches, hasLength(1));
      expect(catalog.ownerCaches.single.cacheId, record.cacheId);
      expect(loaded.reboundCount, 0);
      expect(loaded.ownerCaches, hasLength(1));
      expect(loaded.ownerCaches.single.cacheId, record.cacheId);
      expect(persisted, hasLength(1));
      expect(persisted.single.cacheId, record.cacheId);
      expect(persisted.single.itemCount, 2);
    },
  );

  test(
    'receiver metadata writes stay deterministic and do not overwrite owner snapshot truth',
    () async {
      final ownerFile = File(p.join(fixtureDirectory.path, 'owner.txt'));
      await ownerFile.writeAsString('owner', flush: true);
      final ownerRecord = await catalog.buildOwnerSelectionCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        filePaths: <String>[ownerFile.path],
        displayName: 'Owner files',
      );

      final entries = <SharedFolderIndexEntry>[
        SharedFolderIndexEntry(
          relativePath: 'docs/readme.txt',
          sizeBytes: 10,
          modifiedAtMs: 1000,
        ),
      ];
      final first = await catalog.saveReceiverCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        receiverMacAddress: '11-22-33-44-55-66',
        remoteFolderIdentity: 'remote://shared/docs',
        remoteDisplayName: 'Shared Docs',
        entries: entries,
      );
      final second = await catalog.saveReceiverCache(
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        receiverMacAddress: '11:22:33:44:55:66',
        remoteFolderIdentity: 'remote://shared/docs',
        remoteDisplayName: 'Shared Docs',
        entries: entries,
      );
      final receiverRows = await repository.listCaches(
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: '11:22:33:44:55:66',
      );

      expect(first.cacheId, second.cacheId);
      expect(receiverRows, hasLength(1));
      expect(receiverRows.single.cacheId, first.cacheId);
      expect(catalog.ownerCaches, hasLength(1));
      expect(catalog.ownerCaches.single.cacheId, ownerRecord.cacheId);
    },
  );

  test(
    'loadOwnerCaches can rebind owner metadata without changing cache identity',
    () async {
      final file = File(p.join(fixtureDirectory.path, 'gamma.txt'));
      await file.writeAsString('gamma', flush: true);
      final record = await catalog.buildOwnerSelectionCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        filePaths: <String>[file.path],
        displayName: 'Gamma',
      );

      final loaded = await catalog.loadOwnerCaches(
        ownerMacAddress: 'FF-EE-DD-CC-BB-AA',
        rebindOwnerCachesToMac: true,
      );

      expect(loaded.reboundCount, 1);
      expect(loaded.ownerCaches, hasLength(1));
      expect(loaded.ownerCaches.single.cacheId, record.cacheId);
      expect(loaded.ownerCaches.single.ownerMacAddress, 'ff:ee:dd:cc:bb:aa');
      expect(catalog.ownerCaches.single.ownerMacAddress, 'ff:ee:dd:cc:bb:aa');
    },
  );
}

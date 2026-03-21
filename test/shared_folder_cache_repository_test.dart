import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late SharedFolderCacheRepository repository;
  late Directory fixtureDirectory;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_cache_');
    repository = SharedFolderCacheRepository(database: harness.database);
    fixtureDirectory = Directory(
      p.join(harness.rootDirectory.path, 'selection_fixture'),
    );
    await fixtureDirectory.create(recursive: true);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'buildOwnerSelectionCache preserves owner metadata and compact json entry semantics',
    () async {
      final fileA = File(p.join(fixtureDirectory.path, 'alpha.txt'));
      final fileB = File(p.join(fixtureDirectory.path, 'beta.txt'));
      await fileA.writeAsString('alpha', flush: true);
      await fileB.writeAsString('beta', flush: true);

      final record = await repository.buildOwnerSelectionCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        filePaths: <String>[fileB.path, fileA.path],
        displayName: 'Selected files',
      );

      final entries = await repository.readIndexEntries(record.cacheId);
      final indexPayload =
          jsonDecode(await File(record.indexFilePath).readAsString())
              as Map<String, dynamic>;

      expect(record.role, SharedFolderCacheRole.owner);
      expect(record.ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
      expect(record.peerMacAddress, isNull);
      expect(record.rootPath, startsWith('selection://'));
      expect(record.displayName, 'Selected files');
      expect(record.indexFilePath, endsWith('.landa-cache.json'));
      expect(entries, hasLength(2));
      expect(
        entries.map((entry) => p.basename(entry.absolutePath!)).toSet(),
        <String>{'alpha.txt', 'beta.txt'},
      );
      expect(indexPayload['schemaVersion'], 1);
      expect(indexPayload['role'], 'owner');
      expect(
        indexPayload['entries'],
        everyElement(
          allOf(
            containsPair('p', isA<String>()),
            containsPair('s', isA<int>()),
            containsPair('m', isA<int>()),
          ),
        ),
      );
    },
  );

  test(
    'saveReceiverCache keeps deterministic cache identity and current file naming semantics',
    () async {
      final entries = <SharedFolderIndexEntry>[
        SharedFolderIndexEntry(
          relativePath: 'docs/readme.txt',
          sizeBytes: 10,
          modifiedAtMs: 1000,
        ),
        SharedFolderIndexEntry(
          relativePath: 'docs/manual.pdf',
          sizeBytes: 20,
          modifiedAtMs: 2000,
        ),
      ];

      final first = await repository.saveReceiverCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        receiverMacAddress: '11-22-33-44-55-66',
        remoteFolderIdentity: 'remote://shared/docs',
        remoteDisplayName: 'Shared Docs',
        entries: entries,
      );
      final second = await repository.saveReceiverCache(
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        receiverMacAddress: '11:22:33:44:55:66',
        remoteFolderIdentity: 'remote://shared/docs',
        remoteDisplayName: 'Shared Docs',
        entries: entries,
      );

      final listed = await repository.listCaches(
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: '11:22:33:44:55:66',
      );
      final restoredEntries = await repository.readIndexEntries(first.cacheId);

      expect(second.cacheId, first.cacheId);
      expect(listed, hasLength(1));
      expect(listed.single.itemCount, 2);
      expect(listed.single.totalBytes, 30);
      expect(listed.single.indexFilePath, contains('receiver_shared_docs_'));
      expect(
        listed.single.indexFilePath,
        endsWith('${first.cacheId}.landa-cache.json'),
      );
      expect(restoredEntries.map((entry) => entry.relativePath), <String>[
        'docs/readme.txt',
        'docs/manual.pdf',
      ]);
    },
  );

  test(
    'rebindOwnerCachesToMac updates existing owner cache rows without changing cache identity',
    () async {
      final file = File(p.join(fixtureDirectory.path, 'gamma.txt'));
      await file.writeAsString('gamma', flush: true);

      final record = await repository.buildOwnerSelectionCache(
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        filePaths: <String>[file.path],
        displayName: 'Gamma',
      );

      final updatedCount = await repository.rebindOwnerCachesToMac(
        ownerMacAddress: 'FF-EE-DD-CC-BB-AA',
      );
      final rebound = await repository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'ff:ee:dd:cc:bb:aa',
      );

      expect(updatedCount, 1);
      expect(rebound, hasLength(1));
      expect(rebound.single.cacheId, record.cacheId);
      expect(rebound.single.ownerMacAddress, 'ff:ee:dd:cc:bb:aa');
    },
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late SharedCacheIndexStore indexStore;
  late Directory fixtureDirectory;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_index_store_');
    indexStore = SharedCacheIndexStore(database: harness.database);
    fixtureDirectory = Directory(
      p.join(harness.rootDirectory.path, 'index_fixture'),
    );
    await fixtureDirectory.create(recursive: true);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'materializeOwnerFolderIndex and readIndexEntries preserve compact json semantics',
    () async {
      final docsDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
      await docsDirectory.create(recursive: true);
      final fileA = File(p.join(docsDirectory.path, 'alpha.txt'));
      final fileB = File(p.join(docsDirectory.path, 'beta.txt'));
      await fileA.writeAsString('alpha', flush: true);
      await fileB.writeAsString('beta', flush: true);

      const cacheId = 'owner-cache-1';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Shared Docs',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: fixtureDirectory.path,
        displayName: 'Shared Docs',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 1234,
      );

      final result = await indexStore.materializeOwnerFolderIndex(
        record: record,
        folderPath: fixtureDirectory.path,
      );
      final entries = await indexStore.readIndexEntries(record);
      final payload =
          jsonDecode(await File(indexPath).readAsString())
              as Map<String, dynamic>;

      expect(result.itemCount, 2);
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.relativePath), <String>[
        'docs/alpha.txt',
        'docs/beta.txt',
      ]);
      expect(payload['schemaVersion'], SharedCacheIndexStore.schemaVersion);
      expect(payload['cacheId'], cacheId);
      expect(payload['role'], 'owner');
      expect(payload['displayName'], 'Shared Docs');
      expect(
        payload['entries'],
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
    'refreshOwnerSelectionIndex prunes unavailable files without changing selection index semantics',
    () async {
      final fileA = File(p.join(fixtureDirectory.path, 'alpha.txt'));
      final fileB = File(p.join(fixtureDirectory.path, 'beta.txt'));
      await fileA.writeAsString('alpha', flush: true);
      await fileB.writeAsString('beta', flush: true);

      const cacheId = 'selection-cache-1';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Selected files',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: 'selection://$cacheId',
        displayName: 'Selected files',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 4321,
      );

      await indexStore.materializeOwnerSelectionIndex(
        record: record,
        filePaths: <String>[fileA.path, fileB.path],
      );
      await fileB.delete();

      final refreshed = await indexStore.refreshOwnerSelectionIndex(record);
      final entries = await indexStore.readIndexEntries(record);
      final payload =
          jsonDecode(await File(indexPath).readAsString())
              as Map<String, dynamic>;

      expect(refreshed.itemCount, 1);
      expect(entries, hasLength(1));
      expect(entries.single.relativePath, 'alpha.txt');
      expect(entries.single.absolutePath, fileA.path);
      expect(payload['schemaVersion'], SharedCacheIndexStore.schemaVersion);
      expect(payload['cacheId'], cacheId);
      expect(payload['rootPath'], 'selection://$cacheId');
      expect((payload['entries'] as List<dynamic>), hasLength(1));
    },
  );

  test(
    'persistCachedManifestEntries stores optional sha256 without changing compact entry identity',
    () async {
      final file = File(p.join(fixtureDirectory.path, 'alpha.txt'));
      await file.writeAsString('alpha', flush: true);

      const cacheId = 'owner-cache-hash';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Shared Docs',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: fixtureDirectory.path,
        displayName: 'Shared Docs',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 1234,
      );

      await indexStore.materializeOwnerFolderIndex(
        record: record,
        folderPath: fixtureDirectory.path,
      );
      await indexStore.persistCachedManifestEntries(
        record: record,
        entries: <SharedFolderIndexEntry>[
          SharedFolderIndexEntry(
            relativePath: 'alpha.txt',
            sizeBytes: file.lengthSync(),
            modifiedAtMs: file.statSync().modified.millisecondsSinceEpoch,
            sha256: 'cached-hash',
          ),
        ],
      );

      final entries = await indexStore.readIndexEntries(record);
      final payload =
          jsonDecode(await File(indexPath).readAsString())
              as Map<String, dynamic>;

      expect(entries.single.sha256, 'cached-hash');
      expect(
        payload['entries'],
        contains(
          allOf(
            containsPair('p', 'alpha.txt'),
            containsPair('h', 'cached-hash'),
          ),
        ),
      );
    },
  );

  test(
    'tree fingerprints stay stable for unchanged indexed state and differ for root vs nested folder views',
    () async {
      final docsDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
      await docsDirectory.create(recursive: true);
      final nestedDirectory = Directory(p.join(docsDirectory.path, 'nested'));
      await nestedDirectory.create(recursive: true);
      await File(
        p.join(docsDirectory.path, 'alpha.txt'),
      ).writeAsString('alpha', flush: true);
      await File(
        p.join(nestedDirectory.path, 'beta.txt'),
      ).writeAsString('beta', flush: true);

      const cacheId = 'owner-cache-fingerprint';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Shared Docs',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: fixtureDirectory.path,
        displayName: 'Shared Docs',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 1234,
      );

      await indexStore.materializeOwnerFolderIndex(
        record: record,
        folderPath: fixtureDirectory.path,
      );

      final rootFingerprintA = await indexStore.readTreeFingerprint(record);
      final rootFingerprintB = await indexStore.readTreeFingerprint(record);
      final nestedFingerprint = await indexStore.readTreeFingerprint(
        record,
        relativeFolderPath: 'docs/nested',
      );

      expect(rootFingerprintA.fingerprint, rootFingerprintB.fingerprint);
      expect(rootFingerprintA.itemCount, 2);
      expect(nestedFingerprint.itemCount, 1);
      expect(
        rootFingerprintA.fingerprint,
        isNot(nestedFingerprint.fingerprint),
      );
    },
  );

  test(
    'tree fingerprints and scoped selections invalidate when indexed folder content changes',
    () async {
      final docsDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
      await docsDirectory.create(recursive: true);
      final alphaFile = File(p.join(docsDirectory.path, 'alpha.txt'));
      await alphaFile.writeAsString('alpha', flush: true);

      const cacheId = 'owner-cache-fingerprint-refresh';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Shared Docs',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: fixtureDirectory.path,
        displayName: 'Shared Docs',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 1234,
      );

      await indexStore.materializeOwnerFolderIndex(
        record: record,
        folderPath: fixtureDirectory.path,
      );
      final beforeFingerprint = await indexStore.readTreeFingerprint(
        record,
        relativeFolderPath: 'docs',
      );
      final beforeSelection = await indexStore.readScopedSelection(
        record,
        folderPrefixFilter: <String>{'docs'},
      );

      await File(
        p.join(docsDirectory.path, 'beta.txt'),
      ).writeAsString('beta', flush: true);
      await indexStore.refreshOwnerFolderSubdirectoryIndex(
        record,
        relativeFolderPath: 'docs',
      );

      final afterFingerprint = await indexStore.readTreeFingerprint(
        record,
        relativeFolderPath: 'docs',
      );
      final afterSelection = await indexStore.readScopedSelection(
        record,
        folderPrefixFilter: <String>{'docs'},
      );

      expect(
        afterFingerprint.fingerprint,
        isNot(beforeFingerprint.fingerprint),
      );
      expect(afterSelection.fingerprint, isNot(beforeSelection.fingerprint));
      expect(afterSelection.itemCount, 2);
    },
  );

  test(
    'scoped selection cache reuses unchanged indexed snapshot and falls through when state changes',
    () async {
      final docsDirectory = Directory(p.join(fixtureDirectory.path, 'docs'));
      await docsDirectory.create(recursive: true);
      await File(
        p.join(docsDirectory.path, 'alpha.txt'),
      ).writeAsString('alpha', flush: true);

      const cacheId = 'owner-cache-scope-cache';
      final indexPath = await indexStore.resolveIndexFilePath(
        role: SharedFolderCacheRole.owner,
        displayName: 'Shared Docs',
        cacheId: cacheId,
      );
      final record = SharedFolderCacheRecord(
        cacheId: cacheId,
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: fixtureDirectory.path,
        displayName: 'Shared Docs',
        indexFilePath: indexPath,
        itemCount: 0,
        totalBytes: 0,
        updatedAtMs: 1234,
      );

      await indexStore.materializeOwnerFolderIndex(
        record: record,
        folderPath: fixtureDirectory.path,
      );

      final firstSelection = await indexStore.readScopedSelection(
        record,
        folderPrefixFilter: <String>{'docs'},
      );
      final secondSelection = await indexStore.readScopedSelection(
        record,
        folderPrefixFilter: <String>{'docs'},
      );

      expect(identical(firstSelection, secondSelection), isTrue);

      await File(
        p.join(docsDirectory.path, 'beta.txt'),
      ).writeAsString('beta', flush: true);
      await indexStore.refreshOwnerFolderSubdirectoryIndex(
        record,
        relativeFolderPath: 'docs',
      );

      final refreshedSelection = await indexStore.readScopedSelection(
        record,
        folderPrefixFilter: <String>{'docs'},
      );

      expect(identical(firstSelection, refreshedSelection), isFalse);
      expect(refreshedSelection.itemCount, 2);
    },
  );
}

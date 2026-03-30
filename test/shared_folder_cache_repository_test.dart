import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/shared_folder_cache_repository.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';
import 'package:path/path.dart' as p;

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late SharedFolderCacheRepository repository;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_cache_rows_');
    repository = SharedFolderCacheRepository(database: harness.database);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'upsertCacheRecord, listCaches, and findOwnerCacheByRootPath preserve row semantics',
    () async {
      final ownerRoot = p.join(harness.rootDirectory.path, 'owner_docs');
      final ownerRecord = _record(
        cacheId: 'owner-cache-1',
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: ownerRoot,
        displayName: 'Owner docs',
        indexFilePath: p.join(harness.rootDirectory.path, 'owner-cache-1.json'),
        itemCount: 2,
        totalBytes: 30,
        updatedAtMs: 1000,
      );
      final receiverRecord = _record(
        cacheId: 'receiver-cache-1',
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: '11:22:33:44:55:66',
        rootPath: 'remote://shared/docs',
        displayName: 'Remote docs',
        indexFilePath: p.join(
          harness.rootDirectory.path,
          'receiver-cache-1.json',
        ),
        itemCount: 1,
        totalBytes: 10,
        updatedAtMs: 2000,
      );

      await repository.upsertCacheRecord(ownerRecord);
      await repository.upsertCacheRecord(receiverRecord);

      final ownerRows = await repository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
      );
      final receiverRows = await repository.listCaches(
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'AA-BB-CC-DD-EE-FF',
        peerMacAddress: '11-22-33-44-55-66',
      );
      final restored = await repository.findCacheById(ownerRecord.cacheId);
      final foundByRoot = await repository.findOwnerCacheByRootPath(
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        rootPath: p.join(ownerRoot, '.'),
      );

      expect(ownerRows, hasLength(1));
      expect(ownerRows.single.cacheId, ownerRecord.cacheId);
      expect(receiverRows, hasLength(1));
      expect(receiverRows.single.cacheId, receiverRecord.cacheId);
      expect(restored?.cacheId, ownerRecord.cacheId);
      expect(foundByRoot?.cacheId, ownerRecord.cacheId);
      expect(foundByRoot?.indexFilePath, ownerRecord.indexFilePath);
    },
  );

  test(
    'deleteCacheRecord removes only the targeted row from persistence',
    () async {
      final first = _record(
        cacheId: 'owner-cache-1',
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: p.join(harness.rootDirectory.path, 'cache_one'),
        displayName: 'One',
        indexFilePath: p.join(harness.rootDirectory.path, 'cache_one.json'),
        itemCount: 1,
        totalBytes: 10,
        updatedAtMs: 1000,
      );
      final second = _record(
        cacheId: 'owner-cache-2',
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: p.join(harness.rootDirectory.path, 'cache_two'),
        displayName: 'Two',
        indexFilePath: p.join(harness.rootDirectory.path, 'cache_two.json'),
        itemCount: 2,
        totalBytes: 20,
        updatedAtMs: 2000,
      );

      await repository.upsertCacheRecord(first);
      await repository.upsertCacheRecord(second);
      await repository.deleteCacheRecord(first.cacheId);

      final deleted = await repository.findCacheById(first.cacheId);
      final remaining = await repository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
      );

      expect(deleted, isNull);
      expect(remaining, hasLength(1));
      expect(remaining.single.cacheId, second.cacheId);
    },
  );

  test(
    'rebindOwnerCachesToMac updates owner rows only and preserves cache identity',
    () async {
      final ownerRecord = _record(
        cacheId: 'owner-cache-1',
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: null,
        rootPath: p.join(harness.rootDirectory.path, 'cache_owner'),
        displayName: 'Owner',
        indexFilePath: p.join(harness.rootDirectory.path, 'cache_owner.json'),
        itemCount: 1,
        totalBytes: 10,
        updatedAtMs: 1000,
      );
      final receiverRecord = _record(
        cacheId: 'receiver-cache-1',
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: '11:22:33:44:55:66',
        rootPath: 'remote://shared/docs',
        displayName: 'Receiver',
        indexFilePath: p.join(
          harness.rootDirectory.path,
          'cache_receiver.json',
        ),
        itemCount: 1,
        totalBytes: 10,
        updatedAtMs: 1000,
      );

      await repository.upsertCacheRecord(ownerRecord);
      await repository.upsertCacheRecord(receiverRecord);

      final updatedCount = await repository.rebindOwnerCachesToMac(
        ownerMacAddress: 'ff-ee-dd-cc-bb-aa',
      );
      final reboundOwners = await repository.listCaches(
        role: SharedFolderCacheRole.owner,
        ownerMacAddress: 'ff:ee:dd:cc:bb:aa',
      );
      final receiverRows = await repository.listCaches(
        role: SharedFolderCacheRole.receiver,
        ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
        peerMacAddress: '11:22:33:44:55:66',
      );

      expect(updatedCount, 1);
      expect(reboundOwners, hasLength(1));
      expect(reboundOwners.single.cacheId, ownerRecord.cacheId);
      expect(reboundOwners.single.ownerMacAddress, 'ff:ee:dd:cc:bb:aa');
      expect(receiverRows, hasLength(1));
      expect(receiverRows.single.cacheId, receiverRecord.cacheId);
      expect(receiverRows.single.ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
    },
  );
}

SharedFolderCacheRecord _record({
  required String cacheId,
  required SharedFolderCacheRole role,
  required String ownerMacAddress,
  required String? peerMacAddress,
  required String rootPath,
  required String displayName,
  required String indexFilePath,
  required int itemCount,
  required int totalBytes,
  required int updatedAtMs,
}) {
  return SharedFolderCacheRecord(
    cacheId: cacheId,
    role: role,
    ownerMacAddress: ownerMacAddress,
    peerMacAddress: peerMacAddress,
    rootPath: rootPath,
    displayName: displayName,
    indexFilePath: indexFilePath,
    itemCount: itemCount,
    totalBytes: totalBytes,
    updatedAtMs: updatedAtMs,
  );
}

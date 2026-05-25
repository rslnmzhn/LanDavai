import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/shared_folder_indexing_command.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/transfer/application/shared_cache_owner_contracts.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

void main() {
  test('indexes selected folder and reports completion progress', () async {
    final states = <SharedFolderIndexingState>[];
    OwnerCacheProgressCallback? capturedProgress;
    int? capturedParallelWorkers;
    var loadOwnerCachesCalls = 0;

    final command = SharedFolderIndexingCommand(
      upsertOwnerFolderCache:
          ({
            required ownerMacAddress,
            required folderPath,
            displayName,
            parallelWorkers,
            onProgress,
          }) async {
            expect(ownerMacAddress, 'aa:bb:cc:dd:ee:ff');
            expect(folderPath, '/share');
            capturedParallelWorkers = parallelWorkers;
            capturedProgress = onProgress;
            onProgress?.call(
              processedFiles: 2,
              totalFiles: 4,
              relativePath: 'movie.mp4',
              stage: OwnerCacheProgressStage.indexing,
            );
            return OwnerFolderCacheUpsertResult(
              record: _record(itemCount: 4),
              created: true,
              previousItemCount: 0,
            );
          },
      localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
      settingsProvider: () =>
          AppSettings.defaults.copyWith(recacheParallelWorkers: 3),
      ensureSharedStorageAccess: () async => true,
      pickFolderPath: () async => '/share',
      loadOwnerCaches: () async {
        loadOwnerCachesCalls += 1;
      },
      onStateChanged: states.add,
      nowProvider: _tickingClock(),
    );

    final result = await command.run();

    expect(result.cancelled, isFalse);
    expect(result.infoMessage, 'Shared folder added. Indexed 4 file(s).');
    expect(capturedProgress, isNotNull);
    expect(capturedParallelWorkers, 3);
    expect(loadOwnerCachesCalls, 1);
    expect(states.first.isAddingShare, isTrue);
    expect(states.first.progress, isNull);
    expect(states[1].progress?.stage, OwnerCacheProgressStage.scanning);
    expect(states[1].visualProgress, 0);
    expect(
      states.any((state) => state.progress?.currentRelativePath == 'movie.mp4'),
      isTrue,
    );
    final completion = states[states.length - 2];
    expect(completion.progress?.processedFiles, 4);
    expect(completion.progress?.eta, Duration.zero);
    expect(completion.visualProgress, 1);
    expect(states.last.isAddingShare, isFalse);
    expect(states.last.progress, isNull);
  });

  test(
    'cancels without picking folder when shared storage access is missing',
    () async {
      var pickedFolder = false;
      var indexedFolder = false;
      final states = <SharedFolderIndexingState>[];

      final command = SharedFolderIndexingCommand(
        upsertOwnerFolderCache:
            ({
              required ownerMacAddress,
              required folderPath,
              displayName,
              parallelWorkers,
              onProgress,
            }) async {
              indexedFolder = true;
              return OwnerFolderCacheUpsertResult(
                record: _record(itemCount: 0),
                created: true,
                previousItemCount: 0,
              );
            },
        localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
        settingsProvider: () => AppSettings.defaults,
        ensureSharedStorageAccess: () async => false,
        pickFolderPath: () async {
          pickedFolder = true;
          return '/share';
        },
        loadOwnerCaches: () async {},
        onStateChanged: states.add,
        nowProvider: DateTime.now,
      );

      final result = await command.run();

      expect(result.cancelled, isTrue);
      expect(pickedFolder, isFalse);
      expect(indexedFolder, isFalse);
      expect(states.map((state) => state.isAddingShare), [true, false]);
    },
  );

  test('describes updated existing folder with positive item delta', () async {
    final command = SharedFolderIndexingCommand(
      upsertOwnerFolderCache:
          ({
            required ownerMacAddress,
            required folderPath,
            displayName,
            parallelWorkers,
            onProgress,
          }) async => OwnerFolderCacheUpsertResult(
            record: _record(itemCount: 7),
            created: false,
            previousItemCount: 4,
          ),
      localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
      settingsProvider: () => AppSettings.defaults,
      ensureSharedStorageAccess: () async => true,
      pickFolderPath: () async => '/share',
      loadOwnerCaches: () async {},
      onStateChanged: (_) {},
      nowProvider: DateTime.now,
    );

    final result = await command.run();

    expect(
      result.infoMessage,
      'Shared folder updated. Found 3 new file(s), total 7.',
    );
  });
}

DateTime Function() _tickingClock() {
  var tick = 0;
  return () => DateTime(2026, 1, 1).add(Duration(milliseconds: tick++ * 150));
}

SharedFolderCacheRecord _record({required int itemCount}) {
  return SharedFolderCacheRecord(
    cacheId: 'cache',
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: 'aa:bb:cc:dd:ee:ff',
    rootPath: '/share',
    displayName: 'share',
    indexFilePath: '/cache/index.json',
    itemCount: itemCount,
    totalBytes: 1024,
    updatedAtMs: 1,
  );
}

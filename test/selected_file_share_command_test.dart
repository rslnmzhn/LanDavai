import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/discovery/application/selected_file_share_command.dart';
import 'package:landa/features/discovery/domain/discovered_device.dart';
import 'package:landa/features/transfer/application/shared_cache_index_store.dart';
import 'package:landa/features/transfer/application/shared_cache_catalog.dart';
import 'package:landa/features/transfer/data/shared_cache_record_store.dart';
import 'package:landa/features/transfer/data/thumbnail_cache_service.dart';
import 'package:landa/features/transfer/domain/shared_folder_cache.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_selected_file_share_command_',
    );
  });

  tearDown(() async {
    await harness.dispose();
  });

  test('addSharedFiles builds owner selection cache', () async {
    final catalog = _RecordingSharedCacheCatalog(harness);
    final command = SelectedFileShareCommand(
      pickFilePaths: () async => <String>['/tmp/a.txt', '/tmp/b.txt'],
      sharedCacheCatalog: catalog,
      sendFilesToDevice: _unusedSendFiles,
      localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
    );

    final result = await command.addSharedFiles();

    expect(result.cancelled, isFalse);
    expect(result.errorMessage, isNull);
    expect(result.infoMessage, 'Shared files added.');
    expect(catalog.ownerSelectionBuilds, 1);
    expect(catalog.lastOwnerMacAddress, 'aa:bb:cc:dd:ee:ff');
    expect(catalog.lastFilePaths, <String>['/tmp/a.txt', '/tmp/b.txt']);
    expect(catalog.lastDisplayName, 'Selected files');
  });

  test('addSharedFiles cancels when picker returns no files', () async {
    final catalog = _RecordingSharedCacheCatalog(harness);
    final command = SelectedFileShareCommand(
      pickFilePaths: () async => const <String>[],
      sharedCacheCatalog: catalog,
      sendFilesToDevice: _unusedSendFiles,
      localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
    );

    final result = await command.addSharedFiles();

    expect(result.cancelled, isTrue);
    expect(catalog.ownerSelectionBuilds, 0);
  });

  test(
    'sendFilesToDevice requires selected target before picking files',
    () async {
      var pickedFiles = false;
      final sent = <_SentFiles>[];
      final command = SelectedFileShareCommand(
        pickFilePaths: () async {
          pickedFiles = true;
          return <String>['/tmp/a.txt'];
        },
        sharedCacheCatalog: _RecordingSharedCacheCatalog(harness),
        sendFilesToDevice: _recordSendFiles(sent),
        localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
      );

      final result = await command.sendFilesToDevice(null);

      expect(result.errorMessage, 'Select a target device first.');
      expect(pickedFiles, isFalse);
      expect(sent, isEmpty);
    },
  );

  test(
    'sendFilesToDevice forwards selected paths to outgoing boundary seam',
    () async {
      final sent = <_SentFiles>[];
      final command = SelectedFileShareCommand(
        pickFilePaths: () async => <String>['/tmp/a.txt'],
        sharedCacheCatalog: _RecordingSharedCacheCatalog(harness),
        sendFilesToDevice: _recordSendFiles(sent),
        localDeviceMacProvider: () => 'aa:bb:cc:dd:ee:ff',
      );

      final result = await command.sendFilesToDevice(
        DiscoveredDevice(
          ip: '192.168.1.40',
          deviceName: 'Laptop',
          lastSeen: DateTime(2026),
        ),
      );

      expect(result.errorMessage, isNull);
      expect(sent, hasLength(1));
      expect(sent.single.targetIp, '192.168.1.40');
      expect(sent.single.targetName, 'Laptop');
      expect(sent.single.selectedPaths, <String>['/tmp/a.txt']);
    },
  );
}

Future<void> _unusedSendFiles({
  required String targetIp,
  required String targetName,
  required List<String> selectedPaths,
}) async {}

SendFilesToDevice _recordSendFiles(List<_SentFiles> sent) {
  return ({
    required String targetIp,
    required String targetName,
    required List<String> selectedPaths,
  }) async {
    sent.add(
      _SentFiles(
        targetIp: targetIp,
        targetName: targetName,
        selectedPaths: selectedPaths,
      ),
    );
  };
}

class _SentFiles {
  const _SentFiles({
    required this.targetIp,
    required this.targetName,
    required this.selectedPaths,
  });

  final String targetIp;
  final String targetName;
  final List<String> selectedPaths;
}

class _RecordingSharedCacheCatalog extends SharedCacheCatalog {
  _RecordingSharedCacheCatalog(TestAppDatabaseHarness harness)
    : super(
        sharedCacheRecordStore: _NoopSharedCacheRecordStore(),
        sharedCacheIndexStore: SharedCacheIndexStore(
          database: harness.database,
          thumbnailCacheService: ThumbnailCacheService(
            database: harness.database,
          ),
        ),
      );

  int ownerSelectionBuilds = 0;
  String? lastOwnerMacAddress;
  List<String>? lastFilePaths;
  String? lastDisplayName;

  @override
  Future<SharedFolderCacheRecord> buildOwnerSelectionCache({
    required String ownerMacAddress,
    required List<String> filePaths,
    String? displayName,
  }) async {
    ownerSelectionBuilds += 1;
    lastOwnerMacAddress = ownerMacAddress;
    lastFilePaths = filePaths;
    lastDisplayName = displayName;
    return _record(ownerMacAddress: ownerMacAddress);
  }
}

class _NoopSharedCacheRecordStore implements SharedCacheRecordStore {
  @override
  Future<void> deleteCacheRecord(String cacheId) async {}

  @override
  Future<SharedFolderCacheRecord?> findCacheById(String cacheId) async => null;

  @override
  Future<SharedFolderCacheRecord?> findOwnerCacheByRootPath({
    required String ownerMacAddress,
    required String rootPath,
  }) async => null;

  @override
  Future<List<SharedFolderCacheRecord>> listCaches({
    SharedFolderCacheRole? role,
    String? ownerMacAddress,
    String? peerMacAddress,
  }) async => const <SharedFolderCacheRecord>[];

  @override
  Future<int> rebindOwnerCachesToMac({required String ownerMacAddress}) async =>
      0;

  @override
  Future<void> upsertCacheRecord(SharedFolderCacheRecord record) async {}
}

SharedFolderCacheRecord _record({required String ownerMacAddress}) {
  return SharedFolderCacheRecord(
    cacheId: 'selection-cache',
    role: SharedFolderCacheRole.owner,
    ownerMacAddress: ownerMacAddress,
    rootPath: 'selection',
    displayName: 'Selected files',
    indexFilePath: '/cache/selection.json',
    itemCount: 1,
    totalBytes: 1,
    updatedAtMs: 1,
  );
}

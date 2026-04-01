import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late TransferHistoryRepository repository;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(prefix: 'landa_history_');
    repository = TransferHistoryRepository(database: harness.database);
  });

  tearDown(() async {
    await harness.dispose();
  });

  test(
    'stores and restores transfer history rows with current json semantics',
    () async {
      await repository.addRecord(
        id: 'first',
        requestId: 'request-1',
        direction: TransferHistoryDirection.download,
        peerName: '   ',
        peerIp: '192.168.1.33',
        rootPath: r'C:\Downloads',
        savedPaths: <String>[r'C:\Downloads\a.txt', r'C:\Downloads\b.txt'],
        fileCount: 2,
        totalBytes: 42,
        status: TransferHistoryStatus.completed,
        createdAtMs: 1000,
      );

      final records = await repository.listRecords();

      expect(records, hasLength(1));
      final record = records.single;
      expect(record.id, 'first');
      expect(record.requestId, 'request-1');
      expect(record.direction, TransferHistoryDirection.download);
      expect(record.peerName, 'Unknown peer');
      expect(record.peerIp, '192.168.1.33');
      expect(record.rootPath, r'C:\Downloads');
      expect(record.savedPaths, <String>[
        r'C:\Downloads\a.txt',
        r'C:\Downloads\b.txt',
      ]);
      expect(record.fileCount, 2);
      expect(record.totalBytes, 42);
      expect(record.status, TransferHistoryStatus.completed);
    },
  );

  test('keeps newest first and preserves direction filtering', () async {
    await repository.addRecord(
      id: 'upload',
      direction: TransferHistoryDirection.upload,
      peerName: 'Uploader',
      peerIp: null,
      rootPath: '/tmp/out',
      savedPaths: <String>['/tmp/out/file.txt'],
      fileCount: 1,
      totalBytes: 10,
      status: TransferHistoryStatus.failed,
      createdAtMs: 100,
    );
    await repository.addRecord(
      id: 'download',
      direction: TransferHistoryDirection.download,
      peerName: 'Downloader',
      peerIp: '10.0.0.5',
      rootPath: '/tmp/in',
      savedPaths: <String>['/tmp/in/file.txt'],
      fileCount: 1,
      totalBytes: 15,
      status: TransferHistoryStatus.completed,
      createdAtMs: 200,
    );

    final allRecords = await repository.listRecords();
    final uploads = await repository.listRecords(
      direction: TransferHistoryDirection.upload,
    );

    expect(allRecords.map((record) => record.id), <String>[
      'download',
      'upload',
    ]);
    expect(uploads.map((record) => record.id), <String>['upload']);
  });
}

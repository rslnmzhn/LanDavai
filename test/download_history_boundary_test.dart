import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/history/application/download_history_boundary.dart';
import 'package:landa/features/history/data/transfer_history_repository.dart';
import 'package:landa/features/history/domain/transfer_history_record.dart';

import 'test_support/test_app_database.dart';

void main() {
  late TestAppDatabaseHarness harness;
  late TransferHistoryRepository repository;
  late DownloadHistoryBoundary boundary;

  setUp(() async {
    harness = await TestAppDatabaseHarness.create(
      prefix: 'landa_download_history_boundary_',
    );
    repository = TransferHistoryRepository(database: harness.database);
    boundary = DownloadHistoryBoundary(transferHistoryRepository: repository);
  });

  tearDown(() async {
    boundary.dispose();
    await harness.dispose();
  });

  test('loads canonical download history projection from repository', () async {
    await repository.addRecord(
      id: 'download-1',
      requestId: 'request-1',
      direction: TransferHistoryDirection.download,
      peerName: 'Remote A',
      peerIp: '192.168.1.10',
      rootPath: '/tmp/downloads',
      savedPaths: const <String>['/tmp/downloads/a.txt'],
      fileCount: 1,
      totalBytes: 10,
      status: TransferHistoryStatus.completed,
      createdAtMs: 200,
    );
    await repository.addRecord(
      id: 'upload-1',
      requestId: 'request-2',
      direction: TransferHistoryDirection.upload,
      peerName: 'Remote B',
      peerIp: '192.168.1.11',
      rootPath: '/tmp/uploads',
      savedPaths: const <String>['/tmp/uploads/b.txt'],
      fileCount: 1,
      totalBytes: 20,
      status: TransferHistoryStatus.failed,
      createdAtMs: 300,
    );

    await boundary.load();

    expect(boundary.records, hasLength(1));
    expect(boundary.records.single.id, 'download-1');
    expect(
      boundary.records.single.direction,
      TransferHistoryDirection.download,
    );
  });

  test(
    'recordDownload persists and refreshes boundary-owned history truth',
    () async {
      await boundary.recordDownload(
        id: 'download-2',
        requestId: 'request-3',
        peerName: 'Remote C',
        peerIp: '192.168.1.12',
        rootPath: '/tmp/downloads-2',
        savedPaths: const <String>['/tmp/downloads-2/c.txt'],
        fileCount: 1,
        totalBytes: 30,
        status: TransferHistoryStatus.completed,
        createdAtMs: 400,
      );

      final rows = await repository.listRecords(
        direction: TransferHistoryDirection.download,
      );

      expect(rows, hasLength(1));
      expect(rows.single.id, 'download-2');
      expect(boundary.records, hasLength(1));
      expect(boundary.records.single.peerName, 'Remote C');
    },
  );
}

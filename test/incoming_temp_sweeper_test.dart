import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/incoming_temp_sweeper.dart';

void main() {
  group('IncomingTempSweeper', () {
    late Directory rootDirectory;

    setUp(() async {
      rootDirectory = await Directory.systemTemp.createTemp(
        'landa_incoming_temp_sweeper_test_',
      );
    });

    tearDown(() async {
      if (await rootDirectory.exists()) {
        await rootDirectory.delete(recursive: true);
      }
    });

    Future<File> createStaleFile(
      String relativePath, {
      int sizeBytes = 10,
    }) async {
      final file = File(
        '${rootDirectory.path}${Platform.pathSeparator}$relativePath',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(sizeBytes, 1), flush: true);
      final oldTimestamp = DateTime.now().subtract(const Duration(hours: 3));
      await file.setLastModified(oldTimestamp);
      return file;
    }

    Future<File> createFreshFile(String relativePath) async {
      final file = File(
        '${rootDirectory.path}${Platform.pathSeparator}$relativePath',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(10, 1), flush: true);
      return file;
    }

    test('missing directory reports zero deletions without throwing', () async {
      final sweeper = const IncomingTempSweeper().sweep(
        Directory(
          '${rootDirectory.path}${Platform.pathSeparator}does_not_exist',
        ),
      );

      final result = await sweeper;
      expect(result.filesDeleted, 0);
      expect(result.bytesFreed, 0);
    });

    test('deletes stale files and frees their bytes', () async {
      final stale = await createStaleFile('stale.bin', sizeBytes: 128);
      final result = await const IncomingTempSweeper().sweep(rootDirectory);

      expect(result.filesDeleted, 1);
      expect(result.bytesFreed, 128);
      expect(await stale.exists(), isFalse);
    });

    test('preserves recent files so a running transfer is not hit', () async {
      final fresh = await createFreshFile('fresh.landa-part');
      final result = await const IncomingTempSweeper().sweep(rootDirectory);

      expect(result.filesDeleted, 0);
      expect(result.bytesFreed, 0);
      expect(await fresh.exists(), isTrue);
    });

    test('sweeps nested stale files but keeps fresh nested ones', () async {
      final staleNested = await createStaleFile('nested/deep/stale.bin');
      final freshNested = await createFreshFile('nested/deep/fresh.landa-part');
      final result = await const IncomingTempSweeper().sweep(rootDirectory);

      expect(result.filesDeleted, 1);
      expect(result.bytesFreed, 10);
      expect(await staleNested.exists(), isFalse);
      expect(await freshNested.exists(), isTrue);
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/share_target/data/share_intent_cache_sweeper.dart';

void main() {
  group('ShareIntentCacheSweeper', () {
    late Directory cacheRoot;

    setUp(() async {
      cacheRoot = await Directory.systemTemp.createTemp(
        'landa_share_intent_cache_test_',
      );
    });

    tearDown(() async {
      if (await cacheRoot.exists()) {
        await cacheRoot.delete(recursive: true);
      }
    });

    Future<File> stageFile(
      String relativePath, {
      required bool stale,
      int sizeBytes = 12,
    }) async {
      final file = File('${cacheRoot.path}/share_intent/$relativePath');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(List<int>.filled(sizeBytes, 9), flush: true);
      if (stale) {
        await file.setLastModified(
          DateTime.now().subtract(const Duration(hours: 48)),
        );
      }
      return file;
    }

    test('sweeps only stale share intent staging files', () async {
      final stale = await stageFile('old.png', stale: true);
      final fresh = await stageFile('new.png', stale: false);

      final result = await ShareIntentCacheSweeper(
        resolveCacheDirectory: () async => cacheRoot,
      ).sweepStaleFiles();

      expect(result.filesDeleted, 1);
      expect(result.bytesFreed, 12);
      expect(await stale.exists(), isFalse);
      expect(await fresh.exists(), isTrue);
    });

    test('missing cache resolver yields a no-op result', () async {
      await stageFile('old.png', stale: true);

      final result = await ShareIntentCacheSweeper(
        resolveCacheDirectory: () async => null,
      ).sweepStaleFiles();

      expect(result.filesDeleted, 0);
      expect(result.bytesFreed, 0);
    });

    test('missing share_intent directory is tolerated', () async {
      final result = await ShareIntentCacheSweeper(
        resolveCacheDirectory: () async => cacheRoot,
      ).sweepStaleFiles();

      expect(result.filesDeleted, 0);
      expect(result.bytesFreed, 0);
    });
  });
}

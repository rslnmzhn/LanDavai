import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/data/transfer_destination_path_allocator.dart';
import 'package:path/path.dart' as p;

void main() {
  group('TransferDestinationPathAllocator', () {
    late Directory rootDirectory;
    const allocator = TransferDestinationPathAllocator();

    setUp(() async {
      rootDirectory = await Directory.systemTemp.createTemp(
        'landa_transfer_destination_allocator_test_',
      );
    });

    tearDown(() async {
      if (await rootDirectory.exists()) {
        await rootDirectory.delete(recursive: true);
      }
    });

    test('sanitizes traversal and unsafe path segments', () {
      final sanitized = allocator.sanitizeRelativePath(
        '../Project/<bad>|name/./file?.txt',
      );

      expect(sanitized, p.join('_', 'Project', '_bad__name', '_', 'file_.txt'));
      expect(sanitized, isNot(contains('..')));
    });

    test('applies destination root prefix and resolves collisions', () async {
      final existing = File(
        p.join(rootDirectory.path, 'SharedRoot', 'docs', 'file.txt'),
      );
      await existing.parent.create(recursive: true);
      await existing.writeAsString('existing');

      final destination = await allocator.allocateDestinationPath(
        destinationDirectory: rootDirectory,
        relativePath: 'docs/file.txt',
        destinationRelativeRootPrefix: 'SharedRoot',
      );

      expect(
        destination,
        p.join(rootDirectory.path, 'SharedRoot', 'docs', 'file (1).txt'),
      );
    });

    test('allocates unique temporary part path beside destination', () async {
      final destinationPath = p.join(rootDirectory.path, 'file.bin');
      final existingTemp = File(
        p.join(rootDirectory.path, '.file.bin.landa-part'),
      );
      await existingTemp.create(recursive: true);

      final tempPath = await allocator.allocateTemporaryDestinationPath(
        destinationPath,
      );

      expect(tempPath, p.join(rootDirectory.path, '.file.bin.landa-part.1'));
    });
  });
}

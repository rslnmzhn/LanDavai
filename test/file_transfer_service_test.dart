import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';

void main() {
  group('FileTransferService', () {
    late Directory rootDirectory;
    late FileTransferService service;

    setUp(() async {
      rootDirectory = await Directory.systemTemp.createTemp(
        'landa_file_transfer_service_test_',
      );
      service = FileTransferService();
    });

    tearDown(() async {
      if (await rootDirectory.exists()) {
        await rootDirectory.delete(recursive: true);
      }
    });

    test(
      'direct single-file transfer succeeds when manifest hash is unknown',
      () async {
        final sourceFile = File(p.join(rootDirectory.path, 'source', 'a.7z'));
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsBytes(List<int>.filled(1024, 7));
        final expectedReceivedHash = await FileHashService()
            .computeSha256ForPath(sourceFile.path);

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-1',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
        );

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-1',
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: sourceFile.path,
              fileName: 'a.7z',
              sizeBytes: await sourceFile.length(),
              sha256: '',
            ),
          ],
        );
        final result = await receiveSession.result;

        expect(result.success, isTrue);
        expect(result.savedPaths, hasLength(1));
        expect(File(result.savedPaths.single).existsSync(), isTrue);
        expect(result.hashVerified, isFalse);
        expect(result.receivedItems.single.sha256, expectedReceivedHash);
      },
    );

    test(
      'transfer still verifies hash when manifest hash is provided',
      () async {
        final sourceFile = File(p.join(rootDirectory.path, 'source', 'b.txt'));
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsString('verified');
        final expectedHash = await FileHashService().computeSha256ForPath(
          sourceFile.path,
        );

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-2',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
        );

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-2',
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: sourceFile.path,
              fileName: 'b.txt',
              sizeBytes: await sourceFile.length(),
              sha256: expectedHash,
            ),
          ],
        );
        final result = await receiveSession.result;

        expect(result.success, isTrue);
        expect(result.hashVerified, isTrue);
        expect(result.receivedItems.single.sha256, expectedHash);
      },
    );

    test(
      'large direct transfer manifest succeeds with relative selector names only',
      () async {
        final sourceFile = File(
          p.join(rootDirectory.path, 'source', 'placeholder.bin'),
        );
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsBytes(const <int>[]);

        const itemCount = 15000;
        final files = List<TransferSourceFile>.generate(
          itemCount,
          (index) => TransferSourceFile(
            sourcePath: sourceFile.path,
            fileName: 'ReactProjects/App_$index/src/file_$index.txt',
            sizeBytes: 0,
            sha256: '',
          ),
          growable: false,
        );

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-large-manifest',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
        );

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-large-manifest',
          files: files,
        );
        final result = await receiveSession.result;

        expect(result.success, isTrue);
        expect(result.receivedItems, hasLength(itemCount));
        expect(
          result.receivedItems.every(
            (item) =>
                item.fileName.startsWith('ReactProjects/') &&
                !item.fileName.contains(sourceFile.parent.path),
          ),
          isTrue,
        );
        expect(
          result.savedPaths.every(
            (path) => path.startsWith(destinationDirectory.path),
          ),
          isTrue,
        );
      },
    );
  });
}

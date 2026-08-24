import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:landa/features/transfer/data/file_hash_service.dart';
import 'package:landa/features/transfer/data/file_transfer_service.dart';
import 'package:landa/features/transfer/data/transfer_header_codec.dart';
import 'package:landa/features/transfer/domain/transfer_request.dart';

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
      if (!await rootDirectory.exists()) {
        return;
      }
      // Windows can transiently lock freshly written temp files (AV/indexer),
      // so retry the recursive delete briefly before giving up.
      for (var attempt = 0; attempt < 5; attempt += 1) {
        try {
          await rootDirectory.delete(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      await rootDirectory.delete(recursive: true);
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
      'receiver commits only flushed files and removes temp artifacts',
      () async {
        final sourceFile = File(p.join(rootDirectory.path, 'source', 'c.bin'));
        await sourceFile.parent.create(recursive: true);
        final bytes = List<int>.generate(1024 * 1024, (index) => index % 251);
        await sourceFile.writeAsBytes(bytes, flush: true);

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-flushed-file',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
        );

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-flushed-file',
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: sourceFile.path,
              fileName: 'nested/c.bin',
              sizeBytes: await sourceFile.length(),
              sha256: '',
            ),
          ],
        );
        final result = await receiveSession.result;
        final savedFile = File(result.savedPaths.single);
        final leftoverTempFiles = await destinationDirectory
            .list(recursive: true)
            .where((entity) => p.basename(entity.path).contains('.landa-part'))
            .toList();

        expect(result.success, isTrue);
        expect(await savedFile.exists(), isTrue);
        expect(await savedFile.length(), bytes.length);
        expect(await savedFile.readAsBytes(), bytes);
        expect(leftoverTempFiles, isEmpty);
      },
    );

    test(
      'receiver fails without reporting success when final path cannot be committed',
      () async {
        final sourceFile = File(p.join(rootDirectory.path, 'source', 'd.bin'));
        await sourceFile.parent.create(recursive: true);
        await sourceFile.writeAsBytes(List<int>.filled(128, 4), flush: true);

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final blockedDestination = Directory(
          p.join(destinationDirectory.path, 'blocked.bin'),
        );
        await blockedDestination.create(recursive: true);
        final receiveSession = await service.startReceiver(
          requestId: 'request-blocked-destination',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
          destinationPathAllocator:
              ({
                required Directory destinationDirectory,
                required String relativePath,
              }) async => blockedDestination.path,
        );

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-blocked-destination',
          files: <TransferSourceFile>[
            TransferSourceFile(
              sourcePath: sourceFile.path,
              fileName: 'blocked.bin',
              sizeBytes: await sourceFile.length(),
              sha256: '',
            ),
          ],
        );
        final result = await receiveSession.result;
        final leftoverTempFiles = await destinationDirectory
            .list(recursive: true)
            .where((entity) => p.basename(entity.path).contains('.landa-part'))
            .toList();

        expect(result.success, isFalse);
        expect(result.savedPaths, isEmpty);
        expect(result.message, contains('Transfer receive failed'));
        expect(leftoverTempFiles, isEmpty);
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
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'whole-share sendFiles continues through later batches and emits batch progress diagnostics',
      () async {
        const totalFileCount = 6;
        final sourceFiles = <File>[];
        final manifestItems = <TransferFileManifestItem>[];
        for (var index = 0; index < totalFileCount; index += 1) {
          final file = File(
            p.join(
              rootDirectory.path,
              'source',
              'batch_$index',
              'file_$index.txt',
            ),
          );
          await file.parent.create(recursive: true);
          await file.writeAsString('payload-$index');
          sourceFiles.add(file);
          manifestItems.add(
            TransferFileManifestItem(
              fileName: 'Workspace/batch_$index/file_$index.txt',
              sizeBytes: await file.length(),
              sha256: '',
            ),
          );
        }

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-batched-whole-share',
          expectedItems: manifestItems,
          destinationDirectory: destinationDirectory,
        );
        final diagnostics = <String>[];

        await service.sendFiles(
          host: InternetAddress.loopbackIPv4.address,
          port: receiveSession.port,
          requestId: 'request-batched-whole-share',
          files: List<TransferSourceFile>.generate(
            2,
            (index) => TransferSourceFile(
              sourcePath: sourceFiles[index].path,
              fileName: manifestItems[index].fileName,
              sizeBytes: manifestItems[index].sizeBytes,
              sha256: '',
            ),
            growable: false,
          ),
          manifestItems: manifestItems,
          resolveBatch: (startIndex) async {
            final endIndex = startIndex + 2 > totalFileCount
                ? totalFileCount
                : startIndex + 2;
            return TransferSourceBatch(
              batchNumber: (startIndex ~/ 2) + 1,
              startIndex: startIndex,
              files: List<TransferSourceFile>.generate(endIndex - startIndex, (
                offset,
              ) {
                final index = startIndex + offset;
                return TransferSourceFile(
                  sourcePath: sourceFiles[index].path,
                  fileName: manifestItems[index].fileName,
                  sizeBytes: manifestItems[index].sizeBytes,
                  sha256: '',
                );
              }, growable: false),
            );
          },
          onDiagnosticEvent:
              ({
                required String stage,
                Map<String, Object?> details = const <String, Object?>{},
                Object? error,
                StackTrace? stackTrace,
              }) {
                diagnostics.add(
                  '$stage:${details['batchNumber'] ?? ''}:${details['cumulativeSentFileCount'] ?? ''}',
                );
              },
        );
        final result = await receiveSession.result;

        expect(result.success, isTrue);
        expect(result.receivedItems, hasLength(totalFileCount));
        expect(result.savedPaths, hasLength(totalFileCount));
        expect(
          diagnostics,
          containsAll(<String>[
            'sender_whole_share_batch_sent:1:2',
            'sender_whole_share_batch_sent:2:4',
            'sender_whole_share_batch_sent:3:6',
          ]),
        );
      },
    );

    test('receiver fails when the sender stalls after connecting', () async {
      final destinationDirectory = Directory(
        p.join(rootDirectory.path, 'destination'),
      );
      await destinationDirectory.create(recursive: true);
      final receiveSession = await service.startReceiver(
        requestId: 'request-stalled-sender',
        expectedItems: null,
        destinationDirectory: destinationDirectory,
        armTimeoutImmediately: false,
        receiveIdleTimeoutOverride: const Duration(milliseconds: 150),
      );

      // Connect but never send anything, simulating a stalled sender.
      final stalledSocket = await Socket.connect(
        InternetAddress.loopbackIPv4.address,
        receiveSession.port,
      );

      final result = await receiveSession.result;

      expect(result.success, isFalse);
      expect(result.message, contains('stalled'));
      expect(result.savedPaths, isEmpty);
      await stalledSocket.close();
    });

    test(
      'receiver keeps a slow-but-progressing transfer alive and completes it',
      () async {
        final sourceFile = File(
          p.join(rootDirectory.path, 'source', 'slow.bin'),
        );
        await sourceFile.parent.create(recursive: true);
        final bytes = List<int>.generate(256 * 1024, (index) => index % 251);
        await sourceFile.writeAsBytes(bytes, flush: true);

        final destinationDirectory = Directory(
          p.join(rootDirectory.path, 'destination'),
        );
        final receiveSession = await service.startReceiver(
          requestId: 'request-slow-sender',
          expectedItems: null,
          destinationDirectory: destinationDirectory,
          armTimeoutImmediately: false,
          // Idle window comfortably longer than the inter-chunk delay below
          // (4x margin) so only a genuine multi-interval silence trips it.
          receiveIdleTimeoutOverride: const Duration(milliseconds: 400),
        );

        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4.address,
          receiveSession.port,
        );
        try {
          const codec = TransferHeaderCodec();
          final header = codec.encode(
            TransferHeader(
              requestId: 'request-slow-sender',
              files: <TransferFileManifestItem>[
                TransferFileManifestItem(
                  fileName: 'slow.bin',
                  sizeBytes: bytes.length,
                  sha256: '',
                ),
              ],
            ),
          );
          final headerLength = ByteData(4)
            ..setUint32(0, header.bytes.length, Endian.big);
          socket.add(headerLength.buffer.asUint8List());
          socket.add(header.bytes);

          // Drip chunks faster than the idle timeout (100ms drip vs 400ms
          // window); each drip re-arms the watchdog so the session is never
          // killed mid-transfer.
          for (var offset = 0; offset < bytes.length; offset += 64 * 1024) {
            final end = (offset + 64 * 1024).clamp(0, bytes.length);
            socket.add(bytes.sublist(offset, end));
            await socket.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await socket.flush();
        } finally {
          await socket.close();
        }

        final result = await receiveSession.result;

        expect(result.success, isTrue);
        expect(result.savedPaths, hasLength(1));
        expect(await File(result.savedPaths.single).readAsBytes(), bytes);
      },
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/nearby_transfer/data/nearby_transfer_storage_service.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'allocateDestinationPath uses deterministic numbered collision policy',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'landa_nearby_storage_',
      );
      addTearDown(() async {
        if (await root.exists()) {
          await root.delete(recursive: true);
        }
      });
      final receiveDirectory = Directory(p.join(root.path, 'incoming'));
      await receiveDirectory.create(recursive: true);
      await File(p.join(receiveDirectory.path, 'photo.png')).writeAsString('a');
      await File(
        p.join(receiveDirectory.path, 'photo (1).png'),
      ).writeAsString('b');
      final service = NearbyTransferStorageService(
        transferStorageService: _StubTransferStorageService(receiveDirectory),
      );

      final allocated = await service.allocateDestinationPath(
        destinationDirectory: receiveDirectory,
        relativePath: 'photo.png',
      );

      expect(allocated, p.join(receiveDirectory.path, 'photo (2).png'));
    },
  );
}

class _StubTransferStorageService extends TransferStorageService {
  _StubTransferStorageService(this.directory);

  final Directory directory;

  @override
  Future<Directory> resolveReceiveDirectory({
    String appFolderName = 'Landa',
  }) async {
    return directory;
  }
}

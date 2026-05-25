import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/transfer/application/shared_download_path_resolver.dart';
import 'package:landa/features/transfer/data/transfer_storage_service.dart';

void main() {
  test('preserves shared root for whole-share requests only', () {
    final resolver = SharedDownloadPathResolver(
      transferStorageService: _FakeTransferStorageService(),
    );

    expect(
      resolver.resolveReceiveLayout(
        selectedRelativePaths: const <String>[],
        selectedFolderPrefixes: const <String>[],
      ),
      SharedDownloadReceiveLayout.preserveSharedRoot,
    );
    expect(
      resolver.resolveReceiveLayout(
        selectedRelativePaths: const <String>['photo.jpg'],
        selectedFolderPrefixes: const <String>[],
      ),
      SharedDownloadReceiveLayout.preserveRelativeStructure,
    );
    expect(
      resolver.resolveReceiveLayout(
        selectedRelativePaths: const <String>[],
        selectedFolderPrefixes: const <String>['album/'],
      ),
      SharedDownloadReceiveLayout.preserveRelativeStructure,
    );
  });

  test('resolves safe receive root prefixes through path policy', () {
    final resolver = SharedDownloadPathResolver(
      transferStorageService: _FakeTransferStorageService(),
    );

    expect(
      resolver.resolveReceiveRootPrefix('Shared: Photos'),
      'Shared_ Photos',
    );
    expect(resolver.resolveReceiveRootPrefix(''), isNull);
    expect(resolver.resolveReceiveRootPrefix('***'), '___');
  });

  test(
    'uses standard app download folder when requested on desktop picker',
    () async {
      final storage = _FakeTransferStorageService(
        supportsPicker: true,
        receiveDirectory: Directory('standard'),
        pickedDirectory: Directory('picked'),
      );
      final resolver = SharedDownloadPathResolver(
        transferStorageService: storage,
      );

      final directory = await resolver
          .resolveRemoteDownloadDestinationDirectory(
            useStandardAppDownloadFolder: true,
          );

      expect(directory!.path, 'standard');
      expect(storage.resolveReceiveDirectoryCalls, 1);
      expect(storage.pickDesktopDownloadDirectoryCalls, 0);
    },
  );

  test(
    'uses desktop picker when supported and standard folder is not requested',
    () async {
      final storage = _FakeTransferStorageService(
        supportsPicker: true,
        receiveDirectory: Directory('standard'),
        pickedDirectory: Directory('picked'),
      );
      final resolver = SharedDownloadPathResolver(
        transferStorageService: storage,
      );

      final directory = await resolver
          .resolveRemoteDownloadDestinationDirectory(
            useStandardAppDownloadFolder: false,
          );

      expect(directory!.path, 'picked');
      expect(storage.resolveReceiveDirectoryCalls, 0);
      expect(storage.pickDesktopDownloadDirectoryCalls, 1);
    },
  );

  test(
    'uses standard app download folder when desktop picker is unsupported',
    () async {
      final storage = _FakeTransferStorageService(
        supportsPicker: false,
        receiveDirectory: Directory('standard'),
        pickedDirectory: Directory('picked'),
      );
      final resolver = SharedDownloadPathResolver(
        transferStorageService: storage,
      );

      final directory = await resolver
          .resolveRemoteDownloadDestinationDirectory(
            useStandardAppDownloadFolder: false,
          );

      expect(directory!.path, 'standard');
      expect(storage.resolveReceiveDirectoryCalls, 1);
      expect(storage.pickDesktopDownloadDirectoryCalls, 0);
    },
  );
}

class _FakeTransferStorageService extends TransferStorageService {
  _FakeTransferStorageService({
    this.supportsPicker = false,
    Directory? receiveDirectory,
    Directory? pickedDirectory,
  }) : receiveDirectory = receiveDirectory ?? Directory('receive'),
       pickedDirectory = pickedDirectory ?? Directory('picked');

  final bool supportsPicker;
  final Directory receiveDirectory;
  final Directory? pickedDirectory;
  int resolveReceiveDirectoryCalls = 0;
  int pickDesktopDownloadDirectoryCalls = 0;

  @override
  bool get supportsDesktopDownloadPicker => supportsPicker;

  @override
  Future<Directory> resolveReceiveDirectory({String appFolderName = 'Landa'}) {
    resolveReceiveDirectoryCalls += 1;
    return Future<Directory>.value(receiveDirectory);
  }

  @override
  Future<Directory?> pickDesktopDownloadDirectory() {
    pickDesktopDownloadDirectoryCalls += 1;
    return Future<Directory?>.value(pickedDirectory);
  }
}

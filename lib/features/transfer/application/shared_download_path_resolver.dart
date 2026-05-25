import 'dart:io';

import '../data/transfer_storage_service.dart';
import 'transfer_path_policy.dart';

enum SharedDownloadReceiveLayout {
  preserveRelativeStructure,
  preserveSharedRoot,
}

class SharedDownloadPathResolver {
  const SharedDownloadPathResolver({
    required TransferStorageService transferStorageService,
    TransferPathPolicy pathPolicy = const TransferPathPolicy(),
  }) : _transferStorageService = transferStorageService,
       _pathPolicy = pathPolicy;

  final TransferStorageService _transferStorageService;
  final TransferPathPolicy _pathPolicy;

  Future<Directory?> resolveRemoteDownloadDestinationDirectory({
    required bool useStandardAppDownloadFolder,
  }) async {
    if (_transferStorageService.supportsDesktopDownloadPicker) {
      if (useStandardAppDownloadFolder) {
        return _transferStorageService.resolveReceiveDirectory(
          appFolderName: 'Landa',
        );
      }
      return _transferStorageService.pickDesktopDownloadDirectory();
    }

    return _transferStorageService.resolveReceiveDirectory(
      appFolderName: 'Landa',
    );
  }

  SharedDownloadReceiveLayout resolveReceiveLayout({
    required List<String> selectedRelativePaths,
    required List<String> selectedFolderPrefixes,
  }) {
    if (selectedRelativePaths.isEmpty && selectedFolderPrefixes.isEmpty) {
      return SharedDownloadReceiveLayout.preserveSharedRoot;
    }
    return SharedDownloadReceiveLayout.preserveRelativeStructure;
  }

  String? resolveReceiveRootPrefix(String sharedLabel) {
    return _pathPolicy.resolveReceiveRootPrefix(sharedLabel);
  }
}

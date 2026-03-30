import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:landa/features/files/presentation/file_explorer/local_file_viewer.dart';
import 'package:landa/features/files/presentation/file_explorer_page.dart';

import 'test_support/test_discovery_controller.dart';

void main() {
  test(
    'FileExplorerPage and LocalFileViewerPage stay directly constructible through explicit imports',
    () async {
      final harness = await TestDiscoveryControllerHarness.create();
      try {
        final viewerFile = File(
          p.join(harness.databaseHarness.rootDirectory.path, 'viewer-note.txt'),
        );
        await viewerFile.writeAsString('viewer smoke');

        final explorer = FileExplorerPage.launch(
          sharedCacheCatalog: harness.sharedCacheCatalog,
          sharedCacheIndexStore: harness.sharedCacheIndexStore,
          previewCacheOwner: harness.previewCacheOwner,
          sharedCacheMaintenanceBoundary:
              harness.sharedCacheMaintenanceBoundary,
          ownerMacAddress: harness.controller.localDeviceMac,
          receiveDirectoryPath: harness.databaseHarness.rootDirectory.path,
        );
        final viewer = LocalFileViewerPage(
          filePath: viewerFile.path,
          previewCacheOwner: harness.previewCacheOwner,
        );

        expect(explorer, isA<FileExplorerPage>());
        expect(viewer, isA<LocalFileViewerPage>());
      } finally {
        await harness.dispose();
      }
    },
  );
}

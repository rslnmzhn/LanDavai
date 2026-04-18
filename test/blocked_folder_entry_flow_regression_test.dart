import 'package:flutter_test/flutter_test.dart';

import 'package:landa/core/utils/app_notification_service.dart';
import 'package:landa/features/discovery/application/shared_cache_maintenance_boundary.dart';
import 'package:landa/features/files/application/file_explorer_contract.dart';
import 'package:landa/features/files/application/files_feature_state_owner.dart';
import 'test_support/test_discovery_controller.dart';

void main() {
  late TestDiscoveryControllerHarness harness;

  setUp(() async {
    harness = await TestDiscoveryControllerHarness.create();
    addTearDown(() async {
      await harness.dispose();
    });
  });

  testWidgets('shared-folder virtual entries keep remove cache wiring intact', (
    tester,
  ) async {
    final mutableState = _MutableVirtualDirectoryState(
      folders: <FileExplorerVirtualFolder>[
        const FileExplorerVirtualFolder(
          name: 'Shared docs',
          folderPath: 'shared-docs',
          removableSharedCacheId: 'cache-1',
        ),
      ],
    );
    final owner = FilesFeatureStateOwner(
      roots: <FileExplorerRoot>[
        FileExplorerRoot(
          label: 'My files',
          path: 'virtual://my-files',
          isSharedFolder: true,
          virtualDirectoryLoader: (folderPath) async => mutableState.build(),
        ),
      ],
    );
    addTearDown(owner.dispose);
    await owner.initialize();
    expect(owner.state.entries, hasLength(1));
    expect(owner.state.entries.single.name, 'Shared docs');
    expect(owner.state.entries.single.removableSharedCacheId, 'cache-1');

    final boundary = _RecordingSharedCacheMaintenanceBoundary(
      sharedCacheCatalog: harness.sharedCacheCatalog,
      sharedCacheIndexStore: harness.sharedCacheIndexStore,
      ownerMacAddressProvider: () => harness.controller.localDeviceMac,
      onRemoveCacheById: (cacheId) async => true,
    );
    addTearDown(boundary.dispose);

    await boundary.removeCacheById(
      owner.state.entries.single.removableSharedCacheId!,
    );

    expect(boundary.removeCacheByIdCalls, 1);
    expect(boundary.lastRemovedCacheId, 'cache-1');
  });
}

class _MutableVirtualDirectoryState {
  _MutableVirtualDirectoryState({
    required List<FileExplorerVirtualFolder> folders,
  }) : _folders = List<FileExplorerVirtualFolder>.from(folders);

  final List<FileExplorerVirtualFolder> _folders;

  FileExplorerVirtualDirectory build() {
    return FileExplorerVirtualDirectory(
      folders: List<FileExplorerVirtualFolder>.from(_folders),
    );
  }
}

class _RecordingSharedCacheMaintenanceBoundary
    extends SharedCacheMaintenanceBoundary {
  _RecordingSharedCacheMaintenanceBoundary({
    required super.sharedCacheCatalog,
    required super.sharedCacheIndexStore,
    required super.ownerMacAddressProvider,
    required this.onRemoveCacheById,
  }) : super(appNotificationService: AppNotificationService.instance);

  final Future<bool> Function(String cacheId) onRemoveCacheById;
  int removeCacheByIdCalls = 0;
  String? lastRemovedCacheId;

  @override
  Future<SharedCacheSummary> summarizeOwnerSharedContent({
    String virtualFolderPath = '',
  }) async {
    return const SharedCacheSummary(
      totalCaches: 1,
      folderCaches: 1,
      selectionCaches: 0,
      totalFiles: 2,
    );
  }

  @override
  Future<bool> removeCacheById(String cacheId) async {
    removeCacheByIdCalls += 1;
    lastRemovedCacheId = cacheId;
    return onRemoveCacheById(cacheId);
  }
}
